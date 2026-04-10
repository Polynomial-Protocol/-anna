import Foundation

struct OnboardingState: Sendable {
    var currentStep: Int = 0

    /// Steps: 0 = welcome, 1 = capabilities, 2 = CLI check, 3 = permissions, 4 = done
    static let totalSteps = 5

    var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: "anna_onboarding_complete") }
        set { UserDefaults.standard.set(newValue, forKey: "anna_onboarding_complete") }
    }
}
