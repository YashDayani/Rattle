import SwiftUI
import Cocoa

// Icons are from Lucide (https://lucide.dev), ISC License, Copyright (c) Lucide Icons and Contributors.
// Some are derived from Feather, MIT License, Copyright (c) 2013-present Cole Bemis.
// Full notices: scripts/lucide-LICENSE.txt (copied into the app bundle by scripts/build.sh).
// Generated from lucide-static 1.56.0; add an icon by adding its SF Symbol name and Lucide body below.

/// Draws the Lucide counterpart of an SF Symbol name, so call sites keep the names they already use.
struct Icon: View {
    let name: String
    let size: CGFloat
    init(_ name: String, _ size: CGFloat = 16) { self.name = name; self.size = size }
    var body: some View {
        if let image = Lucide.image(name) {
            Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: name).font(.system(size: size * 0.8))
        }
    }
}

@MainActor
enum Lucide {
    private static var cache: [String: NSImage] = [:]

    /// Template image for an SF Symbol name, or nil when there is no Lucide counterpart.
    static func image(_ symbol: String, size: CGFloat? = nil) -> NSImage? {
        guard let body = bodies[symbol] else { return nil }
        let base: NSImage
        if let hit = cache[symbol] { base = hit } else {
            let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\" fill=\"none\" stroke=\"#000\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\">\(body)</svg>"
            guard let made = NSImage(data: Data(svg.utf8)) else { return nil }
            made.isTemplate = true
            cache[symbol] = made
            base = made
        }
        guard let size, let copy = base.copy() as? NSImage else { return base }
        copy.size = NSSize(width: size, height: size)
        copy.isTemplate = true
        return copy
    }

    /// SF Symbol name -> Lucide icon body (the name in the comment is the Lucide icon).
    private static let bodies: [String: String] = [
        "arrow.clockwise": #"<path d="M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8" /><path d="M21 3v5h-5" />"#,   // rotate-cw
        "arrow.up.arrow.down": #"<path d="m21 16-4 4-4-4" /><path d="M17 20V4" /><path d="m3 8 4-4 4 4" /><path d="M7 4v16" />"#,   // arrow-up-down
        "arrow.down.right": #"<path d="m7 7 10 10" /><path d="M17 7v10H7" />"#,   // arrow-down-right
        "arrow.right": #"<path d="M5 12h14" /><path d="m12 5 7 7-7 7" />"#,   // arrow-right
        "arrow.up.circle.fill": #"<circle cx="12" cy="12" r="10" /><path d="m16 12-4-4-4 4" /><path d="M12 16V8" />"#,   // circle-arrow-up
        "arrow.up.right": #"<path d="M7 7h10v10" /><path d="M7 17 17 7" />"#,   // arrow-up-right
        "bell": #"<path d="M10.268 21a2 2 0 0 0 3.464 0" /><path d="M3.262 15.326A1 1 0 0 0 4 17h16a1 1 0 0 0 .74-1.673C19.41 13.956 18 12.499 18 8A6 6 0 0 0 6 8c0 4.499-1.411 5.956-2.738 7.326" />"#,   // bell
        "bell.slash": #"<path d="M10.268 21a2 2 0 0 0 3.464 0" /><path d="M17 17H4a1 1 0 0 1-.74-1.673C4.59 13.956 6 12.499 6 8a6 6 0 0 1 .258-1.742" /><path d="m2 2 20 20" /><path d="M8.668 3.01A6 6 0 0 1 18 8c0 2.687.77 4.653 1.707 6.05" />"#,   // bell-off
        "bubble.left": #"<path d="M2.992 16.342a2 2 0 0 1 .094 1.167l-1.065 3.29a1 1 0 0 0 1.236 1.168l3.413-.998a2 2 0 0 1 1.099.092 10 10 0 1 0-4.777-4.719" />"#,   // message-circle
        "chart.bar": #"<path d="M3 3v16a2 2 0 0 0 2 2h16" /><path d="M18 17V9" /><path d="M13 17V5" /><path d="M8 17v-3" />"#,   // chart-column
        "checkmark": #"<path d="M20 6 9 17l-5-5" />"#,   // check
        "checkmark.circle.fill": #"<circle cx="12" cy="12" r="10" /><path d="m16 9-5.5 5.5L8 12" />"#,   // circle-check
        "checkmark.square.fill": #"<rect width="18" height="18" x="3" y="3" rx="2" /><path d="m16 9-5.5 5.5L8 12" />"#,   // square-check
        "chevron.down": #"<path d="m6 9 6 6 6-6" />"#,   // chevron-down
        "circle": #"<circle cx="12" cy="12" r="10" />"#,   // circle
        "cpu": #"<path d="M12 20v2" /><path d="M12 2v2" /><path d="M17 20v2" /><path d="M17 2v2" /><path d="M2 12h2" /><path d="M2 17h2" /><path d="M2 7h2" /><path d="M20 12h2" /><path d="M20 17h2" /><path d="M20 7h2" /><path d="M7 20v2" /><path d="M7 2v2" /><rect x="4" y="4" width="16" height="16" rx="2" /><rect x="8" y="8" width="8" height="8" rx="1" />"#,   // cpu
        "desktopcomputer": #"<rect width="20" height="14" x="2" y="3" rx="2" /><line x1="8" x2="16" y1="21" y2="21" /><line x1="12" x2="12" y1="17" y2="21" />"#,   // monitor
        "doc.on.doc": #"<rect width="14" height="14" x="8" y="8" rx="2" ry="2" /><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2" />"#,   // copy
        "doc.text": #"<path d="M6 22a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h8a2.4 2.4 0 0 1 1.704.706l3.588 3.588A2.4 2.4 0 0 1 20 8v12a2 2 0 0 1-2 2z" /><path d="M14 2v5a1 1 0 0 0 1 1h5" /><path d="M10 9H8" /><path d="M16 13H8" /><path d="M16 17H8" />"#,   // file-text
        "envelope": #"<path d="m22 7-8.991 5.727a2 2 0 0 1-2.009 0L2 7" /><rect x="2" y="4" width="20" height="16" rx="2" />"#,   // mail
        "exclamationmark.triangle.fill": #"<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3" /><path d="M12 9v4" /><path d="M12 17h.01" />"#,   // triangle-alert
        "flame": #"<path d="M12 3q1 4 4 6.5t3 5.5a1 1 0 0 1-14 0 5 5 0 0 1 1-3 1 1 0 0 0 5 0c0-2-1.5-3-1.5-5q0-2 2.5-4" />"#,   // flame
        "gearshape": #"<path d="M9.671 4.136a2.34 2.34 0 0 1 4.659 0 2.34 2.34 0 0 0 3.319 1.915 2.34 2.34 0 0 1 2.33 4.033 2.34 2.34 0 0 0 0 3.831 2.34 2.34 0 0 1-2.33 4.033 2.34 2.34 0 0 0-3.319 1.915 2.34 2.34 0 0 1-4.659 0 2.34 2.34 0 0 0-3.32-1.915 2.34 2.34 0 0 1-2.33-4.033 2.34 2.34 0 0 0 0-3.831A2.34 2.34 0 0 1 6.35 6.051a2.34 2.34 0 0 0 3.319-1.915" /><circle cx="12" cy="12" r="3" />"#,   // settings
        "hands.sparkles.fill": #"<path d="M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2" /><path d="M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2" /><path d="M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8" /><path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15" />"#,   // hand
        "infinity": #"<path d="M6 16c5 0 7-8 12-8a4 4 0 0 1 0 8c-5 0-7-8-12-8a4 4 0 1 0 0 8" />"#,   // infinity
        "laptopcomputer": #"<path d="M18 5a2 2 0 0 1 2 2v8.526a2 2 0 0 0 .212.897l1.068 2.127a1 1 0 0 1-.9 1.45H3.62a1 1 0 0 1-.9-1.45l1.068-2.127A2 2 0 0 0 4 15.526V7a2 2 0 0 1 2-2z" /><path d="M20.054 15.987H3.946" />"#,   // laptop
        "lock.fill": #"<rect width="18" height="11" x="3" y="11" rx="2" ry="2" /><path d="M7 11V7a5 5 0 0 1 10 0v4" />"#,   // lock
        "magnifyingglass": #"<path d="m21 21-4.34-4.34" /><circle cx="11" cy="11" r="8" />"#,   // search
        "mic": #"<path d="M12 19v3" /><path d="M19 10v2a7 7 0 0 1-14 0v-2" /><rect x="9" y="2" width="6" height="13" rx="3" />"#,   // mic
        "note.text": #"<path d="M8 2v4" /><path d="M12 2v4" /><path d="M16 2v4" /><rect width="16" height="18" x="4" y="4" rx="2" /><path d="M8 10h6" /><path d="M8 14h8" /><path d="M8 18h5" />"#,   // notepad-text
        "pencil": #"<path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z" /><path d="m15 5 4 4" />"#,   // pencil
        "person.crop.circle": #"<path d="M17.925 20.056a6 6 0 0 0-11.851.001" /><circle cx="12" cy="11" r="4" /><circle cx="12" cy="12" r="10" />"#,   // circle-user-round
        "person.wave.2.fill": #"<path d="M8.8 20v-4.1l1.9.2a2.3 2.3 0 0 0 2.164-2.1V8.3A5.37 5.37 0 0 0 2 8.25c0 2.8.656 3.054 1 4.55a5.77 5.77 0 0 1 .029 2.758L2 20" /><path d="M19.8 17.8a7.5 7.5 0 0 0 .003-10.603" /><path d="M17 15a3.5 3.5 0 0 0-.025-4.975" />"#,   // speech
        "questionmark.circle": #"<circle cx="12" cy="12" r="10" /><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" /><path d="M12 17h.01" />"#,   // circle-help
        "record.circle": #"<circle cx="12" cy="12" r="1" /><circle cx="12" cy="12" r="10" />"#,   // circle-dot
        "scissors": #"<circle cx="6" cy="6" r="3" /><path d="M8.12 8.12 12 12" /><path d="M20 4 8.12 15.88" /><circle cx="6" cy="18" r="3" /><path d="M14.8 14.8 20 20" />"#,   // scissors
        "shield": #"<path d="M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z" />"#,   // shield
        "sidebar.left": #"<rect width="18" height="18" x="3" y="3" rx="2" /><path d="M9 3v18" />"#,   // panel-left
        "slider.horizontal.3": #"<path d="M10 5H3" /><path d="M12 19H3" /><path d="M14 3v4" /><path d="M16 17v4" /><path d="M21 12h-9" /><path d="M21 19h-5" /><path d="M21 5h-7" /><path d="M8 10v4" /><path d="M8 12H3" />"#,   // sliders-horizontal
        "sparkles": #"<path d="M11.017 2.814a1 1 0 0 1 1.966 0l1.051 5.558a2 2 0 0 0 1.594 1.594l5.558 1.051a1 1 0 0 1 0 1.966l-5.558 1.051a2 2 0 0 0-1.594 1.594l-1.051 5.558a1 1 0 0 1-1.966 0l-1.051-5.558a2 2 0 0 0-1.594-1.594l-5.558-1.051a1 1 0 0 1 0-1.966l5.558-1.051a2 2 0 0 0 1.594-1.594z" /><path d="M20 2v4" /><path d="M22 4h-4" /><circle cx="4" cy="20" r="2" />"#,   // sparkles
        "speaker.wave.2": #"<path d="M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z" /><path d="M16 9a5 5 0 0 1 0 6" /><path d="M19.364 18.364a9 9 0 0 0 0-12.728" />"#,   // volume-2
        "speedometer": #"<path d="m12 14 4-4" /><path d="M3.34 19a10 10 0 1 1 17.32 0" />"#,   // gauge
        "square": #"<rect width="18" height="18" x="3" y="3" rx="2" />"#,   // square
        "square.and.arrow.up": #"<path d="M12 2v13" /><path d="m16 6-4-4-4 4" /><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" />"#,   // share
        "sun.max.fill": #"<circle cx="12" cy="12" r="4" /><path d="M12 2v2" /><path d="M12 20v2" /><path d="m4.93 4.93 1.41 1.41" /><path d="m17.66 17.66 1.41 1.41" /><path d="M2 12h2" /><path d="M20 12h2" /><path d="m6.34 17.66-1.41 1.41" /><path d="m19.07 4.93-1.41 1.41" />"#,   // sun
        "text.book.closed": #"<path d="M4 19.5v-15A2.5 2.5 0 0 1 6.5 2H19a1 1 0 0 1 1 1v18a1 1 0 0 1-1 1H6.5a1 1 0 0 1 0-5H20" /><path d="m8 13 4-7 4 7" /><path d="M9.1 11h5.7" />"#,   // book-a
        "text.bubble": #"<path d="M22 17a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 21.286V5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2z" /><path d="M7 11h10" /><path d="M7 15h6" /><path d="M7 7h8" />"#,   // message-square-text
        "text.word.spacing": #"<circle cx="7" cy="12" r="3" /><path d="M10 9v6" /><circle cx="17" cy="12" r="3" /><path d="M14 7v8" /><path d="M22 17v1c0 .5-.5 1-1 1H3c-.5 0-1-.5-1-1v-1" />"#,   // whole-word
        "textformat": #"<path d="M12 4v16" /><path d="M4 7V5a1 1 0 0 1 1-1h14a1 1 0 0 1 1 1v2" /><path d="M9 20h6" />"#,   // type
        "trash": #"<path d="M10 11v6" /><path d="M14 11v6" /><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6" /><path d="M3 6h18" /><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" />"#,   // trash-2
        "wand.and.stars": #"<path d="m21.64 3.64-1.28-1.28a1.21 1.21 0 0 0-1.72 0L2.36 18.64a1.21 1.21 0 0 0 0 1.72l1.28 1.28a1.2 1.2 0 0 0 1.72 0L21.64 5.36a1.2 1.2 0 0 0 0-1.72" /><path d="m14 7 3 3" /><path d="M5 6v4" /><path d="M19 14v4" /><path d="M10 2v2" /><path d="M7 8H3" /><path d="M21 16h-4" /><path d="M11 3H9" />"#,   // wand-sparkles
        "waveform": #"<path d="M2 10v3" /><path d="M6 6v11" /><path d="M10 3v18" /><path d="M14 8v7" /><path d="M18 5v13" /><path d="M22 10v3" />"#,   // audio-lines
        "waveform.badge.mic": #"<path d="M2 10v3" /><path d="M6 6v11" /><path d="M10 3v18" /><path d="M14 8v7" /><path d="M18 5v13" /><path d="M22 10v3" />"#,   // audio-lines
        "xmark": #"<path d="M18 6 6 18" /><path d="m6 6 12 12" />"#,   // x
        "xmark.circle": #"<circle cx="12" cy="12" r="10" /><path d="m15 9-6 6" /><path d="m9 9 6 6" />"#,   // circle-x
    ]
}
