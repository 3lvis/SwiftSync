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
                var id: Int = 0
                var title: String = ""
                var labels: [Label] = []
            }

            final class Label {
                var id: Int = 0
            }
            """,
            expandedSource: """
            final class Ticket {
                var id: Int = 0
                var title: String = ""
                var labels: [Label] = []
            }

            final class Label {
                var id: Int = 0
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "To-many relationship 'labels' in @Syncable model 'Ticket' must declare @Relationship(inverse: ...). Explicit inverses are required to avoid SwiftData relationship corruption during sync.",
                    line: 5,
                    column: 9,
                    severity: .error
                )
            ],
            macros: macros,
            indentationWidth: .spaces(4)
        )
    }
}
