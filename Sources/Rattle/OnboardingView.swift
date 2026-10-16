import SwiftUI

/// First-run onboarding: six short steps that leave Rattle ready to dictate.
struct OnboardingView: View {
    var finish: () -> Void
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var downloads = ModelDownloader.shared
    @ObservedObject private var dictation = DictationController.shared
    @LocalState private var step: OnboardingStep = .name
    @LocalState private var forward = true
    @LocalState private var tick = 0
    @LocalState private var practice = ""
    @LocalState private var copied = false
    @FocusState private var focused: Bool
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    /// Art tiles stay light in both appearances so the doodles read the same.
    private static let tile = Color(red: 0.984, green: 0.973, blue: 0.945)   // #fbf8f1
    private static let ok = Color(red: 0.18, green: 0.55, blue: 0.34)

    private var settings: Settings { store.settings }
    private var model: WhisperModel { WhisperModel.all.first { $0.id == settings.model } ?? WhisperModel.all[0] }
    private var checks: OnboardingChecks {
        _ = tick
        return OnboardingChecks(name: settings.userName, micGranted: Permissions.micGranted, axGranted: Permissions.accessibilityGranted,
                                engine: settings.speechEngine, localModelInstalled: model.installed,
                                whisperInstalled: Transcriber.enginePath != nil, groqKey: settings.groqKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            art
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(Theme.serif(30)).tracking(-0.9).foregroundStyle(Theme.ink)
                Text(subtitle).font(Theme.sans(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6).padding(.bottom, 18)
                content
            }
            .padding(.horizontal, 10).padding(.top, 22)
            .id(step)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: forward ? 24 : -24)), removal: .opacity))
            Spacer(minLength: 12)
            footer
        }
        .padding(.horizontal, 22).padding(.top, 44).padding(.bottom, 22)
        .frame(width: 720, height: 620)
        .background(Theme.window)
        .onReceive(poll) { _ in
            tick += 1
            if step == .permissions, Permissions.accessibilityGranted { dictation.retryHotkey() }
        }
        .onChange(of: step) { _ in
            dictation.practiceMode = step == .key
            focused = step == .name || step == .key
        }
        .onAppear { focused = true }
        .onDisappear { dictation.practiceMode = false }
    }

    // MARK: Chrome

    private var art: some View {
        ZStack {
            Self.tile
            if let image = OnboardingArt.image(for: step) {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).padding(18)
                    .id(step).transition(.opacity)
            }
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl).stroke(Theme.line))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(OnboardingStep.allCases, id: \.self) { s in
                    Capsule().fill(s == step ? Theme.ink : Theme.switchOff).frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            Spacer()
            if OnboardingFlow.canSkip(step, checks) {
                Button("Skip for now") { go(OnboardingFlow.next(step)) }
                    .buttonStyle(.plain).font(Theme.sans(13.5)).foregroundStyle(Theme.muted).pointer()
            }
            if let back = OnboardingFlow.back(step) {
                Button("Back") { go(back, forward: false) }
                    .buttonStyle(.plain).font(Theme.sans(13.5)).foregroundStyle(Theme.muted).pointer().padding(.horizontal, 6)
            }
            PillButton(title: step == .done ? "Start using Rattle" : "Continue", prominent: true) {
                if let next = OnboardingFlow.next(step) { go(next) } else { finish() }
            }
            .disabled(!OnboardingFlow.canContinue(step, checks))
            .opacity(OnboardingFlow.canContinue(step, checks) ? 1 : 0.4)
        }
        .padding(.horizontal, 10)
        .animation(Theme.Motion.quick, value: step)
    }

    private func go(_ target: OnboardingStep?, forward: Bool = true) {
        guard let target else { return }
        self.forward = forward
        withAnimation(Theme.Motion.standard) { step = target }
    }

    // MARK: Copy

    private var keyName: String { settings.shortcut.title }

    private var title: String {
        switch step {
        case .name: return "Welcome to Rattle"
        case .look: return "Pick a look"
        case .permissions: return "Two quick permissions"
        case .engine: return "Where should speech become text?"
        case .key: return "Hold a key and speak"
        case .done: return "You're all set, \(settings.userName.trimmingCharacters(in: .whitespaces))"
        }
    }

    private var subtitle: String {
        switch step {
        case .name: return "Talk instead of typing, in any app on your Mac. First, what should we call you?"
        case .look: return "Rattle follows your Mac by default. You can change this later."
        case .permissions: return "Rattle needs to hear you and to type into other apps."
        case .engine: return "You can switch any time in Settings → Model."
        case .key: return "Pick the key you'll hold while talking, then try it below."
        case .done: return "Hold \(keyName) in any app to dictate. Meetings, notes and AI summaries are in the sidebar whenever you want them."
        }
    }

    // MARK: Steps

    @ViewBuilder private var content: some View {
        switch step {
        case .name: nameStep
        case .look: lookStep
        case .permissions: permissionsStep
        case .engine: engineStep
        case .key: keyStep
        case .done: EmptyView()
        }
    }

    private var nameStep: some View {
        TextField("Your name", text: $store.settings.userName)
            .textFieldStyle(.plain).font(Theme.sans(15)).focused($focused)
            .padding(.horizontal, 13).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.line))
            .onSubmit { if OnboardingFlow.canContinue(.name, checks) { go(.look) } }
    }

    private var lookStep: some View {
        HStack(spacing: 10) {
            ForEach(AppearanceMode.allCases) { mode in
                let on = settings.appearance == mode
                Button { store.settings.appearance = mode; Theme.apply(mode) } label: {
                    VStack(spacing: 8) {
                        swatch(mode).frame(height: 46).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).stroke(Theme.line))
                        Text(mode.title).font(Theme.sans(13, .medium)).foregroundStyle(Theme.ink)
                    }
                    .padding(10).frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(on ? Theme.ink : Theme.line, lineWidth: on ? 1.5 : 1))
                    .contentShape(Rectangle())
                }.buttonStyle(.press).pointer()
            }
        }
    }

    @ViewBuilder private func swatch(_ mode: AppearanceMode) -> some View {
        let light = Color(red: 0.961, green: 0.957, blue: 0.941), dark = Color(red: 0.125, green: 0.125, blue: 0.125)
        switch mode {
        case .light: light
        case .dark: dark
        case .system: HStack(spacing: 0) { light; dark }
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 0) {
            permissionRow("Microphone", "To hear your voice", granted: checks.micGranted) {
                Permissions.requestMic { _ in tick += 1 }
            }
            Divider().overlay(Theme.line).padding(.horizontal, 14)
            permissionRow("Accessibility", "To type where your cursor is", granted: checks.axGranted) {
                Permissions.requestAccessibility(); Permissions.openPrivacy("Privacy_Accessibility")
            }
        }
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).stroke(Theme.line))
    }

    private func permissionRow(_ title: String, _ detail: String, granted: Bool, allow: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.sans(14, .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if granted {
                Label { Text("Allowed") } icon: { Icon("checkmark", 13) }.font(Theme.sans(12.5, .medium)).foregroundStyle(Self.ok)
            } else {
                PillButton(title: "Allow", prominent: true, action: allow)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var engineStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                engineCard(.local, "On this Mac", "Private and works offline. \(model.size) download.")
                engineCard(.cloud, "Groq cloud", "Fastest. Needs a free API key from console.groq.com.")
            }
            if settings.speechEngine == .local { localStatus } else {
                SecureField("Groq API key (gsk_…)", text: $store.settings.groqKey)
                    .textFieldStyle(.plain).font(Theme.sans(14))
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.panel))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.line))
            }
        }
    }

    private func engineCard(_ engine: SpeechEngine, _ title: String, _ detail: String) -> some View {
        let on = settings.speechEngine == engine
        return Button { store.settings.speechEngine = engine } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(Theme.sans(14, .medium)).foregroundStyle(Theme.ink)
                Text(detail).font(Theme.sans(12.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(on ? Theme.ink : Theme.line, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.press).pointer()
    }

    @ViewBuilder private var localStatus: some View {
        HStack(spacing: 10) {
            if model.installed {
                Label { Text("\(model.title) is ready") } icon: { Icon("checkmark", 13) }.foregroundStyle(Self.ok)
            } else if let p = downloads.progress[model.id] {
                ProgressView(value: p).tint(Theme.ink).frame(width: 160)
                Text("Downloading \(Int(p * 100))%").foregroundStyle(Theme.muted)
            } else {
                PillButton(title: "Download model", prominent: true) { downloads.download(model) }
            }
            Spacer()
        }.font(Theme.sans(13))
        if Transcriber.enginePath == nil {
            HStack(spacing: 10) {
                Text("Also install whisper.cpp:").foregroundStyle(Theme.muted)
                Text("brew install whisper-cpp").font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.ink)
                PillButton(title: copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString("brew install whisper-cpp", forType: .string); copied = true
                }
            }.font(Theme.sans(13))
        }
    }

    private var keyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(OnboardingFlow.keyChoices) { key in
                    let on = settings.shortcut == key
                    Button { store.settings.shortcut = key; dictation.applyShortcut() } label: {
                        Text(key.title).font(Theme.sans(13.5, .medium)).foregroundStyle(on ? Theme.onInk : Theme.ink)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(on ? Theme.ink : Theme.panel))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(on ? Theme.ink : Theme.line))
                    }.buttonStyle(.press).pointer()
                }
            }
            TextField("Hold \(keyName) and say “Hello Rattle”", text: $practice)
                .textFieldStyle(.plain).font(Theme.sans(15)).focused($focused)
                .padding(.horizontal, 13).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: practice.isEmpty ? [4, 3] : [])))
            if dictation.lastPracticeText != nil {
                Label { Text("Nice, that works.") } icon: { Icon("checkmark", 13) }.font(Theme.sans(13, .medium)).foregroundStyle(Self.ok)
            }
        }
    }
}
