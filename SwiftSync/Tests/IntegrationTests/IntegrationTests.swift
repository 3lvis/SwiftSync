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

@Model
final class AutoTag {
    @Attribute(.unique) var id: Int
    var name: String
    var tasks: [AutoTask]

    init(id: Int, name: String, tasks: [AutoTask] = []) {
        self.id = id
        self.name = name
        self.tasks = tasks
    }
}

@Syncable
@Model
final class AutoTask {
    @Attribute(.unique) var id: Int
    var title: String

    @RemoteKey("tag_ids")
    @Relationship(inverse: \AutoTag.tasks)
    var tags: [AutoTag]

    init(id: Int, title: String, tags: [AutoTag] = []) {
        self.id = id
        self.title = title
        self.tags = tags
    }
}

@Model
final class AutoNestedMember {
    @Attribute(.unique) var id: Int
    var fullName: String
    var ownedTeams: [AutoNestedTeam]
    var memberTeams: [AutoNestedTeam]

    init(
        id: Int,
        fullName: String,
        ownedTeams: [AutoNestedTeam] = [],
        memberTeams: [AutoNestedTeam] = []
    ) {
        self.id = id
        self.fullName = fullName
        self.ownedTeams = ownedTeams
        self.memberTeams = memberTeams
    }
}

@Syncable
@Model
final class AutoNestedTeam {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \AutoNestedMember.ownedTeams)
    var owner: AutoNestedMember?
    @Relationship(inverse: \AutoNestedMember.memberTeams)
    var members: [AutoNestedMember]

    init(id: Int, name: String, owner: AutoNestedMember? = nil, members: [AutoNestedMember] = []) {
        self.id = id
        self.name = name
        self.owner = owner
        self.members = members
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

extension AutoTag: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<AutoTag, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> AutoTag {
        AutoTag(
            id: try payload.required(Int.self, for: "id"),
            name: try payload.required(String.self, for: "name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        let incomingName: String = try payload.required(String.self, for: "name")
        guard name != incomingName else { return false }
        name = incomingName
        return true
    }
}

extension AutoNestedMember: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<AutoNestedMember, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> AutoNestedMember {
        AutoNestedMember(
            id: try payload.required(Int.self, for: "id"),
            fullName: try payload.required(String.self, for: "full_name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        let incomingFullName: String = try payload.required(String.self, for: "full_name")
        guard fullName != incomingFullName else { return false }
        fullName = incomingFullName
        return true
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

extension Team {
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

extension Employee {
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

extension UserWithNotes {
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

extension UserTagsByObjects {
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

extension UserTagsByIDs {
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
final class NoteFolder {
    @Attribute(.unique) var id: Int
    var name: String

    init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

@Model
final class UniqueIDNote {
    @Attribute(.unique) var id: Int
    var text: String
    var folder: NoteFolder?

    init(id: Int, text: String, folder: NoteFolder? = nil) {
        self.id = id
        self.text = text
        self.folder = folder
    }
}

extension UniqueIDNote: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<UniqueIDNote, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> UniqueIDNote {
        UniqueIDNote(
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

extension UniqueIDNote: ParentScopedModel {
    typealias SyncParent = NoteFolder
    static var parentRelationship: ReferenceWritableKeyPath<UniqueIDNote, NoteFolder?> { \.folder }
}

@Model
final class UniqueEmailNote {
    var id: Int
    @Attribute(.unique) var email: String
    var text: String
    var folder: NoteFolder?

    init(id: Int, email: String, text: String, folder: NoteFolder? = nil) {
        self.id = id
        self.email = email
        self.text = text
        self.folder = folder
    }
}

extension UniqueEmailNote: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<UniqueEmailNote, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> UniqueEmailNote {
        UniqueEmailNote(
            id: try payload.required(Int.self, for: "id"),
            email: try payload.required(String.self, for: "email"),
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

extension UniqueEmailNote: ParentScopedModel {
    typealias SyncParent = NoteFolder
    static var parentRelationship: ReferenceWritableKeyPath<UniqueEmailNote, NoteFolder?> { \.folder }
}

// InferredNote: non-unique id, NOT ParentScopedModel – uses the inferred sync overload.
// Without @Attribute(.unique) on id, the new behavior should be scoped (two parents → two rows).
@Model
final class InferredNote {
    var id: Int
    var text: String
    var folder: NoteFolder?

    init(id: Int, text: String, folder: NoteFolder? = nil) {
        self.id = id
        self.text = text
        self.folder = folder
    }
}

extension InferredNote: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<InferredNote, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> InferredNote {
        InferredNote(
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

@Syncable
@Model
final class KeyStyleRecord {
    @Attribute(.unique) var id: Int
    var projectID: String

    init(id: Int, projectID: String) {
        self.id = id
        self.projectID = projectID
    }
}

@Syncable
@Model
final class RemotePathContactRecord {
    @Attribute(.unique) var id: Int
    @RemotePath("profile.contact.email") var email: String?

    init(id: Int, email: String?) {
        self.id = id
        self.email = email
    }
}

@Syncable
@Model
final class RemotePathCamelRecord {
    @Attribute(.unique) var id: Int
    @RemotePath("profile.contact_email") var contactEmail: String?

    init(id: Int, contactEmail: String?) {
        self.id = id
        self.contactEmail = contactEmail
    }
}

@Syncable
@Model
final class RemotePathOwner {
    @Attribute(.unique) var id: Int
    var fullName: String

    init(id: Int, fullName: String) {
        self.id = id
        self.fullName = fullName
    }
}

@Syncable
@Model
final class RemotePathIssue {
    @Attribute(.unique) var id: Int
    var title: String
    @RemotePath("relationships.owner") var owner: RemotePathOwner?

    init(id: Int, title: String, owner: RemotePathOwner? = nil) {
        self.id = id
        self.title = title
        self.owner = owner
    }
}

@Syncable
@Model
final class InferredTask {
    @Attribute(.unique) var id: Int
    var title: String
    @Relationship(inverse: \InferredComment.task)
    var comments: [InferredComment]

    init(id: Int, title: String, comments: [InferredComment] = []) {
        self.id = id
        self.title = title
        self.comments = comments
    }
}

@Syncable
@Model
final class InferredComment {
    @Attribute(.unique) var id: Int
    var text: String
    var task: InferredTask?

    init(id: Int, text: String, task: InferredTask? = nil) {
        self.id = id
        self.text = text
        self.task = task
    }
}

@Syncable
@Model
final class InferredOrphanRecord {
    @Attribute(.unique) var id: Int
    var text: String

    init(id: Int, text: String) {
        self.id = id
        self.text = text
    }
}

@Syncable
@Model
final class RoleUser {
    @Attribute(.unique) var id: Int
    var name: String
    @Relationship(inverse: \RoleTicket.assignee)
    var assignedTickets: [RoleTicket]
    @Relationship(inverse: \RoleTicket.reviewer)
    var reviewTickets: [RoleTicket]

    init(
        id: Int,
        name: String,
        assignedTickets: [RoleTicket] = [],
        reviewTickets: [RoleTicket] = []
    ) {
        self.id = id
        self.name = name
        self.assignedTickets = assignedTickets
        self.reviewTickets = reviewTickets
    }
}

@Syncable
@Model
final class RoleTicket {
    @Attribute(.unique) var id: Int
    var title: String
    var assignee: RoleUser?
    var reviewer: RoleUser?

    init(id: Int, title: String, assignee: RoleUser? = nil, reviewer: RoleUser? = nil) {
        self.id = id
        self.title = title
        self.assignee = assignee
        self.reviewer = reviewer
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

extension ConcurrentRaceUser: SyncUpdatableModel {
    typealias SyncID = Int
    static var syncIdentity: KeyPath<ConcurrentRaceUser, Int> { \.id }

    static func make(from payload: SyncPayload) throws -> ConcurrentRaceUser {
        ConcurrentRaceUser(
            id: try payload.required(Int.self, for: "id"),
            fullName: try payload.required(String.self, for: "full_name")
        )
    }

    func apply(_ payload: SyncPayload) throws -> Bool {
        var changed = false
        if payload.contains("full_name") {
            let incoming: String = try payload.required(String.self, for: "full_name")
            if fullName != incoming {
                fullName = incoming
                changed = true
            }
        }
        return changed
    }

    func applyRelationships(_: SyncPayload, in _: ModelContext) async throws -> Bool {
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
    func testSyncableGeneratedNestedRelationshipsUpsertAndReplaceMembership() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AutoNestedTeam.self, AutoNestedMember.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [[
                "id": 10,
                "name": "Team",
                "owner": ["id": 1, "full_name": "Owner"],
                "members": [
                    ["id": 1, "full_name": "Owner"],
                    ["id": 2, "full_name": "Member Two"]
                ]
            ]],
            as: AutoNestedTeam.self,
            in: context
        )

        var teams = try context.fetch(FetchDescriptor<AutoNestedTeam>())
        XCTAssertEqual(teams.count, 1)
        XCTAssertEqual(teams[0].owner?.id, 1)
        XCTAssertEqual(Set(teams[0].members.map(\.id)), Set([1, 2]))

        try await SwiftSync.sync(
            payload: [[
                "id": 10,
                "name": "Team v2",
                "owner": ["id": 2, "full_name": "Member Two Updated"],
                "members": [
                    ["id": 2, "full_name": "Member Two Updated"],
                    ["id": 3, "full_name": "Member Three"]
                ]
            ]],
            as: AutoNestedTeam.self,
            in: context
        )

        teams = try context.fetch(FetchDescriptor<AutoNestedTeam>())
        XCTAssertEqual(teams[0].name, "Team v2")
        XCTAssertEqual(teams[0].owner?.id, 2)
        XCTAssertEqual(Set(teams[0].members.map(\.id)), Set([2, 3]))

        let allMembers = try context.fetch(FetchDescriptor<AutoNestedMember>())
        XCTAssertEqual(allMembers.first(where: { $0.id == 2 })?.fullName, "Member Two Updated")

        try await SwiftSync.sync(
            payload: [[
                "id": 10,
                "name": "Team v2",
                "owner": NSNull(),
                "members": NSNull()
            ]],
            as: AutoNestedTeam.self,
            in: context
        )

        teams = try context.fetch(FetchDescriptor<AutoNestedTeam>())
        XCTAssertNil(teams[0].owner)
        XCTAssertEqual(teams[0].members.count, 0)
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
    func testParentSyncInfersSingleRelationshipWithoutParentScopedModelConformance() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: InferredTask.self, InferredComment.self, configurations: configuration)
        let context = ModelContext(container)

        let taskA = InferredTask(id: 1, title: "A")
        let taskB = InferredTask(id: 2, title: "B")
        context.insert(taskA)
        context.insert(taskB)
        try context.save()

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "A-1"],
                ["id": 2, "text": "A-2"]
            ],
            as: InferredComment.self,
            in: context,
            parent: taskA
        )
        try await SwiftSync.sync(
            payload: [
                ["id": 3, "text": "B-3"]
            ],
            as: InferredComment.self,
            in: context,
            parent: taskB
        )

        try await SwiftSync.sync(
            payload: [
                ["id": 1, "text": "A-1 Updated"]
            ],
            as: InferredComment.self,
            in: context,
            parent: taskA
        )

        let rows = try context.fetch(FetchDescriptor<InferredComment>())
        XCTAssertEqual(Set(rows.filter { $0.task?.id == 1 }.map(\.id)), Set([1]))
        XCTAssertEqual(rows.first(where: { $0.id == 1 })?.text, "A-1 Updated")
        XCTAssertEqual(Set(rows.filter { $0.task?.id == 2 }.map(\.id)), Set([3]))
    }

    @MainActor
    func testParentSyncInferenceThrowsWhenNoRelationshipCandidateExists() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: InferredTask.self, InferredOrphanRecord.self, configurations: configuration)
        let context = ModelContext(container)

        let task = InferredTask(id: 1, title: "A")
        context.insert(task)
        try context.save()

        var capturedError: Error?
        do {
            try await SwiftSync.sync(
                payload: [["id": 1, "text": "orphan"]],
                as: InferredOrphanRecord.self,
                in: context,
                parent: task
            )
        } catch {
            capturedError = error
        }

        guard let syncError = capturedError as? SyncError else {
            XCTFail("Expected SyncError, got: \(String(describing: capturedError))")
            return
        }
        guard case .invalidPayload(_, let reason) = syncError else {
            XCTFail("Expected invalidPayload, got: \(syncError)")
            return
        }
        XCTAssertTrue(reason.contains("Found 0 candidate to-one relationships"), "Unexpected reason: \(reason)")
        XCTAssertTrue(reason.contains("ParentScopedModel.parentRelationship"), "Unexpected reason: \(reason)")
    }

    @MainActor
    func testParentSyncInferenceThrowsWhenRelationshipCandidatesAreAmbiguous() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RoleUser.self, RoleTicket.self, configurations: configuration)
        let context = ModelContext(container)

        let user = RoleUser(id: 1, name: "U1")
        context.insert(user)
        try context.save()

        var capturedError: Error?
        do {
            try await SwiftSync.sync(
                payload: [["id": 10, "title": "T-10"]],
                as: RoleTicket.self,
                in: context,
                parent: user
            )
        } catch {
            capturedError = error
        }

        guard let syncError = capturedError as? SyncError else {
            XCTFail("Expected SyncError, got: \(String(describing: capturedError))")
            return
        }
        guard case .invalidPayload(_, let reason) = syncError else {
            XCTFail("Expected invalidPayload, got: \(syncError)")
            return
        }
        XCTAssertTrue(reason.contains("Ambiguous parent relationship"), "Unexpected reason: \(reason)")
        XCTAssertTrue(reason.contains("assignee"), "Unexpected reason: \(reason)")
        XCTAssertTrue(reason.contains("reviewer"), "Unexpected reason: \(reason)")
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

    @MainActor
    func testSyncContainerDefaultInputKeyStyleSnakeCaseMapsAcronymPropertyName() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(for: KeyStyleRecord.self, configurations: configuration)

        try await syncContainer.sync(
            payload: [["id": 1, "project_id": "P-1"]],
            as: KeyStyleRecord.self
        )

        let rows = try syncContainer.mainContext.fetch(FetchDescriptor<KeyStyleRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.projectID, "P-1")
    }

    @MainActor
    func testSyncContainerCamelCaseInputKeyStyleMapsCamelPayload() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(
            for: KeyStyleRecord.self,
            inputKeyStyle: .camelCase,
            configurations: configuration
        )

        try await syncContainer.sync(
            payload: [["id": 1, "projectId": "P-2"]],
            as: KeyStyleRecord.self
        )

        let rows = try syncContainer.mainContext.fetch(FetchDescriptor<KeyStyleRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.projectID, "P-2")
    }

    @MainActor
    func testSyncContainerCamelCaseInputKeyStyleMapsCamelToOneForeignKey() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(
            for: AutoEmployee.self,
            AutoCompany.self,
            inputKeyStyle: .camelCase,
            configurations: configuration
        )

        try await syncContainer.sync(
            payload: [["id": 10, "name": "Acme"]],
            as: AutoCompany.self
        )

        try await syncContainer.sync(
            payload: [["id": 1, "name": "Ava", "companyId": 10]],
            as: AutoEmployee.self
        )

        var employees = try syncContainer.mainContext.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertEqual(employees.count, 1)
        XCTAssertEqual(employees[0].company?.id, 10)

        try await syncContainer.sync(
            payload: [["id": 1, "name": "Ava", "companyId": NSNull()]],
            as: AutoEmployee.self
        )

        employees = try syncContainer.mainContext.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertNil(employees[0].company)
    }

    @MainActor
    func testSyncContainerCamelCaseInputKeyStyleMapsCamelToManyForeignKeys() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(
            for: AutoTask.self,
            AutoTag.self,
            inputKeyStyle: .camelCase,
            configurations: configuration
        )

        try await syncContainer.sync(
            payload: [
                ["id": 1, "name": "Urgent"],
                ["id": 2, "name": "Client"]
            ],
            as: AutoTag.self
        )

        try await syncContainer.sync(
            payload: [["id": 100, "title": "Launch", "tagIds": [1, 2]]],
            as: AutoTask.self
        )

        var tasks = try syncContainer.mainContext.fetch(FetchDescriptor<AutoTask>())
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(Set(tasks[0].tags.map(\.id)), Set([1, 2]))

        try await syncContainer.sync(
            payload: [["id": 100, "title": "Launch", "tagIds": [2]]],
            as: AutoTask.self
        )

        tasks = try syncContainer.mainContext.fetch(FetchDescriptor<AutoTask>())
        XCTAssertEqual(Set(tasks[0].tags.map(\.id)), Set([2]))
    }

    @MainActor
    func testSyncRemotePathScalarImportsDeepValueWithMissingAndNullSemantics() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(for: RemotePathContactRecord.self, configurations: configuration)

        try await syncContainer.sync(
            payload: [[
                "id": 1,
                "profile": [
                    "contact": [
                        "email": "first@example.com"
                    ]
                ]
            ]],
            as: RemotePathContactRecord.self
        )

        var rows = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathContactRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].email, "first@example.com")

        try await syncContainer.sync(
            payload: [["id": 1]],
            as: RemotePathContactRecord.self
        )

        rows = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathContactRecord>())
        XCTAssertEqual(rows[0].email, "first@example.com")

        try await syncContainer.sync(
            payload: [[
                "id": 1,
                "profile": [
                    "contact": [
                        "email": NSNull()
                    ]
                ]
            ]],
            as: RemotePathContactRecord.self
        )

        rows = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathContactRecord>())
        XCTAssertNil(rows[0].email)
    }

    @MainActor
    func testSyncRemotePathScalarRespectsContainerCamelCaseMode() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(
            for: RemotePathCamelRecord.self,
            inputKeyStyle: .camelCase,
            configurations: configuration
        )

        try await syncContainer.sync(
            payload: [[
                "id": 1,
                "profile": [
                    "contactEmail": "camel@example.com"
                ]
            ]],
            as: RemotePathCamelRecord.self
        )

        let rows = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathCamelRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].contactEmail, "camel@example.com")
    }

    @MainActor
    func testSyncRemotePathToOneNestedRelationshipImportsAndClearsFromDeepPath() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(
            for: RemotePathIssue.self,
            RemotePathOwner.self,
            configurations: configuration
        )

        try await syncContainer.sync(
            payload: [[
                "id": 1,
                "title": "Issue 1",
                "relationships": [
                    "owner": [
                        "id": 10,
                        "full_name": "Alice"
                    ]
                ]
            ]],
            as: RemotePathIssue.self
        )

        var issues = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathIssue>())
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].owner?.id, 10)
        XCTAssertEqual(issues[0].owner?.fullName, "Alice")

        try await syncContainer.sync(
            payload: [["id": 1, "title": "Issue 1 updated"]],
            as: RemotePathIssue.self
        )

        issues = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathIssue>())
        XCTAssertEqual(issues[0].owner?.id, 10)

        try await syncContainer.sync(
            payload: [[
                "id": 1,
                "title": "Issue 1 updated",
                "relationships": [
                    "owner": NSNull()
                ]
            ]],
            as: RemotePathIssue.self
        )

        issues = try syncContainer.mainContext.fetch(FetchDescriptor<RemotePathIssue>())
        XCTAssertNil(issues[0].owner)
    }

    func testSyncableMakeUsesRemotePathForScalarProperty() throws {
        let payload = SyncPayload(
            values: [
                "id": 1,
                "profile": [
                    "contact": [
                        "email": "from-make@example.com"
                    ]
                ]
            ]
        )

        let row = try RemotePathContactRecord.make(from: payload)
        XCTAssertEqual(row.email, "from-make@example.com")
    }

    @MainActor
    func testSyncRemotePathScalarWithDirectContext() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RemotePathContactRecord.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [[
                "id": 1,
                "profile": [
                    "contact": [
                        "email": "direct@example.com"
                    ]
                ]
            ]],
            as: RemotePathContactRecord.self,
            in: context
        )

        let rows = try context.fetch(FetchDescriptor<RemotePathContactRecord>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].email, "direct@example.com")
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
    func testSyncContainerInfersSingleParentRelationship() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let syncContainer = try SyncContainer(for: InferredTask.self, InferredComment.self, configurations: configuration)

        let taskA = InferredTask(id: 1, title: "A")
        let taskB = InferredTask(id: 2, title: "B")
        syncContainer.mainContext.insert(taskA)
        syncContainer.mainContext.insert(taskB)
        try syncContainer.mainContext.save()

        try await syncContainer.sync(
            payload: [
                ["id": 1, "text": "A-1"],
                ["id": 2, "text": "A-2"]
            ],
            as: InferredComment.self,
            parent: taskA
        )
        try await syncContainer.sync(
            payload: [
                ["id": 3, "text": "B-3"]
            ],
            as: InferredComment.self,
            parent: taskB
        )
        try await syncContainer.sync(
            payload: [
                ["id": 1, "text": "A-1 Updated"]
            ],
            as: InferredComment.self,
            parent: taskA
        )

        let rows = try syncContainer.mainContext.fetch(FetchDescriptor<InferredComment>())
        XCTAssertEqual(Set(rows.filter { $0.task?.id == 1 }.map(\.id)), Set([1]))
        XCTAssertEqual(Set(rows.filter { $0.task?.id == 2 }.map(\.id)), Set([3]))
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
    func testSyncItemUpdatesExistingRowWithoutDeletingOthers() async throws {
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
            item: ["id": 1, "full_name": "One Updated"],
            as: User.self,
            in: context
        )

        let rows = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.first(where: { $0.id == 1 })?.fullName, "One Updated")
        XCTAssertEqual(rows.first(where: { $0.id == 2 })?.fullName, "Two")
    }

    @MainActor
    func testSyncItemInsertsNewRowWhenNotFound() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: User.self, configurations: configuration)
        let context = ModelContext(container)

        try await SwiftSync.sync(
            payload: [["id": 1, "full_name": "One"]],
            as: User.self,
            in: context
        )

        try await SwiftSync.sync(
            item: ["id": 2, "full_name": "Two"],
            as: User.self,
            in: context
        )

        let rows = try context.fetch(FetchDescriptor<User>())
        XCTAssertEqual(rows.count, 2)
        XCTAssertNotNil(rows.first(where: { $0.id == 1 }))
        XCTAssertNotNil(rows.first(where: { $0.id == 2 }))
    }

    @MainActor
    func testSyncItemWithParentUpdatesExistingRowWithoutDeletingOthers() async throws {
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
            item: ["id": 1, "text": "First Updated"],
            as: SuperNote.self,
            in: context,
            parent: parent
        )

        let notes = try context.fetch(FetchDescriptor<SuperNote>())
            .filter { $0.superUser?.persistentModelID == parent.persistentModelID }
        XCTAssertEqual(notes.count, 2)
        XCTAssertEqual(notes.first(where: { $0.id == 1 })?.text, "First Updated")
        XCTAssertEqual(notes.first(where: { $0.id == 2 })?.text, "Second")
    }

    @MainActor
    func testSyncItemWithParentInsertsNewRowWhenNotFound() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SuperUser.self, SuperNote.self, configurations: configuration)
        let context = ModelContext(container)
        let parent = SuperUser(id: 10, name: "Parent")
        context.insert(parent)
        try context.save()

        try await SwiftSync.sync(
            payload: [["id": 1, "text": "First"]],
            as: SuperNote.self,
            in: context,
            parent: parent
        )

        try await SwiftSync.sync(
            item: ["id": 2, "text": "Second"],
            as: SuperNote.self,
            in: context,
            parent: parent
        )

        let notes = try context.fetch(FetchDescriptor<SuperNote>())
            .filter { $0.superUser?.persistentModelID == parent.persistentModelID }
        XCTAssertEqual(notes.count, 2)
        XCTAssertNotNil(notes.first(where: { $0.id == 1 }))
        XCTAssertNotNil(notes.first(where: { $0.id == 2 }))
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
    func testUniqueAttributeOnSyncIdentityImpliesGlobalPolicy() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NoteFolder.self, UniqueIDNote.self, configurations: configuration)
        let context = ModelContext(container)

        let folderA = NoteFolder(id: 1, name: "A")
        let folderB = NoteFolder(id: 2, name: "B")
        context.insert(folderA)
        context.insert(folderB)
        try context.save()

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "original"]],
            as: UniqueIDNote.self,
            in: context,
            parent: folderA
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "moved"]],
            as: UniqueIDNote.self,
            in: context,
            parent: folderB
        )

        let all = try context.fetch(FetchDescriptor<UniqueIDNote>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.text, "moved")
        XCTAssertEqual(all.first?.folder?.id, 2)
    }

    @MainActor
    func testInferredParentSyncWithoutUniqueAttributeUsesScopedPolicy() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NoteFolder.self, InferredNote.self, configurations: configuration)
        let context = ModelContext(container)

        let folderA = NoteFolder(id: 1, name: "A")
        let folderB = NoteFolder(id: 2, name: "B")
        context.insert(folderA)
        context.insert(folderB)
        try context.save()

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "A-note"]],
            as: InferredNote.self,
            in: context,
            parent: folderA
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "text": "B-note"]],
            as: InferredNote.self,
            in: context,
            parent: folderB
        )

        let all = try context.fetch(FetchDescriptor<InferredNote>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.folder?.id == 1 })?.text, "A-note")
        XCTAssertEqual(all.first(where: { $0.folder?.id == 2 })?.text, "B-note")
    }

    @MainActor
    func testUniqueAttributeOnNonIdentityFieldDoesNotImplyGlobalPolicy() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: NoteFolder.self, UniqueEmailNote.self, configurations: configuration)
        let context = ModelContext(container)

        let folderA = NoteFolder(id: 1, name: "A")
        let folderB = NoteFolder(id: 2, name: "B")
        context.insert(folderA)
        context.insert(folderB)
        try context.save()

        try await SwiftSync.sync(
            payload: [["id": 10, "email": "a@example.com", "text": "A-note"]],
            as: UniqueEmailNote.self,
            in: context,
            parent: folderA
        )

        try await SwiftSync.sync(
            payload: [["id": 10, "email": "b@example.com", "text": "B-note"]],
            as: UniqueEmailNote.self,
            in: context,
            parent: folderB
        )

        let all = try context.fetch(FetchDescriptor<UniqueEmailNote>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all.first(where: { $0.folder?.id == 1 })?.text, "A-note")
        XCTAssertEqual(all.first(where: { $0.folder?.id == 2 })?.text, "B-note")
    }

    @MainActor
    func testStrictForeignKeyTypingDoesNotCoerceRelationshipIDs() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AutoCompany.self, AutoEmployee.self, configurations: configuration)
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

        // String "10" should NOT coerce to Int 10 for strict FK typing.
        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": "10"]],
            as: AutoEmployee.self,
            in: context
        )

        var rows = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertNil(rows.first?.company)

        // Integer 10 matches the expected type and should resolve the FK.
        try await SwiftSync.sync(
            payload: [["id": 1, "name": "Ava", "company_id": 10]],
            as: AutoEmployee.self,
            in: context
        )

        rows = try context.fetch(FetchDescriptor<AutoEmployee>())
        XCTAssertEqual(rows.first?.company?.id, 10)
    }

}
