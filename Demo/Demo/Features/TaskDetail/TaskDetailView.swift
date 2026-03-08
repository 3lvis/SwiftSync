import SwiftData
import DemoCore
import SwiftSync
import SwiftUI

struct TaskDetailView: View {
    let taskID: String
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    @StateObject var machine: TaskDetailMachine
    @State private var showingEditSheet = false

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
            machine.send(.onAppear)
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
        .overlay {
            loadOverlay
        }
    }
}
