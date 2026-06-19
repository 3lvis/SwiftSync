import Foundation
import SwiftData

extension SwiftSync {
    /// A model opts into offline round-trip by marking its identity `@Attribute(.preserveValueOnDeletion)`
    /// — which offline genuinely requires (to recover a deleted row's id from its history tombstone) and
    /// which is a harmless no-op otherwise. Its presence is therefore the offline signal: when set, the
    /// pull honors pending local edits and preserves never-pushed local inserts; when absent, the pull
    /// keeps plain "server is authoritative" semantics.
    static func identityPreservesValueOnDeletion<Model: SyncModelable>(
        _: Model.Type, in context: ModelContext
    ) -> Bool {
        let identityName = Model.syncIdentityPropertyName
        guard !identityName.isEmpty else { return false }
        guard
            let attribute = context.container.schema
                .entities.first(where: { $0.name == String(describing: Model.self) })?
                .attributesByName[identityName]
        else { return false }
        return attribute.options.contains(.preserveValueOnDeletion)
    }

    /// Offline push/pending requires the identity to be `.preserveValueOnDeletion` — otherwise a
    /// deleted row's id can't be recovered from history and its deletion would be silently lost. Fail
    /// loudly and actionably rather than dropping deletes.
    static func requireOfflineCapable<Model: SyncModelable>(_: Model.Type, in context: ModelContext) throws {
        guard identityPreservesValueOnDeletion(Model.self, in: context) else {
            throw SyncError.schemaValidation(
                reason: """
                    \(String(reflecting: Model.self)) is used with offline push, but its identity \
                    ("\(Model.syncIdentityPropertyName)") is not marked @Attribute(.preserveValueOnDeletion). \
                    Add that option to the identity so deletions can be recovered from store history and pushed.
                    """)
        }
    }
}
