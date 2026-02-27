import Combine
import SwiftData
import SwiftSync
import UIKit

final class UserTasksViewController: UITableViewController {

    // MARK: - Dependencies

    private let user: User
    private let syncContainer: SyncContainer

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var displayedTasks: [Task] = []

    private lazy var assignedPublisher = SyncQueryPublisher(
        Task.self,
        relatedTo: User.self,
        relatedID: user.id,
        through: \Task.assignee,
        in: syncContainer,
        sortBy: [SortDescriptor(\Task.title)]
    )

    private lazy var reviewerPublisher = SyncQueryPublisher(
        Task.self,
        relatedTo: User.self,
        relatedID: user.id,
        through: \Task.reviewers,
        in: syncContainer,
        sortBy: [SortDescriptor(\Task.title)]
    )

    private lazy var watcherPublisher = SyncQueryPublisher(
        Task.self,
        relatedTo: User.self,
        relatedID: user.id,
        through: \Task.watchers,
        in: syncContainer,
        sortBy: [SortDescriptor(\Task.title)]
    )

    private lazy var diffableDataSource: UITableViewDiffableDataSource<String, String> = {
        let source = UITableViewDiffableDataSource<String, String>(tableView: tableView) { [weak self] tableView, indexPath, taskID in
            let cell = tableView.dequeueReusableCell(withIdentifier: "TaskCell", for: indexPath)
            guard let task = self?.displayedTasks.first(where: { $0.id == taskID }) else { return cell }
            var config = cell.defaultContentConfiguration()
            config.text = task.title
            config.secondaryText = self.map { Self.roleDescription(task: task, user: $0.user) }
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryType = .none
            return cell
        }
        source.defaultRowAnimation = .fade
        return source
    }()

    // MARK: - Init

    @MainActor
    init(user: User, syncContainer: SyncContainer) {
        self.user = user
        self.syncContainer = syncContainer
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "TaskCell")
        tableView.dataSource = diffableDataSource
        Publishers.CombineLatest3(
            assignedPublisher.$rows,
            reviewerPublisher.$rows,
            watcherPublisher.$rows
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] assigned, reviewers, watchers in
            guard let self else { return }
            let merged = Self.merge(assigned: assigned, reviewers: reviewers, watchers: watchers)
            self.displayedTasks = merged
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections(["tasks"])
            snapshot.appendItems(merged.map(\.id), toSection: "tasks")
            self.diffableDataSource.apply(snapshot, animatingDifferences: true)
        }
        .store(in: &cancellables)
    }

    // MARK: - Pure helpers

    private static func merge(assigned: [Task], reviewers: [Task], watchers: [Task]) -> [Task] {
        var seen = Set<String>()
        return (assigned + reviewers + watchers)
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private static func roleDescription(task: Task, user: User) -> String {
        var roles: [String] = []
        if task.assignee?.id == user.id { roles.append("Assignee") }
        if task.reviewers.contains(where: { $0.id == user.id }) { roles.append("Reviewer") }
        if task.watchers.contains(where: { $0.id == user.id }) { roles.append("Watcher") }
        return roles.joined(separator: " · ")
    }
}
