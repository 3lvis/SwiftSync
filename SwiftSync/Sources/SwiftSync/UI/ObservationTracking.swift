import Dispatch
import Observation

extension SwiftSync {
    /// Re-runs `update` on every change to the `@Observable` values it reads — bridging Observation to
    /// imperative callers (a UIKit controller, a machine) that can't lean on SwiftUI's view-body tracking.
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
