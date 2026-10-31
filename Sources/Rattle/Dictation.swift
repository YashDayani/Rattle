import Cocoa
import Combine

enum DictationPhase: Equatable { case idle, listening(handsFree: Bool), processing, message(String) }

@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()
    @Published var phase: DictationPhase = .idle
    @Published var levels: [Float] = Array(repeating: 0, count: 14)
    @Published var lastError: String?
    /// Onboarding's practice box: dictation still types, but isn't saved to history or counted in Insights.
    var practiceMode = false
    @Published var lastPracticeText: String?
    /// Decided when a dictation starts, so a slow transcription can't change where it's counted.
    private var practiceRun = false

    /// A dictation is practice only if onboarding's practice step is showing and Rattle itself had focus.
    nonisolated static func isPractice(practiceMode: Bool, frontPID: pid_t?, ownPID: pid_t) -> Bool {
        practiceMode && frontPID == ownPID
    }

    private let recorder = AudioRecorder()
    private let hotkey = HotkeyManager()
    private enum Mode { case dictate, command }
    private var mode: Mode = .dictate
    private var selection: String?
    private var commandHeld = false
    private var startedAt = Date()
    private var frontApp: NSRunningApplication?
    private var maxTimer: Timer?
    private var lastLevelPush = Date.distantPast
    private var store: AppStore { .shared }

    var isRecording: Bool { if case .listening = phase { return true } else { return false } }

    func boot() {
        hotkey.isActive = { [weak self] in self?.isRecording ?? false }
        hotkey.onEvent = { [weak self] event in self?.handle(event) }
        recorder.onLevel = { [weak self] rms in
            let now = Date()
            DispatchQueue.main.async {
                guard let self, now.timeIntervalSince(self.lastLevelPush) > 0.045 else { return }
                self.lastLevelPush = now
                self.levels.removeFirst(); self.levels.append(min(1, rms * 9))
            }
        }
        hotkey.start()
        applyShortcut()
    }

    func applyShortcut() {
        var bindings = store.settings.bindings
        if !store.settings.commandModeEnabled { bindings.commandMode = [] }
        hotkey.bindings = bindings
    }

    /// The shortcut editor records keys itself, so the global shortcuts must stay quiet while it listens.
    func setShortcutsSuspended(_ suspended: Bool) { hotkey.suspended = suspended }

    private func handle(_ event: ShortcutEvent) {
        switch event {
        case .press(.pushToTalk): pressed()
        case .release(.pushToTalk): released()
        case .press(.commandMode): commandPressed()
        case .release(.commandMode): commandReleased()
        case .trigger(.handsFree): handsFreeTriggered()
        case .trigger(.cancel): cancel()
        case .trigger(.pressEnter): afterModifiersLift { TextInserter.pressReturn() }
        case .trigger(.pasteLast): pasteLastTranscript()
        case .trigger(.copyLast): copyLastTranscript()
        case .trigger(.notetaker): NotetakerController.shared.toggle()
        default: break
        }
    }

    // MARK: Last transcript
    private var lastTranscript: String? { store.history.first?.text }

    private func copyLastTranscript() {
        guard let text = lastTranscript else { flash("No dictation to copy yet"); return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        flash("Copied last transcript")
    }

    /// A shortcut's own modifiers are still down when it fires; sending a key before they lift would carry them along.
    private func afterModifiersLift(_ action: @escaping () -> Void) {
        Task {
            for _ in 0..<40 where !NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            action()
        }
    }

    private func pasteLastTranscript() {
        guard let text = lastTranscript else { flash("No dictation to paste yet"); return }
        afterModifiersLift { TextInserter.insert(text) }
    }

    // MARK: Command mode (select text, hold the command key, say what to change)
    private func commandPressed() {
        guard phase == .idle else { return }
        commandHeld = true
        phase = .processing   // brief: reading the selection
        Task {
            let sel = await TextInserter.captureSelection()
            guard commandHeld else { phase = .idle; return }
            selection = sel
            mode = .command
            phase = .idle
            start()
        }
    }
    private func commandReleased() {
        commandHeld = false
        if case .listening = phase, mode == .command {
            if Date().timeIntervalSince(startedAt) < 0.3 { cancel(silent: true) } else { stop() }
        }
    }

    func retryHotkey() { hotkey.start() }
    var hotkeyRunning: Bool { hotkey.start() }

    // MARK: State machine
    private func pressed() {
        switch phase {
        case .idle, .message: mode = .dictate; selection = nil; start()
        case .listening(let hf) where hf: stop()   // hands-free: second press ends it
        default: break
        }
    }
    private func released() {
        if case .listening(let hf) = phase, !hf {
            if Date().timeIntervalSince(startedAt) < 0.3 { cancel(silent: true) } else { stop() }
        }
    }
    /// Hands-free: lock a push-to-talk already in progress, or start listening on its own, and stop on the next press.
    private func handsFreeTriggered() {
        switch phase {
        case .idle, .message:
            mode = .dictate; selection = nil; start()
            lockHandsFree()
        case .listening(false): lockHandsFree()
        case .listening(true): stop()
        default: break
        }
    }
    private func lockHandsFree() { if case .listening(false) = phase { phase = .listening(handsFree: true) } }

    private func start() {
        guard Permissions.micGranted else {
            Permissions.requestMic { _ in }
            flash("Allow microphone access in Settings")
            return
        }
        frontApp = NSWorkspace.shared.frontmostApplication
        practiceRun = Self.isPractice(practiceMode: practiceMode, frontPID: frontApp?.processIdentifier, ownPID: getpid())
        do {
            try recorder.start(deviceUID: store.settings.micUID)
        } catch {
            flash(error.localizedDescription); return
        }
        levels = Array(repeating: 0, count: levels.count)
        startedAt = Date()
        phase = .listening(handsFree: false)
        if store.settings.soundsEnabled { Sounds.shared.play("start") }
        maxTimer?.invalidate()
        maxTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: false) { [weak self] _ in Task { @MainActor in self?.stop() } }
    }

    func cancel(silent: Bool = false) {
        maxTimer?.invalidate()
        _ = recorder.stop()
        phase = .idle
        if !silent && store.settings.soundsEnabled { Sounds.shared.play("stop") }
    }

    func toggleFromUI() { isRecording ? stop() : (phase == .idle ? start() : ()) }

    private func stop() {
        maxTimer?.invalidate()
        let samples = recorder.stop()
        let duration = Date().timeIntervalSince(startedAt)
        if store.settings.soundsEnabled { Sounds.shared.play("stop") }
        guard samples.count > 16000 / 4 else { phase = .idle; return }
        phase = .processing
        let settings = store.settings
        let dict = store.dictionary, snips = store.snippets
        let category = StyleCategory.forBundle(frontApp?.bundleIdentifier)
        let appName = frontApp?.localizedName ?? "Unknown"
        let bundleID = frontApp?.bundleIdentifier
        let model = WhisperModel.all.first { $0.id == settings.model } ?? WhisperModel.all[0]
        let mode = self.mode, selection = self.selection
        Task {
            do {
                let raw = try await Transcriber.transcribe(samples: samples, model: model, language: settings.language, vocabulary: dict.map { $0.replacement ?? $0.word }, cloud: settings.cloudSpeech)
                var text: String
                var corrected = 0, dictFixes = 0
                if mode == .command {
                    var lite = settings; lite.cleanup = .light
                    let instruction = TextProcessor.process(raw: raw, settings: lite, dictionary: dict, snippets: [], category: .other)
                    guard !instruction.isEmpty else { phase = .idle; return }
                    text = try await Transforms.command(instruction: instruction, selection: selection, settings: settings)
                } else {
                    let r = TextProcessor.processDetailed(raw: raw, settings: settings, dictionary: dict, snippets: snips, category: category)
                    text = r.text; corrected = r.corrected; dictFixes = r.dictFixes
                    guard !text.isEmpty else { phase = .idle; return }
                    if let t = store.transform(id: settings.autoTransformID) {
                        // Never lose a dictation because the AI server is slow or offline.
                        if let out = try? await Transforms.run(t, on: text, settings: settings, timeout: 12), !out.isEmpty { text = out }
                    }
                }
                guard !text.isEmpty else { phase = .idle; return }
                frontApp?.activate()
                try? await Task.sleep(nanoseconds: 80_000_000)
                TextInserter.insert(text)
                if practiceRun { lastPracticeText = text }
                else { store.history.insert(HistoryItem(date: Date(), raw: raw, text: text, duration: duration, appName: appName, bundleID: bundleID, corrected: corrected, dictFixes: dictFixes), at: 0) }
                if settings.soundsEnabled { Sounds.shared.play("done") }
                phase = .idle
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    private func flash(_ msg: String) {
        lastError = msg
        phase = .message(msg)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if case .message = self?.phase { self?.phase = .idle }
        }
    }
}
