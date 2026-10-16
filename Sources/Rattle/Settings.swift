import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", system = "System", notetaker = "Meetings", ai = "AI", mcp = "MCP", migration = "Migration", model = "Model", privacy = "Data and Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .system: return "laptopcomputer"
        case .notetaker: return "record.circle"
        case .ai: return "sparkle"
        case .mcp: return "powerplug"
        case .migration: return "square.and.arrow.down"
        case .model: return "cpu"
        case .privacy: return "shield"
        }
    }
}

struct SettingsModal: View {
    var close: () -> Void
    @ObservedObject var router = Router.shared
    private var tab: SettingsTab { get { router.settingsTab } nonmutating set { router.settingsTab = newValue } }
    @ObservedObject var store = AppStore.shared

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings").font(Theme.sans(20, .semibold)).foregroundStyle(Theme.ink).padding(.leading, 12).padding(.top, 6).padding(.bottom, 16)
                ForEach(SettingsTab.allCases) { t in
                    Button { tab = t } label: {
                        HStack(spacing: 10) {
                            Icon(t.icon, 20).frame(width: 20, height: 20)
                            Text(t.rawValue).font(Theme.sans(14, .medium))
                            Spacer()
                        }.foregroundStyle(Theme.ink).padding(.horizontal, 12).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(tab == t ? Theme.selected : .clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.press).pointer()
                }
                Spacer()
                Text("Rattle v1.0").font(Theme.sans(11)).foregroundStyle(Theme.muted).padding(.leading, 12)
            }
            .padding(.horizontal, 10).padding(.vertical, 22).frame(width: 210).background(Theme.window)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(tab.rawValue).font(Theme.serif(28)).tracking(-1.1); Spacer()
                        Button(action: close) { Icon("xmark", 15) }.buttonStyle(.press).pointer().foregroundStyle(Theme.muted)
                    }
                    switch tab {
                    case .general: GeneralTab()
                    case .system: SystemTab()
                    case .notetaker: NotetakerTab()
                    case .ai: AITab()
                    case .mcp: MCPTab()
                    case .migration: MigrationTab()
                    case .model: ModelTab()
                    case .privacy: PrivacyTab()
                    }
                }.padding(.horizontal, 44).padding(.vertical, 40)
            }.background(Theme.panel)
        }
        .frame(width: 960, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 10)
    }
}

struct GeneralTab: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var mics = AudioDevices.inputs()
    var body: some View {
        Card {
            SettingRow(title: "Shortcuts", detail: "Hold \(store.settings.shortcut.title) and speak. Press space to lock hands-free.") {
                Dropdown(selection: Binding(get: { store.settings.shortcut }, set: { store.settings.shortcut = $0; DictationController.shared.applyShortcut() }),
                         options: Shortcut.allCases.map { ($0, $0.title) }, width: 160)
            }
            SettingRow(title: "Microphone", detail: store.settings.micUID == nil ? "Auto-detect (\(AudioDevices.defaultInputName()))" : (mics.first { $0.uid == store.settings.micUID }?.name ?? "Selected device")) {
                Dropdown(selection: Binding(get: { store.settings.micUID ?? "" }, set: { store.settings.micUID = $0.isEmpty ? nil : $0 }),
                         options: [("", "Auto-detect")] + mics.map { ($0.uid, $0.name) }, width: 200)
            }
            SettingRow(title: "Dictation language", detail: languageNote) {
                Dropdown(selection: $store.settings.language, options: Self.languages.map { ($0.0, $0.1) }, width: 160)
            }
            SettingRow(title: "Onboarding", detail: "Walk through setup again.", last: true) {
                PillButton(title: "Show again") {
                    store.settings.onboardingDone = false
                    Router.shared.showSettings = false
                    OnboardingWindowController.shared.show()
                }
            }
        }
        .onAppear { mics = AudioDevices.inputs() }
    }
    private var languageNote: String {
        if store.settings.speechEngine == .cloud { return "Groq will transcribe in this language." }
        return (WhisperModel.all.first { $0.id == store.settings.model }?.multilingual ?? false) ? "Whisper will transcribe in this language." : "English-only model selected. Pick a multilingual model to change language."
    }
    static let languages = [("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"), ("ru", "Russian"), ("auto", "Auto-detect")]
}

struct SystemTab: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        Card {
            SettingRow(title: "Appearance", detail: "Follow macOS, or always use light or dark.") {
                Dropdown(selection: Binding(get: { store.settings.appearance }, set: { store.settings.appearance = $0; Theme.apply($0) }),
                         options: AppearanceMode.allCases.map { ($0, $0.title) }, width: 160)
            }
            SettingRow(title: "Launch Rattle at login", detail: "Start in the menu bar when you sign in.") {
                Toggle("", isOn: Binding(get: { store.settings.launchAtLogin }, set: { on in
                    store.settings.launchAtLogin = on
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                })).toggleStyle(ThemeSwitchStyle()).labelsHidden()
            }
            SettingRow(title: "Show app in Dock", detail: "Otherwise Rattle lives only in the menu bar.") {
                Toggle("", isOn: Binding(get: { store.settings.showInDock }, set: {
                    store.settings.showInDock = $0
                    NSApp.setActivationPolicy($0 ? .regular : .accessory)
                })).toggleStyle(ThemeSwitchStyle()).labelsHidden()
            }
            SettingRow(title: "Show Flow Bar", detail: "The pill at the bottom of your screen while dictating.") {
                Toggle("", isOn: Binding(get: { store.settings.showFlowBar }, set: {
                    store.settings.showFlowBar = $0
                    (NSApp.delegate as? AppDelegate)?.flowBar.setVisible($0)
                })).toggleStyle(ThemeSwitchStyle()).labelsHidden()
            }
            SettingRow(title: "Dictation sounds", detail: "Play a soft cue when dictation starts and stops.", last: true) {
                Toggle("", isOn: $store.settings.soundsEnabled).toggleStyle(ThemeSwitchStyle()).labelsHidden()
            }
        }
    }
}

struct ModelTab: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var dl = ModelDownloader.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                engineOption(.local, icon: "laptopcomputer", title: "Local", detail: "whisper.cpp on this Mac. Audio never leaves your device.")
                engineOption(.cloud, icon: "cloud", title: "Cloud", detail: "Groq's hosted Whisper. Faster, but audio is sent to Groq.")
            }
            if store.settings.speechEngine == .cloud { cloudSettings } else { localSettings }
        }
    }

    private func engineOption(_ engine: SpeechEngine, icon: String, title: String, detail: String) -> some View {
        let on = store.settings.speechEngine == engine
        return Button { select(engine) } label: {
            HStack(alignment: .top, spacing: 12) {
                Icon(icon, 20).foregroundStyle(Theme.ink).padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(Theme.sans(13.5)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Icon(on ? "checkmark.circle.fill" : "circle", 18).foregroundStyle(on ? Theme.ink : Theme.switchOff)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg).strokeBorder(on ? Theme.ink : Theme.line, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.press).pointer()
    }

    private func select(_ engine: SpeechEngine) {
        guard store.settings.speechEngine != engine else { return }
        store.settings.speechEngine = engine
        // Only keep the local speech server running while it is the engine in use.
        if engine == .local, let m = WhisperModel.all.first(where: { $0.id == store.settings.model }) { WhisperServer.shared.ensure(model: m) }
        else { WhisperServer.shared.stop() }
    }

    private var cloudSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                SettingRow(title: "Groq API key", detail: "Stored on this Mac. Create one at console.groq.com/keys.") {
                    SecureField("gsk_…", text: $store.settings.groqKey).textFieldStyle(.roundedBorder).frame(width: 260)
                }
                SettingRow(title: "Model", detail: "Turbo is faster; Large v3 is the most accurate.", last: true) {
                    Dropdown(selection: $store.settings.groqModel, options: CloudSpeech.models.map { ($0.id, $0.title) }, width: 260)
                }
            }
            if store.settings.groqKey.isEmpty {
                Text("Add a key to start using cloud transcription. Until then dictation will show an error.").font(Theme.sans(13)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var localSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                ForEach(Array(WhisperModel.all.enumerated()), id: \.element.id) { i, m in
                    SettingRow(title: m.title, detail: m.size + (m.installed ? " · Downloaded" : ""), last: i == WhisperModel.all.count - 1) {
                        HStack(spacing: 10) {
                            if let p = dl.progress[m.id] { ProgressView(value: p).frame(width: 90) }
                            else if !m.installed { PillButton(title: "Download") { dl.download(m) } }
                            if m.installed {
                                if store.settings.model == m.id { Label { Text("Active") } icon: { Icon("checkmark.circle.fill", 14) }.font(Theme.sans(12.5, .medium)).foregroundStyle(.green) }
                                else { PillButton(title: "Use") { store.settings.model = m.id } }
                            }
                        }
                    }
                }
            }
            if let e = dl.error { Text(e).font(Theme.sans(12)).foregroundStyle(.red) }
            Card {
                SettingRow(title: "whisper.cpp engine", detail: Transcriber.enginePath ?? "Not found. Install with: brew install whisper-cpp", last: true) {
                    Icon(Transcriber.enginePath != nil ? "checkmark.circle.fill" : "xmark.circle", 16).foregroundStyle(Transcriber.enginePath != nil ? .green : .red)
                }
            }
        }
    }
}

struct PrivacyTab: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var confirm = false
    var body: some View {
        Card {
            if store.settings.speechEngine == .cloud {
                SettingRow(title: "Cloud transcription", detail: "Audio is sent to Groq to be transcribed. Switch to Local in Settings → Model to keep it on this Mac.") { Icon("cloud", 16).foregroundStyle(Theme.muted) }
            } else {
                SettingRow(title: "Local-only processing", detail: "Transcription runs on-device. No audio or text is sent anywhere.") { Icon("lock.fill", 16).foregroundStyle(Theme.muted) }
            }
            SettingRow(title: "Dictation history", detail: "\(store.history.count) saved on this Mac in Application Support/Rattle.") {
                PillButton(title: "Clear") { confirm = true }
            }
            SettingRow(title: "Open data folder", detail: "History, dictionary, snippets and models.", last: true) {
                PillButton(title: "Reveal") { NSWorkspace.shared.open(AppStore.supportDir) }
            }
        }
        .alert("Delete all dictation history?", isPresented: $confirm) {
            Button("Delete", role: .destructive) { store.history = [] }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct NotetakerTab: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                SettingRow(title: "Record call audio", detail: "Capture what your Mac is playing so the other side of a call is transcribed too. macOS asks for System Audio Recording permission the first time.") {
                    Toggle("", isOn: $store.settings.notetakerCaptureSystemAudio).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                }
                SettingRow(title: "Keep the recording", detail: "Save each meeting's audio on this Mac so you can listen back or download it later.") {
                    Toggle("", isOn: $store.settings.notetakerSaveAudio).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                }
                SettingRow(title: "Write notes automatically", detail: "When a recording ends, summarize it with your AI model (title, summary, decisions, action items).", last: true) {
                    Toggle("", isOn: $store.settings.notetakerSummaries).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                }
            }
            Text("Choose the transcription and summary models in Settings → AI. Only the transcript text is sent to your AI model, and with a local model it never leaves this Mac.")
                .font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
        }
    }
}

struct AITab: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var models: [String] = []
    @LocalState private var status: String = ""
    @LocalState private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meeting summaries and Transforms use any OpenAI-compatible server. Rattle defaults to LM Studio running on this Mac.")
                .font(Theme.sans(13.5)).foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    preset("LM Studio", "http://localhost:1234/v1")
                    preset("Ollama", "http://localhost:11434/v1")
                    preset("OpenAI", "https://api.openai.com/v1")
                    preset("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai")
                }
                HStack(spacing: 8) {
                    preset("Groq", "https://api.groq.com/openai/v1")
                    preset("Mistral", "https://api.mistral.ai/v1")
                    preset("OpenRouter", "https://openrouter.ai/api/v1")
                }
            }
            Card {
                SettingRow(title: "Server URL", detail: "OpenAI-compatible base URL.") {
                    TextField("http://localhost:1234/v1", text: $store.settings.llmBaseURL).textFieldStyle(.roundedBorder).frame(width: 260)
                }
                SettingRow(title: "Model", detail: store.settings.llmModel.isEmpty ? "Automatic: uses the first model the server offers." : store.settings.llmModel) {
                    Dropdown(selection: $store.settings.llmModel,
                             options: [("", "Automatic")]
                                + (!store.settings.llmModel.isEmpty && !models.contains(store.settings.llmModel) ? [(store.settings.llmModel, store.settings.llmModel)] : [])
                                + models.map { ($0, $0) },
                             width: 260)
                }
                SettingRow(title: "API key", detail: "Only needed for hosted services. Stored on this Mac.", last: true) {
                    SecureField("Optional", text: $store.settings.llmKey).textFieldStyle(.roundedBorder).frame(width: 260)
                }
            }
            HStack(spacing: 12) {
                PillButton(title: testing ? "Testing…" : "Test connection", prominent: true) { test() }.disabled(testing)
                Text(status).font(Theme.sans(13)).foregroundStyle(status.hasPrefix("Connected") ? .green : Theme.muted)
            }
            Text("Meetings").font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink).padding(.top, 6)
            Card {
                SettingRow(title: "Transcription model", detail: "Speech model that writes meeting transcripts. Cloud models need a Groq key in Settings → Model.") {
                    Dropdown(selection: $store.settings.meetingSpeechModel, options: speechOptions, width: 260)
                }
                SettingRow(title: "Summary model", detail: store.settings.summaryModel.isEmpty ? "Uses the model above." : "Writes meeting notes. Transforms keep using the model above.") {
                    Dropdown(selection: $store.settings.summaryModel,
                             options: [("", "Same as AI model")]
                                + (!store.settings.summaryModel.isEmpty && !models.contains(store.settings.summaryModel) ? [(store.settings.summaryModel, store.settings.summaryModel)] : [])
                                + models.map { ($0, $0) },
                             width: 260)
                }
                SettingRow(title: "Summarize from audio", detail: GeminiAudio.supports(store.settings)
                           ? "Sends the meeting recording to Gemini instead of the transcript. Needs Keep the recording on in Settings → Meetings; meetings without a recording use the transcript."
                           : "Only works with Gemini. Other AI servers summarize the transcript.", last: true) {
                    Toggle("", isOn: $store.settings.summaryFromAudio).toggleStyle(ThemeSwitchStyle()).labelsHidden()
                }
            }
            Text("Running LM Studio? Start its server from the Developer tab or with: lms server start")
                .font(Theme.sans(12.5)).foregroundStyle(Theme.muted)
        }
        .onAppear { test() }
    }

    private var speechOptions: [(value: String, title: String)] {
        let dictation = store.settings.speechEngine == .cloud
            ? CloudSpeech.models.first { $0.id == store.settings.groqModel }?.title ?? store.settings.groqModel
            : WhisperModel.all.first { $0.id == store.settings.model }?.title ?? store.settings.model
        return [("", "Same as dictation (\(dictation))")]
            + WhisperModel.all.map { ("local:\($0.id)", "Local · \($0.title)" + ($0.installed ? "" : " (not downloaded)")) }
            + CloudSpeech.models.map { ("cloud:\($0.id)", "Groq · \($0.title)") }
    }

    private func preset(_ name: String, _ url: String) -> some View {
        PillButton(title: name) { store.settings.llmBaseURL = url; store.settings.llmModel = ""; test() }
    }

    private func test() {
        testing = true; status = ""
        Task {
            do {
                let m = try await LLM.models(LLM.Config(store.settings))
                models = m
                status = m.isEmpty ? "Connected, but no model is loaded." : "Connected · \(m.count) model\(m.count == 1 ? "" : "s") available"
            } catch { status = error.localizedDescription }
            testing = false
        }
    }
}
