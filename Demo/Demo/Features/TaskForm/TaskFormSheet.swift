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
    @State private var draft: Task

    @State private var machine: TaskFormMachine
    @State private var newItemTitle = ""
    @State private var itemEditMode: EditMode = .inactive

    init(mode: TaskFormMode, syncContainer: SyncContainer, syncEngine: DemoSyncEngine) {
        self.mode = mode
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine

        let ctx = ModelContext(syncContainer.modelContainer)
        ctx.autosaveEnabled = false
        self.editContext = ctx
        _machine = State(
            initialValue: TaskFormMachine(syncContainer: syncContainer, syncEngine: syncEngine, editContext: ctx)
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
            Form { content }
            .environment(\.editMode, $itemEditMode)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task(loadMetadata)
        .task(id: defaultsTaskID, applyDefaults)
        .animation(.snappy(duration: 0.2), value: itemIDs)
        .taskFormPresentations(
            saveFailureIsPresented: saveFailureIsPresented,
            saveFailureMessage: saveFailureMessage
        )
        .presentationDetents([.large])
    }
}

extension TaskFormSheet {
    @ViewBuilder
    var content: some View {
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

    private var defaultsTaskID: String {
        "\(machine.taskStateOptions.map(\.id).joined(separator: ","))|\(machine.users.map(\.id).joined(separator: ","))"
    }

    private var itemIDs: [String] {
        machine.sortedItems(in: draft).map(\.id)
    }

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Cancel") { dismiss() }
                .disabled(machine.saveState == .submitting)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: save) {
                saveButtonLabel
            }
            .disabled(isSaveDisabled)
        }
    }

    var navigationTitle: String {
        switch mode {
        case .create: "New Task"
        case .edit: "Edit Task"
        }
    }

    var confirmLabel: String {
        switch mode {
        case .create: "Create"
        case .edit: "Save"
        }
    }

    var isSaveDisabled: Bool {
        guard machine.saveState != .submitting,
              !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return true }
        if case .create = mode {
            return draft.state.isEmpty || draft.authorID.isEmpty
        }
        return false
    }

    @ViewBuilder
    var saveButtonLabel: some View {
        HStack(spacing: 6) {
            if machine.saveState == .submitting {
                ProgressView().controlSize(.small)
            }
            Text(confirmLabel)
        }
    }

    var saveFailureIsPresented: Binding<Bool> {
        Binding(
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
    }

    var saveFailureMessage: String {
        if case .failed(let error) = machine.saveState {
            return error.message
        }
        return "Unknown error"
    }

    func save() {
        machine.send(.save(mode: mode, draft: draft, onSuccess: {
            dismiss()
        }))
    }

    func loadMetadata() {
        machine.send(.metadata(.onAppear))
    }

    func applyDefaults() {
        machine.applyDefaultsIfNeeded(to: draft)
    }

    func itemTitleBinding(for item: Item) -> Binding<String> {
        Binding(
            get: { item.title },
            set: { newValue in
                _ = machine.mutateItems(.updateTitle(item: item, title: newValue), in: draft)
            }
        )
    }
}

private extension View {
    func taskFormPresentations(
        saveFailureIsPresented: Binding<Bool>,
        saveFailureMessage: String
    ) -> some View {
        self.alert("Save Failed", isPresented: saveFailureIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveFailureMessage)
        }
    }
}

extension TaskFormSheet {
    var titleSection: some View {
        Section("Title") {
            TextEditor(text: $draft.title)
                .frame(minHeight: 60)
        }
    }

    var descriptionSection: some View {
        Section("Description") {
            TextEditor(text: $draft.descriptionText)
                .frame(minHeight: 120)
        }
    }

    var itemsSection: some View {
        let items = machine.sortedItems(in: draft)

        return Section("Items") {
            HStack(spacing: 8) {
                TextField("Add item...", text: $newItemTitle)
                    .textInputAutocapitalization(.sentences)

                Button("Add") {
                    if machine.mutateItems(.add(title: newItemTitle), in: draft) {
                        newItemTitle = ""
                    }
                }
                .disabled(newItemTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if items.count > 1 {
                Button(itemEditMode == .active ? "Done Reordering" : "Reorder Items") {
                    withAnimation(.snappy(duration: 0.2)) {
                        itemEditMode = itemEditMode == .active ? .inactive : .active
                    }
                }
            }

            if items.isEmpty {
                Text("No items")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { item in
                    HStack(spacing: 10) {
                        TextField("Item title", text: itemTitleBinding(for: item))

                        Spacer(minLength: 4)

                        Button(role: .destructive) {
                            _ = machine.mutateItems(.delete(item), in: draft)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { source, destination in
                    _ = machine.mutateItems(.move(from: source, to: destination), in: draft)
                }
            }
        }
    }

    var stateSection: some View {
        Section("State") {
            switch machine.taskStateOptionsState {
            case .loading:
                LabeledContent("State") {
                    ProgressView("Loading states...")
                }
            case .available:
                ForEach(machine.taskStateOptions, id: \.id) { option in
                    Button {
                        draft.state = option.id
                        draft.stateLabel = option.label
                    } label: {
                        HStack {
                            Text(option.label).foregroundStyle(.primary)
                            Spacer()
                            if draft.state == option.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            case .unavailable:
                LabeledContent("State") {
                    Text("Unavailable").foregroundStyle(.secondary)
                }
            }
        }
    }

    var assigneeSection: some View {
        Section("Assignee") {
            switch machine.userOptionsState {
            case .loading:
                LabeledContent("People") {
                    ProgressView("Loading people...")
                }
            case .available:
                Button {
                    draft.assigneeID = nil
                } label: {
                    HStack {
                        Text("Unassigned").foregroundStyle(.primary)
                        Spacer()
                        if draft.assigneeID == nil {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                ForEach(machine.users, id: \.id) { user in
                    Button {
                        draft.assigneeID = user.id
                    } label: {
                        HStack {
                            Text(user.displayName).foregroundStyle(.primary)
                            Spacer()
                            if draft.assigneeID == user.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            case .unavailable:
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var authorSection: some View {
        Section("Author") {
            switch machine.userOptionsState {
            case .loading:
                LabeledContent("People") {
                    ProgressView("Loading people...")
                }
            case .available:
                ForEach(machine.users, id: \.id) { user in
                    Button {
                        draft.authorID = user.id
                    } label: {
                        HStack {
                            Text(user.displayName).foregroundStyle(.primary)
                            Spacer()
                            if draft.authorID == user.id {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            case .unavailable:
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var reviewersSection: some View {
        Section("Reviewers") {
            switch machine.userOptionsState {
            case .loading:
                LabeledContent("People") {
                    ProgressView("Loading people...")
                }
            case .available:
                ForEach(machine.users, id: \.id) { user in
                    Button {
                        if draft.reviewers.contains(where: { $0.id == user.id }) {
                            draft.reviewers.removeAll(where: { $0.id == user.id })
                        } else {
                            draft.reviewers.append(user)
                        }
                    } label: {
                        HStack {
                            Text(user.displayName).foregroundStyle(.primary)
                            Spacer()
                            if draft.reviewers.contains(where: { $0.id == user.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            case .unavailable:
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    var watchersSection: some View {
        Section("Watchers") {
            switch machine.userOptionsState {
            case .loading:
                LabeledContent("People") {
                    ProgressView("Loading people...")
                }
            case .available:
                ForEach(machine.users, id: \.id) { user in
                    Button {
                        if draft.watchers.contains(where: { $0.id == user.id }) {
                            draft.watchers.removeAll(where: { $0.id == user.id })
                        } else {
                            draft.watchers.append(user)
                        }
                    } label: {
                        HStack {
                            Text(user.displayName).foregroundStyle(.primary)
                            Spacer()
                            if draft.watchers.contains(where: { $0.id == user.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            case .unavailable:
                Text("Unavailable")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    var loadErrorSection: some View {
        if let metadataError = machine.metadataErrorPresentation {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text(metadataError.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
