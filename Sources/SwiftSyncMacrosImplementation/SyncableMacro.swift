import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

private struct SyncedProperty {
    let name: String
    let typeSource: String
    let isOptional: Bool
}

public struct SyncableMacro: ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            return []
        }

        let typeName = classDecl.name.text
        let properties = syncedProperties(from: classDecl)

        guard !properties.isEmpty else {
            return []
        }

        guard let identityProperty = properties.first(where: { $0.name == "id" }) ??
            properties.first(where: { $0.name == "remoteID" })
        else {
            return []
        }

        let makeArguments = properties.map { property -> String in
            "\(property.name): \(payloadReadExpression(for: property))"
        }
        .joined(separator: ",\n            ")

        let applyBody = properties
            .filter { $0.name != identityProperty.name }
            .map(applyBlock(for:))
            .joined(separator: "\n\n")

        return [
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): SyncUpdatableModel {
                    typealias SyncID = \(raw: identityProperty.typeSource)

                    static var syncIdentity: KeyPath<\(raw: typeName), \(raw: identityProperty.typeSource)> { \\.\(raw: identityProperty.name) }

                    static func make(from payload: SyncPayload) throws -> \(raw: typeName) {
                        \(raw: typeName)(
                            \(raw: makeArguments)
                        )
                    }

                    func apply(_ payload: SyncPayload) throws -> Bool {
                        var changed = false
                        \(raw: applyBody)
                        return changed
                    }
                }
                """
            )
        ]
    }

    private static func syncedProperties(from classDecl: ClassDeclSyntax) -> [SyncedProperty] {
        classDecl.memberBlock.members.compactMap { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return nil }
            guard variable.bindings.count == 1 else { return nil }
            guard !variable.modifiers.contains(where: { $0.name.text == "static" }) else { return nil }

            guard let binding = variable.bindings.first,
                binding.accessorBlock == nil,
                let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                let annotation = binding.typeAnnotation
            else {
                return nil
            }

            let typeSource = annotation.type.trimmedDescription
            let isOptional = typeSource.hasSuffix("?")

            return SyncedProperty(
                name: pattern.identifier.text,
                typeSource: typeSource,
                isOptional: isOptional
            )
        }
    }

    private static func payloadReadExpression(for property: SyncedProperty) -> String {
        if property.isOptional {
            return "payload.value(for: \"\(property.name)\")"
        }
        return "try payload.required(\(property.typeSource).self, for: \"\(property.name)\")"
    }

    private static func applyBlock(for property: SyncedProperty) -> String {
        let incoming = "incoming\(property.name.prefix(1).uppercased())\(property.name.dropFirst())"
        let read: String
        if property.isOptional {
            read = "let \(incoming): \(property.typeSource) = payload.value(for: \"\(property.name)\")"
        } else {
            read = "let \(incoming): \(property.typeSource) = try payload.required(\(property.typeSource).self, for: \"\(property.name)\")"
        }

        return """
        \(read)
        if \(property.name) != \(incoming) {
            \(property.name) = \(incoming)
            changed = true
        }
        """
    }
}

@main
struct SwiftSyncMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SyncableMacro.self
    ]
}
