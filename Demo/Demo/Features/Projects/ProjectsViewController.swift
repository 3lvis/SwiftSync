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
    private let loadMachine: ScreenLoadMachine

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
        self.loadMachine = ScreenLoadMachine { error in
            presentError(error, retryActionTitle: "Retry", fallbackMessage: "Could not load projects.")
        }
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
            }
            .store(in: &cancellables)

        loadMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.renderLoadState(state)
            }
            .store(in: &cancellables)

        renderLoadState(loadMachine.state)
        requestLoad(.onAppear)
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let projectID = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        onSelect(projectID)
    }

    // MARK: - Loading UI

    @objc
    private func retryTapped() {
        requestLoad(.retry)
    }

    private func requestLoad(_ event: ScreenLoadEvent) {
        loadMachine.send(event, run: { [weak self] in
            guard let self else { return }
            try await self.syncEngine.syncProjects()
        })
    }

    private func renderLoadState(_ state: ScreenLoadState) {
        switch state {
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
