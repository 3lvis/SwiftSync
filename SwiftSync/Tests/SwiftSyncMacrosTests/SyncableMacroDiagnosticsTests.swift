import XCTest
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport

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
}
