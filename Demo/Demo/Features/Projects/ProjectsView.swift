import DemoCore
import SwiftSync
import SwiftUI

struct ProjectsView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine
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
