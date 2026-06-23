public struct SyncRelationshipOperations: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let insert = SyncRelationshipOperations(rawValue: 1 << 0)
    public static let update = SyncRelationshipOperations(rawValue: 1 << 1)
    public static let delete = SyncRelationshipOperations(rawValue: 1 << 2)
    public static let all: SyncRelationshipOperations = [.insert, .update, .delete]
}
