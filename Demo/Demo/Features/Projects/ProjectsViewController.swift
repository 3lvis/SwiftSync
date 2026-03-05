import Combine
import SwiftSync
import UIKit

final class ProjectsViewController: UITableViewController {

    // MARK: - Dependencies

    private let syncContainer: SyncContainer
    private let syncEngine: DemoSyncEngine
    private let onSelect: (String) -> Void

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private var projects: [Project] = []

    private lazy var publisher = SyncQueryPublisher(
        Project.self,
        in: syncContainer,
        sortBy: [SortDescriptor(\Project.name), SortDescriptor(\Project.id)]
    )

    private lazy var diffableDataSource: UITableViewDiffableDataSource<String, String> = {
        let source = UITableViewDiffableDataSource<String, String>(tableView: tableView) { [weak self] tableView, indexPath, projectID in
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProjectCell", for: indexPath)
            guard let project = self?.projects.first(where: { $0.id == projectID }) else { return cell }
            var config = cell.defaultContentConfiguration()
            config.text = project.name
            config.secondaryText = project.taskCount == 1 ? "1 task" : "\(project.taskCount) tasks"
            config.secondaryTextProperties.color = .secondaryLabel
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        source.defaultRowAnimation = .fade
        return source
    }()

    // MARK: - Init

    @MainActor
    init(syncContainer: SyncContainer, syncEngine: DemoSyncEngine, onSelect: @escaping (String) -> Void) {
        self.syncContainer = syncContainer
        self.syncEngine = syncEngine
        self.onSelect = onSelect
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProjectCell")
        tableView.dataSource = diffableDataSource

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refresh

        publisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                guard let self else { return }
                self.projects = rows
                var snapshot = NSDiffableDataSourceSnapshot<String, String>()
                snapshot.appendSections(["projects"])
                snapshot.appendItems(rows.map(\.id), toSection: "projects")
                self.diffableDataSource.apply(snapshot, animatingDifferences: true)
            }
            .store(in: &cancellables)

        _Concurrency.Task { await syncEngine.loadProjects() }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let projectID = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        onSelect(projectID)
    }

    // MARK: - Actions

    @objc private func handleRefresh() {
        _Concurrency.Task {
            await syncEngine.loadProjects(reason: .pullToRefresh)
            await MainActor.run { self.tableView.refreshControl?.endRefreshing() }
        }
    }
}
