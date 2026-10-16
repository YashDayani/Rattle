import SwiftUI

/// Recoloured Open Doodles bundled in Illustrations/ (see scripts/make-illustrations.py).
@MainActor
enum Illustration {
    static let dictationEmpty = "float"
    static let meetingsEmpty = "coffee"
    static let notesEmpty = "reading"

    private static var cache: [String: NSImage] = [:]

    /// Inside the app bundle when built with scripts/build.sh; the repo's Illustrations folder under `swift run` and tests.
    static func url(_ name: String) -> URL? {
        let file = "Illustrations/\(name).svg"
        let bundled = Bundle.main.resourceURL?.appendingPathComponent(file)
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(file)
        return [bundled, repo].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = url(name), let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// An illustration on its own, sized by height; draws nothing if the file is missing.
struct IllustrationView: View {
    let name: String
    var height: CGFloat = 150
    var body: some View {
        if let image = Illustration.image(name) {
            Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit).frame(height: height)
                .accessibilityHidden(true)
        }
    }
}
