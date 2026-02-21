import XCTest
import SwiftData
import SwiftSync

@Syncable
@Model
final class User {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class LooseUser {
    var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class RemoteUser {
    @Attribute(.unique) var remoteID: Int
    var fullName: String

    init(remoteID: Int, fullName: String) {
        self.remoteID = remoteID
        self.fullName = fullName
    }
}

@Syncable
@Model
final class ExternalUser {
    @PrimaryKey
    @Attribute(.unique) var xid: String
    var name: String

    init(xid: String, name: String) {
        self.xid = xid
        self.name = name
    }
}

@Syncable
@Model
final class Profile {
    @Attribute(.unique) var id: Int
    var firstName: String
    var updatedAt: Date

    init(id: Int, firstName: String, updatedAt: Date) {
        self.id = id
        self.firstName = firstName
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class OptionalDateProfile {
    @Attribute(.unique) var id: Int
    var updatedAt: Date?

    init(id: Int, updatedAt: Date?) {
        self.id = id
        self.updatedAt = updatedAt
    }
}

@Syncable
@Model
final class PrimitiveUser {
    @Attribute(.unique) var id: Int
    var name: String
    var age: Int
    var score: Double
    var isActive: Bool
    var updatedAt: Date
    var token: UUID
    var bigCount: Int64
    var nickname: String?

    init(
        id: Int,
        name: String,
        age: Int,
        score: Double,
        isActive: Bool,
        updatedAt: Date,
        token: UUID,
        bigCount: Int64,
        nickname: String?
    ) {
        self.id = id
        self.name = name
        self.age = age
        self.score = score
        self.isActive = isActive
        self.updatedAt = updatedAt
        self.token = token
        self.bigCount = bigCount
        self.nickname = nickname
    }
}

@Syncable
@Model
final class ExternalMappedUser {
    @PrimaryKey(remote: "external_id")
    @Attribute(.unique) var xid: String
    var name: String

    init(xid: String, name: String) {
        self.xid = xid
        self.name = name
    }
}

@Syncable
@Model
final class StringIDUser {
    @Attribute(.unique) var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class Member {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Model
final class Team {
    @Attribute(.unique) var id: Int
    var name: String
    var owner: Member?
    var members: [Member]

    init(id: Int, name: String, owner: Member? = nil, members: [Member] = []) {
        self.id = id
        self.name = name
        self.owner = owner
        self.members = members
    }
}

@Model
final class Company {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class Employee {
    @Attribute(.unique) var id: Int
    var name: String
    var company: Company?

    init(id: Int, name: String, company: Company? = nil) {
        self.id = id
        self.name = name
        self.company = company
    }
}

@Syncable
@Model
final class AutoCompany {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class AutoEmployee {
    @Attribute(.unique) var id: Int
    var name: String
    var company: AutoCompany?

    init(id: Int, name: String, company: AutoCompany? = nil) {
        self.id = id
        self.name = name
        self.company = company
    }
}

extension AutoEmployee: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        try syncApplyGeneratedRelationships(payload, in: context)
    }
}

@Syncable
@Model
final class AutoTag {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Syncable
@Model
final class AutoTask {
    @Attribute(.unique) var id: Int
    var title: String

    @RemoteKey("tag_ids")
    var tags: [AutoTag]

    init(id: Int, title: String, tags: [AutoTag] = []) {
        self.id = id
        self.title = title
        self.tags = tags
    }
}

extension AutoTask: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        try syncApplyGeneratedRelationships(payload, in: context)
    }
}

@Model
final class Note {
    @Attribute(.unique) var id: Int
    var text: String

    init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

@Model
final class UserWithNotes {
    @Attribute(.unique) var id: Int
    var name: String
    var notes: [Note]

    init(id: Int, name: String, notes: [Note] = []) {
        self.id = id
        self.name = name
        self.notes = notes
    }
}

@Model
final class Tag {
    @Attribute(.unique) var id: Int
    var name: String
    var usersByObjects: [UserTagsByObjects]
    var usersByIDs: [UserTagsByIDs]

    init(id: Int, name: String) {
        self.id = id
        self.name = name
        self.usersByObjects = []
        self.usersByIDs = []
    }
}

@Model
final class UserTagsByObjects {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \Tag.usersByObjects)
    var tags: [Tag]

    init(id: Int, name: String, tags: [Tag] = []) {
        self.id = id
        self.name = name
        self.tags = tags
    }
}

@Model
final class UserTagsByIDs {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \Tag.usersByIDs)
    var tags: [Tag]

    init(id: Int, name: String, tags: [Tag] = []) {
        self.id = id
        self.name = name
        self.tags = tags
    }
}

@Model
final class SuperUser {
    @Attribute(.unique) var id: Int
    var name: String
    var notes: [SuperNote]

    init(id: Int, name: String, notes: [SuperNote] = []) {
        self.id = id
        self.name = name
        self.notes = notes
    }
}

@Model
final class SuperNote {
    @Attribute(.unique) var id: Int
    var text: String
    @Relationship(inverse: \SuperUser.notes)
    var superUser: SuperUser?

    init(id: Int, text: String, superUser: SuperUser? = nil) {
        self.id = id
        self.text = text
        self.superUser = superUser
    }
}

extension Team: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<Team, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> Team {
        Team(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            return true
        }
        return false
    }
}

extension Team: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        var changed = false

        if payload.contains("owner") {
            let nextOwner: Member?
            if let ownerPayload: [String: Any] = payload.value(for: "owner") {
                nextOwner = try upsertMember(from: ownerPayload, in: context)
            } else {
                nextOwner = nil
            }

            if owner?.id != nextOwner?.id {
                owner = nextOwner
                changed = true
            }
        }

        if payload.contains("members") {
            let desiredMembers: [Member]
            if let memberPayloads: [[String: Any]] = payload.value(for: "members") {
                var resolvedMembers: [Member] = []
                for memberPayload in memberPayloads {
                    resolvedMembers.append(try upsertMember(from: memberPayload, in: context))
                }
                desiredMembers = resolvedMembers
            } else {
                // Explicit null for members means clear membership.
                desiredMembers = []
            }
            if members.map(\.id) != desiredMembers.map(\.id) {
                members = desiredMembers
                changed = true
            }
        }

        return changed
    }

    private func upsertMember(from payload: [String: Any], in context: ModelContext) throws -> Member {
        let syncPayload = SyncPayload(values: payload)
        let memberID: Int = try syncPayload.required(Int.self, for: "id")
        let allMembers = try context.fetch(FetchDescriptor<Member>())
        if let existing = allMembers.first(where: { $0.id == memberID }) {
            _ = try existing.apply(syncPayload)
            return existing
        }
        let created = try Member.make(from: syncPayload)
        context.insert(created)
        return created
    }
}

extension Company: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<Company, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> Company {
        Company(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension Employee: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<Employee, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> Employee {
        Employee(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension Employee: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        // Support to-one by foreign key scalar (company_id).
        guard payload.contains("company_id") else { return false }

        let companyID: Int? = payload.value(for: "company_id")
        if let companyID {
            let companies = try context.fetch(FetchDescriptor<Company>())
            let nextCompany = companies.first(where: { $0.id == companyID })
            if company?.id != nextCompany?.id {
                company = nextCompany
                return true
            }
            return false
        } else {
            if company != nil {
                company = nil
                return true
            }
            return false
        }
    }
}

extension Note: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<Note, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> Note {
        Note(
            id: try payload.required(Int.self, for: "id"),
            text: try payload.required(String.self, for: "text")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingText: String = try payload.required(String.self, for: "text")
        if text != incomingText {
            text = incomingText
            changed = true
        }
        return changed
    }
}

extension UserWithNotes: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<UserWithNotes, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> UserWithNotes {
        UserWithNotes(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension UserWithNotes: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        // Support to-many by foreign key scalar array (notes_ids).
        guard payload.contains("notes_ids") else { return false }

        let desiredIDs: [Int]
        if let value: [Int] = payload.value(for: "notes_ids") {
            desiredIDs = value
        } else {
            desiredIDs = []
        }

        let allNotes = try context.fetch(FetchDescriptor<Note>())
        let byID = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.id, $0) })
        let desiredNotes = desiredIDs.compactMap { byID[$0] }

        if notes.map(\.id) != desiredNotes.map(\.id) {
            notes = desiredNotes
            return true
        }
        return false
    }
}

extension Tag: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<Tag, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> Tag {
        Tag(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension UserTagsByObjects: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<UserTagsByObjects, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> UserTagsByObjects {
        UserTagsByObjects(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension UserTagsByObjects: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        guard payload.contains("tags") else { return false }
        let desiredTags: [Tag]
        if let tagPayloads: [[String: Any]] = payload.value(for: "tags") {
            var resolved: [Tag] = []
            for tagPayload in tagPayloads {
                resolved.append(try upsertTag(from: tagPayload, in: context))
            }
            desiredTags = resolved
        } else {
            desiredTags = []
        }
        if tags.map(\.id) != desiredTags.map(\.id) {
            tags = desiredTags
            return true
        }
        return false
    }

    private func upsertTag(from payload: [String: Any], in context: ModelContext) throws -> Tag {
        let syncPayload = SyncPayload(values: payload)
        let tagID: Int = try syncPayload.required(Int.self, for: "id")
        let allTags = try context.fetch(FetchDescriptor<Tag>())
        if let existing = allTags.first(where: { $0.id == tagID }) {
            _ = try existing.apply(syncPayload)
            return existing
        }
        let created = try Tag.make(from: syncPayload)
        context.insert(created)
        return created
    }
}

extension UserTagsByIDs: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<UserTagsByIDs, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> UserTagsByIDs {
        UserTagsByIDs(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension UserTagsByIDs: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        guard payload.contains("tags_ids") else { return false }
        let desiredIDs: [Int]
        if let ids: [Int] = payload.value(for: "tags_ids") {
            desiredIDs = ids
        } else {
            desiredIDs = []
        }
        let allTags = try context.fetch(FetchDescriptor<Tag>())
        let byID = Dictionary(uniqueKeysWithValues: allTags.map { ($0.id, $0) })
        let desiredTags = desiredIDs.compactMap { byID[$0] }
        if tags.map(\.id) != desiredTags.map(\.id) {
            tags = desiredTags
            return true
        }
        return false
    }
}

extension SuperUser: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<SuperUser, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> SuperUser {
        SuperUser(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingName: String = try payload.required(String.self, for: "name")
        if name != incomingName {
            name = incomingName
            changed = true
        }
        return changed
    }
}

extension SuperNote: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<SuperNote, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> SuperNote {
        SuperNote(
            id: try payload.required(Int.self, for: "id"),
            text: payload.value(for: "text") ?? ""
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        let incomingText: String = payload.value(for: "text") ?? ""
        if text != incomingText {
            text = incomingText
            changed = true
        }
        return changed
    }
}

extension SuperNote: ParentScopedModel {
    typealias SyncParent = SuperUser
    static var parentRelationship: ReferenceWritableKeyPath<SuperNote, SuperUser?> { \.superUser }
}

@Model
final class ScopedBucket {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \ScopedItem.bucket)
    var items: [ScopedItem]

    init(id: Int, name: String, items: [ScopedItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

@Model
final class ScopedItem {
    var id: Int
    var text: String
    var bucket: ScopedBucket?

    init(id: Int, text: String, bucket: ScopedBucket? = nil) {
        self.id = id
        self.text = text
        self.bucket = bucket
    }
}

extension ScopedItem: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<ScopedItem, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> ScopedItem {
        ScopedItem(
            id: try payload.required(Int.self, for: "id"),
            text: try payload.required(String.self, for: "text")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("text") {
            let incoming: String = try payload.required(String.self, for: "text")
            if text != incoming {
                text = incoming
                changed = true
            }
        }
        return changed
    }
}

extension ScopedItem: ParentScopedModel {
    typealias SyncParent = ScopedBucket
    static var parentRelationship: ReferenceWritableKeyPath<ScopedItem, ScopedBucket?> { \.bucket }
}

@Model
final class GlobalBucket {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \GlobalItem.bucket)
    var items: [GlobalItem]

    init(id: Int, name: String, items: [GlobalItem] = []) {
        self.id = id
        self.name = name
        self.items = items
    }
}

@Model
final class GlobalItem {
    @Attribute(.unique) var id: Int
    var text: String
    var bucket: GlobalBucket?

    init(id: Int, text: String, bucket: GlobalBucket? = nil) {
        self.id = id
        self.text = text
        self.bucket = bucket
    }
}

extension GlobalItem: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<GlobalItem, Int> { \.id }
    static var syncIdentityPolicy: SyncIdentityPolicy { .global }

    static func make(from payload: SyncPayload) throws -> GlobalItem {
        GlobalItem(
            id: try payload.required(Int.self, for: "id"),
            text: try payload.required(String.self, for: "text")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("text") {
            let incoming: String = try payload.required(String.self, for: "text")
            if text != incoming {
                text = incoming
                changed = true
            }
        }
        return changed
    }
}

extension GlobalItem: ParentScopedModel {
    typealias SyncParent = GlobalBucket
    static var parentRelationship: ReferenceWritableKeyPath<GlobalItem, GlobalBucket?> { \.bucket }
}

@Model
final class OpsCompany {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class OpsEmployee {
    @Attribute(.unique) var id: Int
    var name: String
    var company: OpsCompany?

    init(id: Int, name: String, company: OpsCompany? = nil) {
        self.id = id
        self.name = name
        self.company = company
    }
}

extension OpsCompany: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<OpsCompany, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OpsCompany {
        OpsCompany(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incoming: String = try payload.required(String.self, for: "name")
            if name != incoming {
                name = incoming
                changed = true
            }
        }
        return changed
    }
}

extension OpsEmployee: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<OpsEmployee, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> OpsEmployee {
        OpsEmployee(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("name") {
            let incoming: String = try payload.required(String.self, for: "name")
            if name != incoming {
                name = incoming
                changed = true
            }
        }
        return changed
    }
}

extension OpsEmployee: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        try await applyRelationships(payload, in: context, operations: .all)
    }

    func applyRelationships(
        _ payload: SyncPayload,
        in context: ModelContext,
        operations: SyncRelationshipOperations
    ) async throws -> Bool {
        guard !operations.isDisjoint(with: [.insert, .update, .delete]) else { return false }
        guard payload.contains("company_id") else { return false }

        if payload.value(for: "company_id", as: NSNull.self) != nil {
            if company != nil {
                company = nil
                return true
            }
            return false
        }

        guard let companyID: Int = payload.strictValue(for: "company_id") else {
            // Strict foreign-key typing: mismatched key type is ignored.
            return false
        }

        let companies = try context.fetch(FetchDescriptor<OpsCompany>())
        let nextCompany = companies.first(where: { $0.id == companyID })
        guard let nextCompany else {
            return false
        }

        if company?.id != nextCompany.id {
            company = nextCompany
            return true
        }
        return false
    }
}

@Syncable
@Model
final class ConcurrentRaceUser {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class DifferentContextConflictUser {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

private actor ConcurrentRaceHooks {
    static let shared = ConcurrentRaceHooks()

    private var blockFirst = false
    private var didBlockFirst = false
    private var firstBlockedContinuation: CheckedContinuation<Void, Never>?
    private var releaseFirstContinuation: CheckedContinuation<Void, Never>?

    func installFirstSyncBlocker() {
        blockFirst = true
        didBlockFirst = false
        firstBlockedContinuation = nil
        releaseFirstContinuation = nil
    }

    func waitUntilFirstSyncBlocked() async {
        if didBlockFirst { return }
        await withCheckedContinuation { continuation in
            firstBlockedContinuation = continuation
        }
    }

    func releaseFirstSync() {
        releaseFirstContinuation?.resume()
        releaseFirstContinuation = nil
        blockFirst = false
    }

    func waitIfInstalled() async {
        if blockFirst {
            blockFirst = false
            didBlockFirst = true
            firstBlockedContinuation?.resume()
            firstBlockedContinuation = nil
            await withCheckedContinuation { continuation in
                releaseFirstContinuation = continuation
            }
        }
    }
}

private actor CancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

extension ConcurrentRaceUser: SyncRelationshipUpdatableModel {
    func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
        _ = payload
        _ = context
        if id == 1 {
            await ConcurrentRaceHooks.shared.waitIfInstalled()
            await Task.yield()
        }
        return false
    }
}

final class IntegrationTests: XCTestCase {
    func testApplyReturnsFalseWhenPayloadMatchesExistingValues() throws {
        let user = User(id: 1, fullName: "Ava Swift")
        let payload = SyncPayload(values: ["id": 1, "full_name": "Ava Swift"])

        let changed = try user.apply(payload)

        XCTAssertFalse(changed)
        XCTAssertEqual(user.fullName, "Ava Swift")
    }

    func testApplyReturnsTrueWhenAnyFieldDiffers() throws {
        let user = User(id: 1, fullName: "Ava Swift")
        let payload = SyncPayload(values: ["id": 1, "full_name": "Ava Updated"])

        let changed = try user.apply(payload)

        XCTAssertTrue(changed)
        XCTAssertEqual(user.fullName, "Ava Updated")
    }

    @MainActor
    func testSyncInsertsThenUpdatesByID() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        let insertPayload: [Any] = [["id": 1, "full_name": "Ava Swift"]]
        try await SwiftSync.sync(payload: insertPayload, as: User.self, in: context)

        var users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.fullName, "Ava Swift")

        let updatePayload: [Any] = [["id": 1, "full_name": "Ava Updated"]]
        try await SwiftSync.sync(payload: updatePayload, as: User.self, in: context)

        users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.fullName, "Ava Updated")
    }

    @MainActor
    func testSyncUsesRemoteIDConvention() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RemoteUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [["id": 55, "full_name": "Remote User"]]
        try await SwiftSync.sync(payload: payload, as: RemoteUser.self, in: context)

        let users = try context.fetch(FetchDescriptor<RemoteUser>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.remoteID, 55)
        XCTAssertEqual(users.first?.fullName, "Remote User")
    }

    @MainActor
    func testSyncLenientIntPrimaryKeyCoercesFloatValue() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [["id": 42.9, "full_name": "Float ID User"]]
        try await SwiftSync.sync(payload: payload, as: User.self, in: context)

        let users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, 42)
        XCTAssertEqual(users.first?.fullName, "Float ID User")
    }

    @MainActor
    func testSyncCoercesStringIDToIntAndMatchesLaterNumericID() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["id": "42", "full_name": "X"]]
        try await SwiftSync.sync(payload: payloadA, as: User.self, in: context)

        var rows = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 42)

        let payloadB: [Any] = [["id": 42, "full_name": "X Updated"]]
        try await SwiftSync.sync(payload: payloadB, as: User.self, in: context)

        rows = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 42)
        XCTAssertEqual(rows.first?.fullName, "X Updated")
    }

    @MainActor
    func testSyncCoercesNumericIDToStringAndMatchesLaterStringID() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StringIDUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["id": 42, "name": "X"]]
        try await SwiftSync.sync(payload: payloadA, as: StringIDUser.self, in: context)

        var rows = try context.fetch(FetchDescriptor<StringIDUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "42")
        XCTAssertEqual(rows.first?.name, "X")

        let payloadB: [Any] = [["id": "42", "name": "X Updated"]]
        try await SwiftSync.sync(payload: payloadB, as: StringIDUser.self, in: context)

        rows = try context.fetch(FetchDescriptor<StringIDUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, "42")
        XCTAssertEqual(rows.first?.name, "X Updated")
    }

    @MainActor
    func testSyncSnakeCaseToCamelCaseWithISO8601Date() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Profile.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [[
            "id": 1,
            "first_name": "Elvis",
            "updated_at": "2014-02-17T00:00:00+00:00"
        ]]
        try await SwiftSync.sync(payload: payload, as: Profile.self, in: context)
        try await SwiftSync.sync(payload: payload, as: Profile.self, in: context)

        let rows = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.firstName, "Elvis")
        XCTAssertEqual(rows.first?.updatedAt, ISO8601DateFormatter().date(from: "2014-02-17T00:00:00+00:00"))
    }

    @MainActor
    func testSyncParsesDateOnlyISOFormat() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Profile.self, configurations: configuration)
        let context = ModelContext(container)

        let payload: [Any] = [[
            "id": 1,
            "first_name": "Elvis",
            "updated_at": "2014-01-02"
        ]]
        try await SwiftSync.sync(payload: payload, as: Profile.self, in: context)

        let rows = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(rows.count, 1)

        var components = DateComponents()
        components.calendar = Calendar(identifier: .iso8601)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2014
        components.month = 1
        components.day = 2
        components.hour = 0
        components.minute = 0
        components.second = 0
        XCTAssertEqual(rows.first?.updatedAt, components.date)
    }

    @MainActor
    func testSyncParsesUnixTimestampVariants() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Profile.self, configurations: configuration)
        let context = ModelContext(container)

        // Seconds
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "A",
                "updated_at": 1_700_000_000
            ]],
            as: Profile.self,
            in: context
        )
        var rows = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        // Milliseconds
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "A",
                "updated_at": 1_700_000_000_000
            ]],
            as: Profile.self,
            in: context
        )
        rows = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))

        // Microseconds
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "A",
                "updated_at": 1_700_000_000_000_000
            ]],
            as: Profile.self,
            in: context
        )
        rows = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    @MainActor
    func testSyncInvalidDateDefaultsRequiredAndNilForOptional() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Profile.self, OptionalDateProfile.self, configurations: configuration)
        let context = ModelContext(container)

        // Required Date field defaults to epoch on invalid input.
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "first_name": "Elvis",
                "updated_at": "not-a-date"
            ]],
            as: Profile.self,
            in: context
        )
        let requiredRows = try context.fetch(FetchDescriptor<Profile>())
        XCTAssertEqual(requiredRows.count, 1)
        XCTAssertEqual(requiredRows.first?.updatedAt, Date(timeIntervalSince1970: 0))

        // Optional Date field stays nil on invalid input.
        try await SwiftSync.sync(
            payload: [[
                "id": 2,
                "updated_at": "not-a-date"
            ]],
            as: OptionalDateProfile.self,
            in: context
        )
        let optionalRows = try context.fetch(FetchDescriptor<OptionalDateProfile>())
        XCTAssertEqual(optionalRows.count, 1)
        XCTAssertNil(optionalRows.first?.updatedAt)
    }

    @MainActor
    func testSyncNullClearsNonOptionalPrimitiveScalarsToDefaults() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: PrimitiveUser.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 1,
            "name": "Alice",
            "age": 40,
            "score": 99.5,
            "is_active": true,
            "updated_at": "2014-02-17T00:00:00+00:00",
            "token": "123E4567-E89B-12D3-A456-426614174000",
            "big_count": Int64(77),
            "nickname": "Al"
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: PrimitiveUser.self, in: context)

        let clearPayload: [Any] = [[
            "id": 1,
            "name": NSNull(),
            "age": NSNull(),
            "score": NSNull(),
            "is_active": NSNull(),
            "updated_at": NSNull(),
            "token": NSNull(),
            "big_count": NSNull(),
            "nickname": NSNull()
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: PrimitiveUser.self, in: context)

        let rows = try context.fetch(FetchDescriptor<PrimitiveUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.name, "")
        XCTAssertEqual(rows.first?.age, 0)
        XCTAssertEqual(rows.first?.score, 0.0)
        XCTAssertEqual(rows.first?.isActive, false)
        XCTAssertEqual(rows.first?.updatedAt, Date(timeIntervalSince1970: 0))
        XCTAssertEqual(rows.first?.token.uuidString, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(rows.first?.bigCount, 0)
        XCTAssertNil(rows.first?.nickname)
    }

    @MainActor
    func testSyncDeletesLocalRowsMissingFromPayload() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [
            ["id": 1, "full_name": "Ava Swift"],
            ["id": 2, "full_name": "Noah Swift"]
        ]
        try await SwiftSync.sync(payload: seedPayload, as: User.self, in: context)

        let replacePayload: [Any] = [["id": 1, "full_name": "Ava Updated"]]
        try await SwiftSync.sync(payload: replacePayload, as: User.self, in: context)

        let users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, 1)
        XCTAssertEqual(users.first?.fullName, "Ava Updated")
    }

    @MainActor
    func testSyncPrimaryKeyDiffingInsertUpdateDeleteInSingleRun() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [
            ["id": 0, "full_name": "User 0"],
            ["id": 1, "full_name": "User 1"],
            ["id": 2, "full_name": "User 2"],
            ["id": 3, "full_name": "User 3"],
            ["id": 4, "full_name": "User 4"]
        ]
        try await SwiftSync.sync(payload: seedPayload, as: User.self, in: context)

        let diffPayload: [Any] = [
            ["id": 0, "full_name": "User 0 Updated"],
            ["id": 1, "full_name": "User 1 Updated"],
            ["id": 6, "full_name": "User 6 New"]
        ]
        try await SwiftSync.sync(payload: diffPayload, as: User.self, in: context)

        let users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 3)

        let ids = Set(users.map(\.id))
        XCTAssertEqual(ids, Set([0, 1, 6]))
        XCTAssertEqual(users.filter { $0.id == 0 }.count, 1)
        XCTAssertEqual(users.filter { $0.id == 1 }.count, 1)
        XCTAssertEqual(users.filter { $0.id == 6 }.count, 1)

        XCTAssertEqual(users.first(where: { $0.id == 0 })?.fullName, "User 0 Updated")
        XCTAssertEqual(users.first(where: { $0.id == 1 })?.fullName, "User 1 Updated")
        XCTAssertEqual(users.first(where: { $0.id == 6 })?.fullName, "User 6 New")
    }

    @MainActor
    func testSyncDeduplicatesLocalDuplicatePrimaryKeys() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: LooseUser.self, configurations: configuration)
        let context = ModelContext(container)

        context.insert(LooseUser(id: 1, fullName: "dup-a"))
        context.insert(LooseUser(id: 1, fullName: "dup-b"))
        context.insert(LooseUser(id: 1, fullName: "dup-c"))
        context.insert(LooseUser(id: 2, fullName: "other"))
        try context.save()

        let payload: [Any] = [["id": 1, "full_name": "single"]]
        do {
            try await SwiftSync.sync(payload: payload, as: LooseUser.self, in: context)
        } catch {
            XCTFail("Expected sync to dedupe local duplicates without crashing, got error: \(error)")
        }

        let rows = try context.fetch(FetchDescriptor<LooseUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.filter { $0.id == 1 }.count, 1)
        XCTAssertEqual(rows.first?.id, 1)
        XCTAssertEqual(rows.first?.fullName, "single")
    }

    @MainActor
    func testSyncUsesCustomPrimaryKeyWithoutIDField() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ExternalUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["xid": "abc", "name": "v1"]]
        try await SwiftSync.sync(payload: payloadA, as: ExternalUser.self, in: context)

        let payloadB: [Any] = [["xid": "abc", "name": "v2"]]
        try await SwiftSync.sync(payload: payloadB, as: ExternalUser.self, in: context)

        let rows = try context.fetch(FetchDescriptor<ExternalUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.xid, "abc")
        XCTAssertEqual(rows.first?.name, "v2")
    }

    @MainActor
    func testSyncUsesCustomPrimaryKeyWithRemoteKeyMapping() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ExternalMappedUser.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [["external_id": "abc", "name": "v1"]]
        try await SwiftSync.sync(payload: payloadA, as: ExternalMappedUser.self, in: context)

        let payloadB: [Any] = [["external_id": "abc", "name": "v2"]]
        try await SwiftSync.sync(payload: payloadB, as: ExternalMappedUser.self, in: context)

        let rows = try context.fetch(FetchDescriptor<ExternalMappedUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.xid, "abc")
        XCTAssertEqual(rows.first?.name, "v2")
    }

    @MainActor
    func testSyncSkipsRowsWithNullOrMissingIdentity() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [
            ["id": 1, "full_name": "One"],
            ["id": 2, "full_name": "Two"]
        ]
        try await SwiftSync.sync(payload: seedPayload, as: User.self, in: context)

        let mixedPayload: [Any] = [
            ["id": NSNull(), "full_name": "Null ID"],
            ["full_name": "Missing ID"],
            ["id": 1, "full_name": "One Updated"]
        ]

        do {
            try await SwiftSync.sync(payload: mixedPayload, as: User.self, in: context)
        } catch {
            XCTFail("Expected sync to skip invalid identity rows, got error: \(error)")
        }

        let users = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users.first?.id, 1)
        XCTAssertEqual(users.first?.fullName, "One Updated")
    }

    @MainActor
    func testSyncRelationshipsApplyToOneAndToMany() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Team.self, Member.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 10,
            "name": "Platform",
            "owner": ["id": 1, "full_name": "Owner A"],
            "members": [
                ["id": 1, "full_name": "Owner A"],
                ["id": 2, "full_name": "Member B"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: Team.self, in: context)

        let updatePayload: [Any] = [[
            "id": 10,
            "name": "Platform Updated",
            "owner": ["id": 2, "full_name": "Member B Updated"],
            "members": [
                ["id": 2, "full_name": "Member B Updated"],
                ["id": 3, "full_name": "Member C"]
            ]
        ]]
        try await SwiftSync.sync(payload: updatePayload, as: Team.self, in: context)

        let teams = try context.fetch(FetchDescriptor<Team>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams.first?.name, "Platform Updated")
        XCTAssertEqual(teams.first?.owner?.id, 2)
        XCTAssertEqual(teams.first?.members.map(\.id), [2, 3])
    }

    @MainActor
    func testSyncRelationshipsClearWithNullAndEmptyCollection() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Team.self, Member.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 11,
            "name": "Platform",
            "owner": ["id": 1, "full_name": "Owner A"],
            "members": [
                ["id": 1, "full_name": "Owner A"],
                ["id": 2, "full_name": "Member B"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: Team.self, in: context)

        let clearPayload: [Any] = [[
            "id": 11,
            "name": "Platform",
            "owner": NSNull(),
            "members": []
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: Team.self, in: context)

        let teams = try context.fetch(FetchDescriptor<Team>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertNil(teams.first?.owner)
        XCTAssertEqual(teams.first?.members.count, 0)
    }

    @MainActor
    func testSyncToManyObjectArrayEmptyClearsRelationshipSet() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserTagsByObjects.self, Tag.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 1,
            "name": "U1",
            "tags": [
                ["id": 10, "name": "t10"],
                ["id": 11, "name": "t11"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: UserTagsByObjects.self, in: context)

        let clearPayload: [Any] = [[
            "id": 1,
            "name": "U1",
            "tags": []
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: UserTagsByObjects.self, in: context)

        let users = try context.fetch(FetchDescriptor<UserTagsByObjects>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users[0].tags.count, 0)
    }

    @MainActor
    func testSyncToManyObjectArrayNullClearsRelationshipSetAndMatchesEmptySemantics() async throws {
        // Snapshot A: clear with empty array.
        let configurationA = ModelConfiguration(isStoredInMemoryOnly: true)
        let containerA = try ModelContainer(for: UserTagsByObjects.self, Tag.self, configurations: configurationA)
        let contextA = ModelContext(containerA)
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 10, "name": "t10"],
                    ["id": 11, "name": "t11"]
                ]
            ]],
            as: UserTagsByObjects.self,
            in: contextA
        )
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "U1",
                "tags": []
            ]],
            as: UserTagsByObjects.self,
            in: contextA
        )
        let usersA = try contextA.fetch(FetchDescriptor<UserTagsByObjects>())

        // Snapshot B: clear with null.
        let configurationB = ModelConfiguration(isStoredInMemoryOnly: true)
        let containerB = try ModelContainer(for: UserTagsByObjects.self, Tag.self, configurations: configurationB)
        let contextB = ModelContext(containerB)
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 10, "name": "t10"],
                    ["id": 11, "name": "t11"]
                ]
            ]],
            as: UserTagsByObjects.self,
            in: contextB
        )
        do {
            try await SwiftSync.sync(
                payload: [[
                    "id": 1,
                    "name": "U1",
                    "tags": NSNull()
                ]],
                as: UserTagsByObjects.self,
                in: contextB
            )
        } catch {
            XCTFail("Expected null to clear to-many relationship without crashing, got error: \(error)")
        }
        let usersB = try contextB.fetch(FetchDescriptor<UserTagsByObjects>())

        XCTAssertEqual(usersA.count, 1)
        XCTAssertEqual(usersB.count, 1)
        XCTAssertEqual(usersA[0].tags.count, 0)
        XCTAssertEqual(usersB[0].tags.count, 0)
        XCTAssertEqual(Set(usersA[0].tags.map(\.id)), Set(usersB[0].tags.map(\.id)))
    }

    @MainActor
    func testSyncRelationshipsMissingKeysPreserveExistingLinks() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Team.self, Member.self, configurations: configuration)
        let context = ModelContext(container)

        let seedPayload: [Any] = [[
            "id": 12,
            "name": "Platform",
            "owner": ["id": 1, "full_name": "Owner A"],
            "members": [
                ["id": 1, "full_name": "Owner A"],
                ["id": 2, "full_name": "Member B"]
            ]
        ]]
        try await SwiftSync.sync(payload: seedPayload, as: Team.self, in: context)

        let nameOnlyPayload: [Any] = [[
            "id": 12,
            "name": "Platform Renamed"
        ]]
        try await SwiftSync.sync(payload: nameOnlyPayload, as: Team.self, in: context)

        let teams = try context.fetch(FetchDescriptor<Team>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams.first?.name, "Platform Renamed")
        XCTAssertEqual(teams.first?.owner?.id, 1)
        XCTAssertEqual(Set(teams.first?.members.map(\.id) ?? []), Set([1, 2]))
    }

    @MainActor
    func testSyncToOneByIDSetsAndClearsRelationship() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Employee.self, Company.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "Apple"]],
            as: Company.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava"]],
            as: Employee.self,
            in: context
        )

        let linkPayload: [Any] = [[
            "id": 1,
            "name": "Ava",
            "company_id": 10
        ]]
        try await SwiftSync.sync(payload: linkPayload, as: Employee.self, in: context)

        var employees = try context.fetch(FetchDescriptor<Employee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertEqual(employees.first?.id, 1)
        XCTAssertEqual(employees.first?.company?.id, 10)

        let clearPayload: [Any] = [[
            "id": 1,
            "name": "Ava",
            "company_id": NSNull()
        ]]
        try await SwiftSync.sync(payload: clearPayload, as: Employee.self, in: context)

        employees = try context.fetch(FetchDescriptor<Employee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertNil(employees.first?.company)
    }

    @MainActor
    func testSyncToOneByIDMissingReferencedCompanyIsDeterministic() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Employee.self, Company.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava"]],
            as: Employee.self,
            in: context
        )

        let missingReferencePayload: [Any] = [[
            "id": 1,
            "name": "Ava",
            "company_id": 999
        ]]
        do {
            try await SwiftSync.sync(payload: missingReferencePayload, as: Employee.self, in: context)
        } catch {
            XCTFail("Expected missing referenced company to be handled without crashing, got error: \(error)")
        }

        let employees = try context.fetch(FetchDescriptor<Employee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertNil(employees.first?.company)
    }

    @MainActor
    func testSyncableGeneratedToOneForeignKeySupportsStrictNullMissingAndUnknown() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AutoEmployee.self, AutoCompany.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "Acme"]],
            as: AutoCompany.self,
            in: context
        )
        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava"]],
            as: AutoEmployee.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "Ava",
                "company_id": 10
            ]],
            as: AutoEmployee.self,
            in: context
        )

        var employees = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertEqual(employees[0].company?.id, 10)

        // Strict FK typing: string payload for Int FK should be ignored.
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "Ava",
                "company_id": "10"
            ]],
            as: AutoEmployee.self,
            in: context
        )
        employees = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertEqual(employees[0].company?.id, 10)

        // Missing key should not clear existing relationship.
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "Ava Updated"
            ]],
            as: AutoEmployee.self,
            in: context
        )
        employees = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertEqual(employees[0].name, "Ava Updated")
        XCTAssertEqual(employees[0].company?.id, 10)

        // Unknown FK keeps current relation unchanged.
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "Ava Updated",
                "company_id": 999
            ]],
            as: AutoEmployee.self,
            in: context
        )
        employees = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertEqual(employees[0].company?.id, 10)

        // Explicit null clears relation.
        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "name": "Ava Updated",
                "company_id": NSNull()
            ]],
            as: AutoEmployee.self,
            in: context
        )
        employees = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertNil(employees[0].company)
    }

    @MainActor
    func testSyncToManyNestedObjectArrayReplacesMembershipAndUpdatesExistingChild() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Team.self, Member.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [[
            "id": 21,
            "name": "Inbox",
            "members": [
                ["id": 101, "full_name": "a"],
                ["id": 102, "full_name": "b"]
            ]
        ]]
        try await SwiftSync.sync(payload: payloadA, as: Team.self, in: context)

        var teams = try context.fetch(FetchDescriptor<Team>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(Set(teams[0].members.map(\.id)), Set([101, 102]))

        let payloadB: [Any] = [[
            "id": 21,
            "name": "Inbox",
            "members": [
                ["id": 102, "full_name": "b2"],
                ["id": 103, "full_name": "c"]
            ]
        ]]
        try await SwiftSync.sync(payload: payloadB, as: Team.self, in: context)

        teams = try context.fetch(FetchDescriptor<Team>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(Set(teams[0].members.map(\.id)), Set([102, 103]))
        XCTAssertFalse(Set(teams[0].members.map(\.id)).contains(101))

        let allMembers = try context.fetch(FetchDescriptor<Member>())
        XCTAssertEqual(allMembers.filter { $0.id == 102 }.count, 1)
        XCTAssertEqual(allMembers.first(where: { $0.id == 102 })?.fullName, "b2")
    }

    @MainActor
    func testSyncToManyByIDsReplacesMembershipExactly() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserWithNotes.self, Note.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 0, "text": "n0"],
                ["id": 1, "text": "n1"],
                ["id": 2, "text": "n2"]
            ],
            as: Note.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "U"]],
            as: UserWithNotes.self,
            in: context
        )

        let payloadA: [Any] = [[
            "id": 10,
            "name": "U",
            "notes_ids": [0, 1]
        ]]
        try await SwiftSync.sync(payload: payloadA, as: UserWithNotes.self, in: context)

        var users = try context.fetch(FetchDescriptor<UserWithNotes>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(Set(users[0].notes.map(\.id)), Set([0, 1]))

        let payloadB: [Any] = [[
            "id": 10,
            "name": "U",
            "notes_ids": [1, 2]
        ]]
        try await SwiftSync.sync(payload: payloadB, as: UserWithNotes.self, in: context)

        users = try context.fetch(FetchDescriptor<UserWithNotes>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(Set(users[0].notes.map(\.id)), Set([1, 2]))
        XCTAssertFalse(Set(users[0].notes.map(\.id)).contains(0))
    }

    @MainActor
    func testSyncableGeneratedToManyIDsDedupeUnknownMissingAndNull() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AutoTask.self, AutoTag.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "name": "Tag 1"],
                ["id": 2, "name": "Tag 2"]
            ],
            as: AutoTag.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [[
                "id": 5,
                "title": "Task A",
                "tag_ids": [1, 2, 2, 999]
            ]],
            as: AutoTask.self,
            in: context
        )

        var tasks = try context.fetch(FetchDescriptor<AutoTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(Set(tasks[0].tags.map(\.id)), Set([1, 2]))

        // Missing key should preserve current to-many links.
        try await SwiftSync.sync(
            payload: [[
                "id": 5,
                "title": "Task A Updated"
            ]],
            as: AutoTask.self,
            in: context
        )
        tasks = try context.fetch(FetchDescriptor<AutoTask>())
        XCTAssertEqual(tasks[0].title, "Task A Updated")
        XCTAssertEqual(Set(tasks[0].tags.map(\.id)), Set([1, 2]))

        // Explicit null clears links.
        try await SwiftSync.sync(
            payload: [[
                "id": 5,
                "title": "Task A Updated",
                "tag_ids": NSNull()
            ]],
            as: AutoTask.self,
            in: context
        )
        tasks = try context.fetch(FetchDescriptor<AutoTask>())
        XCTAssertEqual(tasks[0].tags.count, 0)
    }

    @MainActor
    func testSyncToManyByIDsIsIdempotentForRepeatedPayload() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserWithNotes.self, Note.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "n1"],
                ["id": 2, "text": "n2"]
            ],
            as: Note.self,
            in: context
        )
        try await SwiftSync.sync(
            payload: [["id": 10, "name": "U"]],
            as: UserWithNotes.self,
            in: context
        )

        let payloadB: [Any] = [[
            "id": 10,
            "name": "U",
            "notes_ids": [1, 2]
        ]]
        try await SwiftSync.sync(payload: payloadB, as: UserWithNotes.self, in: context)
        try await SwiftSync.sync(payload: payloadB, as: UserWithNotes.self, in: context)

        let users = try context.fetch(FetchDescriptor<UserWithNotes>())
        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(Set(users[0].notes.map(\.id)), Set([1, 2]))

        let notes = try context.fetch(FetchDescriptor<Note>())
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(Set(notes.map(\.id)), Set([1, 2]))
    }

    @MainActor
    func testSyncManyToManyObjectsAndIDsProduceEquivalentFinalGraph() async throws {
        let objectGraph = try await runManyToManyObjectsScenario()
        let idsGraph = try await runManyToManyIDsScenario()

        XCTAssertEqual(objectGraph, idsGraph)
        XCTAssertEqual(objectGraph[1], Set([2, 4]))
        XCTAssertEqual(objectGraph[2], Set([3]))
    }

    @MainActor
    func testSyncManyToManyObjectsAndIDsHaveEquivalentAddRemoveOutcomes() async throws {
        let objectGraph = try await runManyToManyObjectsScenario()
        let idsGraph = try await runManyToManyIDsScenario()

        // No duplicate join edges in either graph.
        XCTAssertEqual(objectGraph[1]?.count, 2)
        XCTAssertEqual(objectGraph[2]?.count, 1)
        XCTAssertEqual(idsGraph[1]?.count, 2)
        XCTAssertEqual(idsGraph[2]?.count, 1)

        // Same add/remove outcomes after update payload.
        XCTAssertFalse(objectGraph[1]?.contains(1) ?? true)
        XCTAssertFalse(idsGraph[1]?.contains(1) ?? true)
        XCTAssertTrue(objectGraph[1]?.contains(4) ?? false)
        XCTAssertTrue(idsGraph[1]?.contains(4) ?? false)
    }

    @MainActor
    func testSyncParentScopedLinksChildrenToExactParent() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SuperUser.self, SuperNote.self, configurations: configuration)
        let context = ModelContext(container)

        let userA = SuperUser(id: 6, name: "A")
        context.insert(userA)
        try context.save()

        let childPayload: [Any] = [
            ["id": 0, "text": "n0"],
            ["id": 1, "text": "n1"]
        ]
        try await SwiftSync.sync(
            payload: childPayload,
            as: SuperNote.self,
            in: context,
            parent: userA
        )

        let notes = try context.fetch(FetchDescriptor<SuperNote>())
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(Set(notes.map(\.id)), Set([0, 1]))
        XCTAssertTrue(notes.allSatisfy { $0.superUser?.id == 6 })
    }

    @MainActor
    func testSyncParentScopedDeleteAffectsOnlyThatParentScope() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SuperUser.self, SuperNote.self, configurations: configuration)
        let context = ModelContext(container)

        let userA = SuperUser(id: 6, name: "A")
        let userB = SuperUser(id: 7, name: "B")
        context.insert(userA)
        context.insert(userB)
        try context.save()

        try await SwiftSync.sync(
            payload: [
                ["id": 0, "text": "a0"],
                ["id": 1, "text": "a1"]
            ],
            as: SuperNote.self,
            in: context,
            parent: userA
        )
        try await SwiftSync.sync(
            payload: [
                ["id": 2, "text": "b2"],
                ["id": 3, "text": "b3"]
            ],
            as: SuperNote.self,
            in: context,
            parent: userB
        )

        // Sync user A scope with one child; user B scope must remain untouched.
        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "a1-updated"]
            ],
            as: SuperNote.self,
            in: context,
            parent: userA
        )

        let notes = try context.fetch(FetchDescriptor<SuperNote>())
        let notesA = notes.filter { $0.superUser?.id == 6 }
        let notesB = notes.filter { $0.superUser?.id == 7 }

        XCTAssertEqual(Set(notesA.map(\.id)), Set([1]))
        XCTAssertEqual(notesA.first?.text, "a1-updated")
        XCTAssertEqual(Set(notesB.map(\.id)), Set([2, 3]))
    }

    @MainActor
    func testParentObjectFromDifferentContextHandledDeterministically() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SuperUser.self, SuperNote.self, configurations: configuration)
        let contextA = ModelContext(container)
        let contextB = ModelContext(container)

        let userFromContextA = SuperUser(id: 42, name: "Parent A")
        contextA.insert(userFromContextA)

        var capturedError: Error?
        do {
            try await SwiftSync.sync(
                payload: [["id": 1001, "text": "cross-context-child"]],
                as: SuperNote.self,
                in: contextB,
                parent: userFromContextA
            )
        } catch {
            capturedError = error
        }

        XCTAssertNotNil(
            capturedError,
            "Expected deterministic handling for cross-context parent usage with a clear diagnostic."
        )
        if let capturedError {
            let description = String(describing: capturedError).lowercased()
            XCTAssertTrue(
                description.contains("context") || description.contains("parent") || description.contains("relationship"),
                "Expected diagnostic to mention parent/context mismatch, got: \(capturedError)"
            )
        }

        let notes = try contextB.fetch(FetchDescriptor<SuperNote>())
        XCTAssertEqual(notes.count, 0, "Safe fallback should avoid partial writes when parent context mismatches.")
    }

    @MainActor
    private func runManyToManyObjectsScenario() async throws -> [Int: Set<Int>] {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserTagsByObjects.self, Tag.self, configurations: configuration)
        let context = ModelContext(container)

        let payloadA: [Any] = [
            [
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 1, "name": "t1"],
                    ["id": 2, "name": "t2"]
                ]
            ],
            [
                "id": 2,
                "name": "U2",
                "tags": [
                    ["id": 2, "name": "t2"],
                    ["id": 3, "name": "t3"]
                ]
            ]
        ]
        try await SwiftSync.sync(payload: payloadA, as: UserTagsByObjects.self, in: context)

        let payloadB: [Any] = [
            [
                "id": 1,
                "name": "U1",
                "tags": [
                    ["id": 2, "name": "t2"],
                    ["id": 4, "name": "t4"]
                ]
            ],
            [
                "id": 2,
                "name": "U2",
                "tags": [
                    ["id": 3, "name": "t3"]
                ]
            ]
        ]
        try await SwiftSync.sync(payload: payloadB, as: UserTagsByObjects.self, in: context)

        let users = try context.fetch(FetchDescriptor<UserTagsByObjects>())
        return Dictionary(uniqueKeysWithValues: users.map { ($0.id, Set($0.tags.map(\.id))) })
    }

    @MainActor
    private func runManyToManyIDsScenario() async throws -> [Int: Set<Int>] {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: UserTagsByIDs.self, Tag.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "name": "t1"],
                ["id": 2, "name": "t2"],
                ["id": 3, "name": "t3"],
                ["id": 4, "name": "t4"]
            ],
            as: Tag.self,
            in: context
        )

        let payloadA: [Any] = [
            ["id": 1, "name": "U1", "tags_ids": [1, 2]],
            ["id": 2, "name": "U2", "tags_ids": [2, 3]]
        ]
        try await SwiftSync.sync(payload: payloadA, as: UserTagsByIDs.self, in: context)

        let payloadB: [Any] = [
            ["id": 1, "name": "U1", "tags_ids": [2, 4]],
            ["id": 2, "name": "U2", "tags_ids": [3]]
        ]
        try await SwiftSync.sync(payload: payloadB, as: UserTagsByIDs.self, in: context)

        let users = try context.fetch(FetchDescriptor<UserTagsByIDs>())
        return Dictionary(uniqueKeysWithValues: users.map { ($0.id, Set($0.tags.map(\.id))) })
    }

    @MainActor
    func testConcurrentSyncSameContextCausesRaceOrConflict() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ConcurrentRaceUser.self, configurations: configuration)
        let context = ModelContext(container)
        context.insert(ConcurrentRaceUser(id: 1, fullName: "Seed"))
        try context.save()

        await ConcurrentRaceHooks.shared.installFirstSyncBlocker()
        defer {
            Task {
                await ConcurrentRaceHooks.shared.installFirstSyncBlocker()
                await ConcurrentRaceHooks.shared.releaseFirstSync()
            }
        }

        let firstTask = Task { @MainActor in
            let payload: [Any] = [
                ["id": 1, "full_name": "Refresh User"],
                ["id": 99, "full_name": "Refresh Insert"]
            ]
            try await SwiftSync.sync(payload: payload, as: ConcurrentRaceUser.self, in: context)
        }
        await ConcurrentRaceHooks.shared.waitUntilFirstSyncBlocked()

        let secondTask = Task { @MainActor in
            let payload: [Any] = [
                ["id": 1, "full_name": "Websocket User"],
                ["id": 99, "full_name": "Websocket Winner"]
            ]
            try await SwiftSync.sync(payload: payload, as: ConcurrentRaceUser.self, in: context)
        }

        await ConcurrentRaceHooks.shared.releaseFirstSync()

        try await firstTask.value
        try await secondTask.value

        let rows = try context.fetch(FetchDescriptor<ConcurrentRaceUser>())
        XCTAssertEqual(Set(rows.map(\.id)), Set([1, 99]))
        XCTAssertEqual(rows.first(where: { $0.id == 99 })?.fullName, "Websocket Winner")
    }

    @MainActor
    func testConcurrentSyncDifferentContextsSameStoreUniqueConstraintConflict() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DifferentContextConflictUser.self, configurations: configuration)
        let foregroundContext = ModelContext(container)
        let backgroundContext = ModelContext(container)
        let readerContext = ModelContext(container)

        let foregroundTask = Task { @MainActor in
            try await SwiftSync.sync(
                payload: [["id": 500, "full_name": "Foreground Winner"]],
                as: DifferentContextConflictUser.self,
                in: foregroundContext
            )
        }

        await Task.yield()
        let backgroundTask = Task { @MainActor in
            try await SwiftSync.sync(
                payload: [["id": 500, "full_name": "Background Winner"]],
                as: DifferentContextConflictUser.self,
                in: backgroundContext
            )
        }

        try await foregroundTask.value
        try await backgroundTask.value

        let rows = try readerContext.fetch(FetchDescriptor<DifferentContextConflictUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 500)
        XCTAssertEqual(rows.first?.fullName, "Background Winner")
    }

    @MainActor
    func testResetEraseDuringInFlightSync() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ConcurrentRaceUser.self, configurations: configuration)
        let syncContext = ModelContext(container)
        let resetContext = ModelContext(container)
        let readerContext = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "full_name": "Seed User"]],
            as: ConcurrentRaceUser.self,
            in: syncContext
        )

        await ConcurrentRaceHooks.shared.installFirstSyncBlocker()
        defer { Task { await ConcurrentRaceHooks.shared.releaseFirstSync() } }

        let syncTask = Task { @MainActor in
            try await SwiftSync.sync(
                payload: [
                    ["id": 1, "full_name": "Post Reset User"],
                    ["id": 2, "full_name": "Inserted During Sync"]
                ],
                as: ConcurrentRaceUser.self,
                in: syncContext
            )
        }

        await ConcurrentRaceHooks.shared.waitUntilFirstSyncBlocked()

        let existing = try resetContext.fetch(FetchDescriptor<ConcurrentRaceUser>())
        for row in existing {
            resetContext.delete(row)
        }
        try resetContext.save()

        await ConcurrentRaceHooks.shared.releaseFirstSync()
        try await syncTask.value

        let rows = try readerContext.fetch(FetchDescriptor<ConcurrentRaceUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertNil(rows.first(where: { $0.id == 1 }))
        XCTAssertEqual(rows.first(where: { $0.id == 2 })?.fullName, "Inserted During Sync")
    }

    @MainActor
    func testBackgroundWriteNotVisibleToMainReadWithoutRefreshPolicy() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let mainContext = ModelContext(container)
        let backgroundContext = ModelContext(container)
        let readerContext = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "full_name": "Initial Name"]],
            as: User.self,
            in: mainContext
        )

        let firstMainRead = try mainContext.fetch(FetchDescriptor<User>())
        XCTAssertEqual(firstMainRead.count, 1)
        XCTAssertEqual(firstMainRead.first?.fullName, "Initial Name")
        let retainedMainRow = try XCTUnwrap(firstMainRead.first)

        try await SwiftSync.sync(
            payload: [["id": 1, "full_name": "Background Updated"]],
            as: User.self,
            in: backgroundContext
        )

        XCTAssertEqual(retainedMainRow.fullName, "Initial Name")

        let secondMainRead = try mainContext.fetch(FetchDescriptor<User>())
        let freshRead = try readerContext.fetch(FetchDescriptor<User>())

        XCTAssertEqual(freshRead.first?.fullName, "Background Updated")
        XCTAssertEqual(secondMainRead.first?.fullName, "Background Updated")
    }

    func testSyncContainerInitializesLikeModelContainerAndSyncs() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try await MainActor.run {
            try SyncContainer(for: User.self, configurations: configuration)
        }
        let writerContext = syncContainer.makeBackgroundContext()

        try await SwiftSync.sync(
            payload: [["id": 10, "full_name": "From SyncContainer"]],
            as: User.self,
            in: writerContext
        )

        let rows = try syncContainer.mainContext.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 10)
        XCTAssertEqual(rows.first?.fullName, "From SyncContainer")
    }

    func testSyncContainerBackgroundSaveVisibilityBehavior() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try await MainActor.run {
            try SyncContainer(for: User.self, configurations: configuration)
        }
        let mainContext = syncContainer.mainContext
        let backgroundContext = syncContainer.makeBackgroundContext()

        try await SwiftSync.sync(
            payload: [["id": 11, "full_name": "Main Seed"]],
            as: User.self,
            in: backgroundContext
        )

        let firstMainRead = try mainContext.fetch(FetchDescriptor<User>())
        let retainedMainRow = try XCTUnwrap(firstMainRead.first)
        XCTAssertEqual(retainedMainRow.fullName, "Main Seed")

        try await SwiftSync.sync(
            payload: [["id": 11, "full_name": "Background Write"]],
            as: User.self,
            in: backgroundContext
        )

        XCTAssertEqual(retainedMainRow.fullName, "Main Seed")

        let secondMainRead = try mainContext.fetch(FetchDescriptor<User>())
        XCTAssertEqual(secondMainRead.first?.fullName, "Background Write")
    }

    @MainActor
    func testSyncCancellationDuringExecutionRollsBackUnsavedChanges() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ConcurrentRaceUser.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "full_name": "Seed User"]],
            as: ConcurrentRaceUser.self,
            in: context
        )

        await ConcurrentRaceHooks.shared.installFirstSyncBlocker()
        defer { Task { await ConcurrentRaceHooks.shared.releaseFirstSync() } }

        let syncTask = Task { @MainActor in
            try await SwiftSync.sync(
                payload: [
                    ["id": 1, "full_name": "Updated User"],
                    ["id": 2, "full_name": "Should Rollback"]
                ],
                as: ConcurrentRaceUser.self,
                in: context
            )
        }

        await ConcurrentRaceHooks.shared.waitUntilFirstSyncBlocked()
        syncTask.cancel()
        await ConcurrentRaceHooks.shared.releaseFirstSync()

        do {
            try await syncTask.value
            XCTFail("Expected cancellation to stop sync.")
        } catch {
            XCTAssertEqual(error as? SyncError, .cancelled)
        }

        let rows = try context.fetch(FetchDescriptor<ConcurrentRaceUser>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.id, 1)
        XCTAssertEqual(rows.first?.fullName, "Seed User")
    }

    @MainActor
    func testSyncCancellationBeforeExecutionExitsWithoutWrites() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)
        let gate = CancellationGate()

        let task = Task { @MainActor in
            await gate.wait()
            try await SwiftSync.sync(
                payload: [["id": 1, "full_name": "Cancelled Before Sync"]],
                as: User.self,
                in: context
            )
        }
        task.cancel()
        await gate.release()

        do {
            try await task.value
            XCTFail("Expected cancellation before execution to skip writes.")
        } catch {
            XCTAssertEqual(error as? SyncError, .cancelled)
        }

        let rows = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 0)
    }

    @MainActor
    func testSyncMissingRowPolicyKeepPreservesExistingRows() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "full_name": "One"],
                ["id": 2, "full_name": "Two"]
            ],
            as: User.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "full_name": "One Updated"]
            ],
            as: User.self,
            in: context,
            missingRowPolicy: .keep
        )

        let rows = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first(where: { $0.id == 1 })?.fullName, "One Updated")
        XCTAssertEqual(rows.first(where: { $0.id == 2 })?.fullName, "Two")
    }

    @MainActor
    func testParentScopedSyncMissingRowPolicyKeepPreservesExistingRows() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SuperUser.self, SuperNote.self, configurations: configuration)
        let context = ModelContext(container)
        let parent = SuperUser(id: 10, name: "Parent")
        context.insert(parent)
        try context.save()

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "First"],
                ["id": 2, "text": "Second"]
            ],
            as: SuperNote.self,
            in: context,
            parent: parent
        )

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "First Updated"]
            ],
            as: SuperNote.self,
            in: context,
            parent: parent,
            missingRowPolicy: .keep
        )

        let notes = try context.fetch(FetchDescriptor<SuperNote>())
            .filter { $0.superUser?.persistentModelID == parent.persistentModelID }
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first(where: { $0.id == 1 })?.text, "First Updated")
        XCTAssertEqual(notes.first(where: { $0.id == 2 })?.text, "Second")
    }

    @MainActor
    func testParentScopedSyncScopedIdentityAllowsDuplicateIDsAcrossParents() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ScopedBucket.self, ScopedItem.self, configurations: configuration)
        let context = ModelContext(container)

        let parentA = ScopedBucket(id: 1, name: "A")
        let parentB = ScopedBucket(id: 2, name: "B")
        context.insert(parentA)
        context.insert(parentB)
        try context.save()

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "A-10"]],
            as: ScopedItem.self,
            in: context,
            parent: parentA
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "B-10"]],
            as: ScopedItem.self,
            in: context,
            parent: parentB
        )

        let all = try context.fetch(FetchDescriptor<ScopedItem>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.filter { $0.id == 10 && $0.bucket?.id == 1 }.first?.text, "A-10")
        XCTAssertEqual(all.filter { $0.id == 10 && $0.bucket?.id == 2 }.first?.text, "B-10")
    }

    @MainActor
    func testParentScopedSyncGlobalIdentityMovesRowAcrossParents() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: GlobalBucket.self, GlobalItem.self, configurations: configuration)
        let context = ModelContext(container)

        let parentA = GlobalBucket(id: 1, name: "A")
        let parentB = GlobalBucket(id: 2, name: "B")
        context.insert(parentA)
        context.insert(parentB)
        try context.save()

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "A-10"]],
            as: GlobalItem.self,
            in: context,
            parent: parentA
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "B-10"]],
            as: GlobalItem.self,
            in: context,
            parent: parentB
        )

        let all = try context.fetch(FetchDescriptor<GlobalItem>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.id, 10)
        XCTAssertEqual(all.first?.text, "B-10")
        XCTAssertEqual(all.first?.bucket?.id, 2)
    }

    @MainActor
    func testParentScopedDeleteAffectsOnlyCurrentParentScopeWhenScoped() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: ScopedBucket.self, ScopedItem.self, configurations: configuration)
        let context = ModelContext(container)

        let parentA = ScopedBucket(id: 1, name: "A")
        let parentB = ScopedBucket(id: 2, name: "B")
        context.insert(parentA)
        context.insert(parentB)
        try context.save()

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "A-1"],
                ["id": 2, "text": "A-2"]
            ],
            as: ScopedItem.self,
            in: context,
            parent: parentA
        )

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "B-1"],
                ["id": 3, "text": "B-3"]
            ],
            as: ScopedItem.self,
            in: context,
            parent: parentB
        )

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "A-1 updated"]
            ],
            as: ScopedItem.self,
            in: context,
            parent: parentA
        )

        let rows = try context.fetch(FetchDescriptor<ScopedItem>())
        XCTAssertEqual(Set(rows.filter { $0.bucket?.id == 1 }.map(\.id)), Set([1]))
        XCTAssertEqual(rows.first(where: { $0.bucket?.id == 1 && $0.id == 1 })?.text, "A-1 updated")
        XCTAssertEqual(Set(rows.filter { $0.bucket?.id == 2 }.map(\.id)), Set([1, 3]))
    }

    @MainActor
    func testRelationshipOperationsSkipRelationshipUpdatesWhenUpdateFlagMissing() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: OpsCompany.self, OpsEmployee.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "Acme"]],
            as: OpsCompany.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": 10]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.insert]
        )

        var rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": NSNull()]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.insert]
        )

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": NSNull()]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.update]
        )

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertNil(rows.first?.company)
    }

    @MainActor
    func testStrictForeignKeyTypingDoesNotCoerceRelationshipIDs() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: OpsCompany.self, OpsEmployee.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 10, "name": "Acme"]],
            as: OpsCompany.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava"]],
            as: OpsEmployee.self,
            in: context
        )

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": "10"]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.update]
        )

        var rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertNil(rows.first?.company)

        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": 10]],
            as: OpsEmployee.self,
            in: context,
            relationshipOperations: [.update]
        )

        rows = try context.fetch(FetchDescriptor<OpsEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)
    }

}
