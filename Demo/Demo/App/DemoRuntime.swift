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
            self.syncContainer = try Self.makeSyncContainer()
        } catch {
            fatalError(Self.formattedSyncContainerInitializationError(error))
        }

        self.syncEngine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)
    }

    func bootstrapIfNeeded() async {
        await syncEngine.bootstrapIfNeeded()
    }

    private static func makeSyncContainer() throws -> SyncContainer {
        let configuration = ModelConfiguration(url: localStoreURL())
        return try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            ChecklistItem.self,
            TaskStateOption.self,
            UserRoleOption.self,
            recoverOnFailure: true,
            configurations: configuration
        )
    }

    private static func localStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return appSupport
            .appendingPathComponent("SwiftSyncDemo", isDirectory: true)
            .appendingPathComponent("client-cache.store")
    }

    private static func formattedSyncContainerInitializationError(_ error: Error) -> String {
        let detail = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        return "Failed to initialize SyncContainer.\n\(detail)"
    }
}
