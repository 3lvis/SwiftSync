import Combine
import DemoCore
import SwiftSync
import UIKit

final class ProjectsViewController: UITableViewController {

    // MARK: - Dependencies

    private let onSelect: (String) -> Void

    // MARK: - State

    private var cancellables = Set<AnyCancellable>()
    private let machine: ProjectsListMachine

    private lazy var statusContainer: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [statusIndicator, statusLabel])
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

    private lazy var diffableDataSource: UITableViewDiffableDataSource<String, String> = {
        let source = UITableViewDiffableDataSource<String, String>(tableView: tableView) { [weak self] tableView, indexPath, projectID in
            let cell = tableView.dequeueReusableCell(withIdentifier: "ProjectCell", for: indexPath)
            guard let project = self?.machine.rows.first(where: { $0.id == projectID }) else { return cell }
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
        self.onSelect = onSelect
        self.machine = ProjectsListMachine(syncContainer: syncContainer, syncEngine: syncEngine)
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

        machine.$rows
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rows in
                guard let self else { return }
                var snapshot = NSDiffableDataSourceSnapshot<String, String>()
                snapshot.appendSections(["projects"])
                snapshot.appendItems(rows.map(\.id), toSection: "projects")
                self.diffableDataSource.apply(snapshot, animatingDifferences: true)
            }
            .store(in: &cancellables)

        machine.$loadState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.renderLoadState(state)
            }
            .store(in: &cancellables)

        renderLoadState(machine.loadState)
        machine.send(.onAppear)
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let projectID = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        onSelect(projectID)
    }

    // MARK: - Loading UI

    private func renderLoadState(_ state: ScreenLoadState) {
        switch state {
        case .idle:
            statusIndicator.stopAnimating()
            statusLabel.text = nil
            tableView.backgroundView?.isHidden = true
        case .loading:
            statusIndicator.startAnimating()
            statusLabel.text = "Loading projects..."
            tableView.backgroundView?.isHidden = false
        case .loaded:
            statusIndicator.stopAnimating()
            statusLabel.text = machine.rows.isEmpty ? "No projects yet." : nil
            tableView.backgroundView?.isHidden = !machine.rows.isEmpty
        case .error(let presentation):
            statusIndicator.stopAnimating()
            statusLabel.text = presentation.message
            tableView.backgroundView?.isHidden = false
        }
    }

}
