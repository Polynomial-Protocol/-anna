import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeDumpView: View {
    let knowledgeStore: KnowledgeStore
    @State private var entries: [KnowledgeEntry] = []
    @State private var searchText: String = ""
    @State private var newNoteText: String = ""
    @State private var showingAddNote = false
    @State private var entryCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 10) {
                Text("Knowledge")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Text("\(entryCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))

                Button { showingAddNote.toggle() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .buttonStyle(.plain)

                Button { exportKnowledge() } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Export")

                Button { importKnowledge() } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .buttonStyle(.plain)
                .help("Import")
            }

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .onSubmit { performSearch() }
                    .onChange(of: searchText) { _, val in
                        if val.isEmpty { loadRecent() }
                    }
                if !searchText.isEmpty {
                    Button { searchText = ""; loadRecent() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            // Add note
            if showingAddNote {
                VStack(alignment: .leading, spacing: 6) {
                    TextEditor(text: $newNoteText)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .frame(height: 60)
                        .padding(6)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    HStack {
                        Spacer()
                        Button("Cancel") { newNoteText = ""; showingAddNote = false }
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.35))
                            .buttonStyle(.plain)
                        Button("Save") { saveNote() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.07), in: Capsule())
                            .buttonStyle(.plain)
                            .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            // Entries
            if entries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text(searchText.isEmpty ? "Empty" : "No results")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.25))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
        .padding(24)
        .task { loadRecent() }
    }

    private func entryRow(_ entry: KnowledgeEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.source.icon)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.25))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
                Text(entry.content)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(2)
            }

            Spacer()

            Text(entry.createdAt, style: .relative)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.2))

            Button { deleteEntry(entry) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.02), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: - Actions

    private func loadRecent() {
        Task { entries = await knowledgeStore.recentEntries(limit: 100); entryCount = await knowledgeStore.entryCount() }
    }

    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { loadRecent(); return }
        Task { entries = await knowledgeStore.search(query: searchText, limit: 50) }
    }

    private func saveNote() {
        let text = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task { await knowledgeStore.addEntry(content: text, source: .note); newNoteText = ""; showingAddNote = false; loadRecent() }
    }

    private func exportKnowledge() {
        Task {
            let all = await knowledgeStore.recentEntries(limit: 10000)
            guard !all.isEmpty else { return }
            let data = all.map { e -> [String: Any] in
                ["title": e.title, "content": e.content, "source": e.source.rawValue, "created_at": ISO8601DateFormatter().string(from: e.createdAt)]
            }
            guard let json = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) else { return }
            await MainActor.run {
                let panel = NSSavePanel()
                panel.allowedContentTypes = [.json]
                panel.nameFieldStringValue = "anna-knowledge.json"
                if panel.runModal() == .OK, let url = panel.url { try? json.write(to: url) }
            }
        }
    }

    private func importKnowledge() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            guard let data = try? Data(contentsOf: url),
                  let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            for item in items {
                guard let content = item["content"] as? String, let srcRaw = item["source"] as? String else { continue }
                let source = EntrySource(rawValue: srcRaw) ?? .note
                await knowledgeStore.addEntry(content: content, source: source, title: item["title"] as? String)
            }
            await MainActor.run { loadRecent() }
        }
    }

    private func deleteEntry(_ entry: KnowledgeEntry) {
        Task { await knowledgeStore.deleteEntry(id: entry.id); loadRecent() }
    }
}
