import Cocoa

/// The recoloured Open Doodles shown on each onboarding step (see scripts/make-onboarding-art.py).
@MainActor
enum OnboardingArt {
    private static var cache: [OnboardingStep: NSImage] = [:]

    static func file(for step: OnboardingStep) -> String {
        switch step {
        case .name: return "loving"
        case .look: return "swinging"
        case .permissions: return "unboxing"
        case .engine: return "sitting-reading"
        case .key: return "groovy"
        case .done: return "jumping"
        }
    }

    /// Inside the app bundle when built with scripts/build.sh; the repo's Onboarding folder under `swift run` and tests.
    static func url(for step: OnboardingStep) -> URL? {
        let name = "\(file(for: step)).svg"
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("Onboarding/\(name)")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Onboarding/\(name)")
        return [bundled, repo].compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func image(for step: OnboardingStep) -> NSImage? {
        if let hit = cache[step] { return hit }
        guard let url = url(for: step), let image = NSImage(contentsOf: url) else { return nil }
        cache[step] = image
        return image
    }
}
