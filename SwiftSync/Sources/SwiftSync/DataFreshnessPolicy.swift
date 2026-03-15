import Foundation

public struct DataKey: Hashable, Sendable {
    public let namespace: String
    public let id: String?

    public init(namespace: String, id: String? = nil) {
        self.namespace = namespace
        self.id = id
    }
}

public enum LoadDecision: Sendable, Equatable {
    case empty
    case fresh
    case stale
}

public struct DataFreshnessPolicy: Sendable {
    public let defaultTTL: TimeInterval
    public let ttlByNamespace: [String: TimeInterval]

    public init(defaultTTL: TimeInterval, ttlByNamespace: [String: TimeInterval]) {
        self.defaultTTL = defaultTTL
        self.ttlByNamespace = ttlByNamespace
    }

    public func decision(
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
