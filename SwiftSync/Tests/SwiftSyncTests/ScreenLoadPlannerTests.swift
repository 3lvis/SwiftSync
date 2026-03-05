import Testing
@testable import SwiftSync

struct ScreenLoadPlannerTests {
    @Test("all fresh decisions use local-first refresh")
    func allFreshUsesLocalFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.fresh, .fresh])
        #expect(path == .localFirstRefresh)
    }

    @Test("empty decision uses network-first")
    func emptyUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.empty])
        #expect(path == .networkFirst)
    }

    @Test("stale decision uses network-first")
    func staleUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.stale])
        #expect(path == .networkFirst)
    }

    @Test("mixed fresh and stale uses network-first")
    func mixedUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [.fresh, .stale])
        #expect(path == .networkFirst)
    }

    @Test("empty decision list uses network-first")
    func emptyListUsesNetworkFirst() {
        let path = ScreenLoadPlanner.path(decisions: [])
        #expect(path == .networkFirst)
    }
}
