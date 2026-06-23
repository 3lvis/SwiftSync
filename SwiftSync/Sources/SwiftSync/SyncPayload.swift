import Foundation

public struct SyncPayload {
    public let values: [String: Any]
    public let keyStyle: KeyStyle
    private let candidateKeysCache = CandidateKeysCache()

    public init(values: [String: Any], keyStyle: KeyStyle = .snakeCase) {
        self.values = values
        self.keyStyle = keyStyle
    }

    public func contains(_ key: String) -> Bool {
        candidateKeys(for: key).contains { candidate in
            rawValue(for: candidate) != nil
        }
    }

    public func value<T>(for key: String, as type: T.Type = T.self) -> T? {
        for candidate in candidateKeys(for: key) {
            guard let raw = rawValue(for: candidate) else { continue }
            if let value = cast(raw, as: T.self) {
                return value
            }
        }
        return nil
    }

    func strictValue<T>(for key: String, as type: T.Type = T.self) -> T? {
        for candidate in candidateKeys(for: key) {
            guard let raw = rawValue(for: candidate) else { continue }
            if let value = raw as? T {
                return value
            }
        }
        return nil
    }

    public func required<T>(_ type: T.Type = T.self, for key: String) throws -> T {
        if let value: T = value(for: key, as: type) {
            return value
        }
        if T.self == Date.self, contains(key) {
            // Date parsing is best-effort; invalid values fall back to epoch for required fields.
            return Date(timeIntervalSince1970: 0) as! T
        }
        if isExplicitNull(for: key), let fallback: T = defaultValueForNull(as: type) {
            return fallback
        }
        throw SyncError.invalidPayload(model: "Payload", reason: "Missing or invalid '\(key)'")
    }

    func strictRequired<T>(_ type: T.Type = T.self, for key: String) throws -> T {
        if let value: T = strictValue(for: key, as: type) {
            return value
        }
        if T.self == Date.self, contains(key) {
            return Date(timeIntervalSince1970: 0) as! T
        }
        if isExplicitNull(for: key), let fallback: T = defaultValueForNull(as: type) {
            return fallback
        }
        throw SyncError.invalidPayload(model: "Payload", reason: "Missing or invalid '\(key)'")
    }

    private func candidateKeys(for key: String) -> [String] {
        if let cached = candidateKeysCache.cache[key] {
            return cached
        }

        var keys: [String] = []
        switch keyStyle {
        case .snakeCase:
            keys.append(
                key.split(separator: ".", omittingEmptySubsequences: false)
                    .map { snakeCased(String($0)) }
                    .joined(separator: "."))
        case .camelCase:
            keys.append(
                key.split(separator: ".", omittingEmptySubsequences: false)
                    .map { segment in
                        let normalizedSnake = snakeCased(String(segment))
                        return camelCased(normalizedSnake)
                    }
                    .joined(separator: "."))
        }
        keys.append(key)
        if key == "remoteID" {
            switch keyStyle {
            case .snakeCase:
                keys.append(contentsOf: ["remote_id", "id"])
            case .camelCase:
                keys.append(contentsOf: ["remoteID", "id"])
            }
        }
        if key == "id" {
            switch keyStyle {
            case .snakeCase:
                keys.append("remote_id")
            case .camelCase:
                keys.append("remoteID")
            }
        }
        var ordered: [String] = []
        var seen: Set<String> = []
        for candidate in keys where seen.insert(candidate).inserted {
            ordered.append(candidate)
        }

        candidateKeysCache.cache[key] = ordered
        return ordered
    }

    private func isExplicitNull(for key: String) -> Bool {
        candidateKeys(for: key).contains { candidate in
            rawValue(for: candidate) is NSNull
        }
    }

    private func rawValue(for keyPath: String) -> Any? {
        if let direct = values[keyPath] {
            return direct
        }

        let segments = keyPath.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard segments.count > 1 else { return nil }

        var current: Any = values
        for segment in segments {
            if let dictionary = current as? [String: Any], let next = dictionary[segment] {
                current = next
                continue
            }
            if let dictionary = current as? NSDictionary, let next = dictionary[segment] {
                current = next
                continue
            }
            return nil
        }
        return current
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
        value.syncSnakeCased
    }

    private func camelCased(_ value: String) -> String {
        guard value.contains("_") else { return value }
        let parts = value.split(separator: "_", omittingEmptySubsequences: true)
        guard let first = parts.first else { return value }
        let tail = parts.dropFirst().map { part in
            guard let leading = part.first else { return "" }
            return String(leading).uppercased() + part.dropFirst().lowercased()
        }
        return String(first).lowercased() + tail.joined()
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
            if let number = raw as? NSNumber {
                return number.intValue as? T
            }
        }

        if T.self == String.self {
            if let int = raw as? Int {
                return String(int) as? T
            }
            if let double = raw as? Double {
                return String(double) as? T
            }
            if let decimal = raw as? Decimal {
                return NSDecimalNumber(decimal: decimal).stringValue as? T
            }
            if let bool = raw as? Bool {
                return String(bool) as? T
            }
            if let url = raw as? URL {
                return url.absoluteString as? T
            }
            if let uuid = raw as? UUID {
                return uuid.uuidString as? T
            }
        }

        if T.self == Bool.self {
            if let int = raw as? Int {
                if int == 1 { return true as? T }
                if int == 0 { return false as? T }
            }
            if let number = raw as? NSNumber {
                if number.intValue == 1 { return true as? T }
                if number.intValue == 0 { return false as? T }
            }
            if let string = raw as? String {
                switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "true", "1", "yes":
                    return true as? T
                case "false", "0", "no":
                    return false as? T
                default:
                    break
                }
            }
        }

        if T.self == UUID.self, let string = raw as? String, let value = UUID(uuidString: string) {
            return value as? T
        }

        if T.self == URL.self, let string = raw as? String, let value = URL(string: string) {
            return value as? T
        }

        if T.self == Double.self {
            if let string = raw as? String, let value = Double(string) {
                return value as? T
            }
            if let int = raw as? Int {
                return Double(int) as? T
            }
            if let number = raw as? NSNumber {
                return number.doubleValue as? T
            }
        }

        if T.self == Float.self {
            if let string = raw as? String, let value = Float(string) {
                return value as? T
            }
            if let int = raw as? Int {
                return Float(int) as? T
            }
            if let number = raw as? NSNumber {
                return number.floatValue as? T
            }
        }

        if T.self == Decimal.self {
            if let string = raw as? String,
                let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
            {
                return value as? T
            }
            if let int = raw as? Int {
                return Decimal(int) as? T
            }
            if let double = raw as? Double {
                return NSDecimalNumber(value: double).decimalValue as? T
            }
            if let number = raw as? NSNumber {
                return number.decimalValue as? T
            }
        }

        if T.self == Date.self {
            if let string = raw as? String, let date = SyncDateParser.dateFromDateString(string) {
                return date as? T
            }
            if let int = raw as? Int, let date = SyncDateParser.dateFromUnixTimestampNumber(NSNumber(value: int)) {
                return date as? T
            }
            if let double = raw as? Double,
                let date = SyncDateParser.dateFromUnixTimestampNumber(NSNumber(value: double))
            {
                return date as? T
            }
            if let number = raw as? NSNumber, let date = SyncDateParser.dateFromUnixTimestampNumber(number) {
                return date as? T
            }
        }

        return nil
    }
}

extension SyncPayload {
    func firstPresentKey(in keys: [String]) -> String? {
        for key in keys where contains(key) {
            return key
        }
        return nil
    }
}

private final class CandidateKeysCache {
    var cache: [String: [String]] = [:]
}
