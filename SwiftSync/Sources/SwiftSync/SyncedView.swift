import SwiftData
import SwiftUI

/// Renders a `SyncedResults` declaratively: `content` when there are rows; otherwise `loading` /
/// `failure` / `empty` based on the sync `phase`. Pair with `@SyncedQuery` and a screen's
/// loading/error/empty plumbing disappears.
///
///     SyncedView($projects) { rows in
///         List(rows) { … }
///     } loading: { ProgressView() }
///       failure: { message in Text(message) }
///       empty:   { Text("No projects yet") }
public struct SyncedView<Model: PersistentModel, Content: View, Loading: View, Failure: View, Empty: View>: View {
    private let results: SyncedResults<Model>
    private let content: ([Model]) -> Content
    private let loading: () -> Loading
    private let failure: (String) -> Failure
    private let empty: () -> Empty

    public init(
        _ results: SyncedResults<Model>,
        @ViewBuilder content: @escaping ([Model]) -> Content,
        @ViewBuilder loading: @escaping () -> Loading,
        @ViewBuilder failure: @escaping (String) -> Failure,
        @ViewBuilder empty: @escaping () -> Empty
    ) {
        self.results = results
        self.content = content
        self.loading = loading
        self.failure = failure
        self.empty = empty
    }

    public var body: some View {
        if !results.rows.isEmpty {
            content(results.rows)
        } else {
            switch results.phase {
            case .idle, .loading:
                loading()
            case .failed(let message):
                failure(message)
            case .loaded:
                empty()
            }
        }
    }
}
