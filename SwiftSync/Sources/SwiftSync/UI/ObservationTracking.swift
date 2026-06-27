import Dispatch
import Observation

extension SwiftSync {
    /// Run `update`, tracking the `@Observable` values it reads, then re-run it on the next change —
    /// continuously. Bridges Observation to imperative callers (a UIKit controller, or a machine mirroring
    /// observable state) that can't lean on SwiftUI's automatic view-body tracking.
    @MainActor
    public static func observeContinuously(_ update: @escaping @MainActor () -> Void) {
        withObservationTracking {
            update()
        } onChange: {
            DispatchQueue.main.async {
                SwiftSync.observeContinuously(update)
            }
        }
    }
}
