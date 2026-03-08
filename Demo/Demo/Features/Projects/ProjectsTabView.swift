import SwiftSync
import SwiftUI
import UIKit

struct ProjectsTabView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine
    @State private var selectedProjectID: String?

    var body: some View {
        NavigationStack {
            _ProjectsRepresentable(syncContainer: syncContainer, syncEngine: syncEngine) { projectID in
                selectedProjectID = projectID
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $selectedProjectID) { projectID in
                ProjectDetailView(
                    projectID: projectID,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }
}

private struct _ProjectsRepresentable: UIViewControllerRepresentable {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine
    let onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> ProjectsViewController {
        ProjectsViewController(syncContainer: syncContainer, syncEngine: syncEngine, onSelect: onSelect)
    }

    func updateUIViewController(_ uiViewController: ProjectsViewController, context: Context) {}
}

// MARK: - Project Detail

private struct ProjectDetailView: View {
    let projectID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @StateObject private var machine: ProjectDetailMachine
    @State private var isShowingCreateTaskSheet = false
    @State private var taskPendingDelete: TaskDeletePrompt?
#if DEBUG
    @State private var showingStressPrompt = false
#endif

    init(projectID: String, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.projectID = projectID
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        _machine = StateObject(
            wrappedValue: ProjectDetailMachine(projectID: projectID, syncContainer: syncContainer, syncEngine: syncEngine)
        )
    }

    var body: some View {
        List {
            loadErrorSection

            Section {
                if let projectModel = machine.project {
                    Text(projectModel.name)
                        .font(.headline)
                        .lineLimit(3)

                    LabeledContent("Tasks", value: projectModel.taskCount == 1 ? "1 task" : "\(projectModel.taskCount) tasks")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Project not found")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Tasks") {
                ForEach(machine.tasks, id: \.id) { task in
                    NavigationLink {
                        TaskDetailView(taskID: task.id, syncContainer: syncContainer, syncEngine: syncEngine)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(task.title)
                                .font(.headline)
                                .lineLimit(3)

                            HStack(spacing: 8) {
                                Text(task.stateLabel)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if let assignee = task.assignee?.displayName {
                                    Text("Assignee: \(assignee)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                if !task.items.isEmpty {
                                    Text("\(task.items.count) items")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            taskPendingDelete = TaskDeletePrompt(id: task.id, title: task.title)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Project")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isShowingCreateTaskSheet = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
            }
        }
        .task {
            requestLoad(.onAppear)
        }
        .sheet(isPresented: $isShowingCreateTaskSheet) {
            TaskFormSheet(
                mode: .create(projectID: projectID),
                syncContainer: syncContainer,
                syncEngine: syncEngine
            )
        }
        .alert(
            "Delete Task?",
            isPresented: Binding(
                get: { taskPendingDelete != nil },
                set: { if !$0 { taskPendingDelete = nil } }
            ),
            presenting: taskPendingDelete
        ) { prompt in
            Button("Delete", role: .destructive) {
                machine.sendDelete(.request(taskID: prompt.id))
                taskPendingDelete = nil
            }
            Button("Cancel", role: .cancel) { taskPendingDelete = nil }
        } message: { prompt in
            Text("Delete \"\(prompt.title)\" from this project?")
        }
        .alert(
            "Delete Failed",
            isPresented: Binding(
                get: {
                    if case .failed = machine.deleteState { return true }
                    return false
                },
                set: { isPresented in
                    if !isPresented {
                        machine.sendDelete(.dismissError)
                    }
                }
            )
        ) {
            if case .failed(let presentation) = machine.deleteState,
               let retryActionTitle = presentation.retryActionTitle {
                Button(retryActionTitle) {
                    machine.sendDelete(.retry)
                }
            }
            Button("OK", role: .cancel) {
                machine.sendDelete(.dismissError)
            }
        } message: {
            if case .failed(let presentation) = machine.deleteState {
                Text(presentation.message)
            } else {
                Text("Could not delete this task.")
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
                syncEngine.startEarthquakeMode(for: .projectDetail(projectID: projectID))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Debug-only Earthquake Mode runs finite add/edit/delete overlap for this project screen.")
        }
        .background(
            ShakeDetector {
                guard !syncEngine.isEarthquakeModeRunning else { return }
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
            ProgressView("Loading project...")
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private func requestLoad(_ event: ScreenLoadEvent) {
        machine.send(event)
    }
}

private struct TaskDeletePrompt: Equatable {
    let id: String
    let title: String
}
