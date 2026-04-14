import SwiftUI
import AVFoundation

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var tourGuideStore: TourGuideStore?
    var permissionsViewModel: PermissionsViewModel?

    @State private var cliStatuses: [CLIStatus] = []
    @State private var apiKeyText: String = ""
    @State private var apiKeySaved = false
    @State private var elevenLabsKeyText: String = ""
    @State private var elevenLabsKeySaved = false
    @State private var previewingVoiceID: String? = nil
    @State private var previewPlayer: AVAudioPlayer? = nil
    @State private var tourGuides: [TourGuide] = []
    @State private var showingFileImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))

                section("Appearance") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Theme")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.55))
                        HStack(spacing: 6) {
                            themeButton("System", value: "system")
                            themeButton("Light", value: "light")
                            themeButton("Dark", value: "dark")
                        }
                    }
                }

                section("Interaction") {
                    toggle("Require confirmation for purchases", $viewModel.settings.requiresConfirmationForPurchases)
                    toggle("Reuse successful action routes", $viewModel.settings.autoReuseSuccessfulRoutes)
                }

                section("Voice") {
                    toggle("Let me talk back to you", $viewModel.settings.ttsEnabled)

                    // Engine picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Engine")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.55))
                        HStack(spacing: 6) {
                            ttsEngineButton("Apple", value: "apple")
                            ttsEngineButton("ElevenLabs", value: "elevenlabs")
                        }
                    }

                    // ElevenLabs settings
                    if viewModel.settings.ttsEngine == "elevenlabs" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.55))

                            HStack(spacing: 8) {
                                SecureField("sk_...", text: $elevenLabsKeyText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                                Button {
                                    APIKeyStore.save(key: elevenLabsKeyText, forService: "ElevenLabs")
                                    elevenLabsKeySaved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { elevenLabsKeySaved = false }
                                } label: {
                                    Text(elevenLabsKeySaved ? "Saved!" : "Save")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(elevenLabsKeySaved ? Color(hex: "69D3B0") : .primary.opacity(0.55))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.primary.opacity(0.07), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            if APIKeyStore.load(forService: "ElevenLabs") != nil {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                    Text("Key stored securely")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                            }

                            Text("Optional — works without a key using the built-in proxy. Add your own key from elevenlabs.io for custom voice selection.")
                                .font(.system(size: 10))
                                .foregroundStyle(.primary.opacity(0.25))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        // Voice picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Voice")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.55))

                            ForEach(ElevenLabsVoice.catalog) { voice in
                                let isSelected = viewModel.settings.elevenLabsVoiceID == voice.id
                                let isPreviewing = previewingVoiceID == voice.id
                                HStack(spacing: 8) {
                                    Button {
                                        viewModel.settings.elevenLabsVoiceID = voice.id
                                        viewModel.persist()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 10))
                                                .foregroundStyle(isSelected ? Color(hex: "69D3B0") : .primary.opacity(0.3))
                                            Text(voice.name)
                                                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                                                .foregroundStyle(.primary.opacity(isSelected ? 0.85 : 0.6))
                                            Text(voice.description)
                                                .font(.system(size: 10))
                                                .foregroundStyle(.primary.opacity(0.3))
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Spacer()

                                    Button {
                                        if isPreviewing {
                                            previewPlayer?.stop()
                                            previewPlayer = nil
                                            previewingVoiceID = nil
                                        } else {
                                            previewVoice(voice)
                                        }
                                    } label: {
                                        Image(systemName: isPreviewing ? "stop.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(isPreviewing ? .primary.opacity(0.5) : Color(hex: "69D3B0").opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Text("Uses ElevenLabs Flash v2.5 for low-latency, natural speech. Falls back to Apple TTS if unavailable.")
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(0.25))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Speed (for Apple TTS)
                    if viewModel.settings.ttsEngine == "apple" {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Speed")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.55))
                            HStack(spacing: 8) {
                                Text("Slow")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.primary.opacity(0.3))
                                Slider(value: Binding(
                                    get: { viewModel.settings.ttsRate },
                                    set: { viewModel.settings.ttsRate = $0; viewModel.persist() }
                                ), in: 0.3...0.65)
                                .tint(.primary.opacity(0.3))
                                Text("Fast")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.primary.opacity(0.3))
                            }
                        }
                    }
                }

                section("Knowledge") {
                    toggle("Remember things for me", $viewModel.settings.knowledgeBaseEnabled)
                    toggle("Pay attention to what I copy", $viewModel.settings.clipboardCaptureEnabled)
                    Text("I'll remember copied text so I can help you better. Sensitive stuff is always filtered out.")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.25))
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("AI Backend") {
                    // Provider picker
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Provider")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.55))

                        HStack(spacing: 6) {
                            ForEach(AIProvider.allCases, id: \.self) { provider in
                                let isSelected = viewModel.settings.aiProvider == provider.rawValue
                                let isAvailable = provider.isAPI || cliStatuses.contains(where: { $0.backend.rawValue == provider.rawValue.replacingOccurrences(of: " CLI", with: "") && $0.isInstalled })

                                Button {
                                    viewModel.settings.aiProvider = provider.rawValue
                                    viewModel.persist()
                                    loadAPIKey(for: provider)
                                } label: {
                                    Text(provider.rawValue)
                                        .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                                        .foregroundStyle(Color.primary.opacity(isSelected ? 0.85 : (isAvailable ? 0.5 : 0.25)))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            isSelected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.03),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // API key input (for API providers)
                    let selectedProvider = AIProvider(rawValue: viewModel.settings.aiProvider) ?? .anthropic
                    if selectedProvider.isAPI {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.55))

                            HStack(spacing: 8) {
                                SecureField("sk-...", text: $apiKeyText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.7))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))

                                Button {
                                    APIKeyStore.save(key: apiKeyText, for: selectedProvider)
                                    apiKeySaved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { apiKeySaved = false }
                                } label: {
                                    Text(apiKeySaved ? "Saved!" : "Save")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(apiKeySaved ? Color(hex: "69D3B0") : .primary.opacity(0.55))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.primary.opacity(0.07), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            let hasKey = APIKeyStore.load(for: selectedProvider) != nil
                            if hasKey {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 9))
                                    Text("Key stored in Keychain")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                            }

                            Text(selectedProvider == .anthropic
                                ? "Get your API key at console.anthropic.com"
                                : "Get your API key at platform.openai.com")
                                .font(.system(size: 10))
                                .foregroundStyle(.primary.opacity(0.25))
                        }
                    }

                    // CLI status (for CLI providers)
                    if selectedProvider.isCLI {
                        let matching = cliStatuses.first(where: { $0.backend.rawValue == selectedProvider.rawValue.replacingOccurrences(of: " CLI", with: "") })
                        if matching?.isInstalled == true {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 9))
                                Text("Installed and ready")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                        } else {
                            Text("Not installed. Run:\n\(selectedProvider == .claudeCLI ? "curl -fsSL https://claude.ai/install.sh | sh" : "npm install -g @openai/codex")")
                                .font(.system(size: 10))
                                .foregroundStyle(.primary.opacity(0.25))
                                .textSelection(.enabled)
                        }

                        Button {
                            cliStatuses = CLIStatus.detectAll()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                                Text("Refresh").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.primary.opacity(0.45))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                section("Tour Guides") {
                    Text("Import a knowledge base file (.txt or .md) to let Anna guide users through any app.")
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.25))
                        .fixedSize(horizontal: false, vertical: true)

                    if tourGuides.isEmpty {
                        Text("No tour guides loaded")
                            .font(.system(size: 11))
                            .foregroundStyle(.primary.opacity(0.35))
                    } else {
                        ForEach(tourGuides) { guide in
                            HStack(spacing: 8) {
                                let isActive = viewModel.settings.activeTourGuideID == guide.id.uuidString
                                Button {
                                    if isActive {
                                        viewModel.settings.activeTourGuideID = ""
                                    } else {
                                        viewModel.settings.activeTourGuideID = guide.id.uuidString
                                    }
                                    viewModel.persist()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 10))
                                            .foregroundStyle(isActive ? Color(hex: "69D3B0") : .primary.opacity(0.3))
                                        Text(guide.displayName)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.primary.opacity(isActive ? 0.8 : 0.5))
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Text(guide.fileName)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.primary.opacity(0.2))

                                Button {
                                    Task {
                                        if viewModel.settings.activeTourGuideID == guide.id.uuidString {
                                            viewModel.settings.activeTourGuideID = ""
                                            viewModel.persist()
                                        }
                                        await tourGuideStore?.removeGuide(guide)
                                        await refreshTourGuides()
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 9))
                                        .foregroundStyle(.primary.opacity(0.25))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        showingFileImporter = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle").font(.system(size: 9))
                            Text("Import Tour Guide").font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.primary.opacity(0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .fileImporter(
                        isPresented: $showingFileImporter,
                        allowedContentTypes: [.plainText],
                        allowsMultipleSelection: false
                    ) { result in
                        guard case .success(let urls) = result, let url = urls.first else { return }
                        let accessing = url.startAccessingSecurityScopedResource()
                        Task {
                            do {
                                let guide = try await tourGuideStore?.importFile(at: url)
                                if let guide {
                                    viewModel.settings.activeTourGuideID = guide.id.uuidString
                                    viewModel.persist()
                                }
                                await refreshTourGuides()
                            } catch {
                                print("Tour guide import failed: \(error)")
                            }
                            if accessing { url.stopAccessingSecurityScopedResource() }
                        }
                    }
                }

                if let pvm = permissionsViewModel {
                    section("Permissions") {
                        if pvm.allGranted {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color(hex: "69D3B0"))
                                Text("All permissions granted")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: "69D3B0").opacity(0.7))
                            }
                        } else {
                            Text("Anna needs a few permissions to work properly. Nothing leaves your Mac.")
                                .font(.system(size: 10))
                                .foregroundStyle(.primary.opacity(0.25))
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ForEach(pvm.statuses) { status in
                            permissionRow(status, viewModel: pvm)
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Permissions refresh automatically when Anna becomes active.")
                                .font(.system(size: 10))
                        }
                        .foregroundStyle(.primary.opacity(0.2))
                    }
                }

                section("Shortcuts") {
                    shortcutRow("Right \u{2318}", "Agent command")
                    shortcutRow("Right \u{2325}", "Dictation")
                    shortcutRow("\u{2318}\u{21E7}Space", "Text bar")
                }
            }
            .padding(24)
        }
        .onAppear {
            cliStatuses = CLIStatus.detectAll()
            let provider = AIProvider(rawValue: viewModel.settings.aiProvider) ?? .anthropic
            loadAPIKey(for: provider)
            elevenLabsKeyText = APIKeyStore.load(forService: "ElevenLabs") ?? ""
            Task { await refreshTourGuides() }
            // Start polling permissions so UI updates live when user grants/revokes in System Settings
            permissionsViewModel?.refresh()
            permissionsViewModel?.startPolling()
        }
        .onDisappear {
            permissionsViewModel?.stopPolling()
        }
    }

    // MARK: - Components

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.3))
                .tracking(1)

            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func toggle(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = $0; viewModel.persist() }
        )) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.6))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
        .tint(.primary.opacity(0.35))
    }

    private func refreshTourGuides() async {
        tourGuides = await tourGuideStore?.allGuides() ?? []
    }

    private func themeButton(_ label: String, value: String) -> some View {
        let isSelected = viewModel.settings.appTheme == value
        return Button {
            viewModel.settings.appTheme = value
            viewModel.persist()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(isSelected ? 0.85 : 0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.03), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func ttsEngineButton(_ label: String, value: String) -> some View {
        let isSelected = viewModel.settings.ttsEngine == value
        return Button {
            viewModel.settings.ttsEngine = value
            viewModel.persist()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(Color.primary.opacity(isSelected ? 0.85 : 0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.primary.opacity(0.1) : Color.primary.opacity(0.03), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func previewVoice(_ voice: ElevenLabsVoice) {
        previewPlayer?.stop()
        previewingVoiceID = voice.id

        Task {
            let apiKey = APIKeyStore.load(forService: "ElevenLabs") ?? ""
            let useProxy = apiKey.isEmpty
            let url: URL
            var request: URLRequest

            if useProxy {
                url = URL(string: "https://clicky-proxy.farza-0cb.workers.dev/tts")!
                request = URLRequest(url: url)
            } else {
                url = URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voice.id)")!
                request = URLRequest(url: url)
                request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
            }

            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let body: [String: Any] = [
                "text": "Hey, I'm \(voice.name). This is what I sound like as your assistant.",
                "model_id": "eleven_flash_v2_5",
                "voice_settings": ["stability": 0.5, "similarity_boost": 0.75]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    await MainActor.run { previewingVoiceID = nil }
                    return
                }
                let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("anna-preview-\(voice.id).mp3")
                try data.write(to: tempFile)
                await MainActor.run {
                    do {
                        self.previewPlayer = try AVAudioPlayer(contentsOf: tempFile)
                        self.previewPlayer?.play()
                        // Clear preview state when done
                        DispatchQueue.main.asyncAfter(deadline: .now() + (self.previewPlayer?.duration ?? 3.0) + 0.5) {
                            if self.previewingVoiceID == voice.id {
                                self.previewingVoiceID = nil
                            }
                        }
                    } catch {
                        self.previewingVoiceID = nil
                    }
                }
            } catch {
                await MainActor.run { previewingVoiceID = nil }
            }
        }
    }

    private func loadAPIKey(for provider: AIProvider) {
        apiKeyText = APIKeyStore.load(for: provider) ?? ""
        apiKeySaved = false
    }

    private func permissionRow(_ status: PermissionStatus, viewModel pvm: PermissionsViewModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: status.kind.icon)
                    .font(.system(size: 12))
                    .foregroundStyle(permissionColor(status).opacity(0.7))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(status.kind.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.7))

                        if status.kind.isRequired {
                            Text("Required")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color(hex: "FFC764").opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(hex: "FFC764").opacity(0.08), in: Capsule())
                        }
                    }

                    Text(status.kind.reason)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.25))
                        .lineLimit(2)
                }

                Spacer()

                // Status badge / action
                switch status.state {
                case .granted:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 9))
                        Text("Granted").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "69D3B0"))

                case .notRequested:
                    Button {
                        pvm.request(status.kind)
                    } label: {
                        Text("Grant")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.6))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
                    .buttonStyle(.plain)

                case .denied:
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 9))
                        Text("Denied").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.red.opacity(0.7))

                case .manualStepRequired:
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9))
                        Text("Action needed").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color(hex: "FFC764").opacity(0.8))
                }
            }

            // Recovery instructions + action buttons when permission needs attention
            if status.needsAttention {
                VStack(alignment: .leading, spacing: 8) {
                    Text(status.kind.denialInstructions)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.35))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button {
                            pvm.request(status.kind)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                                Text("Retry").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.primary.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)

                        Button {
                            pvm.openSettings(for: status.kind)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gear").font(.system(size: 9))
                                Text("Open System Settings").font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(.primary.opacity(0.6))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 26)
            }
        }
    }

    private func permissionColor(_ status: PermissionStatus) -> Color {
        switch status.state {
        case .granted: return Color(hex: "69D3B0")
        case .denied: return .red
        case .manualStepRequired: return Color(hex: "FFC764")
        case .notRequested: return .primary
        }
    }

    private func shortcutRow(_ key: String, _ desc: String) -> some View {
        HStack(spacing: 10) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary.opacity(0.4))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            Text(desc)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.45))
        }
    }

}
