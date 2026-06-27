import DemoCore
import SwiftUI

struct ProjectsRepresentable: UIViewControllerRepresentable {
    let syncEngine: DemoSyncEngine
    let onSelect: (String) -> Void

    func makeUIViewController(context: Context) -> ProjectsViewController {
        ProjectsViewController(syncEngine: syncEngine, onSelect: onSelect)
    }

    func updateUIViewController(_ uiViewController: ProjectsViewController, context: Context) {}
}

struct ProjectsView: View {
    let syncEngine: DemoSyncEngine
    @State private var selectedProjectID: String?

    var body: some View {
        NavigationStack {
            ProjectsRepresentable(syncEngine: syncEngine) { projectID in
                selectedProjectID = projectID
            }
            .navigationTitle("Projects")
            .navigationDestination(item: $selectedProjectID) { projectID in
                ProjectView(
                    projectID: projectID,
                    syncEngine: syncEngine
                )
            }
        }
    }
}
