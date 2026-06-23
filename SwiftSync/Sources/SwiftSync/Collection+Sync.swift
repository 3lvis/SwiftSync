import Foundation
import SwiftData

extension Array where Element: Hashable {
    func syncDedupedPreservingOrder() -> [Element] {
        var seen: Set<Element> = []
        var output: [Element] = []
        for element in self where seen.insert(element).inserted {
            output.append(element)
        }
        return output
    }
}

extension Sequence where Element: PersistentModel {
    var syncModelIDSet: Set<PersistentIdentifier> {
        Set(map(\.persistentModelID))
    }
}
