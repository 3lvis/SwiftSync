import DemoCore
import SwiftSync
import SwiftUI

struct ProjectsRepresentable: UIViewControllerRepresentable {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine
    let onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> ProjectsViewController {
        ProjectsViewController(syncContainer: syncContainer, syncEngine: syncEngine, onSelect: onSelect)
    }

    func updateUIViewController(_ uiViewController: ProjectsViewController, context: Context) {}
}

struct ProjectsView: View {
    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine
    @State private var selectedProjectID: String?

    var body: some View {
        NavigationStack {
            ProjectsRepresentable(syncContainer: syncContainer, syncEngine: syncEngine) { projectID in
                selectedProjectID = projectID
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $selectedProjectID) { projectID in
                ProjectView(
                    projectID: projectID,
                    syncContainer: syncContainer,
                    syncEngine: syncEngine
                )
            }
        }
    }
}
