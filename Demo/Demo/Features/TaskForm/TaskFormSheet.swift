import SwiftData
import DemoCore
import SwiftSync
import SwiftUI

struct TaskFormSheet: View {
    let mode: TaskFormMode
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    @Environment(\.dismiss) private var dismiss

    // Throwaway context — autosave disabled. Never saved to the store.
    // On cancel it is simply released; on save we export the values and call the API.
    let editContext: ModelContext

    // The draft lives in editContext. For create it is a freshly-inserted Task.
    // For edit it is the same row fetched into this isolated context.
    // Relationship arrays (reviewers, watchers) are real [User] objects from editContext,
    // so the pickers can assign them directly without cross-context crashes.
    @State var draft: Task

    @StateObject var machine: TaskFormMachine
    @State var newItemTitle = ""
    @State var itemEditMode: EditMode = .inactive

    init(mode: TaskFormMode, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.mode = mode
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        let ctx = ModelContext(syncContainer.modelContainer)
        ctx.autosaveEnabled = false
        self.editContext = ctx
        _machine = StateObject(
            wrappedValue: TaskFormMachine(syncContainer: syncContainer, syncEngine: syncEngine, editContext: ctx)
        )

        switch mode {
        case .create(let projectID):
            let task = Task(projectID: projectID)
            ctx.insert(task)
            _draft = State(initialValue: task)

        case .edit(let task):
            let taskID = task.id
            let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == taskID })
            let fetched = (try? ctx.fetch(descriptor))?.first
            // Fallback should never be reached in practice — the row is always in the store.
            // If it somehow is, we fall back to the passed object (which lives in mainContext,
            // so edits won't reach the store either, preserving the no-save guarantee).
            _draft = State(initialValue: fetched ?? task)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                loadErrorSection
                titleSection
                descriptionSection
                itemsSection
                stateSection
                assigneeSection
                if case .create = mode { authorSection }
                reviewersSection
                watchersSection
            }
            .environment(\.editMode, $itemEditMode)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(machine.saveState == .submitting)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        machine.send(.save(mode: mode, draft: draft, onSuccess: {
                            dismiss()
                        }))
                    } label: {
                        HStack(spacing: 6) {
                            if machine.saveState == .submitting { ProgressView().controlSize(.small) }
                            Text(confirmLabel)
                        }
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .task {
            machine.send(.metadata(.onAppear))
        }
        .task(id: "\(machine.taskStateOptions.map(\.id).joined(separator: ","))|\(machine.users.map(\.id).joined(separator: ","))") {
            machine.applyDefaultsIfNeeded(to: draft)
        }
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: {
                    if case .failed = machine.saveState { return true }
                    return false
                },
                set: { isPresented in
                    if !isPresented {
                        machine.send(.dismissSaveError)
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if case .failed(let error) = machine.saveState {
                Text(error.message)
            } else {
                Text("Unknown error")
            }
        }
        .presentationDetents([.large])
    }
}
