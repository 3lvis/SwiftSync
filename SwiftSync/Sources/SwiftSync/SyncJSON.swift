import Foundation

/// A `Sendable`, structured JSON value.
///
/// `sync(...)` runs off the main actor, so a payload crossing into it must be `Sendable` — which a raw
/// `[String: Any]` is not. `SyncJSON` is the carrier: box your JSON once with `init(dictionary:)`, hand it
/// to `sync` across actor boundaries, and read it back with the keyed accessors. It conforms to
/// `SyncPayloadConvertible`, so it feeds `sync(payload:)` / `sync(item:)` directly.
public enum SyncJSON: Sendable, SyncPayloadConvertible {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: SyncJSON])
    case array([SyncJSON])
    case null

    /// Boxes an arbitrary JSON value. `NSNumber` is matched first so a JSON boolean isn't mistaken for `1`
    /// (a `Bool` bridges to `NSNumber` and would otherwise satisfy `as? Int`).
    public init(_ value: Any) throws {
        switch value {
        case let value as SyncJSON:
            self = value
        case is NSNull:
            self = .null
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if value.doubleValue.rounded(.towardZero) == value.doubleValue {
                self = .int(value.intValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as String:
            self = .string(value)
        case let value as [String: Any]:
            self = .object(try value.mapValues { try SyncJSON($0) })
        case let value as [Any]:
            self = .array(try value.map { try SyncJSON($0) })
        default:
            throw SyncError.invalidPayload(
                model: "SyncJSON", reason: "unsupported value of type \(type(of: value))")
        }
    }

    /// Boxes a JSON object.
    public init(dictionary: [String: Any]) throws {
        self = .object(try dictionary.mapValues { try SyncJSON($0) })
    }

    public func toSyncPayloadDictionary() -> [String: Any] {
        guard case .object(let members) = self else { return [:] }
        return members.mapValues(\.foundationValue)
    }

    /// The string at `key` when this is an object whose value there is a string.
    public func string(_ key: String) -> String? {
        guard case .object(let members) = self, case .string(let value)? = members[key] else { return nil }
        return value
    }

    /// The object elements of the array at `key` when this is an object.
    public func objectArray(_ key: String) -> [SyncJSON]? {
        guard case .object(let members) = self, case .array(let elements)? = members[key] else { return nil }
        return elements.filter { if case .object = $0 { return true } else { return false } }
    }

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .object(let value): return value.mapValues(\.foundationValue)
        case .array(let value): return value.map(\.foundationValue)
        case .null: return NSNull()
        }
    }
}
