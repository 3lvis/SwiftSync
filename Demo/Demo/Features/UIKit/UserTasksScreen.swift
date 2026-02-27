import SwiftSync
import SwiftUI
import UIKit

/// SwiftUI view that embeds `UserTasksViewController` and owns the navigation
/// title so SwiftUI (which controls the nav bar when hosting UIKit) renders it.
///
/// Usage (inside a SwiftUI `NavigationStack`):
/// ```swift
/// NavigationLink(destination: UserTasksScreen(user: user, syncContainer: syncContainer)) {
///     Text(user.displayName)
/// }
/// ```
struct UserTasksScreen: View {

    let user: User
    let syncContainer: SyncContainer

    var body: some View {
        _UserTasksRepresentable(user: user, syncContainer: syncContainer)
            .navigationTitle(user.displayName)
            .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - UIViewControllerRepresentable

private struct _UserTasksRepresentable: UIViewControllerRepresentable {

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
