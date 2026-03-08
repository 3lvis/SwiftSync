import DemoCore
import SwiftUI

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
            if machine.taskStateOptions.isEmpty {
                LabeledContent("State") {
                    if machine.metadataLoadState.isLoading {
                        ProgressView()
                    } else {
                        Text("Unavailable").foregroundStyle(.secondary)
                    }
                }
            } else {
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
            }
        }
    }

    var assigneeSection: some View {
        Section("Assignee") {
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
        }
    }

    var authorSection: some View {
        Section("Author") {
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
        }
    }

    var reviewersSection: some View {
        Section("Reviewers") {
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
        }
    }

    var watchersSection: some View {
        Section("Watchers") {
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
        }
    }

    @ViewBuilder
    var loadErrorSection: some View {
        if let metadataError = machine.metadataLoadState.errorPresentation {
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
