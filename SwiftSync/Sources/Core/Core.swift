import Foundation
import SwiftData

public enum SwiftSync {}

public protocol SyncModelable: PersistentModel {
    associatedtype SyncID: Hashable & Codable & Sendable
    static var syncIdentity: KeyPath<Self, SyncID> { get }
    static var syncIdentityRemoteKeys: [String] { get }
}

public extension SyncModelable {
    static var syncIdentityRemoteKeys: [String] { ["id", "remote_id", "remoteID"] }
}

public protocol SyncQuerySortableModel: SyncModelable {
    static func syncSortDescriptor(for keyPath: PartialKeyPath<Self>) -> SortDescriptor<Self>?
}

public extension SyncQuerySortableModel {
    static func syncSortDescriptors(for keyPaths: [PartialKeyPath<Self>]) -> [SortDescriptor<Self>] {
        keyPaths.compactMap { syncSortDescriptor(for: $0) }
    }
}

public protocol SyncUpdatableModel: SyncModelable {
    static func make(from payload: SyncPayload) throws -> Self
    func apply(_ payload: SyncPayload) throws -> Bool
}

public protocol SyncRelationshipUpdatableModel: SyncUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool
}

public protocol ParentScopedModel: SyncUpdatableModel {
    associatedtype SyncParent: PersistentModel
    static var parentRelationship: ReferenceWritableKeyPath<Self, SyncParent?> { get }
}

public enum ExportRelationshipMode: Sendable {
    case array
    case nested
    case none
}

public enum ExportKeyStyle: Sendable {
    case snakeCase
    case camelCase

    public func transform(_ value: String) -> String {
        switch self {
        case .camelCase:
            return value
        case .snakeCase:
            return toSnakeCase(value)
        }
    }

    private func toSnakeCase(_ value: String) -> String {
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
}

public struct ExportOptions: Sendable {
    public var keyStyle: ExportKeyStyle
    public var relationshipMode: ExportRelationshipMode
    public var dateFormatter: DateFormatter
    public var includeNulls: Bool

    public init(
        keyStyle: ExportKeyStyle = .snakeCase,
        relationshipMode: ExportRelationshipMode = .array,
        dateFormatter: DateFormatter = ExportOptions.defaultDateFormatter(),
        includeNulls: Bool = true
    ) {
        self.keyStyle = keyStyle
        self.relationshipMode = relationshipMode
        self.dateFormatter = dateFormatter
        self.includeNulls = includeNulls
    }

    public static var camelCase: ExportOptions {
        var options = ExportOptions()
        options.keyStyle = .camelCase
        return options
    }

    public static var excludedRelationships: ExportOptions {
        var options = ExportOptions()
        options.relationshipMode = .none
        return options
    }

    public static func defaultDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        return formatter
    }
}

public struct ExportState {
    private var visiting: Set<String> = []

    public init() {}

    public mutating func enter<Model: PersistentModel>(_ model: Model) -> Bool {
        let key = String(describing: model.persistentModelID)
        let inserted = visiting.insert(key).inserted
        return inserted
    }

    public mutating func leave<Model: PersistentModel>(_ model: Model) {
        let key = String(describing: model.persistentModelID)
        visiting.remove(key)
    }
}

public protocol ExportModel: SyncModelable {
    func exportObject(using options: ExportOptions, state: inout ExportState) -> [String: Any]
}

public func exportEncodeValue(_ raw: Any, options: ExportOptions) -> Any? {
    switch raw {
    case let value as String:
        return value
    case let value as Bool:
        return value
    case let value as Int:
        return value
    case let value as Int8:
        return Int(value)
    case let value as Int16:
        return Int(value)
    case let value as Int32:
        return Int(value)
    case let value as Int64:
        return value
    case let value as UInt:
        return value
    case let value as UInt8:
        return UInt(value)
    case let value as UInt16:
        return UInt(value)
    case let value as UInt32:
        return UInt(value)
    case let value as UInt64:
        return value
    case let value as Double:
        return value
    case let value as Float:
        return value
    case let value as Decimal:
        return NSDecimalNumber(decimal: value)
    case let value as Date:
        return options.dateFormatter.string(from: value)
    case let value as UUID:
        return value.uuidString
    case let value as URL:
        return value.absoluteString
    case let value as Data:
        return value.base64EncodedString()
    case let value as [String]:
        return value
    case let value as [Int]:
        return value
    case let value as [Double]:
        return value
    case let value as [Bool]:
        return value
    case let value as [Any]:
        return value.compactMap { exportEncodeValue($0, options: options) }
    default:
        return nil
    }
}

public func exportSetValue(_ value: Any, for keyPath: String, into target: inout [String: Any]) {
    let parts = keyPath.split(separator: ".").map(String.init)
    guard !parts.isEmpty else { return }
    exportSetValue(value, path: parts, into: &target)
}

private func exportSetValue(_ value: Any, path: [String], into target: inout [String: Any]) {
    guard let head = path.first else { return }
    if path.count == 1 {
        target[head] = value
        return
    }
    var nested = (target[head] as? [String: Any]) ?? [:]
    exportSetValue(value, path: Array(path.dropFirst()), into: &nested)
    target[head] = nested
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

public enum SyncError: Error, Sendable, Equatable {
    case invalidPayload(model: String, reason: String)
    case cancelled
}

public enum SyncMissingRowPolicy: Sendable {
    case delete
    case keep
}
