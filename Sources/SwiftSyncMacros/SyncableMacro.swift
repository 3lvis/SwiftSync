import SwiftSyncCore

@attached(extension, conformances: SyncUpdatableModel, names: named(SyncID), named(syncIdentity), named(syncIdentityRemoteKeys), named(make), named(apply))
public macro Syncable() = #externalMacro(module: "SwiftSyncMacrosImplementation", type: "SyncableMacro")

@attached(peer)
public macro PrimaryKey(remote: String? = nil) = #externalMacro(module: "SwiftSyncMacrosImplementation", type: "PrimaryKeyMacro")
