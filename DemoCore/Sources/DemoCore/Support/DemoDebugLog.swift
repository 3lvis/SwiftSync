import Foundation

enum DemoDebugLog {
    static func emit(_ category: String, _ message: @autoclosure () -> String) {
        let timestamp = String(format: "%.3f", Date().timeIntervalSince1970)
        print("[DemoDebug][\(timestamp)][\(category)] \(message())")
    }
}
