import Foundation

enum CommandSafety {
    static let blockedSubstrings: [String] = [
        "rm -rf /",
        "sudo rm -rf",
        "mkfs",
        "diskutil erase",
        "dd if=",
        "shutdown -h",
        "reboot",
        "launchctl unload",
        "| sh",
        "| bash"
    ]

    static func isAllowed(_ command: String) -> Bool {
        let lowered = command.lowercased()
        return !blockedSubstrings.contains(where: { lowered.contains($0) })
    }
}

struct ShellExecutionResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
    let timedOut: Bool

    var combinedOutput: String {
        let joined = [stdout, stderr]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return joined.isEmpty ? "(no output)" : joined
    }
}

protocol ShellExecuting: Sendable {
    func run(command: String, requiresAdmin: Bool, timeoutSeconds: TimeInterval) async -> ShellExecutionResult
}

final class ShellExecutor: ShellExecuting {
    private let pathPrefix = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; "

    func run(command: String, requiresAdmin: Bool, timeoutSeconds: TimeInterval) async -> ShellExecutionResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: self.runSync(command: command, requiresAdmin: requiresAdmin, timeoutSeconds: timeoutSeconds))
            }
        }
    }

    private func runSync(command: String, requiresAdmin: Bool, timeoutSeconds: TimeInterval) -> ShellExecutionResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        if requiresAdmin {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", appleScript(for: pathPrefix + command)]
        } else {
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-lc", pathPrefix + command]
        }

        do {
            try process.run()
        } catch {
            return ShellExecutionResult(
                exitCode: -1,
                stdout: "",
                stderr: "Failed to run command: \(error.localizedDescription)",
                timedOut: false
            )
        }

        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            finished.signal()
        }

        let timeout = DispatchTime.now() + timeoutSeconds
        let didTimeout = finished.wait(timeout: timeout) == .timedOut
        if didTimeout {
            process.terminate()
            _ = finished.wait(timeout: .now() + 2)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ShellExecutionResult(
            exitCode: didTimeout ? -2 : process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: didTimeout
        )
    }

    private func appleScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return "do shell script \"\(escaped)\" with administrator privileges"
    }
}
