import SwiftUI

/// A request for a short name (new folder, rename), shown as Rattle's own dialog over the window.
struct NamePrompt: Identifiable {
    let id = UUID()
    var title: String
    var placeholder: String = "Name"
    var initial: String = ""
    var confirm: String = "Save"
    var onSave: (String) -> Void

    /// The name to save, or nil when it's blank.
    static func cleaned(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

struct NamePromptDialog: View {
    let prompt: NamePrompt
    var close: () -> Void
    @LocalState private var text = ""
    @FocusState private var focused: Bool

    private var name: String? { NamePrompt.cleaned(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(prompt.title).font(Theme.serif(24)).tracking(-0.6).foregroundStyle(Theme.ink).padding(.bottom, 16)
            TextField(prompt.placeholder, text: $text)
                .textFieldStyle(.plain).font(Theme.sans(15)).focused($focused)
                .padding(.horizontal, 13).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.panel))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(focused ? Theme.ink : Theme.line, lineWidth: focused ? 1.5 : 1))
                .onSubmit(save)
            HStack(spacing: 8) {
                Spacer()
                PillButton(title: "Cancel", action: close).keyboardShortcut(.cancelAction)
                PillButton(title: prompt.confirm, prominent: true, action: save)
                    .disabled(name == nil).opacity(name == nil ? 0.4 : 1)
            }
            .padding(.top, 20)
        }
        .padding(24)
        .frame(width: 380)
        // Shadow on the card shape only, so the field and buttons don't each get one.
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl).fill(Theme.page).shadow(color: .black.opacity(0.18), radius: 30, y: 12))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl).stroke(Theme.line))
        .onAppear { text = prompt.initial; focused = true }
    }

    private func save() {
        guard let name else { return }
        prompt.onSave(name)
        close()
    }
}
