import SwiftSync
import SwiftUI
import UIKit

struct UserTasksScreen: View {

    let user: User
    let syncContainer: SyncContainer

    var body: some View {
        _UserTasksRepresentable(user: user, syncContainer: syncContainer)
            .navigationTitle(user.displayName)
            .navigationBarTitleDisplayMode(.inline)
    }
}

private struct _UserTasksRepresentable: UIViewControllerRepresentable {

    let user: User
    let syncContainer: SyncContainer

    func makeUIViewController(context: Context) -> UserTasksViewController {
        UserTasksViewController(user: user, syncContainer: syncContainer)
    }

    func updateUIViewController(_ uiViewController: UserTasksViewController, context: Context) {}
}
