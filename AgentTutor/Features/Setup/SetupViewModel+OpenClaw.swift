import Foundation

extension SetupViewModel {
    var canInstallOpenClaw: Bool {
        if case .running = openClawInstallStatus {
            return false
        }
        return true
    }

    func installOpenClawStep() {
        guard stage == .openClaw else { return }
        guard canInstallOpenClaw else { return }

        openClawInstallStatus = .running
        userNotice = ""

        Task {
            await logger.log(level: .info, message: "openclaw_step_started")

            let checks: [(name: String, command: String)] = [
                ("openclaw-cli formula", "brew list openclaw-cli >/dev/null 2>&1"),
                ("openclaw cask", "brew list --cask openclaw >/dev/null 2>&1 || [ -d '/Applications/OpenClaw.app' ]"),
            ]

            var missingTargets: Set<String> = []

            for check in checks {
                appendLog("Check: \(check.name)")
                appendLog("$ \(check.command)")
                let result = await shell.run(
                    command: check.command,
                    authMode: .standard,
                    timeoutSeconds: 120
                )
                appendLog(result.combinedOutput)
                if result.exitCode != 0 {
                    missingTargets.insert(check.name)
                }
            }

            let installCommands: [(name: String, command: String)] = [
                ("openclaw-cli formula", "brew install openclaw-cli"),
                ("openclaw cask", "brew install --cask openclaw"),
            ]

            for command in installCommands where missingTargets.contains(command.name) {
                appendLog("$ \(command.command)")
                let result = await shell.run(
                    command: command.command,
                    authMode: .standard,
                    timeoutSeconds: 1200
                )
                appendLog(result.combinedOutput)

                if result.exitCode != 0 {
                    openClawInstallStatus = .failed("OpenClaw install failed.")
                    userNotice = "OpenClaw installation failed. You can retry or skip."
                    await logger.log(level: .error, message: "openclaw_step_failed", metadata: [
                        "command": command.command,
                        "exit_code": String(result.exitCode),
                    ])
                    return
                }
            }

            openClawInstallStatus = .succeeded
            navigationDirection = .forward
            stage = .completion
            userNotice = "OpenClaw installed successfully."
            await logger.log(level: .info, message: "openclaw_step_completed")
        }
    }

    func skipOpenClawStep() {
        guard stage == .openClaw else { return }
        navigationDirection = .forward
        stage = .completion
        userNotice = "Skipped OpenClaw installation."

        Task {
            await logger.log(level: .warning, message: "openclaw_step_skipped")
        }
    }
}
