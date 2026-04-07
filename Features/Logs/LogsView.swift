import SwiftUI

struct LogsView: View {
    @ObservedObject var logger: RuntimeLogger

    @State private var selectedDate: String = ""
    @State private var filterText: String = ""
    @State private var autoRefresh = true
    @State private var refreshTimer: Timer?
    @State private var diskLines: [String] = []

    private var availableDates: [String] {
        logger.availableLogDates()
    }

    private var todayString: String {
        RuntimeLogger.dayFormatter.string(from: Date())
    }

    private var displayedLines: [String] {
        let lines: [String]
        if selectedDate.isEmpty || selectedDate == todayString {
            lines = logger.recentLines
        } else {
            lines = diskLines
        }

        if filterText.isEmpty { return lines }
        let query = filterText.lowercased()
        return lines.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            Divider().overlay(Color.white.opacity(0.06))

            logContent
        }
        .background(AnnaPalette.pane)
        .onAppear {
            if selectedDate.isEmpty {
                selectedDate = todayString
            }
            loadDiskLogs()
            startAutoRefresh()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: selectedDate) { _, _ in
            loadDiskLogs()
        }
        .onChange(of: autoRefresh) { _, on in
            if on { startAutoRefresh() } else { stopAutoRefresh() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Picker("Date", selection: $selectedDate) {
                Text("Today").tag(todayString)
                ForEach(availableDates.filter { $0 != todayString }, id: \.self) { date in
                    Text(date).tag(date)
                }
            }
            .frame(width: 180)

            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                TextField("Filter...", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .frame(maxWidth: 200)

            Toggle("Auto", isOn: $autoRefresh)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            Button {
                loadDiskLogs()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.6))

            Text("\(displayedLines.count) lines")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(displayedLines.enumerated()), id: \.offset) { index, line in
                        logLine(line)
                            .id(index)
                    }
                }
                .padding(12)
            }
            .background(AnnaPalette.canvas)
            .onChange(of: logger.recentLines.count) { _, _ in
                if autoRefresh && (selectedDate.isEmpty || selectedDate == todayString) {
                    proxy.scrollTo(0, anchor: .top)
                }
            }
        }
    }

    private func logLine(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(colorForLine(line))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 1)
    }

    // MARK: - Helpers

    private func loadDiskLogs() {
        guard selectedDate != todayString else {
            diskLines = []
            return
        }
        diskLines = logger.readLogs(for: selectedDate, lastN: 1000)
    }

    private func startAutoRefresh() {
        stopAutoRefresh()
        guard autoRefresh else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                loadDiskLogs()
            }
        }
    }

    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func colorForLine(_ line: String) -> Color {
        let lowered = line.lowercased()
        if lowered.contains("error") || lowered.contains("failed") || lowered.contains("crash") {
            return .red
        }
        if lowered.contains("warning") || lowered.contains("blocked") || lowered.contains("denied") {
            return .orange
        }
        if lowered.contains("[voice]") || lowered.contains("[hotkey]") || lowered.contains("[capture]") {
            return .cyan
        }
        if lowered.contains("success") || lowered.contains("granted") || lowered.contains("completed") {
            return .green
        }
        if lowered.contains("[permission]") {
            return .yellow
        }
        return .white.opacity(0.7)
    }
}
