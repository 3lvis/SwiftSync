import Foundation
import SwiftData

// MARK: - Shared String Case Conversion Utilities

fileprivate enum ScalarClass {
    case upper
    case lower
    case digit
    case other
}

fileprivate func scalarClass(_ scalar: UnicodeScalar) -> ScalarClass {
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

// MARK: - SwiftSync API

public enum SwiftSync {}

public protocol SyncModelable: PersistentModel {
    associatedtype SyncID: Hashable & Codable & Sendable
    static var syncIdentity: KeyPath<Self, SyncID> { get }
    static var syncIdentityRemoteKeys: [String] { get }
    static var syncIdentityPolicy: SyncIdentityPolicy { get }
    static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { get }
    static func syncRelatedModelType(for keyPath: PartialKeyPath<Self>) -> (any PersistentModel.Type)?
}

public extension SyncModelable {
    static var syncIdentityRemoteKeys: [String] { ["id", "remote_id", "remoteID"] }
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }
    static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { [] }

    static func syncRelatedModelType(for keyPath: PartialKeyPath<Self>) -> (any PersistentModel.Type)? {
        _ = keyPath
        return nil
    }

    static var syncDefaultRefreshModelTypeNames: Set<String> {
        Set(syncDefaultRefreshModelTypes.map { String(reflecting: $0) })
    }

    static func syncRefreshModelTypes(for keyPaths: [PartialKeyPath<Self>]) -> [any PersistentModel.Type] {
        keyPaths.compactMap { syncRelatedModelType(for: $0) }
    }

    static func syncRefreshModelTypeNames(for keyPaths: [PartialKeyPath<Self>]) -> Set<String> {
        Set(syncRefreshModelTypes(for: keyPaths).map { String(reflecting: $0) })
    }
}

public protocol SyncQuerySortableModel: SyncModelable {
    static func syncSortDescriptor(for keyPath: PartialKeyPath<Self>) -> SortDescriptor<Self>?
}

public extension SyncQuerySortableModel {
    static func syncSortDescriptors(for keyPaths: [PartialKeyPath<Self>]) -> [SortDescriptor<Self>] {
        keyPaths.compactMap { syncSortDescriptor(for: $0) }
    }
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

public protocol SyncRelationshipSchemaIntrospectable {
    static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] { get }
}

public extension SyncRelationshipSchemaIntrospectable {
    static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] { [] }
}

public protocol SyncUpdatableModel: SyncModelable {
    static func make(from payload: SyncPayload) throws -> Self
    func apply(_ payload: SyncPayload) throws -> Bool
}

public protocol SyncRelationshipUpdatableModel: SyncUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool
}

public extension SyncRelationshipUpdatableModel {
    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        _ = operations
        return try await applyRelationships(payload, in: context)
    }
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = context
    let canClear = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }
    guard payload.value(for: key, as: NSNull.self) != nil else { return false }
    guard canClear else { return false }
    if owner[keyPath: relationship] != nil {
        owner[keyPath: relationship] = nil
        return true
    }
    return false
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: SyncModelable>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    let canLink = !operations.isDisjoint(with: [.insert, .update])
    let canClear = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        guard canClear else { return false }
        if owner[keyPath: relationship] != nil {
            owner[keyPath: relationship] = nil
            return true
        }
        return false
    }

    guard let nextID: Related.SyncID = payload.strictValue(for: key) else {
        return false
    }

    let relatedRows = try context.fetch(FetchDescriptor<Related>())
    let relatedByID = Dictionary(
        uniqueKeysWithValues: relatedRows.map { row in
            (syncIdentityKey(from: row[keyPath: Related.syncIdentity]), row)
        }
    )

    guard let nextRelated = relatedByID[syncIdentityKey(from: nextID)] else {
        // Old Sync parity: unknown FK row is a soft no-op.
        return false
    }

    guard canLink else { return false }
    if owner[keyPath: relationship]?.persistentModelID != nextRelated.persistentModelID {
        owner[keyPath: relationship] = nextRelated
        return true
    }
    return false
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = owner
    _ = relationship
    _ = payload
    _ = keys
    _ = context
    _ = operations
    return false
}

@discardableResult
public func syncApplyToOneForeignKey<Owner, Related: SyncModelable>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    let canLink = !operations.isDisjoint(with: [.insert, .update])
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        // Non-optional to-one relationships cannot be cleared.
        return false
    }

    guard let nextID: Related.SyncID = payload.strictValue(for: key) else {
        return false
    }

    let relatedRows = try context.fetch(FetchDescriptor<Related>())
    let relatedByID = Dictionary(
        uniqueKeysWithValues: relatedRows.map { row in
            (syncIdentityKey(from: row[keyPath: Related.syncIdentity]), row)
        }
    )
    guard let nextRelated = relatedByID[syncIdentityKey(from: nextID)] else {
        return false
    }

    guard canLink else { return false }
    if owner[keyPath: relationship].persistentModelID != nextRelated.persistentModelID {
        owner[keyPath: relationship] = nextRelated
        return true
    }
    return false
}

@discardableResult
public func syncApplyToManyForeignKeys<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = context
    let canClear = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        guard canClear else { return false }
        if !owner[keyPath: relationship].isEmpty {
            owner[keyPath: relationship] = []
            return true
        }
        return false
    }

    if let anyIDs: [Any] = payload.strictValue(for: key), anyIDs.isEmpty {
        guard canClear else { return false }
        if !owner[keyPath: relationship].isEmpty {
            owner[keyPath: relationship] = []
            return true
        }
    }

    return false
}

@discardableResult
public func syncApplyToManyForeignKeys<Owner, Related: SyncModelable>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    let canAdd = !operations.isDisjoint(with: [.insert, .update])
    let canDelete = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        guard canDelete else { return false }
        if !owner[keyPath: relationship].isEmpty {
            owner[keyPath: relationship] = []
            return true
        }
        return false
    }

    guard let rawIDs: [Related.SyncID] = payload.strictValue(for: key) else {
        return false
    }

    // Old Sync behavior avoids duplicate membership; dedupe input deterministically.
    let desiredIDs = dedupePreservingOrder(rawIDs)
    let relatedRows = try context.fetch(FetchDescriptor<Related>())
    let relatedByID = Dictionary(
        uniqueKeysWithValues: relatedRows.map { row in
            (syncIdentityKey(from: row[keyPath: Related.syncIdentity]), row)
        }
    )
    let desiredRelated = desiredIDs.compactMap { relatedByID[syncIdentityKey(from: $0)] }

    // SwiftData does not expose ordered-relationship metadata; treat to-many as unordered membership.
    let current = owner[keyPath: relationship]
    let next = mergeUnorderedRelationships(
        current: current,
        desired: desiredRelated,
        allowDelete: canDelete,
        allowAdd: canAdd
    )
    if modelIDSet(current) != modelIDSet(next) {
        owner[keyPath: relationship] = next
        return true
    }
    return false
}

@discardableResult
public func syncApplyToOneNestedObject<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = owner
    _ = relationship
    _ = payload
    _ = keys
    _ = context
    _ = operations
    return false
}

@discardableResult
public func syncApplyToOneNestedObject<Owner, Related: SyncUpdatableModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, Related?>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    let canLink = !operations.isDisjoint(with: [.insert, .update])
    let canClear = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        guard canClear else { return false }
        if owner[keyPath: relationship] != nil {
            owner[keyPath: relationship] = nil
            return true
        }
        return false
    }

    guard let nestedValues: [String: Any] = payload.strictValue(for: key) else {
        return false
    }
    let nestedPayload = SyncPayload(values: nestedValues, keyStyle: payload.keyStyle)
    var changed = false
    let relatedRows = try context.fetch(FetchDescriptor<Related>())
    var relatedByID: [String: Related] = Dictionary(
        uniqueKeysWithValues: relatedRows.compactMap { row in
            guard let identity = resolveIdentity(from: row) else { return nil }
            return (identity, row)
        }
    )

    var resolvedRelated: Related?
    if let nestedIdentity = resolveIdentity(from: nestedPayload, model: Related.self),
        let existing = relatedByID[nestedIdentity]
    {
        if operations.contains(.update), try existing.apply(nestedPayload) {
            changed = true
        }
        resolvedRelated = existing
    } else if let current = owner[keyPath: relationship], operations.contains(.update),
        resolveIdentity(from: nestedPayload, model: Related.self) == nil
    {
        if try current.apply(nestedPayload) {
            changed = true
        }
        resolvedRelated = current
    } else if operations.contains(.insert) {
        let created = try Related.make(from: nestedPayload)
        context.insert(created)
        if let createdIdentity = resolveIdentity(from: created) {
            relatedByID[createdIdentity] = created
        }
        resolvedRelated = created
        changed = true
    }

    guard canLink, let resolvedRelated else { return changed }
    if owner[keyPath: relationship]?.persistentModelID != resolvedRelated.persistentModelID {
        owner[keyPath: relationship] = resolvedRelated
        changed = true
    }
    return changed
}

@discardableResult
public func syncApplyToManyNestedObjects<Owner, Related: PersistentModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    _ = owner
    _ = relationship
    _ = payload
    _ = keys
    _ = context
    _ = operations
    return false
}

@discardableResult
public func syncApplyToManyNestedObjects<Owner, Related: SyncUpdatableModel>(
    _ owner: Owner,
    relationship: ReferenceWritableKeyPath<Owner, [Related]>,
    payload: SyncPayload,
    keys: [String],
    in context: ModelContext,
    operations: SyncRelationshipOperations = .all
) throws -> Bool {
    let canAdd = !operations.isDisjoint(with: [.insert, .update])
    let canDelete = operations.contains(.delete)
    guard let key = firstPresentPayloadKey(payload, keys: keys) else { return false }

    if payload.value(for: key, as: NSNull.self) != nil {
        guard canDelete else { return false }
        if !owner[keyPath: relationship].isEmpty {
            owner[keyPath: relationship] = []
            return true
        }
        return false
    }

    guard let nestedValues: [[String: Any]] = payload.strictValue(for: key) else {
        return false
    }

    var changed = false
    let relatedRows = try context.fetch(FetchDescriptor<Related>())
    var relatedByID: [String: Related] = Dictionary(
        uniqueKeysWithValues: relatedRows.compactMap { row in
            guard let identity = resolveIdentity(from: row) else { return nil }
            return (identity, row)
        }
    )

    var desired: [Related] = []
    var desiredIDs: Set<PersistentIdentifier> = []
    for nestedValue in nestedValues {
        let nestedPayload = SyncPayload(values: nestedValue, keyStyle: payload.keyStyle)
        var resolved: Related?

        if let nestedIdentity = resolveIdentity(from: nestedPayload, model: Related.self),
            let existing = relatedByID[nestedIdentity]
        {
            if operations.contains(.update), try existing.apply(nestedPayload) {
                changed = true
            }
            resolved = existing
        } else if operations.contains(.insert) {
            let created = try Related.make(from: nestedPayload)
            context.insert(created)
            if let createdIdentity = resolveIdentity(from: created) {
                relatedByID[createdIdentity] = created
            }
            resolved = created
            changed = true
        }

        if let resolved, desiredIDs.insert(resolved.persistentModelID).inserted {
            desired.append(resolved)
        }
    }

    let current = owner[keyPath: relationship]
    let next = mergeUnorderedRelationships(
        current: current,
        desired: desired,
        allowDelete: canDelete,
        allowAdd: canAdd
    )

    if modelIDSet(current) != modelIDSet(next) {
        owner[keyPath: relationship] = next
        changed = true
    }

    return changed
}

private func firstPresentPayloadKey(_ payload: SyncPayload, keys: [String]) -> String? {
    for key in keys where payload.contains(key) {
        return key
    }
    return nil
}

private func dedupePreservingOrder<ID: Hashable>(_ input: [ID]) -> [ID] {
    var seen: Set<ID> = []
    var output: [ID] = []
    output.reserveCapacity(input.count)
    for value in input {
        if seen.insert(value).inserted {
            output.append(value)
        }
    }
    return output
}

private func modelIDSet<Model: PersistentModel>(_ models: [Model]) -> Set<PersistentIdentifier> {
    Set(models.map(\.persistentModelID))
}

private func mergeUnorderedRelationships<Model: PersistentModel>(
    current: [Model],
    desired: [Model],
    allowDelete: Bool,
    allowAdd: Bool
) -> [Model] {
    let desiredIDs = Set(desired.map(\.persistentModelID))

    var next: [Model]
    if allowDelete {
        next = current.filter { desiredIDs.contains($0.persistentModelID) }
    } else {
        next = current
    }

    guard allowAdd else { return next }

    let nextIDs = Set(next.map(\.persistentModelID))
    for model in desired where !nextIDs.contains(model.persistentModelID) {
        next.append(model)
    }
    return next
}

private func resolveIdentity<Model: SyncModelable>(from payload: SyncPayload, model: Model.Type) -> String? {
    _ = model
    for key in Model.syncIdentityRemoteKeys {
        if let identity = payload.value(for: key, as: Model.SyncID.self) {
            return syncIdentityKey(from: identity)
        }
    }
    return nil
}

private func resolveIdentity<Model: SyncModelable>(from row: Model) -> String? {
    syncIdentityKey(from: row[keyPath: Model.syncIdentity])
}

private func syncIdentityKey<ID: Hashable>(from identity: ID) -> String {
    String(describing: identity)
}

public protocol ParentScopedModel: SyncUpdatableModel {
    associatedtype SyncParent: PersistentModel
    static var parentRelationship: ReferenceWritableKeyPath<Self, SyncParent?> { get }
}

public extension ParentScopedModel {
    static var syncIdentityPolicy: SyncIdentityPolicy { .scopedByParent }
}

public protocol GlobalParentScopedModel: ParentScopedModel {}

public extension GlobalParentScopedModel {
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }
}

public enum SyncIdentityPolicy: Sendable {
    case global
    case scopedByParent
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
        let scalars = Array(value.unicodeScalars)
        for (index, scalar) in scalars.enumerated() {
            let current = scalarClass(scalar)
            if index > 0, current == .upper {
                let previous = scalarClass(scalars[index - 1])
                let next = index + 1 < scalars.count ? scalarClass(scalars[index + 1]) : nil
                let startsNewWord = previous == .lower || previous == .digit
                let endsAcronym = previous == .upper && next == .lower
                if (startsNewWord || endsAcronym), output.last != "_" {
                    output.append("_")
                }
            }
            output.append(String(scalar).lowercased())
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
    public let keyStyle: SyncInputKeyStyle

    public init(values: [String: Any], keyStyle: SyncInputKeyStyle = .snakeCase) {
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

    public func strictValue<T>(for key: String, as type: T.Type = T.self) -> T? {
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
        if T.self == Date.self, containsCandidateValue(for: key) {
            // Date parsing is best-effort; invalid values fall back to epoch for required fields.
            return Date(timeIntervalSince1970: 0) as! T
        }
        if isExplicitNull(for: key), let fallback: T = defaultValueForNull(as: type) {
            return fallback
        }
        throw SyncError.invalidPayload(model: "Payload", reason: "Missing or invalid '\(key)'")
    }

    public func strictRequired<T>(_ type: T.Type = T.self, for key: String) throws -> T {
        if let value: T = strictValue(for: key, as: type) {
            return value
        }
        if T.self == Date.self, containsCandidateValue(for: key) {
            return Date(timeIntervalSince1970: 0) as! T
        }
        if isExplicitNull(for: key), let fallback: T = defaultValueForNull(as: type) {
            return fallback
        }
        throw SyncError.invalidPayload(model: "Payload", reason: "Missing or invalid '\(key)'")
    }

    private func candidateKeys(for key: String) -> [String] {
        var keys: [String] = []
        switch keyStyle {
        case .snakeCase:
            keys.append(key.split(separator: ".", omittingEmptySubsequences: false)
                .map { snakeCased(String($0)) }
                .joined(separator: "."))
        case .camelCase:
            keys.append(key.split(separator: ".", omittingEmptySubsequences: false)
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
        return ordered
    }

    private func containsCandidateValue(for key: String) -> Bool {
        candidateKeys(for: key).contains { candidate in
            rawValue(for: candidate) != nil
        }
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
                if (startsNewWord || endsAcronym), output.last != "_" {
                    output.append("_")
                }
            }
            output.append(String(scalar).lowercased())
        }
        return output
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
            if let string = raw as? String, let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) {
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

public enum SyncInputKeyStyle: Sendable {
    case snakeCase
    case camelCase
}
