public enum ScreenLoadPlanner {
    public static func path(decisions: [LoadDecision], forceNetworkRefresh: Bool) -> ScopeLoadPath {
        if forceNetworkRefresh {
            return .networkOnly
        }

        if decisions.allSatisfy({ $0 == .fresh }) {
            return .localFirstRefresh
        }

        return .networkFirst
    }
}
