import SwiftSync
import SwiftUI
import UIKit

/// SwiftUI wrapper that embeds `UserTasksViewController` in a navigation stack.
///
/// Usage (inside a SwiftUI `NavigationStack`):
/// ```swift
/// NavigationLink(destination: UserTasksScreen(user: user, syncContainer: syncContainer)) {
///     Text(user.displayName)
/// }
/// ```
struct UserTasksScreen: UIViewControllerRepresentable {

    let user: User
    let syncContainer: SyncContainer

    func makeUIViewController(context: Context) -> UserTasksViewController {
        UserTasksViewController(user: user, syncContainer: syncContainer)
    }

    func updateUIViewController(_ uiViewController: UserTasksViewController, context: Context) {
        // The view controller manages its own updates via SyncQueryPublisher.
        // Nothing to push from SwiftUI side.
    }
}
