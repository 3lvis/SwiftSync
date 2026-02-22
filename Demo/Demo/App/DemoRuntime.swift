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
            self.syncContainer = try Self.makeSyncContainerResettingLocalStoreIfNeeded()
        } catch {
            fatalError("Failed to initialize SyncContainer: \(error)")
        }

        self.syncEngine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)
    }

    func bootstrapIfNeeded() async {
        await syncEngine.bootstrapIfNeeded()
    }

    private static func makeSyncContainerResettingLocalStoreIfNeeded() throws -> SyncContainer {
        let storeURL = localStoreURL()
        let configuration = ModelConfiguration(url: storeURL)

        do {
            return try makeSyncContainer(configuration: configuration)
        } catch {
            // Demo schema changes are frequent. Reset the local cache store and retry once.
            try removeLocalStoreFiles(at: storeURL)
            return try makeSyncContainer(configuration: configuration)
        }
    }

    private static func makeSyncContainer(configuration: ModelConfiguration) throws -> SyncContainer {
        try SyncContainer(
            for: Project.self,
            User.self,
            Task.self,
            Tag.self,
            Comment.self,
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

    private static func removeLocalStoreFiles(at storeURL: URL) throws {
        let directory = storeURL.deletingLastPathComponent()
        let baseName = storeURL.lastPathComponent

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let siblingNames = [
            baseName,
            "\(baseName)-shm",
            "\(baseName)-wal"
        ]

        for name in siblingNames {
            let url = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
    }
}
