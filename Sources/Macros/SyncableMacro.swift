import Core

@attached(extension, conformances: SyncUpdatableModel, names: named(SyncID), named(syncIdentity), named(syncIdentityRemoteKeys), named(make), named(apply))
public macro Syncable() = #externalMacro(module: "MacrosImplementation", type: "SyncableMacro")

@attached(peer)
public macro PrimaryKey(remote: String? = nil) = #externalMacro(module: "MacrosImplementation", type: "PrimaryKeyMacro")
