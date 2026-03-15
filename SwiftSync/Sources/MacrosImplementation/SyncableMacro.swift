import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics
import SwiftCompilerPlugin

private struct SyncedProperty {
    let name: String
    let typeSource: String
    let isOptional: Bool
    let isPrimaryKey: Bool
    let primaryKeyRemoteKey: String?
    let remoteKey: String?
    let isNotExport: Bool
    let isRelationship: Bool
    let isToManyRelationship: Bool
    let hasExplicitRelationshipInverse: Bool
}

private struct ReservedModelPropertyNameDiagnostic: DiagnosticMessage {
    let propertyName: String
    let suggestedName: String

    var message: String {
        """
        '\(propertyName)' is a blocked SwiftData/Swift property name for @Syncable models. \
        Rename it to '\(suggestedName)' and map the API key with @RemoteKey("\(propertyName)").
        """
    }

    var diagnosticID: MessageID {
        MessageID(domain: "SwiftSync.SyncableMacro", id: "blocked-property-name-\(propertyName)")
    }

    var severity: DiagnosticSeverity { .error }
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

        emitBlockedNameDiagnostics(in: classDecl, context: context)

        let typeName = classDecl.name.text
        let declarationAccessModifier = classDecl.modifiers
            .map { $0.name.text }
            .first(where: { ["public", "open"].contains($0) })
        let memberAccessModifier = declarationAccessModifier.map { "\($0) " } ?? ""
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
            .filter { $0.name != identityProperty.name && !$0.isRelationship }
            .map(applyBlock(for:))
            .joined(separator: "\n\n")

        let exportBody = properties
            .filter { !$0.isNotExport }
            .map(exportBlock(for:))
            .joined(separator: "\n\n")
        let defaultRefreshModelTypesBody = defaultRefreshModelTypesBlock(for: properties)
        let relatedModelTypeBody = relatedModelTypeBlock(for: properties, typeName: typeName)
        let relationshipSchemaDescriptorsBody = relationshipSchemaDescriptorsBlock(for: properties)
        let relationshipApplyBody = relationshipApplyBlock(for: properties, typeName: typeName)
        let parentPredicateBody = syncParentPredicateBlock(for: properties, typeName: typeName)

        return [
            try ExtensionDeclSyntax(
                """
                extension \(type.trimmed): SyncUpdatableModel {
                    \(raw: memberAccessModifier)typealias SyncID = \(raw: identityProperty.typeSource)

                    \(raw: memberAccessModifier)static var syncIdentity: KeyPath<\(raw: typeName), \(raw: identityProperty.typeSource)> { \\.\(raw: identityProperty.name) }
                    \(raw: memberAccessModifier)static func syncIdentityPredicate(matching identity: \(raw: identityProperty.typeSource)) -> Predicate<\(raw: typeName)>? {
                        Predicate<\(raw: typeName)> { row in
                            PredicateExpressions.build_Equal(
                                lhs: PredicateExpressions.build_KeyPath(
                                    root: row,
                                    keyPath: \\.\(raw: identityProperty.name)
                                ),
                                rhs: PredicateExpressions.build_Arg(identity)
                            )
                        }
                    }
                    \(raw: memberAccessModifier)static func syncParentPredicate(
                        parentPersistentID: PersistentIdentifier,
                        relationship: PartialKeyPath<\(raw: typeName)>
                    ) -> Predicate<\(raw: typeName)>? {
                        \(raw: parentPredicateBody)
                    }
                    \(raw: needsCustomRemoteIdentityKeys ? "\(memberAccessModifier)static var syncIdentityRemoteKeys: [String] { [\"\(generatedRemoteIdentityKey)\"] }" : "")
                    \(raw: memberAccessModifier)static var syncDefaultRefreshModelTypes: [any PersistentModel.Type] { \(raw: defaultRefreshModelTypesBody) }

                    \(raw: memberAccessModifier)static func syncRelatedModelType(for keyPath: PartialKeyPath<\(raw: typeName)>) -> (any PersistentModel.Type)? {
                        \(raw: relatedModelTypeBody)
                    }

                    \(raw: memberAccessModifier)static var syncRelationshipSchemaDescriptors: [SyncRelationshipSchemaDescriptor] {
                        \(raw: relationshipSchemaDescriptorsBody)
                    }

                    \(raw: memberAccessModifier)static func make(from payload: SyncPayload) throws -> \(raw: typeName) {
                        \(raw: typeName)(
                            \(raw: makeArguments)
                        )
                    }

                    \(raw: memberAccessModifier)func apply(_ payload: SyncPayload) throws -> Bool {
                        var changed = false
                        \(raw: applyBody)
                        return changed
                    }

                    \(raw: memberAccessModifier)func syncApplyGeneratedRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        operations: SyncRelationshipOperations = .all
                    ) throws -> Bool {
                        guard !operations.isDisjoint(with: [.insert, .update, .delete]) else { return false }
                        \(raw: relationshipApplyBody.isEmpty ? "return false" : "var changed = false")
                        \(raw: relationshipApplyBody)
                        \(raw: relationshipApplyBody.isEmpty ? "" : "return changed")
                    }

                    \(raw: memberAccessModifier)func applyRelationships(_ payload: SyncPayload, in context: ModelContext) async throws -> Bool {
                        try syncApplyGeneratedRelationships(payload, in: context, operations: .all)
                    }

                    \(raw: memberAccessModifier)func applyRelationships(
                        _ payload: SyncPayload,
                        in context: ModelContext,
                        operations: SyncRelationshipOperations
                    ) async throws -> Bool {
                        try syncApplyGeneratedRelationships(payload, in: context, operations: operations)
                    }

                    \(raw: memberAccessModifier)func export(keyStyle: KeyStyle, dateFormatter: DateFormatter) -> [String: Any] {
                        if !ExportState.enter(self) {
                            return [:]
                        }
                        defer { ExportState.leave(self) }

                        var result: [String: Any] = [:]
                        \(raw: exportBody)
                        return result
                    }

                    \(raw: memberAccessModifier)func syncMarkChanged() {
                        self.\(raw: identityProperty.name) = self.\(raw: identityProperty.name)
                    }
                }
                """
            )
        ]
    }

    private static let blockedPropertyNameSuggestions: [String: String] = [
        "description": "descriptionText",
        "hashValue": "hashValueRaw"
    ]

    private static func emitBlockedNameDiagnostics(
        in classDecl: ClassDeclSyntax,
        context: some MacroExpansionContext
    ) {
        for member in classDecl.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self),
                variable.bindings.count == 1,
                let binding = variable.bindings.first,
                let pattern = binding.pattern.as(IdentifierPatternSyntax.self)
            else {
                continue
            }

            let propertyName = pattern.identifier.text
            guard let suggestedName = blockedPropertyNameSuggestions[propertyName] else {
                continue
            }

            let message = ReservedModelPropertyNameDiagnostic(
                propertyName: propertyName,
                suggestedName: suggestedName
            )
            context.diagnose(Diagnostic(node: Syntax(pattern.identifier), message: message))
        }
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
            let isNotExport = isNotExportPresent(variable)
            let relationshipInfo = relationshipInfo(from: typeSource)

            return SyncedProperty(
                name: pattern.identifier.text,
                typeSource: typeSource,
                isOptional: isOptional,
                isPrimaryKey: isPrimaryKey,
                primaryKeyRemoteKey: primaryKeyRemoteKey,
                remoteKey: remoteKey,
                isNotExport: isNotExport,
                isRelationship: relationshipInfo.isRelationship,
                isToManyRelationship: relationshipInfo.isToMany,
                hasExplicitRelationshipInverse: hasExplicitRelationshipInverse(variable)
            )
        }
    }

    private static func relationshipSchemaDescriptorsBlock(for properties: [SyncedProperty]) -> String {
        let descriptors = properties.compactMap { property -> String? in
            guard property.isRelationship else { return nil }
            guard let relatedType = relationshipModelTypeName(for: property) else { return nil }
            return """
            SyncRelationshipSchemaDescriptor(
                propertyName: "\(property.name)",
                relatedTypeName: String(reflecting: \(relatedType).self),
                isToMany: \(property.isToManyRelationship ? "true" : "false"),
                hasExplicitInverseAnchor: \(property.hasExplicitRelationshipInverse ? "true" : "false")
            )
            """
        }

        guard !descriptors.isEmpty else { return "[]" }
        return "[\n\(descriptors.joined(separator: ",\n"))\n]"
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

    private static func hasExplicitRelationshipInverse(_ variable: VariableDeclSyntax) -> Bool {
        for attribute in variable.attributes {
            guard let syntax = attribute.as(AttributeSyntax.self) else { continue }
            let rawName = syntax.attributeName.trimmedDescription
            guard rawName == "Relationship" || rawName.hasSuffix(".Relationship") else { continue }
            guard let arguments = syntax.arguments?.as(LabeledExprListSyntax.self) else { continue }
            if arguments.contains(where: { $0.label?.text == "inverse" }) {
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

    private static func defaultRefreshModelTypesBlock(for properties: [SyncedProperty]) -> String {
        var relationshipTypes: [String] = []
        for property in properties where property.isRelationship {
            guard let relationshipType = relationshipModelTypeName(for: property) else { continue }
            if !relationshipTypes.contains(relationshipType) {
                relationshipTypes.append(relationshipType)
            }
        }
        guard !relationshipTypes.isEmpty else {
            return "[]"
        }
        let values = relationshipTypes.map { "\($0).self" }.joined(separator: ", ")
        return "[\(values)]"
    }

    private static func relatedModelTypeBlock(for properties: [SyncedProperty], typeName: String) -> String {
        let relationshipProperties = properties.filter { $0.isRelationship }
        guard !relationshipProperties.isEmpty else {
            return "return nil"
        }

        let blocks = relationshipProperties.compactMap { property -> String? in
            guard let relationshipType = relationshipModelTypeName(for: property) else { return nil }
            return """
            if keyPath == \\\(typeName).\(property.name) {
                return \(relationshipType).self
            }
            """
        }
        guard !blocks.isEmpty else {
            return "return nil"
        }
        return "\(blocks.joined(separator: "\n"))\nreturn nil"
    }

    private static func relationshipModelTypeName(for property: SyncedProperty) -> String? {
        guard property.isRelationship else { return nil }

        let trimmed = property.typeSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let unwrapped = unwrapOptional(type: trimmed)
        if unwrapped.hasPrefix("[") && unwrapped.hasSuffix("]") {
            return String(unwrapped.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return unwrapped
    }

    private static func exportBlock(for property: SyncedProperty) -> String {
        let keyLiteral = exportKeyLiteral(for: property)
        let keyExpr = keyLiteral != nil ? "\"\(keyLiteral!)\"" : "keyStyle.transform(\"\(property.name)\")"

        if property.isRelationship {
            if property.isToManyRelationship {
                return """
                do {
                    let baseKey = \(keyExpr)
                    let exportedChildren: [[String: Any]] = self.\(property.name).compactMap { child in
                        let anyChild: Any = child
                        guard let exportable = anyChild as? any SyncUpdatableModel else { return nil }
                        return exportable.export(keyStyle: keyStyle, dateFormatter: dateFormatter)
                    }
                    exportSetValue(exportedChildren, for: baseKey, into: &result)
                }
                """
            }
            return """
            do {
                let baseKey = \(keyExpr)
                let anyChild: Any? = self.\(property.name)
                if let exportable = anyChild as? any SyncUpdatableModel {
                    let child = exportable.export(keyStyle: keyStyle, dateFormatter: dateFormatter)
                    exportSetValue(child, for: baseKey, into: &result)
                } else {
                    exportSetValue(NSNull(), for: baseKey, into: &result)
                }
            }
            """
        }

        if property.isOptional {
            return """
            if let value = self.\(property.name) {
                if let encoded = exportEncodeValue(value, dateFormatter: dateFormatter) {
                    exportSetValue(encoded, for: \(keyExpr), into: &result)
                } else {
                    exportSetValue(NSNull(), for: \(keyExpr), into: &result)
                }
            } else {
                exportSetValue(NSNull(), for: \(keyExpr), into: &result)
            }
            """
        }

        return """
        if let encoded = exportEncodeValue(self.\(property.name), dateFormatter: dateFormatter) {
            exportSetValue(encoded, for: \(keyExpr), into: &result)
        } else {
            exportSetValue(NSNull(), for: \(keyExpr), into: &result)
        }
        """
    }

    private static func exportKeyLiteral(for property: SyncedProperty) -> String? {
        if let remoteKey = property.remoteKey, !remoteKey.isEmpty {
            return remoteKey
        }
        if let primaryKeyRemoteKey = property.primaryKeyRemoteKey, !primaryKeyRemoteKey.isEmpty {
            return primaryKeyRemoteKey
        }
        return nil
    }

    private static func payloadReadExpression(for property: SyncedProperty) -> String {
        let inputKey = syncInputKey(for: property)
        if property.isRelationship {
            if property.isToManyRelationship {
                return "[]"
            }
            if property.isOptional {
                return "nil"
            }
        }
        if property.isOptional {
            return "payload.value(for: \"\(inputKey)\")"
        }
        return "try payload.required(\(property.typeSource).self, for: \"\(inputKey)\")"
    }

    private static func applyBlock(for property: SyncedProperty) -> String {
        let inputKey = syncInputKey(for: property)
        let incoming = "incoming\(property.name.prefix(1).uppercased())\(property.name.dropFirst())"
        let read: String
        if property.isOptional {
            read = "let \(incoming): \(property.typeSource) = payload.value(for: \"\(inputKey)\")"
        } else {
            read = "let \(incoming): \(property.typeSource) = try payload.required(\(property.typeSource).self, for: \"\(inputKey)\")"
        }

        return """
        if payload.contains("\(inputKey)") {
            \(read)
            if self.\(property.name) != \(incoming) {
                self.\(property.name) = \(incoming)
                changed = true
            }
        }
        """
    }

    private static func relationshipApplyBlock(for properties: [SyncedProperty], typeName: String) -> String {
        let relationshipProperties = properties.filter { $0.isRelationship }
        guard !relationshipProperties.isEmpty else {
            return ""
        }

        let blocks: [String] = relationshipProperties.compactMap { property in
            let fkKeys = relationshipForeignKeyInputKeys(for: property)
            let nestedKeys = relationshipNestedInputKeys(for: property)
            guard !fkKeys.isEmpty || !nestedKeys.isEmpty else { return nil }
            let fkKeysLiteral = fkKeys.map { "\"\($0)\"" }.joined(separator: ", ")
            let nestedKeysLiteral = nestedKeys.map { "\"\($0)\"" }.joined(separator: ", ")
            let fkPresence = presenceExpression(for: fkKeys)
            let nestedPresence = presenceExpression(for: nestedKeys)

            if property.isToManyRelationship {
                return """
                if \(fkPresence) {
                    if try syncApplyToManyForeignKeys(
                        self,
                        relationship: \\\(typeName).\(property.name),
                        payload: payload,
                        keys: [\(fkKeysLiteral)],
                        in: context,
                        operations: operations
                    ) {
                        changed = true
                    }
                } else if \(nestedPresence) {
                    if try syncApplyToManyNestedObjects(
                        self,
                        relationship: \\\(typeName).\(property.name),
                        payload: payload,
                        keys: [\(nestedKeysLiteral)],
                        in: context,
                        operations: operations
                    ) {
                        changed = true
                    }
                }
                """
            }

            return """
            if \(fkPresence) {
                if try syncApplyToOneForeignKey(
                    self,
                    relationship: \\\(typeName).\(property.name),
                    payload: payload,
                    keys: [\(fkKeysLiteral)],
                    in: context,
                    operations: operations
                ) {
                    changed = true
                }
            } else if \(nestedPresence) {
                if try syncApplyToOneNestedObject(
                    self,
                    relationship: \\\(typeName).\(property.name),
                    payload: payload,
                    keys: [\(nestedKeysLiteral)],
                    in: context,
                    operations: operations
                ) {
                    changed = true
                }
            }
            """
        }

        return blocks.joined(separator: "\n\n")
    }

    private static func syncParentPredicateBlock(for properties: [SyncedProperty], typeName: String) -> String {
        let toOneRelationships = properties.filter { $0.isRelationship && !$0.isToManyRelationship }
        guard !toOneRelationships.isEmpty else {
            return "return nil"
        }

        let cases = toOneRelationships.map { property in
            """
            if relationship == \\.\(property.name) {
                return #Predicate<\(typeName)> { row in
                    row.\(property.name)?.persistentModelID == parentPersistentID
                }
            }
            """
        }.joined(separator: "\n")

        return """
        \(cases)
        return nil
        """
    }

    private static func relationshipForeignKeyInputKeys(for property: SyncedProperty) -> [String] {
        if let remoteKey = property.remoteKey, !remoteKey.isEmpty {
            if remoteKey.contains(".") {
                return []
            }
            return [remoteKey]
        }

        if property.isToManyRelationship {
            let plural = "\(property.name)_ids"
            let singular = "\(singularized(property.name))_ids"
            return Array(Set([plural, singular])).sorted()
        }

        return ["\(property.name)_id"]
    }

    private static func relationshipNestedInputKeys(for property: SyncedProperty) -> [String] {
        var keys: [String] = [property.name]
        if let remoteKey = property.remoteKey, !remoteKey.isEmpty {
            keys.append(remoteKey)
        }
        return Array(Set(keys)).sorted()
    }

    private static func presenceExpression(for keys: [String]) -> String {
        guard !keys.isEmpty else { return "false" }
        return keys.map { "payload.contains(\"\($0)\")" }.joined(separator: " || ")
    }

    private static func singularized(_ value: String) -> String {
        guard value.count > 1 else { return value }
        if value.hasSuffix("ies") {
            return String(value.dropLast(3)) + "y"
        }
        if value.hasSuffix("ses") || value.hasSuffix("xes") || value.hasSuffix("zes") ||
            value.hasSuffix("ches") || value.hasSuffix("shes")
        {
            return String(value.dropLast(2))
        }
        if value.hasSuffix("s") {
            return String(value.dropLast())
        }
        return value
    }

    private static func syncInputKey(for property: SyncedProperty) -> String {
        if let primaryKeyRemoteKey = property.primaryKeyRemoteKey, !primaryKeyRemoteKey.isEmpty {
            return primaryKeyRemoteKey
        }
        if let remoteKey = property.remoteKey, !remoteKey.isEmpty {
            return remoteKey
        }
        return property.name
    }
}

public struct PrimaryKeyMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

public struct NotExportMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

public struct RemoteKeyMacro: PeerMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] { [] }
}

@main
struct MacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        SyncableMacro.self,
        PrimaryKeyMacro.self,
        NotExportMacro.self,
        RemoteKeyMacro.self
    ]
}
