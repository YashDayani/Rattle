import AVFoundation

/// The first-run onboarding steps, in order.
enum OnboardingStep: Int, CaseIterable {
    case name, look, permissions, engine, key, done
}

/// What the onboarding needs to know to decide whether a step can be left.
struct OnboardingChecks {
    var name: String
    var micGranted: Bool
    var axGranted: Bool
    var engine: SpeechEngine
    var localModelInstalled: Bool
    var whisperInstalled: Bool
    var groqKey: String
}

/// Step order and the rules for Continue and Skip. No UI here, so it can be tested.
enum OnboardingFlow {
    /// Right ⌘ is left out: it's the default Command Mode key, and sharing it turns Command Mode off.
    static let keyChoices: [Shortcut] = [.fn, .rightOption, .rightControl]

    static func canContinue(_ step: OnboardingStep, _ c: OnboardingChecks) -> Bool {
        switch step {
        case .name: return !c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .permissions: return c.micGranted && c.axGranted
        case .engine:
            switch c.engine {
            case .local: return c.localModelInstalled && c.whisperInstalled
            case .cloud: return !c.groqKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        case .look, .key, .done: return true
        }
    }

    /// Only the steps that may depend on things outside Rattle (System Settings, Homebrew, a Groq key) can be skipped.
    static func canSkip(_ step: OnboardingStep, _ c: OnboardingChecks) -> Bool {
        (step == .permissions || step == .engine) && !canContinue(step, c)
    }

    /// Once access was denied, macOS won't ask again, so Allow has to open System Settings instead.
    static func micAllowOpensSettings(_ status: AVAuthorizationStatus) -> Bool { status == .denied || status == .restricted }

    static func next(_ step: OnboardingStep) -> OnboardingStep? { OnboardingStep(rawValue: step.rawValue + 1) }
    static func back(_ step: OnboardingStep) -> OnboardingStep? { OnboardingStep(rawValue: step.rawValue - 1) }
}
