import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

private struct SyncedProperty {
    let name: String
    let typeSource: String
    let isOptional: Bool
    let isPrimaryKey: Bool
    let primaryKeyRemoteKey: String?
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

        let explicitPrimaryKey = properties.first(where: \.isPrimaryKey)
        guard let identityProperty = explicitPrimaryKey ?? properties.first(where: { $0.name == "id" }) ??
            properties.first(where: { $0.name == "remoteID" })
        else {
            return []
        }
        let explicitRemoteIdentityKey = identityProperty.primaryKeyRemoteKey.flatMap { key in
            key.isEmpty ? nil : key
        }
        let generatedRemoteIdentityKey = explicitRemoteIdentityKey ?? identityProperty.name
        let needsCustomRemoteIdentityKeys = explicitPrimaryKey != nil

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
                    \(raw: needsCustomRemoteIdentityKeys ? "static var syncIdentityRemoteKeys: [String] { [\"\(generatedRemoteIdentityKey)\"] }" : "")

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
            let primaryKeyRemoteKey = primaryKeyRemoteKeyIfPresent(variable)
            let isPrimaryKey = primaryKeyRemoteKey != nil

            return SyncedProperty(
                name: pattern.identifier.text,
                typeSource: typeSource,
                isOptional: isOptional,
                isPrimaryKey: isPrimaryKey,
                primaryKeyRemoteKey: primaryKeyRemoteKey
            )
        }
    }

    private static func primaryKeyRemoteKeyIfPresent(_ variable: VariableDeclSyntax) -> String? {
        for attribute in variable.attributes {
            guard let syntax = attribute.as(AttributeSyntax.self) else { continue }
            let rawName = syntax.attributeName.trimmedDescription
            guard rawName == "PrimaryKey" || rawName.hasSuffix(".PrimaryKey") else { continue }

            if let arguments = syntax.arguments?.as(LabeledExprListSyntax.self) {
                for argument in arguments {
                    guard argument.label?.text == "remote" else { continue }
                    if let literal = argument.expression.as(StringLiteralExprSyntax.self) {
                        for segment in literal.segments {
                            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                                return stringSegment.content.text
                            }
                        }
                    }
                }
            }

            // Marker without explicit remote key defaults to local property name.
            return ""
        }
        return nil
    }

    private static func payloadReadExpression(for property: SyncedProperty) -> String {
        let remoteKey: String
        if let key = property.primaryKeyRemoteKey, !key.isEmpty {
            remoteKey = key
        } else {
            remoteKey = property.name
        }
        if property.isOptional {
            return "payload.value(for: \"\(remoteKey)\")"
        }
        return "try payload.required(\(property.typeSource).self, for: \"\(remoteKey)\")"
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

public struct PrimaryKeyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        _ = node
        _ = declaration
        _ = context
        return []
    }
}

@main
struct MacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SyncableMacro.self,
        PrimaryKeyMacro.self
    ]
}
