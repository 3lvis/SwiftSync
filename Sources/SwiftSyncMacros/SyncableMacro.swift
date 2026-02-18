import SwiftSyncCore

@attached(extension, conformances: SyncUpdatableModel, names: named(SyncID), named(syncIdentity), named(make), named(apply))
public macro Syncable() = #externalMacro(module: "SwiftSyncMacrosImplementation", type: "SyncableMacro")
