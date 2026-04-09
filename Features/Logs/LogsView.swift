import SwiftUI

struct LogsView: View {
    @ObservedObject var logger: RuntimeLogger

    @State private var selectedDate: String = ""
    @State private var filterText: String = ""
    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?
    @State private var diskLines: [String] = []

    private var availableDates: [String] { logger.availableLogDates() }
    private var todayString: String { RuntimeLogger.dayFormatter.string(from: Date()) }

    private var displayedLines: [String] {
        let lines = (selectedDate.isEmpty || selectedDate == todayString) ? logger.recentLines : diskLines
        if filterText.isEmpty { return lines }
        let q = filterText.lowercased()
        return lines.filter { $0.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 10) {
                Picker("", selection: $selectedDate) {
                    Text("Today").tag(todayString)
                    ForEach(availableDates.filter { $0 != todayString }, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(width: 140)

                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.3))
                    TextField("Filter...", text: $filterText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .frame(maxWidth: 160)

                Toggle("Auto", isOn: $autoRefresh)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(.white.opacity(0.3))

                Spacer()

                Button { loadDiskLogs() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)

                Text("\(displayedLines.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Log content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(displayedLines.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(colorFor(line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 1)
                                .id(i)
                        }
                    }
                    .padding(10)
                }
                .background(Color(red: 0.05, green: 0.05, blue: 0.07))
                .onChange(of: logger.recentLines.count) { _, _ in
                    if autoRefresh && (selectedDate.isEmpty || selectedDate == todayString) {
                        proxy.scrollTo(0, anchor: .top)
                    }
                }
            }
        }
        .onAppear {
            if selectedDate.isEmpty { selectedDate = todayString }
            loadDiskLogs(); startAutoRefresh()
        }
        .onDisappear { stopAutoRefresh() }
        .onChange(of: selectedDate) { _, _ in loadDiskLogs() }
        .onChange(of: autoRefresh) { _, on in if on { startAutoRefresh() } else { stopAutoRefresh() } }
    }

    private func loadDiskLogs() {
        guard selectedDate != todayString else { diskLines = []; return }
        diskLines = logger.readLogs(for: selectedDate, lastN: 1000)
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        guard autoRefresh else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in loadDiskLogs() }
        }
    }

    private func stopAutoRefresh() { refreshTimer?.invalidate(); refreshTimer = nil }

    private func colorFor(_ line: String) -> Color {
        let l = line.lowercased()
        if l.contains("error") || l.contains("failed") { return .red.opacity(0.8) }
        if l.contains("warning") || l.contains("denied") { return .orange.opacity(0.7) }
        if l.contains("[voice]") || l.contains("[hotkey]") || l.contains("[capture]") { return .cyan.opacity(0.6) }
        if l.contains("success") || l.contains("granted") { return .green.opacity(0.6) }
        return .white.opacity(0.5)
    }
}
