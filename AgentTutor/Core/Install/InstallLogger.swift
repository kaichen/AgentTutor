import Foundation

enum LogLevel: String, Sendable {
    case info
    case warning
    case error
}

struct LogEntry: Codable, Sendable {
    let timestamp: String
    let level: String
    let message: String
    let metadata: [String: String]
}

actor InstallLogger {
    nonisolated let logFileURL: URL
    private let encoder = JSONEncoder()

    init(fileManager: FileManager = .default, now: Date = Date()) {
        encoder.outputFormatting = [.withoutEscapingSlashes]

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: now).replacingOccurrences(of: ":", with: "-")

        let appSupportBase = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())

        let logsDirectory = appSupportBase
            .appendingPathComponent("AgentTutor", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
            logFileURL = logsDirectory.appendingPathComponent("session-\(stamp).jsonl")
            if !fileManager.fileExists(atPath: logFileURL.path) {
                fileManager.createFile(atPath: logFileURL.path, contents: Data())
            }
        } catch {
            let fallback = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("AgentTutor-session-\(stamp).jsonl")
            logFileURL = fallback
            if !fileManager.fileExists(atPath: fallback.path) {
                fileManager.createFile(atPath: fallback.path, contents: Data())
            }
        }
    }

    func log(level: LogLevel, message: String, metadata: [String: String] = [:]) {
        let entry = LogEntry(
            timestamp: ISO8601DateFormatter().string(from: Date()),
            level: level.rawValue,
            message: message,
            metadata: metadata
        )

        guard
            let jsonData = try? encoder.encode(entry),
            var line = String(data: jsonData, encoding: .utf8)
        else {
            return
        }

        line.append("\n")
        guard let lineData = line.data(using: .utf8) else {
            return
        }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: lineData)
            } catch {
                // Drop log write errors to avoid blocking setup flow.
            }
        }
    }

    func readLogContents() -> String {
        guard let data = try? Data(contentsOf: logFileURL) else {
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
