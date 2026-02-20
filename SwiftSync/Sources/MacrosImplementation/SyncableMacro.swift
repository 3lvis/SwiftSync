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
    let remoteKey: String?
    let remotePath: String?
    let isNotExport: Bool
    let isRelationship: Bool
    let isToManyRelationship: Bool
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

        let exportBody = properties
            .filter { !$0.isNotExport }
            .map(exportBlock(for:))
            .joined(separator: "\n\n")

        return [
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): SyncUpdatableModel, ExportModel {
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

                    func exportObject(using options: ExportOptions, state: inout ExportState) -> [String: Any] {
                        if !state.enter(self) {
                            return [:]
                        }
                        defer { state.leave(self) }

                        var result: [String: Any] = [:]
                        \(raw: exportBody)
                        return result
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
            let remoteKey = remoteKeyIfPresent(variable)
            let remotePath = remotePathIfPresent(variable)
            let isNotExport = isNotExportPresent(variable)
            let relationshipInfo = relationshipInfo(from: typeSource)

            return SyncedProperty(
                name: pattern.identifier.text,
                typeSource: typeSource,
                isOptional: isOptional,
                isPrimaryKey: isPrimaryKey,
                primaryKeyRemoteKey: primaryKeyRemoteKey,
                remoteKey: remoteKey,
                remotePath: remotePath,
                isNotExport: isNotExport,
                isRelationship: relationshipInfo.isRelationship,
                isToManyRelationship: relationshipInfo.isToMany
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

    private static func remoteKeyIfPresent(_ variable: VariableDeclSyntax) -> String? {
        literalArgument(for: "RemoteKey", in: variable)
    }

    private static func remotePathIfPresent(_ variable: VariableDeclSyntax) -> String? {
        literalArgument(for: "RemotePath", in: variable)
    }

    private static func literalArgument(for attributeName: String, in variable: VariableDeclSyntax) -> String? {
        for attribute in variable.attributes {
            guard let syntax = attribute.as(AttributeSyntax.self) else { continue }
            let rawName = syntax.attributeName.trimmedDescription
            guard rawName == attributeName || rawName.hasSuffix(".\(attributeName)") else { continue }
            if let arguments = syntax.arguments?.as(LabeledExprListSyntax.self),
                let first = arguments.first,
                let literal = first.expression.as(StringLiteralExprSyntax.self)
            {
                for segment in literal.segments {
                    if let stringSegment = segment.as(StringSegmentSyntax.self) {
                        return stringSegment.content.text
                    }
                }
            }
        }
        return nil
    }

    private static func isNotExportPresent(_ variable: VariableDeclSyntax) -> Bool {
        for attribute in variable.attributes {
            guard let syntax = attribute.as(AttributeSyntax.self) else { continue }
            let rawName = syntax.attributeName.trimmedDescription
            if rawName == "NotExport" || rawName.hasSuffix(".NotExport") {
                return true
            }
        }
        return false
    }

    private static func relationshipInfo(from typeSource: String) -> (isRelationship: Bool, isToMany: Bool) {
        let trimmed = typeSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped = unwrapOptional(type: trimmed)

        if unwrapped.hasPrefix("[") && unwrapped.hasSuffix("]") {
            let inner = String(unwrapped.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            if isScalarType(inner) {
                return (false, false)
            }
            return (true, true)
        }

        if isScalarType(unwrapped) {
            return (false, false)
        }

        return (true, false)
    }

    private static func unwrapOptional(type: String) -> String {
        if type.hasSuffix("?") {
            return String(type.dropLast())
        }
        if type.hasPrefix("Optional<"), type.hasSuffix(">") {
            return String(type.dropFirst("Optional<".count).dropLast())
        }
        return type
    }

    private static func isScalarType(_ type: String) -> Bool {
        let normalized = type.replacingOccurrences(of: "Foundation.", with: "")
        switch normalized {
        case "String", "Bool", "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            "Double", "Float", "Decimal", "Date", "UUID", "URL", "Data":
            return true
        default:
            return false
        }
    }

    private static func exportBlock(for property: SyncedProperty) -> String {
        let keyLiteral = exportKeyLiteral(for: property)
        let keyExpr = keyLiteral != nil ? "\"\(keyLiteral!)\"" : "options.keyStyle.transform(\"\(property.name)\")"

        if property.isRelationship {
            if property.isToManyRelationship {
                return """
                if options.relationshipMode != .none {
                    let baseKey = \(keyExpr)
                    let exportedChildren: [[String: Any]] = \(property.name).compactMap { child in
                        let anyChild: Any = child
                        guard let exportable = anyChild as? any ExportModel else { return nil }
                        return exportable.exportObject(using: options, state: &state)
                    }
                    switch options.relationshipMode {
                    case .array:
                        exportSetValue(exportedChildren, for: baseKey, into: &result)
                    case .nested:
                        var nested: [String: Any] = [:]
                        for (index, child) in exportedChildren.enumerated() {
                            nested[String(index)] = child
                        }
                        exportSetValue(nested, for: "\\(baseKey)_attributes", into: &result)
                    case .none:
                        break
                    }
                }
                """
            }
            return """
            if options.relationshipMode != .none {
                let baseKey = \(keyExpr)
                let anyChild: Any? = \(property.name)
                if let exportable = anyChild as? any ExportModel {
                    let child = exportable.exportObject(using: options, state: &state)
                    switch options.relationshipMode {
                    case .array:
                        exportSetValue(child, for: baseKey, into: &result)
                    case .nested:
                        exportSetValue(child, for: "\\(baseKey)_attributes", into: &result)
                    case .none:
                        break
                    }
                } else if options.includeNulls {
                    switch options.relationshipMode {
                    case .array:
                        exportSetValue(NSNull(), for: baseKey, into: &result)
                    case .nested:
                        exportSetValue(NSNull(), for: "\\(baseKey)_attributes", into: &result)
                    case .none:
                        break
                    }
                }
            }
            """
        }

        if property.isOptional {
            return """
            if let value = \(property.name) {
                if let encoded = exportEncodeValue(value, options: options) {
                    exportSetValue(encoded, for: \(keyExpr), into: &result)
                } else if options.includeNulls {
                    exportSetValue(NSNull(), for: \(keyExpr), into: &result)
                }
            } else if options.includeNulls {
                exportSetValue(NSNull(), for: \(keyExpr), into: &result)
            }
            """
        }

        return """
        if let encoded = exportEncodeValue(\(property.name), options: options) {
            exportSetValue(encoded, for: \(keyExpr), into: &result)
        } else if options.includeNulls {
            exportSetValue(NSNull(), for: \(keyExpr), into: &result)
        }
        """
    }

    private static func exportKeyLiteral(for property: SyncedProperty) -> String? {
        if let remotePath = property.remotePath, !remotePath.isEmpty {
            return remotePath
        }
        if let remoteKey = property.remoteKey, !remoteKey.isEmpty {
            return remoteKey
        }
        if let primaryKeyRemoteKey = property.primaryKeyRemoteKey, !primaryKeyRemoteKey.isEmpty {
            return primaryKeyRemoteKey
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

public struct NotExportMacro: PeerMacro {
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

public struct RemoteKeyMacro: PeerMacro {
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

public struct RemotePathMacro: PeerMacro {
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
        PrimaryKeyMacro.self,
        NotExportMacro.self,
        RemoteKeyMacro.self,
        RemotePathMacro.self
    ]
}
