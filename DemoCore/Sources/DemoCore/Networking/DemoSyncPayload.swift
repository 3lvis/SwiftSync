import Foundation
import SwiftSync

public enum DemoSyncPayloadError: LocalizedError {
    case unsupportedValue(path: String, type: String)
    case expectedObject(path: String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedValue(path, type):
            return "Unsupported payload value at \(path): \(type)."
        case let .expectedObject(path):
            return "Expected object payload at \(path)."
        }
    }
}

public struct DemoSyncPayload: Sendable, SyncPayloadConvertible {
    public let values: [String: DemoSyncValue]

    public init(values: [String: DemoSyncValue]) {
        self.values = values
    }

    public init(dictionary: [String: Any]) throws {
        self.values = try dictionary.reduce(into: [:]) { partialResult, element in
            partialResult[element.key] = try DemoSyncValue(anyValue: element.value, path: element.key)
        }
    }

    public func toSyncPayloadDictionary() -> [String: Any] {
        values.mapValues { $0.foundationValue }
    }

    public func string(_ key: String) -> String? {
        values[key]?.stringValue
    }

    public func objectArray(_ key: String) -> [DemoSyncPayload]? {
        values[key]?.objectArrayValue
    }
}

public enum DemoSyncValue: Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: DemoSyncValue])
    case array([DemoSyncValue])
    case null

    fileprivate init(anyValue: Any, path: String) throws {
        switch anyValue {
        case let value as String:
            self = .string(value)
        case let value as Int:
            self = .int(value)
        case let value as Bool:
            self = .bool(value)
        case let value as Double:
            self = .double(value)
        case let value as Float:
            self = .double(Double(value))
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                self = .bool(value.boolValue)
            } else if value.doubleValue.rounded(.towardZero) == value.doubleValue {
                self = .int(value.intValue)
            } else {
                self = .double(value.doubleValue)
            }
        case let value as [String: Any]:
            self = .object(try value.reduce(into: [:]) { partialResult, element in
                let nestedPath = "\(path).\(element.key)"
                partialResult[element.key] = try DemoSyncValue(anyValue: element.value, path: nestedPath)
            })
        case let value as [Any]:
            self = .array(try value.enumerated().map { index, element in
                try DemoSyncValue(anyValue: element, path: "\(path)[\(index)]")
            })
        case _ as NSNull:
            self = .null
        default:
            throw DemoSyncPayloadError.unsupportedValue(path: path, type: String(describing: type(of: anyValue)))
        }
    }

    fileprivate var foundationValue: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        case let .double(value):
            return value
        case let .bool(value):
            return value
        case let .object(value):
            return value.mapValues { $0.foundationValue }
        case let .array(value):
            return value.map { $0.foundationValue }
        case .null:
            return NSNull()
        }
    }

    fileprivate var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    fileprivate var objectArrayValue: [DemoSyncPayload]? {
        guard case let .array(value) = self else { return nil }
        return value.compactMap { item in
            guard case let .object(objectValue) = item else { return nil }
            return DemoSyncPayload(values: objectValue)
        }
    }
}
