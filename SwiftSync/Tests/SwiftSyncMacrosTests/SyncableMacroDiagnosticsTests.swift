import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import MacrosImplementation

final class SyncableMacroDiagnosticsTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "Syncable": SyncableMacro.self
    ]

    func testSyncableDoesNotWarnForToManyRelationshipWithoutExplicitInverse() {
        assertMacroExpansion(
            """
            @Syncable
            final class Ticket {
                var labels: [Label] = []
            }

            final class Label {
                var id: Int = 0
            }
            """,
            expandedSource: """
                final class Ticket {
                    var labels: [Label] = []
                }

                final class Label {
                    var id: Int = 0
                }
                """,
            diagnostics: [],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testSyncableGeneratesPublicMembersForPublicModel() {
        assertMacroExpansion(
            """
            @Syncable
            public final class Ticket {
                public var id: String = ""
                public var title: String = ""
            }
            """,
            expandedSource: """
                public final class Ticket {
                    public var id: String = ""
                    public var title: String = ""
                }

                extension Ticket: SyncUpdatableModel {
                    public typealias SyncID = String

                    public static var syncIdentity: KeyPath<Ticket, String> {
                        \\.id
                    }
                    public static func syncIdentityPredicate(matching identity: String) -> Predicate<Ticket>? {
                        Predicate<Ticket> { row in
                            PredicateExpressions.build_Equal(
                                lhs: PredicateExpressions.build_KeyPath(
                                    root: row,
                                    keyPath: \\.id
                                ),
                                rhs: PredicateExpressions.build_Arg(identity)
                            )
                        }
                    }
                    public static func syncIdentityPredicate(matchingAny identities: [String]) -> Predicate<Ticket>? {
                        Predicate<Ticket> { row in
                            PredicateExpressions.build_contains(
                                PredicateExpressions.build_Arg(identities),
                                PredicateExpressions.build_KeyPath(
                                    root: row,
                                    keyPath: \\.id
                                )
                            )
                        }
                    }
                    public static func syncParentPredicate(
                        parentPersistentID: PersistentIdentifier,
                        relationship: PartialKeyPath<Ticket>
                    ) -> Predicate<Ticket>? {
                        return nil
                    }

                    public static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] {
                        []
                    }

                    public static func syncRelatedModelType(for keyPath: PartialKeyPath<Ticket>) -> (any PersistentModel.Type)? {
                        return nil
                    }

                    public static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] {
                        []
                    }

                    public static func make(from payload: SyncPayload) throws -> Ticket {
                        Ticket(
                            id: try payload.required(String.self, for: "id"),
                            title: try payload.required(String.self, for: "title")
                        )
                    }

                    public func apply(_ payload: SyncPayload) throws -> Bool {
                        var changed = false
                        if payload.contains("title") {
                    let incomingTitle: String = try payload.required(String.self, for: "title")
                    if self.title != incomingTitle {
                        self.title = incomingTitle
                        changed = true
                    }
                        }
                        return changed
                    }

                    public func syncApplyGeneratedRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        operations: SyncRelationshipOperations = .all
                    ) throws -> Bool {
                        guard !operations.isDisjoint(with: [.insert, .update, .delete]) else {
                            return false
                        }
                        return false


                    }

                    public func applyRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        isolation: isolated (any Actor)? = #isolation
                    ) async throws -> Bool {
                        try syncApplyGeneratedRelationships(payload, in: context, operations: .all)
                    }

                    public func applyRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        operations: SyncRelationshipOperations,
                        isolation: isolated (any Actor)? = #isolation
                    ) async throws -> Bool {
                        try syncApplyGeneratedRelationships(payload, in: context, operations: operations)
                    }

                    public func export(keyStyle: KeyStyle, dateFormatter: DateFormatter) -> [String: Any] {
                        if !ExportState.enter(self) {
                            return [:]
                        }
                        defer {
                            ExportState.leave(self)
                        }

                        var result: [String: Any] = [:]
                        if let encoded = exportEncodeValue(self.id, dateFormatter: dateFormatter) {
                    exportSetValue(encoded, for: keyStyle.transform("id"), into: &result)
                        } else {
                    exportSetValue(NSNull(), for: keyStyle.transform("id"), into: &result)
                        }

                        if let encoded = exportEncodeValue(self.title, dateFormatter: dateFormatter) {
                            exportSetValue(encoded, for: keyStyle.transform("title"), into: &result)
                        } else {
                            exportSetValue(NSNull(), for: keyStyle.transform("title"), into: &result)
                        }
                        return result
                    }

                    public func syncMarkChanged() {
                        self.id = self.id
                    }
                }
                """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testSyncableApplyReturnsFalseWhenNoMutableScalarProperties() {
        assertMacroExpansion(
            """
            @Syncable
            final class Note {
                var id: Int = 0
            }
            """,
            expandedSource: """
                final class Note {
                    var id: Int = 0
                }

                extension Note: SyncUpdatableModel {
                    typealias SyncID = Int

                    static var syncIdentity: KeyPath<Note, Int> {
                        \\.id
                    }
                    static func syncIdentityPredicate(matching identity: Int) -> Predicate<Note>? {
                        Predicate<Note> { row in
                            PredicateExpressions.build_Equal(
                                lhs: PredicateExpressions.build_KeyPath(
                                    root: row,
                                    keyPath: \\.id
                                ),
                                rhs: PredicateExpressions.build_Arg(identity)
                            )
                        }
                    }
                    static func syncIdentityPredicate(matchingAny identities: [Int]) -> Predicate<Note>? {
                        Predicate<Note> { row in
                            PredicateExpressions.build_contains(
                                PredicateExpressions.build_Arg(identities),
                                PredicateExpressions.build_KeyPath(
                                    root: row,
                                    keyPath: \\.id
                                )
                            )
                        }
                    }
                    static func syncParentPredicate(
                        parentPersistentID: PersistentIdentifier,
                        relationship: PartialKeyPath<Note>
                    ) -> Predicate<Note>? {
                        return nil
                    }

                    static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] {
                        []
                    }

                    static func syncRelatedModelType(for keyPath: PartialKeyPath<Note>) -> (any PersistentModel.Type)? {
                        return nil
                    }

                    static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] {
                        []
                    }

                    static func make(from payload: SyncPayload) throws -> Note {
                        Note(
                            id: try payload.required(Int.self, for: "id")
                        )
                    }

                    func apply(_ payload: SyncPayload) throws -> Bool {
                        return false


                    }

                    func syncApplyGeneratedRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        operations: SyncRelationshipOperations = .all
                    ) throws -> Bool {
                        guard !operations.isDisjoint(with: [.insert, .update, .delete]) else {
                            return false
                        }
                        return false


                    }

                    func applyRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        isolation: isolated (any Actor)? = #isolation
                    ) async throws -> Bool {
                        try syncApplyGeneratedRelationships(payload, in: context, operations: .all)
                    }

                    func applyRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        operations: SyncRelationshipOperations,
                        isolation: isolated (any Actor)? = #isolation
                    ) async throws -> Bool {
                        try syncApplyGeneratedRelationships(payload, in: context, operations: operations)
                    }

                    func export(keyStyle: KeyStyle, dateFormatter: DateFormatter) -> [String: Any] {
                        if !ExportState.enter(self) {
                            return [:]
                        }
                        defer {
                            ExportState.leave(self)
                        }

                        var result: [String: Any] = [:]
                        if let encoded = exportEncodeValue(self.id, dateFormatter: dateFormatter) {
                    exportSetValue(encoded, for: keyStyle.transform("id"), into: &result)
                        } else {
                    exportSetValue(NSNull(), for: keyStyle.transform("id"), into: &result)
                        }
                        return result
                    }

                    func syncMarkChanged() {
                        self.id = self.id
                    }
                }
                """,
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }
}
