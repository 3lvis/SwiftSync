import Foundation
import Testing
@testable import SwiftSync

struct ScopeSyncStatusReducerTests {
    @Test("network-first start enters loading")
    func networkFirstStartPhase() {
        let now = Date(timeIntervalSince1970: 10)
        let status = ScopeSyncStatusReducer.start(path: .networkFirst, now: now)

        #expect(status.phase == .loading)
        #expect(status.path == .networkFirst)
        #expect(status.errorMessage == nil)
        #expect(status.updatedAt == now)
    }

    @Test("local-first start enters refreshing")
    func localFirstStartPhase() {
        let status = ScopeSyncStatusReducer.start(path: .localFirstRefresh, now: Date(timeIntervalSince1970: 11))
        #expect(status.phase == .refreshing)
    }

    @Test("success settles to idle and clears errors")
    func successTransition() {
        let started = ScopeSyncStatus(phase: .failed, path: .networkOnly, errorMessage: "boom", updatedAt: Date(timeIntervalSince1970: 12))
        let done = ScopeSyncStatusReducer.succeed(previous: started, now: Date(timeIntervalSince1970: 13))

        #expect(done.phase == .idle)
        #expect(done.path == .networkOnly)
        #expect(done.errorMessage == nil)
        #expect(done.updatedAt == Date(timeIntervalSince1970: 13))
    }

    @Test("failure preserves path and sets message")
    func failureTransition() {
        let started = ScopeSyncStatusReducer.start(path: .localFirstRefresh, now: Date(timeIntervalSince1970: 20))
        let failed = ScopeSyncStatusReducer.fail(previous: started, errorMessage: "offline", now: Date(timeIntervalSince1970: 21))

        #expect(failed.phase == .failed)
        #expect(failed.path == .localFirstRefresh)
        #expect(failed.errorMessage == "offline")
    }
}
