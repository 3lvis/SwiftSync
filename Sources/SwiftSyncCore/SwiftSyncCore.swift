import Foundation
import SwiftData

public enum SwiftSync {}

public protocol SyncModel: PersistentModel {
    associatedtype SyncID: Hashable & Codable & Sendable
    static var syncIdentity: KeyPath<Self, SyncID> { get }
    static var syncIdentityRemoteKeys: [String] { get }
}

public protocol SyncSchemaProviding: PersistentModel {
    static var syncSchema: SyncSchema<Self> { get }
}

public extension SyncModel {
    static var syncIdentityRemoteKeys: [String] { ["id", "remote_id", "remoteID"] }
}

public protocol SyncUpdatableModel: SyncModel {
    static func make(from payload: SyncPayload) throws -> Self
    func apply(_ payload: SyncPayload) throws -> Bool
}

public protocol SyncRelationshipUpdatableModel: SyncUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext, options: SyncOptions) async throws -> Bool
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

public protocol SyncTransform: Sendable {
    associatedtype Output: Sendable
    func decode(_ remoteValue: Any) throws -> Output
    func encode(_ localValue: Output) throws -> Any
}

public struct AnySyncTransform<Value: Sendable>: @unchecked Sendable {
    private let decodeImpl: @Sendable (Any) throws -> Value
    private let encodeImpl: @Sendable (Value) throws -> Any

    public init<T: SyncTransform>(_ transform: T) where T.Output == Value {
        self.decodeImpl = transform.decode
        self.encodeImpl = transform.encode
    }

    public init(
        decode: @escaping @Sendable (Any) throws -> Value,
        encode: @escaping @Sendable (Value) throws -> Any
    ) {
        self.decodeImpl = decode
        self.encodeImpl = encode
    }

    public func decode(_ remoteValue: Any) throws -> Value {
        try decodeImpl(remoteValue)
    }

    public func encode(_ localValue: Value) throws -> Any {
        try encodeImpl(localValue)
    }
}

public enum BuiltInTransforms {
    public static var iso8601Date: AnySyncTransform<Date> {
        AnySyncTransform<Date>(
            decode: { any in
                guard let value = any as? String else {
                    throw SyncError.invalidPayload(model: "Date", reason: "Expected ISO-8601 string")
                }
                guard let date = ISO8601DateFormatter().date(from: value) else {
                    throw SyncError.invalidPayload(model: "Date", reason: "Invalid ISO-8601 date")
                }
                return date
            },
            encode: { value in
                ISO8601DateFormatter().string(from: value)
            }
        )
    }

    public static var unixTimestampDate: AnySyncTransform<Date> {
        AnySyncTransform<Date>(
            decode: { any in
                if let seconds = any as? TimeInterval {
                    return Date(timeIntervalSince1970: seconds)
                }
                if let intSeconds = any as? Int {
                    return Date(timeIntervalSince1970: TimeInterval(intSeconds))
                }
                throw SyncError.invalidPayload(model: "Date", reason: "Expected unix timestamp")
            },
            encode: { value in
                Int(value.timeIntervalSince1970)
            }
        )
    }

    public static var urlString: AnySyncTransform<URL> {
        AnySyncTransform<URL>(
            decode: { any in
                guard let value = any as? String, let url = URL(string: value) else {
                    throw SyncError.invalidPayload(model: "URL", reason: "Expected URL string")
                }
                return url
            },
            encode: { value in
                value.absoluteString
            }
        )
    }

    public static var uuidString: AnySyncTransform<UUID> {
        AnySyncTransform<UUID>(
            decode: { any in
                guard let value = any as? String, let uuid = UUID(uuidString: value) else {
                    throw SyncError.invalidPayload(model: "UUID", reason: "Expected UUID string")
                }
                return uuid
            },
            encode: { value in
                value.uuidString
            }
        )
    }

    public static var decimalString: AnySyncTransform<Decimal> {
        AnySyncTransform<Decimal>(
            decode: { any in
                guard let value = any as? String, let decimal = Decimal(string: value) else {
                    throw SyncError.invalidPayload(model: "Decimal", reason: "Expected decimal string")
                }
                return decimal
            },
            encode: { value in
                NSDecimalNumber(decimal: value).stringValue
            }
        )
    }
}

public struct DeleteScope: Sendable {
    public let descriptor: String

    private init(descriptor: String) {
        self.descriptor = descriptor
    }

    public static var none: DeleteScope { .init(descriptor: "none") }

    public static func byRemoteQuery(_ queryName: String) -> DeleteScope {
        .init(descriptor: "remoteQuery:\(queryName)")
    }

    public static func byPredicateDescription(_ description: String) -> DeleteScope {
        .init(descriptor: "predicate:\(description)")
    }
}

public struct SyncCheckpoint: Codable, Hashable, Sendable {
    public var stream: String
    public var token: String
    public var updatedAt: Date

    public init(stream: String, token: String, updatedAt: Date) {
        self.stream = stream
        self.token = token
        self.updatedAt = updatedAt
    }
}

public struct SyncOptions: Sendable {
    public var deleteScope: DeleteScope
    public var dryRun: Bool
    public var batchSize: Int
    public var checkpoint: SyncCheckpoint?

    public init(
        deleteScope: DeleteScope = .none,
        dryRun: Bool = false,
        batchSize: Int = 500,
        checkpoint: SyncCheckpoint? = nil
    ) {
        self.deleteScope = deleteScope
        self.dryRun = dryRun
        self.batchSize = max(1, batchSize)
        self.checkpoint = checkpoint
    }
}

public struct SyncPolicy<Model: PersistentModel>: @unchecked Sendable {
    public var onWillInsert: (@Sendable ([String: Any]) throws -> [String: Any])?
    public var onWillUpdate: (@Sendable ([String: Any]) throws -> [String: Any])?
    public var onDidApply: (@Sendable (Model) -> Void)?
    public var onConflict: (@Sendable (_ local: Model, _ remote: [String: Any]) throws -> Void)?

    public init() {}
}

public enum SyncError: Error, Sendable {
    case missingIdentity(model: String, key: String)
    case duplicateIdentity(model: String, identity: String)
    case unsupportedTransform(model: String, key: String)
    case unsafeDeleteScope(model: String)
    case schemaDrift(model: String, key: String)
    case conflictResolutionFailed(model: String, identity: String)
    case invalidPayload(model: String, reason: String)
}

public struct SyncSchema<Model: PersistentModel>: Sendable {
    public struct Field: Sendable {
        public enum Kind: Sendable {
            case identity
            case required
            case optional
            case toOne
            case toMany
        }

        public var kind: Kind
        public var localPath: String
        public var remoteKey: String

        public init(kind: Kind, localPath: String, remoteKey: String) {
            self.kind = kind
            self.localPath = localPath
            self.remoteKey = remoteKey
        }
    }

    public var fields: [Field]
    public var policyValue: SyncPolicy<Model>?

    public init() {
        self.fields = []
        self.policyValue = nil
    }

    public func identity<ID: Hashable & Sendable>(
        _ keyPath: KeyPath<Model, ID>,
        remote: String
    ) -> Self {
        var copy = self
        copy.fields.append(.init(kind: .identity, localPath: String(describing: keyPath), remoteKey: remote))
        return copy
    }

    public func field<Value: Sendable>(
        _ keyPath: KeyPath<Model, Value>,
        remote: String,
        transform: AnySyncTransform<Value>? = nil
    ) -> Self {
        _ = transform
        var copy = self
        copy.fields.append(.init(kind: .required, localPath: String(describing: keyPath), remoteKey: remote))
        return copy
    }

    public func optionalField<Value: Sendable>(
        _ keyPath: KeyPath<Model, Value?>,
        remote: String,
        transform: AnySyncTransform<Value>? = nil
    ) -> Self {
        _ = transform
        var copy = self
        copy.fields.append(.init(kind: .optional, localPath: String(describing: keyPath), remoteKey: remote))
        return copy
    }

    public func toOne<Child: PersistentModel>(
        _ keyPath: KeyPath<Model, Child?>,
        remoteObject: String? = nil,
        remoteID: String? = nil
    ) -> Self {
        _ = keyPath
        var copy = self
        if let remoteObject {
            copy.fields.append(.init(kind: .toOne, localPath: String(describing: keyPath), remoteKey: remoteObject))
        }
        if let remoteID {
            copy.fields.append(.init(kind: .toOne, localPath: String(describing: keyPath), remoteKey: remoteID))
        }
        return copy
    }

    public func toMany<Child: PersistentModel>(
        _ keyPath: KeyPath<Model, [Child]>,
        remoteObjects: String? = nil,
        remoteIDs: String? = nil,
        ordered: Bool = false
    ) -> Self {
        _ = ordered
        var copy = self
        if let remoteObjects {
            copy.fields.append(.init(kind: .toMany, localPath: String(describing: keyPath), remoteKey: remoteObjects))
        }
        if let remoteIDs {
            copy.fields.append(.init(kind: .toMany, localPath: String(describing: keyPath), remoteKey: remoteIDs))
        }
        return copy
    }

    public func policy(_ policy: SyncPolicy<Model>) -> Self {
        var copy = self
        copy.policyValue = policy
        return copy
    }
}
