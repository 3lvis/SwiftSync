import XCTest
import SwiftData
@testable import SwiftSync

final class SyncContainerRecoveryTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case first
        case second
    }

    func testRecoveryPolicyResetAndRetryOnceRetriesAfterReset() throws {
        let config = ModelConfiguration(url: temporaryDirectory().appendingPathComponent("retry.store"))

        var attempts = 0
        var resetCalls = 0

        let value: Int = try SyncContainer._recoverContainerInitialization(
            recovery: .resetAndRetry,
            configurations: [config],
            makeContainer: {
                attempts += 1
                if attempts == 1 {
                    throw TestError.first
                }
                return 42
            },
            resetPersistentStores: { configs in
                resetCalls += 1
                XCTAssertEqual(configs.count, 1)
            }
        )

        XCTAssertEqual(value, 42)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(resetCalls, 1)
    }

    func testRecoveryPolicyNoneDoesNotResetOrRetry() {
        let config = ModelConfiguration(url: temporaryDirectory().appendingPathComponent("no-retry.store"))

        var attempts = 0
        var resetCalls = 0

        XCTAssertThrowsError(
            try SyncContainer._recoverContainerInitialization(
                recovery: .none,
                configurations: [config],
                makeContainer: {
                    attempts += 1
                    throw TestError.first
                },
                resetPersistentStores: { _ in
                    resetCalls += 1
                }
            )
        ) { error in
            XCTAssertEqual(error as? TestError, .first)
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(resetCalls, 0)
    }

    func testResetPersistentStoreFilesRemovesStoreAndPrefixedSidecarsButNotUnrelatedFiles() throws {
        let directory = temporaryDirectory().appendingPathComponent(UUID().uuidString, isDirectory: true)
        let storeURL = directory.appendingPathComponent("client-cache.store")

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let filesToCreate = [
            storeURL,
            directory.appendingPathComponent("client-cache.store-wal"),
            directory.appendingPathComponent("client-cache.store-shm"),
            directory.appendingPathComponent("client-cache.store.support"),
            directory.appendingPathComponent("unrelated.store")
        ]

        for url in filesToCreate {
            fm.createFile(atPath: url.path, contents: Data("x".utf8))
        }

        try SyncContainer._resetPersistentStoreFiles(for: [ModelConfiguration(url: storeURL)])

        XCTAssertFalse(fm.fileExists(atPath: storeURL.path))
        XCTAssertFalse(fm.fileExists(atPath: directory.appendingPathComponent("client-cache.store-wal").path))
        XCTAssertFalse(fm.fileExists(atPath: directory.appendingPathComponent("client-cache.store-shm").path))
        XCTAssertFalse(fm.fileExists(atPath: directory.appendingPathComponent("client-cache.store.support").path))
        XCTAssertTrue(fm.fileExists(atPath: directory.appendingPathComponent("unrelated.store").path))
    }

    func testRecoveryPolicyResetAndRetryOnceCanRecoverFromObjectiveCException() throws {
        let config = ModelConfiguration(url: temporaryDirectory().appendingPathComponent("objc-exception.store"))

        var attempts = 0
        var resetCalls = 0

        let value: Int = try SyncContainer._recoverContainerInitialization(
            recovery: .resetAndRetry,
            configurations: [config],
            makeContainer: {
                attempts += 1
                return try SyncContainer._executeCatchingObjectiveCException {
                    if attempts == 1 {
                        NSException(
                            name: .internalInconsistencyException,
                            reason: "Simulated unsupported migration exception"
                        ).raise()
                    }
                    return 7
                }
            },
            resetPersistentStores: { _ in
                resetCalls += 1
            }
        )

        XCTAssertEqual(value, 7)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(resetCalls, 1)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("SwiftSyncTests", isDirectory: true)
    }
}
