import SwiftData
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @State private var hasTriggeredInitialSync = false
    @StateObject private var machine: TaskDetailMachine
    @State private var showingEditSheet = false
#if DEBUG
    @State private var showingStressPrompt = false
#endif

    init(taskID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.taskID = taskID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _machine = StateObject(
            wrappedValue: TaskDetailMachine(taskID: taskID, syncContainer: syncContainer, syncEngine: syncEngine)
        )
    }

    var body: some View {
        List {
            loadErrorSection
            taskSection
            descriptionSection
            itemsSection
            peopleSection
        }
        .navigationTitle("Task")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
                .disabled(machine.task == nil)
            }
        }
        .task {
            guard !hasTriggeredInitialSync else { return }
            hasTriggeredInitialSync = true
            requestLoad(.onAppear)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let taskModel = machine.task {
                TaskFormSheet(
                    mode: .edit(task: taskModel),
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
#if DEBUG
        .overlay(alignment: .bottom) {
            if syncEngine.isEarthquakeModeRunning,
               let status = syncEngine.earthquakeStatusText {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                    Text(status)
                        .font(.caption)
                        .lineLimit(2)
                    Spacer(minLength: 8)
                    Button("Stop") {
                        syncEngine.stopEarthquakeMode()
                    }
                    .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .shadow(radius: 6)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
            }
        }
        .alert("Stress test this screen?", isPresented: $showingStressPrompt) {
            Button("Start Stress", role: .destructive) {
                syncEngine.startEarthquakeMode(for: .taskDetail(taskID: taskID))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Debug-only Earthquake Mode runs finite add/edit/delete overlap for this task screen.")
        }
        .background(
            ShakeDetector {
                guard !syncEngine.isEarthquakeModeRunning else { return }
                guard !showingEditSheet else { return }
                showingStressPrompt = true
            }
            .allowsHitTesting(false)
        )
#endif
        .overlay {
            loadOverlay
        }
    }

    @ViewBuilder
    private var loadErrorSection: some View {
        if let presentation = machine.loadState.errorPresentation {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(presentation.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let retryActionTitle = presentation.retryActionTitle {
                        Button(retryActionTitle) {
                            requestLoad(.retry)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private var loadOverlay: some View {
        if machine.loadState.isLoading {
            ProgressView("Loading task...")
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func requestLoad(_ event: ScreenLoadEvent) {
        machine.send(event)
    }

    private var taskSection: some View {
        Section {
            if let taskModel = machine.task {
                VStack(alignment: .leading, spacing: 12) {
                    Text(taskModel.title)
                        .font(.title2)
                        .fontWeight(.bold)
                    HStack(spacing: 8) {
                        Text(taskModel.stateLabel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        Text(taskModel.author?.displayName ?? "Unknown")
                            .font(.caption)
                            .fontWeight(.medium)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, 4)
            } else {
                Text("Task not found")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var descriptionSection: some View {
        Section("Description") {
            Text(machine.task?.descriptionText ?? "")
                .font(.body)
        }
    }

    @ViewBuilder
    private var itemsSection: some View {
        if machine.task != nil {
            Section("Items") {
                if machine.items.isEmpty {
                    Text("No items")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(machine.items, id: \.id) { item in
                        Text(item.title)
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var peopleSection: some View {
        if let taskModel = machine.task {
            Section("Assignee") {
                Text(taskModel.assignee?.displayName ?? "Unassigned")
                    .foregroundStyle(taskModel.assignee == nil ? .secondary : .primary)
            }

            Section("Reviewers") {
                if taskModel.reviewers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(taskModel.reviewers.sorted { $0.displayName < $1.displayName }, id: \.id) { reviewer in
                        Text(reviewer.displayName)
                    }
                }
            }

            Section("Watchers") {
                if taskModel.watchers.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(
                        taskModel.watchers.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
                        id: \.id
                    ) { watcher in
                        Text(watcher.displayName)
                    }
                }
            }
        }
    }

}
