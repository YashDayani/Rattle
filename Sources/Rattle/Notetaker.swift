import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation

/// Captures everything the Mac is playing (the other side of a call) using a Core Audio process tap (macOS 14.4+).
/// Output is 16 kHz mono Float32, same as the microphone path.
final class SystemAudioTap {
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let lock = NSLock()
    private var samples: [Float] = []
    private var format = AudioStreamBasicDescription()
    private let queue = DispatchQueue(label: "rattle.systemtap", qos: .userInitiated)
    private(set) var running = false

    struct TapError: LocalizedError { let message: String; var errorDescription: String? { message } }

    func start() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "Rattle System Audio"
        desc.uuid = UUID()
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr else { throw TapError(message: "Couldn't start system audio capture (error \(status)). Allow System Audio Recording for Rattle in System Settings → Privacy & Security.") }

        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &format)
        guard status == noErr, format.mSampleRate > 0 else { stop(); throw TapError(message: "Couldn't read the system audio format (error \(status)).") }

        var agg: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Rattle Aggregate",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]],
        ]
        if let uid = Self.defaultOutputUID() {
            agg[kAudioAggregateDeviceMainSubDeviceKey] = uid
            agg[kAudioAggregateDeviceSubDeviceListKey] = [[kAudioSubDeviceUIDKey: uid]]
        }
        status = AudioHardwareCreateAggregateDevice(agg as CFDictionary, &aggID)
        guard status == noErr else { stop(); throw TapError(message: "Couldn't create the capture device (error \(status)).") }

        let fmt = format
        status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, queue) { [weak self] _, inData, _, _, _ in
            self?.process(inData, fmt)
        }
        guard status == noErr else { stop(); throw TapError(message: "Couldn't attach to system audio (error \(status)).") }
        status = AudioDeviceStart(aggID, procID)
        guard status == noErr else { stop(); throw TapError(message: "Couldn't start system audio (error \(status)).") }
        running = true
    }

    func stop() {
        if aggID != kAudioObjectUnknown {
            if let p = procID { AudioDeviceStop(aggID, p); AudioDeviceDestroyIOProcID(aggID, p) }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil; aggID = AudioObjectID(kAudioObjectUnknown); tapID = AudioObjectID(kAudioObjectUnknown)
        running = false
    }

    func drain() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        let out = samples; samples = []; return out
    }

    private func process(_ input: UnsafePointer<AudioBufferList>, _ fmt: AudioStreamBasicDescription) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let nonInterleaved = fmt.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let channels = max(1, Int(fmt.mChannelsPerFrame))
        var mono: [Float] = []
        if nonInterleaved {
            guard let first = list.first, let base = first.mData else { return }
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            mono = [Float](repeating: 0, count: frames)
            var used = 0
            for b in list {
                guard let d = b.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let n = min(frames, Int(b.mDataByteSize) / MemoryLayout<Float>.size)
                for i in 0..<n { mono[i] += d[i] }
                used += 1
            }
            _ = base
            if used > 1 { let k = 1 / Float(used); for i in 0..<frames { mono[i] *= k } }
        } else {
            guard let b = list.first, let d = b.mData?.assumingMemoryBound(to: Float.self) else { return }
            let frames = Int(b.mDataByteSize) / MemoryLayout<Float>.size / channels
            mono = [Float](repeating: 0, count: frames)
            for f in 0..<frames {
                var sum: Float = 0
                for c in 0..<channels { sum += d[f * channels + c] }
                mono[f] = sum / Float(channels)
            }
        }
        let out = Self.resample(mono, from: fmt.mSampleRate)
        lock.lock(); samples.append(contentsOf: out); lock.unlock()
    }

    /// Box-filter decimation to 16 kHz (cheap, good enough for speech recognition).
    private static func resample(_ x: [Float], from rate: Double) -> [Float] {
        if rate == 16000 { return x }
        let step = rate / 16000
        var out: [Float] = []
        out.reserveCapacity(Int(Double(x.count) / step) + 1)
        var pos = 0.0
        while Int(pos + step) <= x.count - 1 {
            let a = Int(pos), b = max(a + 1, Int(pos + step))
            var s: Float = 0
            for i in a..<b { s += x[i] }
            out.append(s / Float(b - a))
            pos += step
        }
        return out
    }

    private static func defaultOutputUID() -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return nil }
        var uidAddr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var cf: Unmanaged<CFString>?
        var s2 = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &uidAddr, 0, nil, &s2, &cf) == noErr, let u = cf else { return nil }
        return u.takeRetainedValue() as String
    }
}

@MainActor
final class NotetakerController: ObservableObject {
    static let shared = NotetakerController()
    enum State: Equatable { case idle, recording, finishing }

    @Published var state: State = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var liveLines: [TranscriptLine] = []
    @Published var warning: String?
    @Published var selectedID: UUID?
    @Published var summarizingID: UUID?
    @Published var answer: String?
    @Published var asking = false

    private let mic = AudioRecorder()
    private let tap = SystemAudioTap()
    private var startedAt = Date()
    private var lastFlushOffset: TimeInterval = 0
    private var ticker: Timer?
    private var chunker: Timer?
    private var chain: Task<Void, Never>?
    private var usingSystemAudio = false
    private var store: AppStore { .shared }

    private let chunkSeconds: TimeInterval = 20

    var tapNote: String { usingSystemAudio ? "Mic + call audio" : "Mic only" }

    func toggle() {
        if state == .recording { Task { await stop() } } else if state == .idle { start() }
    }

    func start() {
        guard state == .idle else { return }
        guard Permissions.micGranted else {
            Permissions.requestMic { _ in }
            warning = "Allow microphone access, then start Notetaker again."
            return
        }
        warning = nil; answer = nil
        liveLines = []; elapsed = 0; lastFlushOffset = 0
        do { try mic.start(deviceUID: store.settings.micUID) } catch { warning = error.localizedDescription; return }
        usingSystemAudio = false
        if store.settings.notetakerCaptureSystemAudio {
            do { try tap.start(); usingSystemAudio = true }
            catch { warning = "Recording your microphone only. \(error.localizedDescription)" }
        }
        startedAt = Date()
        state = .recording
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in guard let self else { return }; self.elapsed = Date().timeIntervalSince(self.startedAt) }
        }
        chunker = Timer.scheduledTimer(withTimeInterval: chunkSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.enqueueFlush() }
        }
    }

    private func enqueueFlush() {
        let m = mic.drain()
        let s = usingSystemAudio ? tap.drain() : []
        let offset = lastFlushOffset
        lastFlushOffset = Date().timeIntervalSince(startedAt)
        let previous = chain
        chain = Task { [weak self] in
            await previous?.value
            await self?.transcribe(mic: m, system: s, offset: offset)
        }
    }

    private func transcribe(mic m: [Float], system s: [Float], offset: TimeInterval) async {
        for (samples, speaker) in [(m, "You"), (s, "Others")] {
            guard samples.count > 16000, Self.rms(samples) > 0.004 else { continue }
            let settings = store.settings
            let model = WhisperModel.all.first { $0.id == settings.model } ?? WhisperModel.all[0]
            guard let raw = try? await Transcriber.transcribe(samples: samples, model: model, language: settings.language, vocabulary: store.dictionary.map { $0.replacement ?? $0.word }) else {
                warning = "Transcription failed. Check the speech model in Settings → Model."
                continue
            }
            let text = Self.clean(raw)
            if !text.isEmpty { liveLines.append(TranscriptLine(time: offset, speaker: speaker, text: text)) }
        }
        liveLines.sort { $0.time < $1.time }
    }

    func stop() async {
        guard state == .recording else { return }
        state = .finishing
        ticker?.invalidate(); chunker?.invalidate()
        let duration = Date().timeIntervalSince(startedAt)
        let m = mic.stop()
        let s = usingSystemAudio ? tap.drain() : []
        tap.stop()
        let offset = lastFlushOffset
        let previous = chain
        await previous?.value
        await transcribe(mic: m, system: s, offset: offset)

        var meeting = Meeting(title: Self.defaultTitle(startedAt), date: startedAt, duration: duration, lines: liveLines, capturedSystemAudio: usingSystemAudio)
        liveLines = []
        state = .idle
        guard !meeting.lines.isEmpty else { warning = "No speech was picked up, so nothing was saved."; return }
        store.meetings.insert(meeting, at: 0)
        selectedID = meeting.id
        if store.settings.notetakerSummaries { await summarize(meeting.id) }
        meeting = store.meetings.first { $0.id == meeting.id } ?? meeting
    }

    func summarize(_ id: UUID) async {
        guard let idx = store.meetings.firstIndex(where: { $0.id == id }) else { return }
        summarizingID = id
        defer { summarizingID = nil }
        let transcript = Self.transcriptText(store.meetings[idx].lines)
        let system = """
        You write concise, accurate meeting notes from a transcript. "You" is the person who recorded; "Others" are the remote participants (not separated by person).
        Output Markdown in exactly this shape:
        # <short title, max 8 words>
        ## Summary
        - 3 to 6 bullets
        ## Decisions
        - bullets, or "None noted"
        ## Action items
        - [ ] item (owner if stated)
        Use only what is in the transcript. Do not invent names, dates or commitments.
        """
        do {
            let out = try await LLM.chat(system: system, user: String(transcript.prefix(24000)), settings: store.settings, maxTokens: 900, timeout: 180)
            guard let i = store.meetings.firstIndex(where: { $0.id == id }) else { return }
            var body = out
            if let first = out.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first, first.hasPrefix("# ") {
                store.meetings[i].title = String(first.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                body = out.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).dropFirst().first.map(String.init) ?? ""
            }
            store.meetings[i].summary = body.trimmingCharacters(in: .whitespacesAndNewlines)
            store.meetings[i].summaryError = nil
        } catch {
            if let i = store.meetings.firstIndex(where: { $0.id == id }) { store.meetings[i].summaryError = error.localizedDescription }
        }
    }

    /// "What are my action items this week?" across recent notes.
    func ask(_ question: String) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        asking = true; answer = nil
        defer { asking = false }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let recent = store.meetings.filter { $0.date > cutoff }.prefix(12)
        guard !recent.isEmpty else { answer = "You don't have any notes from the last 30 days yet."; return }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        var context = ""
        for m in recent {
            let body = m.summary.isEmpty ? Self.transcriptText(m.lines).prefix(3000) : Substring(m.summary)
            context += "### \(m.title) (\(df.string(from: m.date)))\n\(body)\n\n"
        }
        let sys = "You answer questions about the user's meeting notes. Today is \(df.string(from: Date())). Answer briefly using only the notes provided; if the answer isn't there, say so."
        do { answer = try await LLM.chat(system: sys, user: "Notes:\n\(String(context.prefix(24000)))\n\nQuestion: \(q)", settings: store.settings, maxTokens: 600) }
        catch { answer = error.localizedDescription }
    }

    // MARK: Helpers
    static func rms(_ x: [Float]) -> Float {
        guard !x.isEmpty else { return 0 }
        var s: Float = 0; for v in x { s += v * v }
        return sqrt(s / Float(x.count))
    }

    static func clean(_ raw: String) -> String {
        var t = raw.replacingOccurrences(of: #"\[[^\]]*\]|\([^)]*\)"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        // Whisper hallucinates these on near-silence.
        let junk = #"^(thank you\.?|thanks for watching\.?|thanks\.?|you\.?|bye\.?|\.+)$"#
        if t.range(of: junk, options: [.regularExpression, .caseInsensitive]) != nil { return "" }
        return t
    }

    static func defaultTitle(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "'Meeting' · MMM d, h:mm a"
        return f.string(from: d)
    }

    static func timestamp(_ t: TimeInterval) -> String {
        let s = Int(t); return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    static func transcriptText(_ lines: [TranscriptLine]) -> String {
        lines.map { "[\(timestamp($0.time))] \($0.speaker): \($0.text)" }.joined(separator: "\n")
    }
}
