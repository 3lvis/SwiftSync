import Foundation
import SwiftData

/// Cycle-detection state for recursive relationship export.
/// This type is an implementation detail of `@Syncable`-generated code.
/// Do not instantiate or reference it directly.
public enum ExportState {
    private static let threadDictionaryKey = "SwiftSync.ExportState"

    /// Returns false if already visiting (cycle detected).
    public static func enter<Model: PersistentModel>(_ model: Model) -> Bool {
        let key = String(describing: model.persistentModelID)
        var visiting = currentVisiting()
        if visiting.contains(key) { return false }
        visiting.insert(key)
        saveVisiting(visiting)
        return true
    }

    public static func leave<Model: PersistentModel>(_ model: Model) {
        let key = String(describing: model.persistentModelID)
        var visiting = currentVisiting()
        visiting.remove(key)
        saveVisiting(visiting)
    }

    private static func currentVisiting() -> Set<String> {
        (Thread.current.threadDictionary[threadDictionaryKey] as? ExportStateBox)?.visiting ?? []
    }

    private static func saveVisiting(_ visiting: Set<String>) {
        Thread.current.threadDictionary[threadDictionaryKey] = ExportStateBox(visiting)
    }
}

private final class ExportStateBox {
    var visiting: Set<String>
    init(_ visiting: Set<String>) { self.visiting = visiting }
}
