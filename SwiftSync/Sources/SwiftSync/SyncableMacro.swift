@attached(extension, conformances: SyncUpdatableModel, names: named(SyncID), named(syncIdentity), named(syncIdentityPredicate), named(syncParentPredicate), named(syncIdentityRemoteKeys), named(syncDefaultRefreshModelTypes), named(syncRelatedModelType), named(syncRelationshipSchemaDescriptors), named(make), named(apply), named(applyRelationships), named(syncApplyGeneratedRelationships), named(export), named(syncMarkChanged))
public macro Syncable() = #externalMacro(module: "MacrosImplementation", type: "SyncableMacro")

@attached(peer)
public macro PrimaryKey(remote: String? = nil) = #externalMacro(module: "MacrosImplementation", type: "PrimaryKeyMacro")

@attached(peer)
public macro NotExport() = #externalMacro(module: "MacrosImplementation", type: "NotExportMacro")

@attached(peer)
public macro RemoteKey(_ key: String) = #externalMacro(module: "MacrosImplementation", type: "RemoteKeyMacro")
