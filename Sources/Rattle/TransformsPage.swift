import SwiftUI

struct TransformsPage: View {
    @ObservedObject var store = AppStore.shared
    @LocalState private var editing: Transform? = nil
    @LocalState private var isNew = false
    @LocalState private var testInput = ""
    @LocalState private var testOutput = ""
    @LocalState private var testID = "polish"
    @LocalState private var running = false
    @LocalState private var error: String? = nil
    @LocalState private var status: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Transforms", subtitle: "Apply a Transform to rewrite, clean up, or restructure text after you dictate.") {
                    PillButton(title: "New transform", prominent: true) { editing = Transform(id: UUID().uuidString, name: "", prompt: ""); isNew = true }
                }
                aiStatus
                Card {
                    SettingRow(title: "Auto apply after dictation", detail: "Run a Transform on every dictation before it's inserted. If the AI is slow, the original text is used.") {
                        Dropdown(selection: Binding(get: { store.settings.autoTransformID ?? "" }, set: { store.settings.autoTransformID = $0.isEmpty ? nil : $0 }),
                                 options: [("", "Off")] + store.allTransforms.map { ($0.id, $0.name) }, width: 200)
                    }
                    SettingRow(title: "Command Mode", detail: commandDetail, last: true) {
                        HStack(spacing: 10) {
                            Dropdown(selection: Binding(get: { store.settings.commandShortcut }, set: { store.settings.commandShortcut = $0; DictationController.shared.applyShortcut() }),
                                     options: Shortcut.allCases.map { ($0, $0.title) }, width: 140)
                            Toggle("", isOn: Binding(get: { store.settings.commandModeEnabled }, set: { store.settings.commandModeEnabled = $0; DictationController.shared.applyShortcut() }))
                                .toggleStyle(ThemeSwitchStyle()).labelsHidden()
                        }
                    }
                }

                Text("Your Transforms").font(Theme.sans(13, .semibold)).foregroundStyle(Theme.muted)
                VStack(spacing: 0) {
                    ForEach(store.allTransforms) { t in
                        HStack(alignment: .top, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(t.name).font(Theme.sans(14, .semibold))
                                    if t.builtIn { Text("Built-in").font(Theme.sans(10.5, .medium)).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.button)) }
                                    if store.settings.autoTransformID == t.id { Text("Auto").font(Theme.sans(10.5, .semibold)).foregroundStyle(Theme.onInk).padding(.horizontal, 6).padding(.vertical, 2).background(Capsule().fill(Theme.ink)) }
                                }
                                Text(t.prompt).font(Theme.sans(12.5)).foregroundStyle(Theme.muted).lineLimit(2)
                            }
                            Spacer()
                            if !t.builtIn {
                                Button { editing = t; isNew = false } label: { Icon("pencil", 16) }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted)
                                Button { store.customTransforms.removeAll { $0.id == t.id }; if store.settings.autoTransformID == t.id { store.settings.autoTransformID = nil } } label: { Icon("trash", 16) }.buttonStyle(.plain).pointer().foregroundStyle(Theme.muted)
                            }
                        }
                        .padding(.horizontal, 16).padding(.vertical, 12).overlay(alignment: .bottom) { Divider().overlay(Theme.line) }
                    }
                }.background(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))

                Text("Try it").font(Theme.sans(13, .semibold)).foregroundStyle(Theme.muted).padding(.top, 6)
                Card {
                    VStack(alignment: .leading, spacing: 12) {
                        TextEditor(text: $testInput).font(Theme.sans(14)).scrollContentBackground(.hidden).frame(height: 90).padding(8)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
                            .overlay(alignment: .topLeading) { if testInput.isEmpty { Text("Paste or type some text…").font(Theme.sans(14)).foregroundStyle(Theme.muted).padding(14).allowsHitTesting(false) } }
                        HStack {
                            Dropdown(selection: $testID, options: store.allTransforms.map { ($0.id, $0.name) }, width: 200)
                            PillButton(title: running ? "Working…" : "Run", prominent: true) { run() }.disabled(running || testInput.isEmpty)
                            Spacer()
                        }
                        if let e = error { Text(e).font(Theme.sans(12.5)).foregroundStyle(.red.opacity(0.85)) }
                        if !testOutput.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(testOutput).font(Theme.sans(14)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12).background(RoundedRectangle(cornerRadius: 9).fill(Theme.panel))
                                PillButton(title: "Copy polished text") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(testOutput, forType: .string) }
                            }
                        }
                    }.padding(18)
                }
            }
            .padding(.bottom, 20)
        }
        .onAppear(perform: checkAI)
        .sheet(item: $editing) { t in
            TransformSheet(transform: t, isNew: isNew) { saved in
                if let i = store.customTransforms.firstIndex(where: { $0.id == saved.id }) { store.customTransforms[i] = saved } else { store.customTransforms.append(saved) }
                editing = nil
            } cancel: { editing = nil }
        }
    }

    private var commandDetail: String {
        let k = store.settings.commandShortcut.title
        if store.settings.commandShortcut == store.settings.shortcut { return "Pick a different key from your dictation shortcut." }
        return "Select text in any app, hold \(k) and say what to change (\"make it shorter\"). With nothing selected, say what to write."
    }

    private var aiStatus: some View {
        HStack(spacing: 10) {
            Circle().fill(status == "ok" ? Color.green : (status == nil ? Color.gray : Color.orange)).frame(width: 8, height: 8)
            Text(status == "ok" ? "AI model connected" : (status ?? "Checking AI server…")).font(Theme.sans(13)).foregroundStyle(Theme.ink)
            Spacer()
            PillButton(title: "AI settings") { Router.shared.openSettings(.ai) }
        }.padding(.horizontal, 16).frame(height: 46).background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }

    private func checkAI() {
        status = nil
        Task {
            do { let m = try await LLM.models(LLM.Config(store.settings)); status = m.isEmpty ? "Connected, but no model is loaded" : "ok" }
            catch { status = "AI server offline. Start LM Studio's server or set one up in AI settings." }
        }
    }

    private func run() {
        guard let t = store.transform(id: testID) else { return }
        running = true; error = nil; testOutput = ""
        Task {
            do { testOutput = try await Transforms.run(t, on: testInput, settings: store.settings) }
            catch { self.error = error.localizedDescription }
            running = false
        }
    }
}

struct TransformSheet: View {
    @LocalState private var name: String
    @LocalState private var prompt: String
    let id: String
    let isNew: Bool
    var save: (Transform) -> Void
    var cancel: () -> Void

    init(transform: Transform, isNew: Bool, save: @escaping (Transform) -> Void, cancel: @escaping () -> Void) {
        id = transform.id; self.isNew = isNew; self.save = save; self.cancel = cancel
        _name = LocalState(wrappedValue: transform.name); _prompt = LocalState(wrappedValue: transform.prompt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "New transform" : "Edit transform").font(Theme.serif(24))
            TextField("Name (e.g. Slack reply)", text: $name).textFieldStyle(.roundedBorder)
            Text("Instruction").font(Theme.sans(12, .semibold)).foregroundStyle(Theme.muted)
            TextEditor(text: $prompt).font(Theme.sans(13)).frame(height: 120).overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line))
            Text("Describe how the text should change. Rattle sends your text plus this instruction to your AI model.").font(Theme.sans(12)).foregroundStyle(Theme.muted)
            HStack { Spacer(); PillButton(title: "Cancel", action: cancel)
                PillButton(title: "Save", prominent: true) { save(Transform(id: id, name: name, prompt: prompt)) }.disabled(name.isEmpty || prompt.isEmpty) }
        }.padding(24).frame(width: 460)
    }
}
