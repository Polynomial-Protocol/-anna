import SwiftUI

@MainActor
final class AppContainer: ObservableObject {
    let permissionService: PermissionService
    let audioCaptureService: AudioCaptureService
    let voiceService: VoiceTranscriptionService
    let speechModelService: SpeechModelService
    let textInsertionService: TextInsertionService
    let screenCaptureService: ScreenCaptureService
    let ttsService: TTSService
    let hotkeyMonitor: ModifierKeyMonitor
    let engine: AssistantEngine

    let responseBubbleController: ResponseBubbleController
    let textBarController: TextBarController
    let pointerOverlayManager: PointerOverlayManager
    let knowledgeStore: KnowledgeStore
    let clipboardWatcher: ClipboardWatcher
    let logger: RuntimeLogger

    @Published var settings: AppSettings {
        didSet {
            settings.save()
            clipboardWatcher.enabled = settings.clipboardCaptureEnabled
        }
    }
    @Published var onboardingState: OnboardingState
    private var hotkeysConfigured = false

    lazy var assistantViewModel: AssistantViewModel = {
        let vm = AssistantViewModel(
            engine: engine,
            permissionService: permissionService,
            ttsService: ttsService,
            pointerOverlayManager: pointerOverlayManager,
            settingsProvider: { self.settings },
            settingsUpdater: { self.settings = $0 }
        )
        vm.logger = logger
        return vm
    }()

    lazy var permissionsViewModel: PermissionsViewModel = {
        PermissionsViewModel(permissionService: permissionService)
    }()

    lazy var speechModelViewModel: SpeechModelViewModel = {
        SpeechModelViewModel(service: speechModelService)
    }()

    lazy var settingsViewModel: SettingsViewModel = {
        SettingsViewModel(
            settings: settings,
            updater: { self.settings = $0 }
        )
    }()

    private init(
        permissionService: PermissionService,
        audioCaptureService: AudioCaptureService,
        voiceService: VoiceTranscriptionService,
        speechModelService: SpeechModelService,
        textInsertionService: TextInsertionService,
        screenCaptureService: ScreenCaptureService,
        ttsService: TTSService,
        hotkeyMonitor: ModifierKeyMonitor,
        engine: AssistantEngine,
        settings: AppSettings,
        onboardingState: OnboardingState,
        responseBubbleController: ResponseBubbleController,
        textBarController: TextBarController,
        pointerOverlayManager: PointerOverlayManager,
        knowledgeStore: KnowledgeStore,
        clipboardWatcher: ClipboardWatcher,
        logger: RuntimeLogger
    ) {
        self.permissionService = permissionService
        self.audioCaptureService = audioCaptureService
        self.voiceService = voiceService
        self.speechModelService = speechModelService
        self.textInsertionService = textInsertionService
        self.screenCaptureService = screenCaptureService
        self.ttsService = ttsService
        self.hotkeyMonitor = hotkeyMonitor
        self.engine = engine
        self.settings = settings
        self.onboardingState = onboardingState
        self.responseBubbleController = responseBubbleController
        self.textBarController = textBarController
        self.pointerOverlayManager = pointerOverlayManager
        self.knowledgeStore = knowledgeStore
        self.clipboardWatcher = clipboardWatcher
        self.logger = logger
    }

    static func live() -> AppContainer {
        let permissionService = MacPermissionService()
        let audioCaptureService = HoldToTalkAudioRecorder()
        let speechModelService = FluidAudioSpeechModelService()
        let voiceService = AppleSpeechTranscriptionService()
        let textInsertionService = ActiveTextInsertionService(permissionService: permissionService)
        let screenCaptureService = ScreenCaptureService()
        let ttsService = TTSService()
        let hotkeyMonitor = ModifierKeyMonitor()

        let directExecutor = DirectActionExecutor()
        let claudeCLI = ClaudeCLIService()
        let conversationStore = ConversationStore()
        let knowledgeStore = KnowledgeStore()
        let clipboardWatcher = ClipboardWatcher(knowledgeStore: knowledgeStore)

        let engine = AssistantEngine(
            audioCaptureService: audioCaptureService,
            voiceService: voiceService,
            textInsertionService: textInsertionService,
            screenCaptureService: screenCaptureService,
            directExecutor: directExecutor,
            claudeCLI: claudeCLI,
            conversationStore: conversationStore,
            knowledgeStore: knowledgeStore
        )

        let logger = RuntimeLogger()
        logger.log("Anna starting up", tag: "app")
        logger.log("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")", tag: "app")
        logger.log("Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")", tag: "app")

        let settings = AppSettings.load()
        let onboarding = OnboardingState()

        Task {
            logger.log("Auto-preparing speech model...", tag: "voice")
            do {
                let status = try await speechModelService.prepareModel()
                logger.log("Speech model ready: \(status.detail)", tag: "voice")
            } catch {
                logger.log("Speech model preparation failed: \(error.localizedDescription)", tag: "voice")
            }
        }

        let container = AppContainer(
            permissionService: permissionService,
            audioCaptureService: audioCaptureService,
            voiceService: voiceService,
            speechModelService: speechModelService,
            textInsertionService: textInsertionService,
            screenCaptureService: screenCaptureService,
            ttsService: ttsService,
            hotkeyMonitor: hotkeyMonitor,
            engine: engine,
            settings: settings,
            onboardingState: onboarding,
            responseBubbleController: ResponseBubbleController(),
            textBarController: TextBarController(),
            pointerOverlayManager: PointerOverlayManager(),
            knowledgeStore: knowledgeStore,
            clipboardWatcher: clipboardWatcher,
            logger: logger
        )

        // Start clipboard watching (respects settings)
        clipboardWatcher.enabled = settings.clipboardCaptureEnabled
        clipboardWatcher.start()

        return container
    }

    func configureHotkeysIfNeeded() {
        guard !hotkeysConfigured else { return }
        hotkeysConfigured = true

        hotkeyMonitor.onCommandPressed = { [weak self] in
            guard let self else { return }
            self.logger.log("Right ⌘ pressed — starting agent capture", tag: "hotkey")
            self.assistantViewModel.beginCapture(mode: .assistantCommand)
            self.responseBubbleController.show(viewModel: self.assistantViewModel)
        }
        hotkeyMonitor.onCommandReleased = { [weak self] in
            guard let self else { return }
            self.logger.log("Right ⌘ released — ending capture", tag: "hotkey")
            self.assistantViewModel.endCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                if !self.assistantViewModel.isCapturing {
                    self.responseBubbleController.hide()
                }
            }
        }
        hotkeyMonitor.onOptionPressed = { [weak self] in
            guard let self else { return }
            self.logger.log("Right ⌥ pressed — starting dictation capture", tag: "hotkey")
            self.assistantViewModel.beginCapture(mode: .dictation)
            self.responseBubbleController.show(viewModel: self.assistantViewModel)
        }
        hotkeyMonitor.onOptionReleased = { [weak self] in
            guard let self else { return }
            self.logger.log("Right ⌥ released — ending dictation", tag: "hotkey")
            self.assistantViewModel.endCapture()
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if !self.assistantViewModel.isCapturing {
                    self.responseBubbleController.hide()
                }
            }
        }
        hotkeyMonitor.start()
        logger.log("Hotkey monitor started — Right ⌘ for agent, Right ⌥ for dictation", tag: "hotkey")

        // Global hotkey: Cmd+Shift+Space → toggle text bar
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            // Space = keyCode 49, Cmd+Shift
            if event.keyCode == 49 &&
               event.modifierFlags.contains(.command) &&
               event.modifierFlags.contains(.shift) {
                DispatchQueue.main.async {
                    self.textBarController.toggle(viewModel: self.assistantViewModel)
                }
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 49 &&
               event.modifierFlags.contains(.command) &&
               event.modifierFlags.contains(.shift) {
                DispatchQueue.main.async {
                    self.textBarController.toggle(viewModel: self.assistantViewModel)
                }
                return nil // consume the event
            }
            return event
        }
        logger.log("Global hotkey registered — ⌘⇧Space for text bar", tag: "hotkey")
    }

    deinit {
        // PermissionsViewModel handles its own refresh via app activation observer
    }
}
