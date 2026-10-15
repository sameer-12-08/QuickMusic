import Foundation

/// Tiny measuring helper. It prints nothing unless you start the app like this:
///
///     QUICKFLAC_STATS=1 .build/release/QuickFLAC
///
/// It measures from the start of our own setup code to the first time the window
/// appears. (Process start-up before that, usually a few dozen milliseconds, is not included.)
enum Diagnostics {
    private static let startTime = Date()

    /// Call as early as possible; a Swift `static let` only gets its value the first time it is touched.
    static func markStart() {
        _ = startTime
    }

    static func logWindowReady() {
        guard ProcessInfo.processInfo.environment["QUICKFLAC_STATS"] != nil else { return }
        let milliseconds = Date().timeIntervalSince(startTime) * 1000
        let line = String(format: "[stats] window ready %.0f ms after app init\n", milliseconds)
        FileHandle.standardError.write(Data(line.utf8))
    }
}
