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
    private var loadState: ScreenLoadState = .idle {
        didSet { updateLoadStateUI() }
    }

    private lazy var statusContainer: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [statusIndicator, statusLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        return stack
    }()

    private let statusIndicator = UIActivityIndicatorView(style: .medium)

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.textAlignment = .center
        return label
    }()

    private lazy var retryButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.title = "Retry"
        let button = UIButton(configuration: config)
        button.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        return button
    }()

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
        tableView.backgroundView = statusContainer

        publisher.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                guard let self else { return }
                self.projects = rows
                var snapshot = NSDiffableDataSourceSnapshot<String, String>()
                snapshot.appendSections(["projects"])
                snapshot.appendItems(rows.map(\.id), toSection: "projects")
                self.diffableDataSource.apply(snapshot, animatingDifferences: true)

                if self.loadState == .loading, !rows.isEmpty {
                    self.loadState = .loaded
                }
            }
            .store(in: &cancellables)

        updateLoadStateUI()
        runInitialLoad()
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let projectID = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        onSelect(projectID)
    }

    // MARK: - Loading UI

    private func runInitialLoad() {
        guard loadState == .idle else { return }
        _Concurrency.Task { [weak self] in
            await self?.loadProjects()
        }
    }

    @objc
    private func retryTapped() {
        _Concurrency.Task { [weak self] in
            await self?.loadProjects()
        }
    }

    @MainActor
    private func loadProjects() async {
        loadState = .loading
        do {
            try await syncEngine.syncProjects()
            if projects.isEmpty {
                loadState = .loaded
            }
        } catch {
            loadState = .error(
                presentError(
                    error,
                    retryActionTitle: "Retry",
                    fallbackMessage: "Could not load projects."
                )
            )
        }
    }

    private func updateLoadStateUI() {
        switch loadState {
        case .idle:
            statusIndicator.stopAnimating()
            statusLabel.text = nil
            retryButton.isHidden = true
            tableView.backgroundView?.isHidden = true
        case .loading:
            statusIndicator.startAnimating()
            statusLabel.text = "Loading projects..."
            retryButton.isHidden = true
            tableView.backgroundView?.isHidden = false
        case .loaded:
            statusIndicator.stopAnimating()
            statusLabel.text = projects.isEmpty ? "No projects yet." : nil
            retryButton.isHidden = true
            tableView.backgroundView?.isHidden = !projects.isEmpty
        case .error(let presentation):
            statusIndicator.stopAnimating()
            statusLabel.text = presentation.message
            retryButton.isHidden = presentation.retryActionTitle == nil
            retryButton.setTitle(presentation.retryActionTitle, for: .normal)
            tableView.backgroundView?.isHidden = false
        }
    }

}
