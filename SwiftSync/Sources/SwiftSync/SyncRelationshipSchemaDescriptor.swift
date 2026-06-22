public struct SyncRelationshipSchemaDescriptor: Sendable {
    public let propertyName: String
    public let relatedTypeName: String
    public let isToMany: Bool
    public let hasExplicitInverseAnchor: Bool

    public init(
        propertyName: String,
        relatedTypeName: String,
        isToMany: Bool,
        hasExplicitInverseAnchor: Bool
    ) {
        self.propertyName = propertyName
        self.relatedTypeName = relatedTypeName
        self.isToMany = isToMany
        self.hasExplicitInverseAnchor = hasExplicitInverseAnchor
    }
}
