public protocol SyncPayloadConvertible: Sendable {
    func toSyncPayloadDictionary() -> [String: Any]
}
