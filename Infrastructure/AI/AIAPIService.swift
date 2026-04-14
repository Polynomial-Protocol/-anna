import Foundation
import AppKit

/// Which AI provider to use
enum AIProvider: String, CaseIterable, Codable, Sendable {
    case anthropic = "Claude API"
    case openai = "ChatGPT API"
    case openrouter = "OpenRouter"
    case claudeCLI = "Claude Code CLI"
    case codexCLI = "Codex CLI"

    var isAPI: Bool {
        self == .anthropic || self == .openai || self == .openrouter
    }

    var isCLI: Bool {
        self == .claudeCLI || self == .codexCLI
    }
}

/// Direct API service for Anthropic Claude and OpenAI ChatGPT.
/// Works on any Mac — no CLI tools needed, just an API key.
actor AIAPIService {
    private let provider: AIProvider
    private let apiKey: String
    private let systemPrompt: String
    private let timeoutSeconds: Double

    init(provider: AIProvider, apiKey: String, systemPrompt: String, timeoutSeconds: Double = 120) {
        self.provider = provider
        self.apiKey = apiKey
        self.systemPrompt = systemPrompt
        self.timeoutSeconds = timeoutSeconds
    }

    func execute(
        userRequest: String,
        screenshotPath: String? = nil,
        screenshotWidth: Int = 0,
        screenshotHeight: Int = 0,
        conversationContext: String? = nil
    ) async throws -> ClaudeCLIResult {
        let startTime = Date()

        switch provider {
        case .anthropic:
            return try await callAnthropic(
                request: userRequest,
                screenshotPath: screenshotPath,
                screenshotWidth: screenshotWidth,
                screenshotHeight: screenshotHeight,
                conversationContext: conversationContext,
                startTime: startTime
            )
        case .openai, .openrouter:
            return try await callOpenAI(
                request: userRequest,
                screenshotPath: screenshotPath,
                screenshotWidth: screenshotWidth,
                screenshotHeight: screenshotHeight,
                conversationContext: conversationContext,
                startTime: startTime
            )
        default:
            throw AnnaError.claudeCLIFailed("AIAPIService only handles API providers")
        }
    }

    // MARK: - Anthropic Claude API

    private func callAnthropic(
        request: String,
        screenshotPath: String?,
        screenshotWidth: Int,
        screenshotHeight: Int,
        conversationContext: String?,
        startTime: Date
    ) async throws -> ClaudeCLIResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        // Build messages
        var userContent: [[String: Any]] = []

        // Add screenshot as base64 image if available
        if let path = screenshotPath,
           let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let base64 = imageData.base64EncodedString()
            let mediaType = path.hasSuffix(".png") ? "image/png" : "image/jpeg"
            userContent.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": mediaType,
                    "data": base64
                ]
            ])
        }

        // Build text content
        var textParts: [String] = []
        if let context = conversationContext, !context.isEmpty {
            textParts.append("Previous conversation:\n\(context)")
        }
        if screenshotPath != nil && screenshotWidth > 0 && screenshotHeight > 0 {
            textParts.append("The screenshot is \(screenshotWidth)x\(screenshotHeight) pixels. Origin (0,0) is the top-left corner. Use [CLICK:x,y:label] to click elements or [POINT:x,y:label] to point. x ranges from 0 to \(screenshotWidth), y ranges from 0 to \(screenshotHeight). Aim for the CENTER of buttons and elements.")
        }
        textParts.append(request)

        userContent.append([
            "type": "text",
            "text": textParts.joined(separator: "\n\n")
        ])

        // Build tools for bash/AppleScript execution
        let tools: [[String: Any]] = [
            [
                "name": "run_command",
                "description": "Execute a shell command on the user's Mac. Use this for AppleScript (osascript), opening URLs, controlling apps, setting reminders, etc.",
                "input_schema": [
                    "type": "object",
                    "properties": [
                        "command": [
                            "type": "string",
                            "description": "The shell command to execute (e.g., 'osascript -e ...' or 'open https://...')"
                        ]
                    ],
                    "required": ["command"]
                ]
            ]
        ]

        let body: [String: Any] = [
            "model": "claude-sonnet-4-5",
            "max_tokens": 1024,
            "system": systemPrompt,
            "tools": tools,
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        return try await executeAnthropicWithTools(url: url, body: body, startTime: startTime)
    }

    /// Handles the Anthropic tool-use loop: send request → get tool calls → execute → send results → get final response
    private func executeAnthropicWithTools(url: URL, body: [String: Any], startTime: Date, depth: Int = 0) async throws -> ClaudeCLIResult {
        guard depth < 10 else {
            return ClaudeCLIResult(text: "Done.", success: true, costUSD: nil,
                                  durationMs: Int(Date().timeIntervalSince(startTime) * 1000))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnnaError.claudeCLIFailed("Invalid response from Anthropic API")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw AnnaError.claudeCLIFailed("Invalid Anthropic API key. Check your key in Settings.")
            }
            if httpResponse.statusCode == 429 {
                throw AnnaError.claudeCLIFailed("Rate limited. Please wait a moment and try again.")
            }
            // Anthropic returns 529 for overload; sometimes 404 with message "Overloaded" during capacity spikes.
            let isOverloaded = httpResponse.statusCode == 529
                || (httpResponse.statusCode == 404 && errorBody.lowercased().contains("overloaded"))
            if isOverloaded && depth < 8 {
                let backoff = UInt64(pow(2.0, Double(depth))) * 500_000_000  // 0.5s, 1s, 2s, 4s...
                try? await Task.sleep(nanoseconds: backoff)
                return try await executeAnthropicWithTools(url: url, body: body, startTime: startTime, depth: depth + 1)
            }
            throw AnnaError.claudeCLIFailed("Anthropic API error (\(httpResponse.statusCode)): \(errorBody.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AnnaError.claudeCLIFailed("Could not parse Anthropic response")
        }

        let stopReason = json["stop_reason"] as? String

        // Check if there are tool calls to execute
        if stopReason == "tool_use" {
            var toolResults: [[String: Any]] = []
            var assistantContent: [[String: Any]] = content

            for block in content {
                guard let type = block["type"] as? String, type == "tool_use",
                      let toolId = block["id"] as? String,
                      let input = block["input"] as? [String: Any],
                      let command = input["command"] as? String else { continue }

                // Execute the command locally
                let result = await executeLocalCommand(command)
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": toolId,
                    "content": result
                ])
            }

            if !toolResults.isEmpty {
                // Send tool results back and get final response
                var newBody = body
                var messages = (body["messages"] as? [[String: Any]]) ?? []
                messages.append(["role": "assistant", "content": assistantContent])
                messages.append(["role": "user", "content": toolResults])
                newBody["messages"] = messages
                return try await executeAnthropicWithTools(url: url, body: newBody, startTime: startTime, depth: depth + 1)
            }
        }

        // Extract text response
        let textBlocks = content.compactMap { block -> String? in
            guard let type = block["type"] as? String, type == "text",
                  let text = block["text"] as? String else { return nil }
            return text
        }

        let responseText = textBlocks.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudeCLIResult(
            text: responseText.isEmpty ? "Done." : responseText,
            success: true,
            costUSD: nil,
            durationMs: durationMs
        )
    }

    // MARK: - OpenAI ChatGPT API

    private func callOpenAI(
        request: String,
        screenshotPath: String?,
        screenshotWidth: Int,
        screenshotHeight: Int,
        conversationContext: String?,
        startTime: Date
    ) async throws -> ClaudeCLIResult {
        let url = URL(string: provider == .openrouter
            ? "https://openrouter.ai/api/v1/chat/completions"
            : "https://api.openai.com/v1/chat/completions")!

        // Build user message content
        var userContent: [[String: Any]] = []

        // Add screenshot as base64 image
        if let path = screenshotPath,
           let imageData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
            let base64 = imageData.base64EncodedString()
            let mediaType = path.hasSuffix(".png") ? "image/png" : "image/jpeg"
            userContent.append([
                "type": "image_url",
                "image_url": ["url": "data:\(mediaType);base64,\(base64)"]
            ])
        }

        var textParts: [String] = []
        if let context = conversationContext, !context.isEmpty {
            textParts.append("Previous conversation:\n\(context)")
        }
        if screenshotPath != nil && screenshotWidth > 0 && screenshotHeight > 0 {
            textParts.append("The screenshot is \(screenshotWidth)x\(screenshotHeight) pixels. Origin (0,0) is the top-left corner. Use [CLICK:x,y:label] to click elements or [POINT:x,y:label] to point. x ranges from 0 to \(screenshotWidth), y ranges from 0 to \(screenshotHeight). Aim for the CENTER of buttons and elements.")
        }
        textParts.append(request)

        userContent.append([
            "type": "text",
            "text": textParts.joined(separator: "\n\n")
        ])

        // Build tools
        let tools: [[String: Any]] = [
            [
                "type": "function",
                "function": [
                    "name": "run_command",
                    "description": "Execute a shell command on the user's Mac. Use this for AppleScript (osascript), opening URLs, controlling apps, setting reminders, etc.",
                    "parameters": [
                        "type": "object",
                        "properties": [
                            "command": [
                                "type": "string",
                                "description": "The shell command to execute"
                            ]
                        ],
                        "required": ["command"]
                    ]
                ]
            ]
        ]

        let body: [String: Any] = [
            "model": provider == .openrouter ? "anthropic/claude-sonnet-4.5" : "gpt-4o",
            "max_tokens": 1024,
            "tools": tools,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        ]

        return try await executeOpenAIWithTools(url: url, body: body, startTime: startTime)
    }

    private func executeOpenAIWithTools(url: URL, body: [String: Any], startTime: Date, depth: Int = 0) async throws -> ClaudeCLIResult {
        guard depth < 10 else {
            return ClaudeCLIResult(text: "Done.", success: true, costUSD: nil,
                                  durationMs: Int(Date().timeIntervalSince(startTime) * 1000))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeoutSeconds
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let durationMs = Int(Date().timeIntervalSince(startTime) * 1000)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnnaError.claudeCLIFailed("Invalid response from OpenAI API")
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                let name = provider == .openrouter ? "OpenRouter" : "OpenAI"
                throw AnnaError.claudeCLIFailed("Invalid \(name) API key. Check your key in Settings.")
            }
            if httpResponse.statusCode == 429 {
                throw AnnaError.claudeCLIFailed("Rate limited. Please wait a moment and try again.")
            }
            throw AnnaError.claudeCLIFailed("OpenAI API error (\(httpResponse.statusCode)): \(errorBody.prefix(200))")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AnnaError.claudeCLIFailed("Could not parse OpenAI response")
        }

        let finishReason = firstChoice["finish_reason"] as? String

        // Handle tool calls
        if finishReason == "tool_calls",
           let toolCalls = message["tool_calls"] as? [[String: Any]] {

            var toolResults: [[String: Any]] = []
            for call in toolCalls {
                guard let id = call["id"] as? String,
                      let function = call["function"] as? [String: Any],
                      let argsString = function["arguments"] as? String,
                      let argsData = argsString.data(using: .utf8),
                      let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any],
                      let command = args["command"] as? String else { continue }

                let result = await executeLocalCommand(command)
                toolResults.append([
                    "role": "tool",
                    "tool_call_id": id,
                    "content": result
                ])
            }

            if !toolResults.isEmpty {
                var newBody = body
                var messages = (body["messages"] as? [[String: Any]]) ?? []
                messages.append(message)  // assistant message with tool_calls
                messages.append(contentsOf: toolResults)
                newBody["messages"] = messages
                return try await executeOpenAIWithTools(url: url, body: newBody, startTime: startTime, depth: depth + 1)
            }
        }

        let responseText = (message["content"] as? String ?? "Done.").trimmingCharacters(in: .whitespacesAndNewlines)
        return ClaudeCLIResult(
            text: responseText.isEmpty ? "Done." : responseText,
            success: true,
            costUSD: nil,
            durationMs: durationMs
        )
    }

    // MARK: - Local Command Execution

    private func executeLocalCommand(_ command: String) async -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["\(home)/.local/bin", "/usr/local/bin", "/opt/homebrew/bin"].joined(separator: ":")
        env["PATH"] = "\(extraPaths):\(env["PATH"] ?? "/usr/bin:/bin")"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()

            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let outStr = String(data: outData, encoding: .utf8) ?? ""
            let errStr = String(data: errData, encoding: .utf8) ?? ""

            if process.terminationStatus == 0 {
                return outStr.isEmpty ? "Command executed successfully." : String(outStr.prefix(2000))
            } else {
                return "Error: \(errStr.isEmpty ? outStr : errStr)".prefix(2000).description
            }
        } catch {
            return "Failed to execute command: \(error.localizedDescription)"
        }
    }
}

// MARK: - API Key Storage (File-based)
//
// Uses ~/Library/Application Support/Anna/ instead of Keychain.
// Keychain prompts the user for their password every time the app is rebuilt
// with ad-hoc signing (the code signature changes). File-based storage
// survives rebuilds and upgrades without any prompts.

enum APIKeyStore {
    private static let keychainService = "com.polynomial.anna"

    private static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Anna", isDirectory: true)
    }

    private static func keyFilePath(for provider: AIProvider) -> URL {
        storageDirectory.appendingPathComponent("apikey-\(provider.rawValue)")
    }

    private static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        // Restrict directory permissions to owner only (rwx------)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: storageDirectory.path
        )
    }

    static func save(key: String, for provider: AIProvider) {
        ensureDirectory()
        let path = keyFilePath(for: provider)
        do {
            try key.write(to: path, atomically: true, encoding: .utf8)
            // Restrict file permissions to owner only (rw-------)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path.path
            )
        } catch {
            // Silently fail — user will see empty key field
        }
    }

    static func load(for provider: AIProvider) -> String? {
        let path = keyFilePath(for: provider)

        // Try file-based storage first
        if let key = try? String(contentsOf: path, encoding: .utf8),
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Migrate from Keychain silently (no UI prompts)
        if let key = loadFromKeychainSilently(for: provider) {
            save(key: key, for: provider)       // persist to file
            deleteFromKeychain(for: provider)    // clean up old entry
            return key
        }

        return nil
    }

    static func delete(for provider: AIProvider) {
        let path = keyFilePath(for: provider)
        try? FileManager.default.removeItem(at: path)
        deleteFromKeychain(for: provider)
    }

    // MARK: - Generic Key Storage (for non-AIProvider keys like ElevenLabs)

    static func save(key: String, forService service: String) {
        ensureDirectory()
        let path = storageDirectory.appendingPathComponent("apikey-\(service)")
        do {
            try key.write(to: path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: path.path
            )
        } catch {}
    }

    static func load(forService service: String) -> String? {
        let path = storageDirectory.appendingPathComponent("apikey-\(service)")
        if let key = try? String(contentsOf: path, encoding: .utf8),
           !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Keychain Migration (silent, no prompts)

    /// Attempts to read from Keychain without triggering a password prompt.
    /// Returns nil if the key doesn't exist or if access would require user interaction.
    private static func loadFromKeychainSilently(for provider: AIProvider) -> String? {
        let account = "apikey-\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            // This flag prevents the system Keychain dialog from appearing.
            // If access requires user interaction, it returns errSecInteractionNotAllowed.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteFromKeychain(for provider: AIProvider) {
        let account = "apikey-\(provider.rawValue)"
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
