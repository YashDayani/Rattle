import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General", system = "System", notetaker = "Notetaker", ai = "AI", model = "Model", privacy = "Data and Privacy"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .system: return "laptopcomputer"
        case .notetaker: return "record.circle"
        case .ai: return "sparkles"
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
                HStack(spacing: 8) {
                    AppIconView(size: 22)
                    Text("Rattle").font(.system(size: 15, weight: .semibold, design: .rounded))
                }.padding(.leading, 10).padding(.bottom, 14)
                Text("SETTINGS").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted).padding(.leading, 12).padding(.bottom, 8)
                ForEach(SettingsTab.allCases) { t in
                    Button { tab = t } label: {
                        HStack(spacing: 10) {
                            Icon(t.icon, 16).frame(width: 20)
                            Text(t.rawValue).font(.system(size: 14, weight: .medium))
                            Spacer()
                        }.foregroundStyle(Theme.ink).padding(.horizontal, 12).frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(tab == t ? Theme.selected : .clear))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).pointer()
                }
                Spacer()
                Text("Rattle v1.0").font(.system(size: 11)).foregroundStyle(Theme.muted).padding(.leading, 12)
            }
            .padding(.horizontal, 10).padding(.vertical, 22).frame(width: 210).background(Color(red: 0.957, green: 0.949, blue: 0.929))

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Text(tab.rawValue).font(Theme.serif(30)); Spacer()
                        Button(action: close) { Icon("xmark", 15) }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted)
                    }
                    switch tab {
                    case .general: GeneralTab()
                    case .system: SystemTab()
                    case .notetaker: NotetakerTab()
                    case .ai: AITab()
                    case .model: ModelTab()
                    case .privacy: PrivacyTab()
                    }
                }.padding(.horizontal, 44).padding(.vertical, 40)
            }.background(Color.white)
        }
        .frame(width: 960, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
            SettingRow(title: "Dictation language", detail: languageNote, last: true) {
                Dropdown(selection: $store.settings.language, options: Self.languages.map { ($0.0, $0.1) }, width: 160)
            }
        }
        .onAppear { mics = AudioDevices.inputs() }
    }
    private var languageNote: String {
        (WhisperModel.all.first { $0.id == store.settings.model }?.multilingual ?? false) ? "Whisper will transcribe in this language." : "English-only model selected. Pick a multilingual model to change language."
    }
    static let languages = [("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("nl", "Dutch"), ("hi", "Hindi"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("ar", "Arabic"), ("ru", "Russian"), ("auto", "Auto-detect")]
}

struct SystemTab: View {
    @ObservedObject var store = AppStore.shared
    var body: some View {
        Card {
            SettingRow(title: "Launch Rattle at login", detail: "Start in the menu bar when you sign in.") {
                Toggle("", isOn: Binding(get: { store.settings.launchAtLogin }, set: { on in
                    store.settings.launchAtLogin = on
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                })).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: "Show app in Dock", detail: "Otherwise Rattle lives only in the menu bar.") {
                Toggle("", isOn: Binding(get: { store.settings.showInDock }, set: {
                    store.settings.showInDock = $0
                    NSApp.setActivationPolicy($0 ? .regular : .accessory)
                })).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: "Show Flow Bar", detail: "The pill at the bottom of your screen while dictating.") {
                Toggle("", isOn: Binding(get: { store.settings.showFlowBar }, set: {
                    store.settings.showFlowBar = $0
                    (NSApp.delegate as? AppDelegate)?.flowBar.setVisible($0)
                })).toggleStyle(.switch).labelsHidden()
            }
            SettingRow(title: "Dictation sounds", detail: "Play a soft cue when dictation starts and stops.", last: true) {
                Toggle("", isOn: $store.settings.soundsEnabled).toggleStyle(.switch).labelsHidden()
            }
        }
    }
}

struct ModelTab: View {
    @ObservedObject var store = AppStore.shared
    @ObservedObject var dl = ModelDownloader.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rattle transcribes on your Mac with whisper.cpp. Audio never leaves your device.").font(.system(size: 13.5)).foregroundStyle(Theme.muted)
            Card {
                ForEach(Array(WhisperModel.all.enumerated()), id: \.element.id) { i, m in
                    SettingRow(title: m.title, detail: m.size + (m.installed ? " · Downloaded" : ""), last: i == WhisperModel.all.count - 1) {
                        HStack(spacing: 10) {
                            if let p = dl.progress[m.id] { ProgressView(value: p).frame(width: 90) }
                            else if !m.installed { PillButton(title: "Download") { dl.download(m) } }
                            if m.installed {
                                if store.settings.model == m.id { Label { Text("Active") } icon: { Icon("checkmark.circle.fill", 14) }.font(.system(size: 12.5, weight: .medium)).foregroundStyle(.green) }
                                else { PillButton(title: "Use") { store.settings.model = m.id } }
                            }
                        }
                    }
                }
            }
            if let e = dl.error { Text(e).font(.system(size: 12)).foregroundStyle(.red) }
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
            SettingRow(title: "Local-only processing", detail: "Transcription runs on-device. No audio or text is sent anywhere.") { Icon("lock.fill", 16).foregroundStyle(Theme.muted) }
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
                    Toggle("", isOn: $store.settings.notetakerCaptureSystemAudio).toggleStyle(.switch).labelsHidden()
                }
                SettingRow(title: "Write notes automatically", detail: "When a recording ends, summarize it with your AI model (title, summary, decisions, action items).", last: true) {
                    Toggle("", isOn: $store.settings.notetakerSummaries).toggleStyle(.switch).labelsHidden()
                }
            }
            Text("Transcription uses your on-device speech model. Only the transcript text is sent to your AI model, and with a local model it never leaves this Mac.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
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
            Text("Notetaker summaries and Transforms use any OpenAI-compatible server. Rattle defaults to LM Studio running on this Mac.")
                .font(.system(size: 13.5)).foregroundStyle(Theme.muted)
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
                Text(status).font(.system(size: 13)).foregroundStyle(status.hasPrefix("Connected") ? .green : Theme.muted)
            }
            Text("Running LM Studio? Start its server from the Developer tab or with: lms server start")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
        }
        .onAppear { test() }
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
