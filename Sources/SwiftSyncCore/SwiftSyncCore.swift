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
        if T.self == Date.self, containsCandidateValue(for: key) {
            // Date parsing is best-effort; invalid values fall back to epoch for required fields.
            return Date(timeIntervalSince1970: 0) as! T
        }
        if isExplicitNull(for: key), let fallback: T = defaultValueForNull(as: type) {
            return fallback
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

    private func containsCandidateValue(for key: String) -> Bool {
        candidateKeys(for: key).contains { candidate in
            values.keys.contains(candidate)
        }
    }

    private func isExplicitNull(for key: String) -> Bool {
        candidateKeys(for: key).contains { candidate in
            values[candidate] is NSNull
        }
    }

    private func defaultValueForNull<T>(as type: T.Type) -> T? {
        switch type {
        case is String.Type:
            return "" as? T
        case is Bool.Type:
            return false as? T
        case is Int.Type:
            return 0 as? T
        case is Int8.Type:
            return Int8(0) as? T
        case is Int16.Type:
            return Int16(0) as? T
        case is Int32.Type:
            return Int32(0) as? T
        case is Int64.Type:
            return Int64(0) as? T
        case is UInt.Type:
            return UInt(0) as? T
        case is UInt8.Type:
            return UInt8(0) as? T
        case is UInt16.Type:
            return UInt16(0) as? T
        case is UInt32.Type:
            return UInt32(0) as? T
        case is UInt64.Type:
            return UInt64(0) as? T
        case is Double.Type:
            return 0.0 as? T
        case is Float.Type:
            return Float(0) as? T
        case is Decimal.Type:
            return Decimal.zero as? T
        case is Date.Type:
            return Date(timeIntervalSince1970: 0) as? T
        case is UUID.Type:
            return UUID(uuidString: "00000000-0000-0000-0000-000000000000") as? T
        default:
            return nil
        }
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

        if T.self == Date.self {
            if let string = raw as? String, let date = SyncDateParser.dateFromDateString(string) {
                return date as? T
            }
            if let int = raw as? Int, let date = SyncDateParser.dateFromUnixTimestampNumber(NSNumber(value: int)) {
                return date as? T
            }
            if let double = raw as? Double, let date = SyncDateParser.dateFromUnixTimestampNumber(NSNumber(value: double)) {
                return date as? T
            }
            if let number = raw as? NSNumber, let date = SyncDateParser.dateFromUnixTimestampNumber(number) {
                return date as? T
            }
        }

        return nil
    }
}

public enum SyncError: Error, Sendable {
    case invalidPayload(model: String, reason: String)
}
