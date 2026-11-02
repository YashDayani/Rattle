import SwiftUI

private struct NotesHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Rattle's own update dialog, shown over the hub window: the new version's notes, then download, install and restart.
struct UpdateDialog: View {
    @ObservedObject private var updater = Updater.shared
    @State private var notesHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch updater.state {
            case .idle, .checking:
                header("Checking for updates…", "Asking GitHub for the latest release.", spinner: true)
                footer { Spacer(); PillButton(title: "Cancel") { updater.dismiss() }.keyboardShortcut(.cancelAction) }
            case .upToDate:
                header("Rattle is up to date", "You have the latest version, \(updater.currentVersion).", symbol: "checkmark.circle.fill")
                footer { Spacer(); PillButton(title: "OK", prominent: true) { updater.dismiss() }.keyboardShortcut(.defaultAction) }
            case .available(let offer):
                header("A new version of Rattle is available",
                       "Rattle \(offer.version) is ready to install. You have \(updater.currentVersion) · \(ByteCountFormatter.string(fromByteCount: offer.size, countStyle: .file)) download.")
                changelog(offer)
                footer {
                    Button { NSWorkspace.shared.open(offer.pageURL) } label: {
                        Text("Release page").font(Theme.sans(13, .medium)).foregroundStyle(Theme.muted).underline()
                    }.buttonStyle(.press).pointer()
                    Spacer()
                    PillButton(title: "Skip this version") { updater.skip(offer) }
                    PillButton(title: "Later") { updater.dismiss() }.keyboardShortcut(.cancelAction)
                    PillButton(title: "Install & restart", prominent: true) { updater.install(offer) }.keyboardShortcut(.defaultAction)
                }
            case .working(let text, let fraction):
                header("Updating Rattle", text)
                VStack(alignment: .leading, spacing: 8) {
                    if let fraction {
                        ProgressView(value: fraction).tint(Theme.ink)
                        Text("\(Int(fraction * 100))%").font(Theme.sans(12)).foregroundStyle(Theme.muted).monospacedDigit()
                    } else {
                        ProgressView().progressViewStyle(.linear).tint(Theme.ink)
                    }
                    Text("Rattle restarts by itself when this is done. Your dictations, notes and settings are not touched.")
                        .font(Theme.sans(12)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 28).padding(.bottom, 28)
            case .failed(let message):
                header("The update didn’t finish", message, symbol: "exclamationmark.triangle.fill", tint: Theme.warn)
                footer { Spacer(); PillButton(title: "OK", prominent: true) { updater.dismiss() }.keyboardShortcut(.defaultAction) }
            case .revealed:
                header("The new version is ready",
                       "Rattle can’t replace itself where it is installed, so the new version is shown in Finder. Quit Rattle and drag the new app over the old one (for example into Applications).",
                       symbol: "folder.fill")
                footer { Spacer(); PillButton(title: "OK", prominent: true) { updater.dismiss() }.keyboardShortcut(.defaultAction) }
            }
        }
        .frame(width: 500)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.xl).fill(Theme.page).shadow(color: .black.opacity(0.18), radius: 30, y: 12))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.xl).stroke(Theme.line))
    }

    private func header(_ title: String, _ subtitle: String?, symbol: String? = nil, tint: Color = Theme.ink, spinner: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AppIconView(size: 56)
                .overlay(alignment: .bottomTrailing) {
                    if let symbol {
                        Icon(symbol, 22).foregroundStyle(tint)
                            .background(Circle().fill(Theme.page).padding(2))
                            .offset(x: 6, y: 6)
                    }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(title).font(Theme.serif(26)).tracking(-0.6).foregroundStyle(Theme.ink)
                    if spinner { ProgressView().controlSize(.small) }
                }
                if let subtitle {
                    Text(subtitle).font(Theme.sans(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
    }

    private func footer<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 8) { content() }.padding(.horizontal, 28).padding(.vertical, 18)
    }

    private func changelog(_ offer: UpdateOffer) -> some View {
        let lines = ReleaseNotes.parse(offer.notes)
        return VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.line)
            Text("What’s new in \(offer.version)").font(Theme.sans(12, .semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    if lines.isEmpty { Text("Bug fixes and improvements.").font(Theme.sans(13)).foregroundStyle(Theme.muted) }
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in row(line) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GeometryReader { Color.clear.preference(key: NotesHeightKey.self, value: $0.size.height) })
            }
            .frame(height: min(max(notesHeight, 40), 200))
            .onPreferenceChange(NotesHeightKey.self) { notesHeight = $0 }
            Divider().overlay(Theme.line)
        }
        .padding(.horizontal, 28)
    }

    @ViewBuilder private func row(_ line: ReleaseNotes.Line) -> some View {
        switch line {
        case .heading(let t):
            Text(t).font(Theme.sans(13, .semibold)).foregroundStyle(Theme.ink).padding(.top, 6)
        case .bullet(let t):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Theme.muted)
                Text(t).fixedSize(horizontal: false, vertical: true)
            }.font(Theme.sans(13)).foregroundStyle(Theme.ink)
        case .text(let t):
            Text(t).font(Theme.sans(13)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}
