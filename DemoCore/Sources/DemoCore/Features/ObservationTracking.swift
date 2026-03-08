import Dispatch
import Observation

@MainActor
public func observeContinuously(_ update: @escaping @MainActor () -> Void) {
    withObservationTracking {
        update()
    } onChange: {
        DispatchQueue.main.async {
            observeContinuously(update)
        }
    }
}
