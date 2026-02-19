import Foundation
import SwiftData

public enum SwiftSync {}

public protocol SyncModel: PersistentModel {
    associatedtype SyncID: Hashable & Codable & Sendable
    static var syncIdentity: KeyPath<Self, SyncID> { get }
    static var syncIdentityRemoteKeys: [String] { get }
}

public extension SyncModel {
    static var syncIdentityRemoteKeys: [String] { ["id", "remote_id", "remoteID"] }
}

public protocol SyncUpdatableModel: SyncModel {
    static func make(from payload: SyncPayload) throws -> Self
    func apply(_ payload: SyncPayload) throws -> Bool
}

public protocol SyncRelationshipUpdatableModel: SyncUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool
}

public struct SyncPayload {
    public let values: [String: Any]

    public init(values: [String: Any]) {
        self.values = values
    }

    public func contains(_ key: String) -> Bool {
        candidateKeys(for: key).contains { values[$0] != nil }
    }

    public func value<T>(for key: String, as type: T.Type = T.self) -> T? {
        for candidate in candidateKeys(for: key) {
            guard let raw = values[candidate] else { continue }
            if let value = cast(raw, as: T.self) {
                return value
            }
        }
        return nil
    }

    public func required<T>(_ type: T.Type = T.self, for key: String) throws -> T {
        if let value: T = value(for: key, as: type) {
            return value
        }
        throw SyncError.invalidPayload(model: "Payload", reason: "Missing or invalid '\(key)'")
    }

    private func candidateKeys(for key: String) -> [String] {
        var keys = [key, snakeCased(key)]
        if key == "remoteID" {
            keys.append(contentsOf: ["remote_id", "id"])
        }
        if key == "id" {
            keys.append(contentsOf: ["remote_id", "remoteID"])
        }
        return Array(Set(keys))
    }

    private func snakeCased(_ value: String) -> String {
        guard !value.isEmpty else { return value }
        var output = ""
        for character in value {
            let scalarString = String(character)
            if scalarString == scalarString.uppercased(), scalarString != scalarString.lowercased(), !output.isEmpty {
                output.append("_")
            }
            output.append(scalarString.lowercased())
        }
        return output
    }

    private func cast<T>(_ raw: Any, as type: T.Type) -> T? {
        if let direct = raw as? T {
            return direct
        }

        if T.self == Int.self {
            if let string = raw as? String, let value = Int(string) {
                return value as? T
            }
            if let double = raw as? Double {
                return Int(double) as? T
            }
        }

        if T.self == String.self {
            if let int = raw as? Int {
                return String(int) as? T
            }
            if let uuid = raw as? UUID {
                return uuid.uuidString as? T
            }
        }

        if T.self == UUID.self, let string = raw as? String, let value = UUID(uuidString: string) {
            return value as? T
        }

        return nil
    }
}

public enum SyncError: Error, Sendable {
    case invalidPayload(model: String, reason: String)
}
