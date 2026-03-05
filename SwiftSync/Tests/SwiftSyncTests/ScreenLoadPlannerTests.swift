import Testing
@testable import SwiftSync

struct ScreenLoadPlannerTests {
    @Test("force refresh always uses network-only")
    func forceRefreshUsesNetworkOnly() {
        let path = ScreenLoadPlanner.path(decisions: [.fresh], forceNetworkRefresh: true)
        #expect(path == .networkOnly)
    }

    @Test("all fresh decisions use local-first refresh")
    func allFreshUsesLocalFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.fresh, .fresh], forceNetworkRefresh: false)
        #expect(path == .localFirstRefresh)
    }

    @Test("empty decision uses network-first")
    func emptyUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.empty], forceNetworkRefresh: false)
        #expect(path == .networkFirst)
    }

    @Test("stale decision uses network-first")
    func staleUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.stale], forceNetworkRefresh: false)
        #expect(path == .networkFirst)
    }

    @Test("mixed fresh and stale uses network-first")
    func mixedUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.fresh, .stale], forceNetworkRefresh: false)
        #expect(path == .networkFirst)
    }
}
