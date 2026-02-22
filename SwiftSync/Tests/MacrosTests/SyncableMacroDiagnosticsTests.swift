import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

@testable import MacrosImplementation

final class SyncableMacroDiagnosticsTests: XCTestCase {
    private let macros: [String: Macro.Type] = [
        "Syncable": SyncableMacro.self
    ]

    func testSyncableEmitsErrorForToManyRelationshipWithoutExplicitInverse() {
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
            diagnostics: [
                DiagnosticSpec(
                    message: "To-many relationship 'labels' in @Syncable model 'Ticket' must declare @Relationship(inverse: ...). Explicit inverses are required to avoid SwiftData relationship corruption during sync.",
                    line: 3,
                    column: 9,
                    severity: .warning
                )
            ],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }

    func testSyncableDoesNotWarnForAllowlistedMissingToManyInverse() {
        assertMacroExpansion(
            """
            @Syncable(allowMissingToManyInverses: ["tags"])
            final class Task {
                var tags: [Tag] = []
            }

            final class Tag {
                var name: String = ""
            }
            """,
            expandedSource: """
            final class Task {
                var tags: [Tag] = []
            }

            final class Tag {
                var name: String = ""
            }
            """,
            diagnostics: [],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }
}
