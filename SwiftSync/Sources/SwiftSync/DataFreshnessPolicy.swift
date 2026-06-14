import Foundation

struct DataKey: Hashable, Sendable {
    let namespace: String
    let id: String?

    init(namespace: String, id: String? = nil) {
        self.namespace = namespace
        self.id = id
    }
}

enum LoadDecision: Sendable, Equatable {
    case empty
    case fresh
    case stale
}

struct DataFreshnessPolicy: Sendable {
    let defaultTTL: TimeInterval
    let ttlByNamespace: [String: TimeInterval]

    init(defaultTTL: TimeInterval, ttlByNamespace: [String: TimeInterval]) {
        self.defaultTTL = defaultTTL
        self.ttlByNamespace = ttlByNamespace
    }

    func decision(
        for key: DataKey,
        hasLocalData: Bool,
        lastSuccessfulSync: Date?,
        now: Date = Date()
    ) -> LoadDecision {
        guard hasLocalData else { return .empty }
        guard let lastSuccessfulSync else { return .stale }

        let ttl = ttlByNamespace[key.namespace] ?? defaultTTL
        let age = now.timeIntervalSince(lastSuccessfulSync)

        return age <= ttl ? .fresh : .stale
    }
}
