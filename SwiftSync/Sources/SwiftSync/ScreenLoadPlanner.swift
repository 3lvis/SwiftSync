public enum ScreenLoadPlanner {
    public static func path(decisions: [LoadDecision]) -> ScopeLoadPath {
        if !decisions.isEmpty, decisions.allSatisfy({ $0 == .fresh }) {
            return .localFirstRefresh
        }

        return .networkFirst
    }
}
