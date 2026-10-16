import Cocoa

/// The recoloured Open Doodles shown on each onboarding step (see scripts/make-illustrations.py).
@MainActor
enum OnboardingArt {
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

    static func url(for step: OnboardingStep) -> URL? { Illustration.url(file(for: step)) }
    static func image(for step: OnboardingStep) -> NSImage? { Illustration.image(file(for: step)) }
}
