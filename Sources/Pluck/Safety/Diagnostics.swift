import Foundation

/// Tiny append-only log of why gestures begin and end (`~/Library/Logs/Pluck/gesture.log`), so "it snapped back
/// on its own" can be answered from facts: which trigger, how long, how far, and what ended it.
///
/// Off unless the person turns it on (Settings > General). It records timings and reasons only: never what is on the
/// screen, what was typed, or what is on the clipboard. Nothing is ever sent anywhere.
enum Diagnostics {
    private static let enabledKey = "pluck.diagnosticLog"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var logURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Pluck/gesture.log")
    }

    private static let queue = DispatchQueue(label: "pluck.diagnostics")
    private static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Pluck")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("gesture.log")
    }()

    static func log(_ message: String) {
        guard enabled else { return }
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        queue.async {
            // Keep it small: start over once it passes ~200 KB.
            if let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int), size > 200_000 {
                try? FileManager.default.removeItem(at: url)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
