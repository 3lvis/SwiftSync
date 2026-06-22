import Foundation
import SwiftData

// MARK: - Shared String Case Conversion Utilities

private enum ScalarClass {
    case upper
    case lower
    case digit
    case other
}

private func scalarClass(_ scalar: UnicodeScalar) -> ScalarClass {
    if CharacterSet.uppercaseLetters.contains(scalar) {
        return .upper
    }
    if CharacterSet.lowercaseLetters.contains(scalar) {
        return .lower
    }
    if CharacterSet.decimalDigits.contains(scalar) {
        return .digit
    }
    return .other
}

private func toSnakeCaseString(_ value: String) -> String {
    guard !value.isEmpty else { return value }
    var output = ""
    let scalars = Array(value.unicodeScalars)
    for (index, scalar) in scalars.enumerated() {
        let current = scalarClass(scalar)
        if index > 0, current == .upper {
            let previous = scalarClass(scalars[index - 1])
            let next = index + 1 < scalars.count ? scalarClass(scalars[index + 1]) : nil
            let startsNewWord = previous == .lower || previous == .digit
            let endsAcronym = previous == .upper && next == .lower
            if startsNewWord || endsAcronym, output.last != "_" {
                output.append("_")
            }
        }
        output.append(String(scalar).lowercased())
    }
    return output
}

// MARK: - SwiftSync API

public enum SwiftSync {}

public protocol SyncModelable: PersistentModel {
    associatedtype SyncID: Hashable & Codable & Sendable
    static var syncIdentity: KeyPath<Self, SyncID> { get }
    /// Swift property name of the identity (synthesised by `@Syncable`). Empty for hand-written
    /// conformances; used by `SyncContainer` to reject uniqueness constraints on non-identity fields.
    static var syncIdentityPropertyName: String { get }
    static func syncIdentityPredicate(matching identity: SyncID) -> Predicate<Self>?
    static func syncIdentityPredicate(matchingAny identities: [SyncID]) -> Predicate<Self>?
    static func syncParentPredicate(
        parentPersistentID: PersistentIdentifier,
        relationship: PartialKeyPath<Self>
    ) -> Predicate<Self>?
    static var syncIdentityRemoteKeys: [String] { get }
    static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { get }
    static func syncRelatedModelType(for keyPath: PartialKeyPath<Self>) -> (any PersistentModel.Type)?
    static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] { get }
}

extension SyncModelable {
    public static var syncIdentityPropertyName: String { "" }
    public static var syncIdentityRemoteKeys: [String] { ["id", "remote_id", "remoteID"] }
    public static func syncIdentityPredicate(matching _: SyncID) -> Predicate<Self>? { nil }
    public static func syncIdentityPredicate(matchingAny _: [SyncID]) -> Predicate<Self>? { nil }
    public static func syncParentPredicate(
        parentPersistentID _: PersistentIdentifier,
        relationship _: PartialKeyPath<Self>
    ) -> Predicate<Self>? { nil }
    public static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { [] }

    public static func syncRelatedModelType(for keyPath: PartialKeyPath<Self>) -> (any PersistentModel.Type)? {
        _ = keyPath
        return nil
    }

    public static var syncDefaultRefreshModelTypeNames: Set<String> {
        Set(syncDefaultRefreshModelTypes.map { String(reflecting: $0) })
    }

    public static func syncRefreshModelTypes(for keyPaths: [PartialKeyPath<Self>]) -> [any PersistentModel.Type] {
        keyPaths.compactMap { syncRelatedModelType(for: $0) }
    }

    public static func syncRefreshModelTypeNames(for keyPaths: [PartialKeyPath<Self>]) -> Set<String> {
        Set(syncRefreshModelTypes(for: keyPaths).map { String(reflecting: $0) })
    }

    public static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] { [] }
}

public struct SyncRelationshipSchemaDescriptor: Sendable {
    public let propertyName: String
    public let relatedTypeName: String
    public let isToMany: Bool
    public let hasExplicitInverseAnchor: Bool

    public init(
        propertyName: String,
        relatedTypeName: String,
        isToMany: Bool,
        hasExplicitInverseAnchor: Bool
    ) {
        self.propertyName = propertyName
        self.relatedTypeName = relatedTypeName
        self.isToMany = isToMany
        self.hasExplicitInverseAnchor = hasExplicitInverseAnchor
    }
}

public protocol SyncUpdatableModel: SyncModelable {
    static func make(from payload: SyncPayload) throws -> Self
    func apply(_ payload: SyncPayload) throws -> Bool
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)?
    ) async throws -> Bool
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)?
    ) async throws -> Bool
    func export(keyStyle: KeyStyle, dateFormatter: DateFormatter) -> [String: Any]

    /// Forces a scalar write so iOS CoreData marks the owning row dirty after a to-many change.
    /// `@Syncable` generates `self.id = self.id`. Hand-written conformances get a no-op default
    /// — override if your model has to-many relationships. See docs/project/ios-dirty-tracking-gap.md.
    func syncMarkChanged()
}

extension SyncUpdatableModel {
    public func syncMarkChanged() {}

    public func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        false
    }

    public func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations,
        isolation: isolated (any Actor)? = #isolation
    ) async throws -> Bool {
        try await applyRelationships(payload, in: context, isolation: isolation)
    }

    public func export(keyStyle _: KeyStyle, dateFormatter _: DateFormatter) -> [String: Any] {
        [:]
    }
}

final class SyncRelationshipLookupCache: @unchecked Sendable {
    private var rowsByType: [ObjectIdentifier: Any] = [:]
    private var rowsByIdentityType: [ObjectIdentifier: Any] = [:]
    // Partial identity maps from id-narrowed fetches. Kept separate from the full-table
    // `rowsByIdentityType` so a partial map is never mistaken for a complete one.
    private var narrowedRowsByIdentityType: [ObjectIdentifier: Any] = [:]

    func rows<Model: PersistentModel>(
        for modelType: Model.Type,
        in context: ModelContext
    ) throws -> [Model] {
        let key = ObjectIdentifier(modelType)
        if let cached = rowsByType[key] as? [Model] {
            return cached
        }

        let fetched = try syncProfile("relationship-fetch") {
            try context.fetch(FetchDescriptor<Model>())
        }
        rowsByType[key] = fetched
        return fetched
    }

    func rowsByIdentity<Model: SyncModelable>(
        for modelType: Model.Type,
        in context: ModelContext
    ) throws -> [String: Model] {
        let key = ObjectIdentifier(modelType)
        if let cached = rowsByIdentityType[key] as? [String: Model] {
            return cached
        }

        let fetched = try rows(for: modelType, in: context)
        let indexed: [String: Model] = syncProfile("relationship-index-by-id") {
            Dictionary(
                uniqueKeysWithValues: fetched.compactMap { row in
                    guard let identity = resolveIdentity(from: row) else { return nil }
                    return (identity, row)
                }
            )
        }
        rowsByIdentityType[key] = indexed
        return indexed
    }

    func rowsByIdentity<Model: SyncModelable>(
        for modelType: Model.Type,
        matching identities: [Model.SyncID],
        in context: ModelContext
    ) throws -> [String: Model] {
        let key = ObjectIdentifier(modelType)
        var map = (narrowedRowsByIdentityType[key] as? [String: Model]) ?? [:]

        // Unresolved ids are intentionally not memoized: a later pass may have inserted them,
        // and the re-fetch is a narrow predicate query over the few still-missing ids.
        let missing = identities.filter { map[syncIdentityKey(from: $0)] == nil }
        guard !missing.isEmpty else { return map }

        guard let predicate = Model.syncIdentityPredicate(matchingAny: missing) else {
            return try rowsByIdentity(for: modelType, in: context)
        }

        let fetched = try syncProfile("relationship-fetch-by-identity") {
            try context.fetch(FetchDescriptor<Model>(predicate: predicate))
        }
        syncProfile("relationship-index-by-id") {
            for row in fetched {
                if let identity = resolveIdentity(from: row) {
                    map[identity] = row
                }
            }
        }
        narrowedRowsByIdentityType[key] = map
        return map
    }

    func append<Model: SyncModelable>(_ row: Model, as modelType: Model.Type) {
        let key = ObjectIdentifier(modelType)
        if var cached = rowsByType[key] as? [Model] {
            cached.append(row)
            rowsByType[key] = cached
        }
        if let identity = resolveIdentity(from: row) {
            if var cached = rowsByIdentityType[key] as? [String: Model] {
                cached[identity] = row
                rowsByIdentityType[key] = cached
            }
            if var cached = narrowedRowsByIdentityType[key] as? [String: Model] {
                cached[identity] = row
                narrowedRowsByIdentityType[key] = cached
            }
        }
    }
}

enum SyncRelationshipLookupState {
    @TaskLocal static var current: SyncRelationshipLookupCache?
}

func resolveIdentity<Model: SyncModelable>(from payload: SyncPayload, model: Model.Type) -> String? {
    _ = model
    for key in Model.syncIdentityRemoteKeys {
        if let identity = payload.value(for: key, as: Model.SyncID.self) {
            return syncIdentityKey(from: identity)
        }
    }
    return nil
}

func resolveIdentity<Model: SyncModelable>(from row: Model) -> String? {
    syncIdentityKey(from: row[keyPath: Model.syncIdentity])
}

func syncIdentityKey<ID: Hashable>(from identity: ID) -> String {
    String(describing: identity)
}

public protocol ParentScopedModel: SyncUpdatableModel {
    associatedtype SyncParent: PersistentModel
    static var parentRelationship: ReferenceWritableKeyPath<Self, SyncParent?> { get }
}

public struct SyncRelationshipOperations: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let insert = SyncRelationshipOperations(rawValue: 1 << 0)
    public static let update = SyncRelationshipOperations(rawValue: 1 << 1)
    public static let delete = SyncRelationshipOperations(rawValue: 1 << 2)
    public static let all: SyncRelationshipOperations = [.insert, .update, .delete]
}

public enum KeyStyle: Sendable {
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
        toSnakeCaseString(value)
    }
}

func defaultExportDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
    return formatter
}

/// Cycle-detection state for recursive relationship export.
/// This type is an implementation detail of `@Syncable`-generated code.
/// Do not instantiate or reference it directly.
public enum ExportState {
    private static let threadDictionaryKey = "SwiftSync.ExportState"

    /// Returns false if already visiting (cycle detected).
    public static func enter<Model: PersistentModel>(_ model: Model) -> Bool {
        let key = String(describing: model.persistentModelID)
        var visiting = currentVisiting()
        if visiting.contains(key) { return false }
        visiting.insert(key)
        saveVisiting(visiting)
        return true
    }

    public static func leave<Model: PersistentModel>(_ model: Model) {
        let key = String(describing: model.persistentModelID)
        var visiting = currentVisiting()
        visiting.remove(key)
        saveVisiting(visiting)
    }

    private static func currentVisiting() -> Set<String> {
        (Thread.current.threadDictionary[threadDictionaryKey] as? ExportStateBox)?.visiting ?? []
    }

    private static func saveVisiting(_ visiting: Set<String>) {
        Thread.current.threadDictionary[threadDictionaryKey] = ExportStateBox(visiting)
    }
}

private final class ExportStateBox {
    var visiting: Set<String>
    init(_ visiting: Set<String>) { self.visiting = visiting }
}

private final class CandidateKeysCache {
    var cache: [String: [String]] = [:]
}

public protocol SyncPayloadConvertible: Sendable {
    func toSyncPayloadDictionary() -> [String: Any]
}

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
        toSnakeCaseString(value)
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

/// The single error currency for SwiftSync: every SwiftSync operation that can fail throws one of
/// these, so a consumer catches one type. (Per-operation push *rejections* are partial-success data,
/// reported as `SyncPushFailure` in the response rather than thrown — see `withPendingChanges`.)
public enum SyncError: Error, Sendable, Equatable {
    case invalidPayload(model: String, reason: String)
    case cancelled
    /// A model's schema is invalid for sync (e.g. an unanchored many-to-many, or a uniqueness
    /// constraint off the sync identity).
    case schemaValidation(reason: String)
    case containerInitialization(reason: String)
}

extension SyncError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidPayload(let model, let reason):
            return "Invalid payload for \(model): \(reason)"
        case .cancelled:
            return "Sync was cancelled."
        case .schemaValidation(let reason):
            return reason
        case .containerInitialization(let reason):
            return reason
        }
    }
}
