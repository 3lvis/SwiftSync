import SwiftUI

struct EngineStatusOverlayView: View {
    @ObservedObject var syncEngine: DemoSyncEngine
    let onClose: () -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Engine Status", systemImage: "server.rack")
                    .font(.headline.weight(.semibold))
                Spacer()
                if syncEngine.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.bold))
                }
                Button("Close", action: onClose)
                    .font(.caption)
            }

            HStack(spacing: 10) {
                Text(syncEngine.isSyncing ? "Syncing" : "Idle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(syncEngine.isSyncing ? Color.blue.opacity(0.15) : Color.gray.opacity(0.14))
                    .clipShape(Capsule())

                if let lastSyncDate = syncEngine.lastSyncDate {
                    Text("Last sync \(lastSyncDate.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = syncEngine.lastErrorMessage {
                Text(error)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.red.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .foregroundStyle(.red)
            }

#if DEBUG
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                Text(syncEngine.earthquakeActiveScopeLabel)
                    .font(.caption)
                    .lineLimit(2)
                Spacer()
                Button(syncEngine.isEarthquakeModeRunning ? "Stop Earthquake" : "Start Earthquake") {
                    syncEngine.toggleEarthquakeMode()
                }
                .font(.caption)
                .disabled(!syncEngine.isEarthquakeModeRunning && !syncEngine.canStartEarthquakeMode)
            }
#endif

            if !isExpanded {
                Text(summaryText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if syncEngine.historyEvents.isEmpty {
                Text("No sync history yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(syncEngine.historyEvents) { event in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 8) {
                                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(event.scope)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                }
                                Text(event.message)
                                    .font(.caption2)
                                if let detail = event.detail, !detail.isEmpty {
                                    Text(detail)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(14)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 6)
    }

    private var summaryText: String {
        let total = syncEngine.historyEvents.count
        let failures = syncEngine.historyEvents.filter { $0.message == "network failed" }.count
        return "\(total) events · \(failures) failures"
    }
}
