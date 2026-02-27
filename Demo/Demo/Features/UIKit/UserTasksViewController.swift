import Combine
import SwiftData
import SwiftSync
import UIKit

// ---------------------------------------------------------------------------
// UserTasksViewController
//
// A UIKit screen that lists all Tasks assigned to, reviewed by, or watched by
// a given User.  It uses SyncQueryPublisher — the UIKit-compatible counterpart
// to @SyncQuery — to stay live as the sync engine updates the store.
//
// Flow:
//   TaskDetailView (SwiftUI)
//     └─ tap Assignee / Reviewer / Watcher row
//          └─ NavigationLink → UserTasksScreen (UIViewControllerRepresentable)
//               └─ embeds this UITableViewController
// ---------------------------------------------------------------------------

final class UserTasksViewController: UITableViewController {

    // MARK: - Dependencies

    private let user: User
    private let syncContainer: SyncContainer

    // MARK: - State

    /// Publisher for tasks where the user appears as assignee.
    private var assignedPublisher: SyncQueryPublisher<Task>!

    /// Publisher for tasks where the user appears in the reviewers list.
    private var reviewerPublisher: SyncQueryPublisher<Task>!

    /// Publisher for tasks where the user appears in the watchers list.
    private var watcherPublisher: SyncQueryPublisher<Task>!

    private var cancellables = Set<AnyCancellable>()
    private var dataSource: UITableViewDiffableDataSource<String, String>!

    /// Merged, deduplicated, sorted task IDs derived from all three publishers.
    private var displayedTasks: [Task] = []

    // MARK: - Init

    @MainActor
    init(user: User, syncContainer: SyncContainer) {
        self.user = user
        self.syncContainer = syncContainer
        super.init(style: .insetGrouped)

        // Three separate publishers — one per role the user can have on a task.
        assignedPublisher = SyncQueryPublisher(
            Task.self,
            relatedTo: User.self,
            relatedID: user.id,
            through: \Task.assignee,
            in: syncContainer,
            sortBy: [SortDescriptor(\Task.title)]
        )

        reviewerPublisher = SyncQueryPublisher(
            Task.self,
            relatedTo: User.self,
            relatedID: user.id,
            through: \Task.reviewers,
            in: syncContainer,
            sortBy: [SortDescriptor(\Task.title)]
        )

        watcherPublisher = SyncQueryPublisher(
            Task.self,
            relatedTo: User.self,
            relatedID: user.id,
            through: \Task.watchers,
            in: syncContainer,
            sortBy: [SortDescriptor(\Task.title)]
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureTableView()
        configureDataSource()
        subscribeToPublishers()
    }

    // MARK: - Table view setup

    private func configureTableView() {
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TaskCell")
    }

    private func configureDataSource() {
        dataSource = UITableViewDiffableDataSource(tableView: tableView) { [weak self] tableView, indexPath, taskID in
            let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell", for: indexPath)
            guard let task = self?.displayedTasks.first(where: { $0.id == taskID }) else {
                return cell
            }
            var config = cell.defaultContentConfiguration()
            config.text = task.title
            config.secondaryText = Self.roleDescription(
                task: task,
                user: self?.user
            )
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryType = .none
            return cell
        }
        dataSource.defaultRowAnimation = .fade
    }

    // MARK: - Combine subscriptions

    private func subscribeToPublishers() {
        // Merge all three publishers — whenever any changes, recompute the deduplicated list.
        Publishers.CombineLatest3(
            assignedPublisher.$rows,
            reviewerPublisher.$rows,
            watcherPublisher.$rows
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] assigned, reviewers, watchers in
            self?.applyMergedTasks(assigned: assigned, reviewers: reviewers, watchers: watchers)
        }
        .store(in: &cancellables)
    }

    private func applyMergedTasks(assigned: [Task], reviewers: [Task], watchers: [Task]) {
        // Deduplicate by ID (a task can appear in multiple roles), preserve title sort order.
        var seen = Set<String>()
        var merged: [Task] = []
        for task in (assigned + reviewers + watchers) {
            if seen.insert(task.id).inserted {
                merged.append(task)
            }
        }
        merged.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        displayedTasks = merged

        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections(["tasks"])
        snapshot.appendItems(merged.map(\.id), toSection: "tasks")
        dataSource.apply(snapshot, animatingDifferences: true)
    }

    // MARK: - Helpers

    private static func roleDescription(task: Task, user: User?) -> String {
        guard let user else { return "" }
        var roles: [String] = []
        if task.assignee?.id == user.id { roles.append("Assignee") }
        if task.reviewers.contains(where: { $0.id == user.id }) { roles.append("Reviewer") }
        if task.watchers.contains(where: { $0.id == user.id }) { roles.append("Watcher") }
        return roles.joined(separator: " · ")
    }
}
