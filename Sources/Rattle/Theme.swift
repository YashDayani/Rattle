import SwiftUI

enum Theme {
    /// A colour that follows the current appearance: `light` in Aqua, `dark` in Dark Aqua (both 0xRRGGBB).
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
        })
    }

    static let window = dyn(0xf5f4f0, 0x202020)
    static let panel = dyn(0xffffff, 0x1a1a1a)      // inputs, menus and the settings sheet
    static let card = dyn(0xf5f4f0, 0x202020)
    static let button = dyn(0xeeebe3, 0x30302f)
    static let selected = dyn(0xeeebe3, 0x30302f)
    static let ink = dyn(0x1a1a1a, 0xe9e8e1)
    static let muted = dyn(0x71716e, 0x9d9c98)
    static let line = dyn(0xeeebe3, 0x30302f)
    static let accent = ink
    static let onInk = dyn(0xffffff, 0x1a1a1a)      // text and glyphs on an ink-filled control
    static let switchOff = dyn(0xc5c0b3, 0x5b5b59)
    static let heroInk = Color(red: 0.102, green: 0.102, blue: 0.102)   // dark text on the always-light controls inside hero cards
    static let heroField = Color.white.opacity(0.95)                    // always-light inputs inside hero cards
    static let warn = dyn(0xf28c1a, 0xf5a04a)                           // amber notices
    static let speaker = dyn(0x3366b3, 0x7ba7e0)                        // the other party in a transcript

    /// Corner-radius scale. Use these instead of literals so every surface shares one rhythm.
    enum Radius {
        static let xs: CGFloat = 4    // small hover chips, close buttons
        static let sm: CGFloat = 6    // inputs, dropdowns, menu items
        static let md: CGFloat = 8    // buttons, list rows, tooltips
        static let lg: CGFloat = 16   // cards and panels
        static let xl: CGFloat = 20   // hero banners
    }

    /// Shared animation curves.
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.15)      // hover, toggles, small state changes
        static let standard = Animation.easeOut(duration: 0.2)    // panels, sidebar, chevrons
        static let spring = Animation.spring(response: 0.25, dampingFraction: 0.9)   // tooltips, pop-ins
    }

    @MainActor static func apply(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { Font.custom("Figtree", size: size).weight(weight) }
    static func serif(_ size: CGFloat) -> Font { Font.custom("EB Garamond", size: size) }

    /// Registers the bundled fonts (Resources/Fonts) for this process. Without them the custom fonts fall back to the system font.
    static func registerFonts() {
        guard let dir = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}

struct PillButton: View {
    let title: String
    var prominent = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(Theme.sans(13, .semibold))
                .foregroundStyle(prominent ? Theme.onInk : Theme.ink)
                .padding(.horizontal, 16).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(prominent ? Theme.ink : Theme.button))
        }.buttonStyle(.press).pointer()
    }
}

/// Switch drawn in theme colours: ink track when on, neutral when off.
struct ThemeSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Capsule().fill(configuration.isOn ? Theme.ink : Theme.switchOff)
            .frame(width: 42, height: 25)
            .overlay(alignment: .leading) {
                Circle().fill(configuration.isOn ? Theme.page : Color.white)
                    .frame(width: 21, height: 21).padding(2).offset(x: configuration.isOn ? 17 : 0)
            }
            .animation(Theme.Motion.quick, value: configuration.isOn)
            .contentShape(Capsule())
            .onTapGesture { configuration.isOn.toggle() }
            .pointer()
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.card))
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
                    Text(detail).font(Theme.sans(15)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 16)
                trailing
            }.padding(.horizontal, 20).padding(.vertical, 16)
            if !last { Divider().overlay(Theme.line).padding(.horizontal, 20) }
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
                Text(title).font(Theme.sans(24, .semibold)).foregroundStyle(Theme.ink)
                if let s = subtitle { Text(s).font(Theme.sans(15)).foregroundStyle(Theme.muted) }
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
/// macOS 15 and later use SwiftUI's own pointer style, which the hosting view applies and keeps through re-renders and animations.
/// macOS 14 has no such API, so it pushes the cursor on hover instead.
private struct PointerCursor: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) { content.pointerStyle(.link) } else { content.modifier(PushedPointerCursor()) }
    }
}

private struct PushedPointerCursor: ViewModifier {
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
    /// For views inside a floating panel that is not the key window (such as the dropdown menu), where SwiftUI's pointer style
    /// does not take effect: pushes the pointing hand on hover instead.
    func panelPointer() -> some View { modifier(PushedPointerCursor()) }
}

/// Plain button with a subtle press response. Pair it with `.pointer()`: `.buttonStyle(.press).pointer()`.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PressBody(configuration: configuration) }

    private struct PressBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var focused
        var body: some View {
            configuration.label
                .opacity(configuration.isPressed ? 0.75 : 1)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).strokeBorder(Theme.ink.opacity(0.4), lineWidth: 2).opacity(focused ? 1 : 0))
                .animation(Theme.Motion.quick, value: configuration.isPressed)
        }
    }
}

/// Centred empty-list message: a muted glyph, a title and an optional hint. Used by every list page.
struct EmptyState: View {
    let icon: String
    let title: String
    var detail: String? = nil
    /// Shown instead of the icon when set (an Illustration name).
    var illustration: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            if let illustration { IllustrationView(name: illustration, height: 150).padding(.bottom, 10) }
            else { Icon(icon, 24).foregroundStyle(Theme.muted).padding(.bottom, 4) }
            Text(title).font(Theme.sans(15, .medium)).foregroundStyle(Theme.ink)
            if let detail { Text(detail).font(Theme.sans(15)).foregroundStyle(Theme.muted).multilineTextAlignment(.center) }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 48)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
extension ButtonStyle where Self == PressStyle { static var press: PressStyle { PressStyle() } }

/// Dark label bubble used by every tooltip: the sidebar's, and `.tip(_:)`.
struct TipBubble: View {
    let text: String
    var on = true
    var body: some View {
        Text(text).font(Theme.sans(12)).foregroundStyle(Theme.onInk)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.md).fill(Theme.ink))
            .scaleEffect(on ? 1 : 0.9)
            .opacity(on ? 1 : 0)
            .animation(Theme.Motion.spring, value: on)
    }
}

private struct Tip: ViewModifier {
    let text: String
    let edge: Edge
    let alignEnd: Bool
    @LocalState private var show = false
    @LocalState private var generation = 0
    func body(content: Content) -> some View {
        content
            .onHover { inside in
                generation += 1
                let g = generation
                if inside && !text.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { if generation == g { show = true } }
                } else { show = false }
            }
            .overlay {
                GeometryReader { g in
                    if edge == .trailing {
                        TipBubble(text: text, on: show)
                            .frame(width: g.size.width, height: g.size.height, alignment: .leading)
                            .offset(x: g.size.width + 4)
                    } else {
                        TipBubble(text: text, on: show)
                            .frame(width: g.size.width, height: g.size.height, alignment: alignEnd ? .topTrailing : .top)
                            .offset(y: g.size.height + 4)
                    }
                }.allowsHitTesting(false)
            }
            .accessibilityLabel(text)
            .zIndex(show ? 10 : 0)
    }
}

extension View {
    /// Themed tooltip after a short hover delay. `.bottom` (default) sits under the view, `.trailing` to its right. `alignEnd` right-aligns a bottom tip to the view (for controls at the window's right edge). Empty text shows nothing.
    func tip(_ text: String, edge: Edge = .bottom, alignEnd: Bool = false) -> some View { modifier(Tip(text: text, edge: edge, alignEnd: alignEnd)) }
}

struct AppIconView: View {
    var size: CGFloat
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? AppDelegate.icon())
            .resizable().interpolation(.high).frame(width: size, height: size)
    }
}
