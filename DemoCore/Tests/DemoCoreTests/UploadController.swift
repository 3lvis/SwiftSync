import DemoCore

/// Deterministic control over the engine's drain uploads. Install it on `FakeDemoAPIClient.beforeUpload`;
/// the first `parksRemaining` uploads each signal they started and park until the test releases them, and
/// every upload after that flows straight through.
///
/// Per-upload (FIFO), never a single global latch: a correct convergence drain uploads N times, so the
/// test parks only the upload(s) it needs to interleave around and lets the rest proceed — a fixed
/// upload count is never assumed (assuming one is what deadlocked earlier attempts).
@MainActor
final class UploadController {
    /// How many of the next uploads should park. Uploads beyond this flow through immediately.
    var parksRemaining: Int

    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var bufferedStarts = 0
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var bufferedReleases = 0

    init(parksRemaining: Int) {
        self.parksRemaining = parksRemaining
    }

    /// Engine side (via `beforeUpload`): if this upload should park, announce it began then suspend until
    /// released; otherwise return at once.
    func gate() async {
        guard parksRemaining > 0 else { return }
        parksRemaining -= 1

        if let waiter = startWaiters.first {
            startWaiters.removeFirst()
            waiter.resume()
        } else {
            bufferedStarts += 1
        }
        if bufferedReleases > 0 {
            bufferedReleases -= 1
            return
        }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    /// Test side: suspend until the next parked upload has begun (and is now suspended).
    func awaitUploadStart() async {
        if bufferedStarts > 0 {
            bufferedStarts -= 1
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    /// Test side: let the oldest parked upload proceed.
    func releaseNextUpload() {
        if let waiter = releaseWaiters.first {
            releaseWaiters.removeFirst()
            waiter.resume()
        } else {
            bufferedReleases += 1
        }
    }
}
