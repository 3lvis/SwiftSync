import Foundation
import Observation
import SwiftData
import SwiftSync

@MainActor
@Observable
public final class DemoRuntime {
    public var scenario: DemoNetworkScenario {
        didSet {
            apiClient.scenario = scenario
        }
    }

    public let syncContainer: SyncContainer
    public let syncEngine: DemoSyncEngine

    private let apiClient: FakeDemoAPIClient

    public init() {
        self.scenario = .fastStable
        self.apiClient = FakeDemoAPIClient(scenario: .fastStable)

        do {
            self.syncContainer = try Self.makeSyncContainer()
        } catch {
            fatalError(Self.formattedSyncContainerInitializationError(error))
        }

        self.syncEngine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)
    }

    private static func makeSyncContainer() throws -> SyncContainer {
        let configuration = ModelConfiguration(url: localStoreURL())
        return try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            Item.self,
            TaskStateOption.self,
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
