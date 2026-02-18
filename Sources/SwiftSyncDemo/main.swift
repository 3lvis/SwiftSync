import Foundation
import SwiftData
import SwiftSyncCore
import SwiftSyncSwiftData
import SwiftSyncTesting

@Model
final class DemoUser {
    @Attribute(.unique) var id: Int
    var name: String
    var email: String
    var createdAt: Date

    init(id: Int, name: String, email: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.email = email
        self.createdAt = createdAt
    }
}

@main
struct SwiftSyncDemo {
    static func main() async {
        do {
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: DemoUser.self, configurations: configuration)
            let context = ModelContext(container)

            try await SwiftSync.sync(
                payload: SwiftSyncFixtures.usersPayload,
                as: DemoUser.self,
                in: context,
                options: SyncOptions(mode: .upsertOnly, dryRun: true)
            )
            print("Sync completed")
        } catch {
            fputs("SwiftSyncDemo failed: \(error)\n", stderr)
        }
    }
}
