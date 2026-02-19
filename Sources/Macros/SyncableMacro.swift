import Core

@attached(extension, conformances: SyncUpdatableModel, ExportModel, names: named(SyncID), named(syncIdentity), named(syncIdentityRemoteKeys), named(make), named(apply), named(exportObject))
public macro Syncable() = #externalMacro(module: "MacrosImplementation", type: "SyncableMacro")

@attached(peer)
public macro PrimaryKey(remote: String? = nil) = #externalMacro(module: "MacrosImplementation", type: "PrimaryKeyMacro")

@attached(peer)
public macro NotExport() = #externalMacro(module: "MacrosImplementation", type: "NotExportMacro")

@attached(peer)
public macro RemoteKey(_ key: String) = #externalMacro(module: "MacrosImplementation", type: "RemoteKeyMacro")

@attached(peer)
public macro RemotePath(_ path: String) = #externalMacro(module: "MacrosImplementation", type: "RemotePathMacro")
