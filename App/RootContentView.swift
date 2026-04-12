import SwiftUI

struct RootContentView: View {
    @EnvironmentObject private var container: AppContainer

    var body: some View {
        ZStack {
            AnnaPalette.canvas.ignoresSafeArea()

            if container.onboardingState.isComplete {
                AnnaWorkspaceView(
                    assistantViewModel: container.assistantViewModel,
                    permissionsViewModel: container.permissionsViewModel,
                    settingsViewModel: container.settingsViewModel,
                    logger: container.logger,
                    knowledgeStore: container.knowledgeStore,
                    tourGuideStore: container.tourGuideStore
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                OnboardingView(
                    state: $container.onboardingState,
                    permissionsViewModel: container.permissionsViewModel,
                    speechModelViewModel: container.speechModelViewModel,
                    ttsService: container.ttsService
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: container.onboardingState.isComplete)
    }
}
