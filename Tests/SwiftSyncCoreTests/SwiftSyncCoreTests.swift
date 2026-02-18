import Testing
@testable import SwiftSyncCore

struct SwiftSyncCoreTests {
    @Test("SyncOptions defaults remain stable")
    func syncOptionsDefaults() {
        let options = SyncOptions()
        #expect(options.batchSize == 500)
        #expect(options.dryRun == false)
    }

    @Test("DeleteScope descriptors remain stable")
    func deleteScopeDescriptors() {
        #expect(DeleteScope.none.descriptor == "none")
        #expect(DeleteScope.byRemoteQuery("users:index").descriptor == "remoteQuery:users:index")
        #expect(DeleteScope.byPredicateDescription("team == 1").descriptor == "predicate:team == 1")
    }
}
