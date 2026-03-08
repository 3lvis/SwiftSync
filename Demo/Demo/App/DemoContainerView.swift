import DemoCore
import SwiftSync
import SwiftUI

struct DemoContainerView: View {
    let syncContainer: SyncContainer
    @ObservedObject var syncEngine: DemoSyncEngine

    var body: some View {
        ProjectsView(syncContainer: syncContainer, syncEngine: syncEngine)
    }
}
