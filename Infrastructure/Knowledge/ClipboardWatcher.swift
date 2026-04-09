import AppKit
import Foundation

@MainActor
final class ClipboardWatcher {
    private let knowledgeStore: KnowledgeStore
    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var lastContent: String = ""
    private var isEnabled: Bool = true

    init(knowledgeStore: KnowledgeStore) {
        self.knowledgeStore = knowledgeStore
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkClipboard()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    var enabled: Bool {
        get { isEnabled }
        set { isEnabled = newValue }
    }

    private func checkClipboard() {
        guard isEnabled else { return }

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let text = pasteboard.string(forType: .string),
              !text.isEmpty,
              text.count >= 10,  // Skip very short copies (single words, etc.)
              text.count <= 50000,  // Skip huge copies
              text != lastContent  // Deduplicate
        else { return }

        lastContent = text

        // Skip if it looks like a password or sensitive data
        if looksLikeSensitiveData(text) { return }

        Task {
            await knowledgeStore.addEntry(content: text, source: .clipboard)
        }
    }

    private func looksLikeSensitiveData(_ text: String) -> Bool {
        let lower = text.lowercased()
        // Skip passwords, tokens, API keys
        if lower.contains("password") && text.count < 200 { return true }
        if lower.contains("secret") && text.count < 200 { return true }
        let sensitivePrefixes = ["sk-", "pk-", "ghp_", "gho_", "glpat-", "xoxb-", "xoxp-",
                                  "eyj", "bearer ", "api_key", "apikey"]
        for prefix in sensitivePrefixes {
            if lower.hasPrefix(prefix) { return true }
        }
        // Skip if it's mostly non-alphanumeric (likely base64/encoded data, but allow code)
        let readableCount = text.filter { $0.isLetter || $0.isNumber || $0.isWhitespace || $0.isPunctuation }.count
        if text.count > 50 && Double(readableCount) / Double(text.count) < 0.4 { return true }
        return false
    }
}
