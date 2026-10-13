import SwiftUI

enum Theme {
    static let window = Color(red: 0.961, green: 0.957, blue: 0.941)
    static let panel = Color.white
    static let card = Color(red: 0.961, green: 0.957, blue: 0.941)
    static let button = Color(red: 0.933, green: 0.922, blue: 0.890)
    static let selected = Color(red: 0.933, green: 0.922, blue: 0.890)
    static let ink = Color(red: 0.102, green: 0.102, blue: 0.102)
    static let muted = Color(red: 0.443, green: 0.443, blue: 0.431)
    static let line = Color(red: 0.933, green: 0.922, blue: 0.890)
    static let accent = Color(red: 0.102, green: 0.102, blue: 0.102)

    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

struct PillButton: View {
    let title: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Theme.ink)
                .padding(.horizontal, 16).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(prominent ? Theme.ink : Theme.button))
        }.buttonStyle(.plain).pointer()
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}

struct SettingRow<Trailing: View>: View {
    let title: String
    let detail: String
    var last = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 14.5, weight: .semibold)).foregroundStyle(Theme.ink)
                    Text(detail).font(.system(size: 13.5)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 16)
                trailing
            }.padding(.horizontal, 26).padding(.vertical, 22)
            if !last { Divider().overlay(Theme.line).padding(.horizontal, 26) }
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.ink)
                if let s = subtitle { Text(s).font(.system(size: 14)).foregroundStyle(Theme.muted) }
            }
            Spacer()
            trailing
        }
    }
}

/// Drop-in replacement for @State. The Command Line Tools toolchain ships without
/// the SwiftUIMacros plugin that the SDK's @State needs, so we build the same thing on @StateObject.
final class StateBox<V>: ObservableObject {
    @Published var value: V
    init(_ v: V) { value = v }
}

@propertyWrapper
struct LocalState<V>: DynamicProperty {
    @StateObject private var box: StateBox<V>
    init(wrappedValue: V) { _box = StateObject(wrappedValue: StateBox(wrappedValue)) }
    var wrappedValue: V {
        get { box.value }
        nonmutating set { box.value = newValue }
    }
    var projectedValue: Binding<V> { Binding(get: { box.value }, set: { box.value = $0 }) }
}

/// Pointing-hand cursor while the mouse is over a clickable view.
private struct PointerCursor: ViewModifier {
    @LocalState private var inside = false
    func body(content: Content) -> some View {
        content
            .onHover { h in
                guard h != inside else { return }
                inside = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onDisappear { if inside { inside = false; NSCursor.pop() } }
    }
}

extension View {
    func pointer() -> some View { modifier(PointerCursor()) }
}

struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? AppDelegate.icon())
            .resizable().interpolation(.high).frame(width: size, height: size)
    }
}
