import UIKit
import DemoCore
import SwiftSync

final class ProjectsViewController: UITableViewController {

    private let onSelect: (String) -> Void

    private let machine: ProjectsViewMachine

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
            cell.accessibilityIdentifier = "projects.row.\(projectID)"
            return cell
        }
        source.defaultRowAnimation = .fade
        return source
    }()

    @MainActor
    init(syncEngine: DemoSyncEngine, onSelect: @escaping (String) -> Void) {
        self.onSelect = onSelect
        self.machine = ProjectsViewMachine(syncEngine: syncEngine)
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ProjectCell")
        tableView.dataSource = diffableDataSource
        tableView.backgroundView = statusContainer
        tableView.accessibilityIdentifier = "projects.table"
        statusLabel.accessibilityIdentifier = "projects.status"

        SwiftSync.observeContinuously { [weak self] in
            guard let self else { return }
            var snapshot = NSDiffableDataSourceSnapshot<String, String>()
            snapshot.appendSections(["projects"])
            snapshot.appendItems(machine.rows.map { $0.id }, toSection: "projects")
            diffableDataSource.apply(snapshot, animatingDifferences: true)
        }
        SwiftSync.observeContinuously { [weak self] in
            guard let self else { return }
            let status = Self.statusPresentation(for: machine.statusState)
            if status.isAnimating { statusIndicator.startAnimating() } else { statusIndicator.stopAnimating() }
            statusLabel.text = status.message
            tableView.backgroundView?.isHidden = status.isBackgroundHidden
        }
        machine.send(.onAppear)
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let projectID = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        onSelect(projectID)
    }

    // What the status area shows for a state, as a value — so the decision is readable, and testable,
    // without a view controller to read it off.
    static func statusPresentation(for state: ProjectsListStatusState) -> (isAnimating: Bool, message: String?, isBackgroundHidden: Bool) {
        switch state {
        case .hidden:
            return (isAnimating: false, message: nil, isBackgroundHidden: true)
        case .loading:
            return (isAnimating: true, message: "Loading projects...", isBackgroundHidden: false)
        case .empty:
            return (isAnimating: false, message: "No projects yet.", isBackgroundHidden: false)
        case .error(let presentation):
            return (isAnimating: false, message: presentation.message, isBackgroundHidden: false)
        }
    }

}
