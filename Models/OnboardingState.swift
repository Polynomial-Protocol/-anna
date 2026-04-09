import Foundation

struct OnboardingState: Sendable {
    var currentStep: Int = 0

    /// Total steps: 0 = welcome, 1 = permissions, 2 = done
    static let totalSteps = 3

    var isComplete: Bool {
        get { UserDefaults.standard.bool(forKey: "anna_onboarding_complete") }
        set { UserDefaults.standard.set(newValue, forKey: "anna_onboarding_complete") }
    }
}
