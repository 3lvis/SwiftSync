import Foundation
import Testing
@testable import SwiftSync

struct DataFreshnessTests {
    @Test("empty when no local data")
    func decisionIsEmptyWithoutLocalRows() {
        let policy = DataFreshnessPolicy(defaultTTL: 60, ttlByNamespace: [:])
        let key = DataKey(namespace: "taskDetail", id: "t-1")

        let decision = policy.decision(
            for: key,
            hasLocalData: false,
            lastSuccessfulSync: Date(timeIntervalSince1970: 10)
        )

        #expect(decision == .empty)
    }

    @Test("stale when local data exists but never synced")
    func decisionIsStaleWithoutTimestamp() {
        let policy = DataFreshnessPolicy(defaultTTL: 60, ttlByNamespace: [:])
        let key = DataKey(namespace: "taskDetail", id: "t-1")

        let decision = policy.decision(for: key, hasLocalData: true, lastSuccessfulSync: nil)

        #expect(decision == .stale)
    }

    @Test("fresh when age is below ttl")
    func decisionIsFreshWhenWithinTTL() {
        let policy = DataFreshnessPolicy(defaultTTL: 10, ttlByNamespace: ["taskDetail": 20])
        let key = DataKey(namespace: "taskDetail", id: "t-1")
        let now = Date(timeIntervalSince1970: 100)

        let decision = policy.decision(
            for: key,
            hasLocalData: true,
            lastSuccessfulSync: Date(timeIntervalSince1970: 85),
            now: now
        )

        #expect(decision == .fresh)
    }

    @Test("stale when age exceeds ttl")
    func decisionIsStaleWhenPastTTL() {
        let policy = DataFreshnessPolicy(defaultTTL: 10, ttlByNamespace: ["taskDetail": 20])
        let key = DataKey(namespace: "taskDetail", id: "t-1")
        let now = Date(timeIntervalSince1970: 100)

        let decision = policy.decision(
            for: key,
            hasLocalData: true,
            lastSuccessfulSync: Date(timeIntervalSince1970: 79),
            now: now
        )

        #expect(decision == .stale)
    }

    @Test("fresh at exact ttl boundary")
    func decisionIsFreshAtTTLBoundary() {
        let policy = DataFreshnessPolicy(defaultTTL: 30, ttlByNamespace: [:])
        let key = DataKey(namespace: "users", id: nil)
        let now = Date(timeIntervalSince1970: 100)

        let decision = policy.decision(
            for: key,
            hasLocalData: true,
            lastSuccessfulSync: Date(timeIntervalSince1970: 70),
            now: now
        )

        #expect(decision == .fresh)
    }
}
