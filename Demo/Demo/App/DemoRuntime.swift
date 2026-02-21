import Combine
import Foundation
import SwiftData
import SwiftSync

@MainActor
final class DemoRuntime: ObservableObject {
    @Published var scenario: DemoNetworkScenario {
        didSet {
            apiClient.scenario = scenario
        }
    }

    let syncContainer: SyncContainer
    let syncEngine: DemoSyncEngine

    private let apiClient: FakeDemoAPIClient

    init() {
        self.scenario = .fastStable
        self.apiClient = FakeDemoAPIClient(scenario: .fastStable)

        do {
            self.syncContainer = try SyncContainer(
                for: Project.self,
                User.self,
                Task.self,
                Tag.self,
                Comment.self,
                configurations: ModelConfiguration()
            )
        } catch {
            fatalError("Failed to initialize SyncContainer: \(error)")
        }

        self.syncEngine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)
    }

    func bootstrapIfNeeded() async {
        await syncEngine.bootstrapIfNeeded()
    }
}
