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

    public let isUITesting: Bool
    public let syncContainer: SyncContainer
    public let syncEngine: DemoSyncEngine

    private let apiClient: FakeDemoAPIClient

    public init() {
        let launchConfiguration = LaunchConfiguration.current()
        self.isUITesting = launchConfiguration.isUITesting
        self.scenario = launchConfiguration.scenario
        self.apiClient = FakeDemoAPIClient(
            scenario: launchConfiguration.scenario,
            seedData: launchConfiguration.seedData,
            networkDelayMode: launchConfiguration.networkDelayMode
        )

        do {
            self.syncContainer = try Self.makeSyncContainer(storeURL: launchConfiguration.storeURL)
        } catch {
            fatalError(Self.formattedSyncContainerInitializationError(error))
        }

        self.syncEngine = DemoSyncEngine(syncContainer: syncContainer, apiClient: apiClient)
    }

    private static func makeSyncContainer(storeURL: URL) throws -> SyncContainer {
        let configuration = ModelConfiguration(url: storeURL)
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

    nonisolated private static func localStoreURL() -> URL {
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

private extension DemoRuntime {
    struct LaunchConfiguration {
        let scenario: DemoNetworkScenario
        let seedData: DemoSeedData?
        let storeURL: URL
        let isUITesting: Bool
        let networkDelayMode: FakeDemoAPIClient.NetworkDelayMode

        static func current() -> LaunchConfiguration {
            let environment = ProcessInfo.processInfo.environment
            let scenario = DemoNetworkScenario(rawValue: environment["SWIFTSYNC_DEMO_SCENARIO"] ?? "") ?? .fastStable

            guard environment["SWIFTSYNC_UI_TESTING"] == "1" else {
                return LaunchConfiguration(
                    scenario: scenario,
                    seedData: nil,
                    storeURL: DemoRuntime.localStoreURL(),
                    isUITesting: false,
                    networkDelayMode: .scenarioDriven
                )
            }

            let runID = environment["SWIFTSYNC_UI_TEST_RUN_ID"] ?? UUID().uuidString
            let storeURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftSyncDemoUITests", isDirectory: true)
                .appendingPathComponent(runID, isDirectory: true)
                .appendingPathComponent("client-cache.store")

            return LaunchConfiguration(
                scenario: scenario,
                seedData: DemoSeedData.generate(),
                storeURL: storeURL,
                isUITesting: true,
                networkDelayMode: .disabled
            )
        }
    }
}
