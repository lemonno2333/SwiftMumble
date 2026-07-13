import Foundation

public final class AudioDiagnostics: @unchecked Sendable {
    public static let shared = AudioDiagnostics()

    private let queue = DispatchQueue(label: "com.leo.SwiftMumble.audioDiagnostics", qos: .utility)
    public let logURL: URL

    private init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/SwiftMumble", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        logURL = directory.appendingPathComponent("audio-diagnostics.log")
    }

    public func beginSession() {
        queue.async { [logURL] in
            try? Data().write(to: logURL, options: .atomic)
            Self.append("diagnostics session started", to: logURL)
        }
    }

    public func record(_ message: String) {
        queue.async { [logURL] in Self.append(message, to: logURL) }
    }

    private static func append(_ message: String, to url: URL) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let uptime = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        let line = "\(timestamp) uptime=\(uptime) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
