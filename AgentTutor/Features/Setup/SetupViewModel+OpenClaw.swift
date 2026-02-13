import Foundation

extension SetupViewModel {
    private struct OpenClawCommandFailure {
        let userMessage: String
        let commandLabel: String
        let command: String
        let result: ShellExecutionResult
    }

    private struct TelegramChannelConfig: Encodable {
        let enabled: Bool
        let botToken: String
    }

    private struct SlackChannelConfig: Encodable {
        let enabled: Bool
        let botToken: String
        let appToken: String?
        let mode: String?
        let signingSecret: String?
    }

    private struct FeishuChannelConfig: Encodable {
        let enabled: Bool
        let appId: String
        let appSecret: String
        let domain: String
    }

    private struct TelegramChannelConfigSnapshot: Decodable {
        let enabled: Bool?
        let botToken: String?
    }

    private struct SlackChannelConfigSnapshot: Decodable {
        let enabled: Bool?
        let botToken: String?
        let appToken: String?
        let mode: String?
        let signingSecret: String?
    }

    private struct FeishuChannelConfigSnapshot: Decodable {
        let enabled: Bool?
        let appId: String?
        let appSecret: String?
        let domain: String?
    }

    var canInstallOpenClaw: Bool {
        if case .running = openClawInstallStatus {
            return false
        }
        if isCheckingOpenClawExistingInstall || !openClawPrecheckCompleted {
            return false
        }
        return openClawValidationErrors.isEmpty
    }

    var canSkipOpenClawStep: Bool {
        !isCheckingOpenClawExistingInstall && openClawPrecheckCompleted
    }

    var shouldShowOpenClawInitializeButton: Bool {
        guard stage == .openClaw else {
            return false
        }
        if case .idle = openClawInstallStatus,
           openClawPrecheckCompleted,
           !isCheckingOpenClawExistingInstall,
           openClawExistingInstallDetected {
            return false
        }
        return true
    }

    var openClawValidationErrors: [String] {
        var errors: [String] = []
        let key1 = normalizedOpenClawValue(apiKey)

        if key1.isEmpty {
            errors.append("key1 is required to initialize OpenClaw.")
        }
        if !apiProvider.supportsOpenClawNonInteractiveOnboard {
            errors.append("Provider \(apiProvider.displayName) from API Key step is not supported for non-interactive OpenClaw onboarding.")
        }
        if openClawSelectedChannels.contains(.telegram),
           !isOpenClawChannelConfigured(.telegram),
           normalizedOpenClawValue(openClawTelegramBotToken).isEmpty {
            errors.append("Telegram bot token is required.")
        }
        if openClawSelectedChannels.contains(.slack) {
            if !isOpenClawChannelConfigured(.slack), normalizedOpenClawValue(openClawSlackBotToken).isEmpty {
                errors.append("Slack bot token is required.")
            }
            switch openClawSlackMode {
            case .socket:
                if !isOpenClawChannelConfigured(.slack), normalizedOpenClawValue(openClawSlackAppToken).isEmpty {
                    errors.append("Slack app token is required for Socket mode.")
                }
            case .http:
                if !isOpenClawChannelConfigured(.slack), normalizedOpenClawValue(openClawSlackSigningSecret).isEmpty {
                    errors.append("Slack signing secret is required for HTTP mode.")
                }
            }
        }
        if openClawSelectedChannels.contains(.feishu) {
            if !isOpenClawChannelConfigured(.feishu), normalizedOpenClawValue(openClawFeishuAppID).isEmpty {
                errors.append("Feishu app ID is required.")
            }
            if !isOpenClawChannelConfigured(.feishu), normalizedOpenClawValue(openClawFeishuAppSecret).isEmpty {
                errors.append("Feishu app secret is required.")
            }
        }

        return errors
    }

    var openClawProviderSupportMessage: String {
        guard apiProvider.supportsOpenClawNonInteractiveOnboard else {
            return "Provider \(apiProvider.displayName) from API Key step cannot be used for non-interactive OpenClaw onboarding."
        }
        return "OpenClaw will use \(apiProvider.displayName) provider and key1 from API Key step."
    }

    var isOpenClawProviderConfigured: Bool {
        apiProvider.supportsOpenClawNonInteractiveOnboard
    }

    func isOpenClawChannelSelected(_ channel: OpenClawChannel) -> Bool {
        openClawSelectedChannels.contains(channel)
    }

    func isOpenClawChannelConfigured(_ channel: OpenClawChannel) -> Bool {
        openClawConfiguredChannels.contains(channel)
    }

    func setOpenClawChannel(_ channel: OpenClawChannel, selected: Bool) {
        guard !isOpenClawChannelConfigured(channel) else {
            openClawSelectedChannels.insert(channel)
            return
        }
        if selected {
            openClawSelectedChannels.insert(channel)
        } else {
            openClawSelectedChannels.remove(channel)
        }
    }

    func refreshOpenClawExistingInstallStatus() {
        guard stage == .openClaw else { return }
        if case .running = openClawInstallStatus {
            return
        }
        guard !isCheckingOpenClawExistingInstall else {
            return
        }

        openClawInstallDetectionTask?.cancel()
        openClawPrecheckCompleted = false
        isCheckingOpenClawExistingInstall = true
        openClawInstallDetectionTask = Task {
            defer {
                isCheckingOpenClawExistingInstall = false
                openClawInstallDetectionTask = nil
                if !Task.isCancelled {
                    openClawPrecheckCompleted = true
                }
            }
            let isInstalled = await hasHealthyOpenClawGateway()
            guard !Task.isCancelled else { return }
            openClawExistingInstallDetected = isInstalled
            if isInstalled {
                let configuredChannels = await detectConfiguredOpenClawChannels()
                guard !Task.isCancelled else { return }
                let previouslyConfiguredChannels = openClawConfiguredChannels
                openClawConfiguredChannels = configuredChannels
                openClawSelectedChannels.subtract(previouslyConfiguredChannels.subtracting(configuredChannels))
                openClawSelectedChannels.formUnion(configuredChannels)
                return
            }
            openClawSelectedChannels.subtract(openClawConfiguredChannels)
            openClawConfiguredChannels = []
        }
    }

    func installOpenClawStep() {
        guard stage == .openClaw else { return }
        if case .running = openClawInstallStatus {
            return
        }
        guard !isCheckingOpenClawExistingInstall, openClawPrecheckCompleted else {
            userNotice = "OpenClaw environment check is not complete yet. Please wait."
            return
        }

        let validationErrors = openClawValidationErrors
        guard validationErrors.isEmpty else {
            let message = validationErrors[0]
            openClawInstallStatus = .failed(message)
            userNotice = message
            return
        }
        guard let onboardAuth = apiProvider.openClawOnboardAuth else {
            let message = "Provider \(apiProvider.displayName) from API Key step cannot be used for non-interactive OpenClaw onboarding."
            openClawInstallStatus = .failed(message)
            userNotice = message
            return
        }

        openClawInstallStatus = .running
        userNotice = ""
        let onboardingAPIKey = normalizedOpenClawValue(apiKey)

        Task {
            await logger.log(level: .info, message: "openclaw_setup_started", metadata: [
                "provider": apiProvider.rawValue,
                "key_source": "key1",
                "selected_channels": String(openClawSelectedChannels.count),
            ])

            if let failure = await ensureOpenClawInstalled() {
                await handleOpenClawFailure(failure)
                return
            }

            if await shouldSkipOpenClawOnboard() {
                openClawInstallStatus = .succeeded
                navigationDirection = .forward
                stage = .completion
                userNotice = "OpenClaw onboarding already completed. Skipping initialization."
                await logger.log(level: .info, message: "openclaw_setup_skipped_existing")
                return
            }

            if let failure = await runOpenClawOnboard(auth: onboardAuth, apiKey: onboardingAPIKey) {
                await handleOpenClawFailure(failure)
                return
            }

            if let failure = await configureOpenClawChannelsIfNeeded() {
                await handleOpenClawFailure(failure)
                return
            }

            openClawInstallStatus = .succeeded
            navigationDirection = .forward
            stage = .completion
            userNotice = openClawSelectedChannels.isEmpty
                ? "OpenClaw initialized successfully."
                : "OpenClaw initialized and channel configuration applied."
            await logger.log(level: .info, message: "openclaw_setup_completed")
        }
    }

    func skipOpenClawStep() {
        guard stage == .openClaw else { return }
        guard canSkipOpenClawStep else {
            userNotice = "OpenClaw environment check is not complete yet. Please wait."
            return
        }
        navigationDirection = .forward
        stage = .completion
        userNotice = "Skipped OpenClaw setup."

        Task {
            await logger.log(level: .warning, message: "openclaw_step_skipped")
        }
    }

    private func ensureOpenClawInstalled() async -> OpenClawCommandFailure? {
        let checks: [(name: String, command: String, installCommand: String)] = [
            (
                "openclaw-cli formula",
                "brew list openclaw-cli >/dev/null 2>&1",
                "brew install openclaw-cli"
            ),
            (
                "openclaw cask",
                "brew list --cask openclaw >/dev/null 2>&1 || [ -d '/Applications/OpenClaw.app' ]",
                "brew install --cask openclaw"
            ),
        ]

        for check in checks {
            appendLog("Check: \(check.name)")
            let checkResult = await runOpenClawCommand(
                check.command,
                timeoutSeconds: 120
            )
            if checkResult.exitCode == 0 {
                continue
            }

            let installResult = await runOpenClawCommand(
                check.installCommand,
                timeoutSeconds: 1200
            )
            if installResult.exitCode != 0 {
                return OpenClawCommandFailure(
                    userMessage: "OpenClaw installation failed.",
                    commandLabel: "install_\(check.name)",
                    command: check.installCommand,
                    result: installResult
                )
            }
        }

        return nil
    }

    private func shouldSkipOpenClawOnboard() async -> Bool {
        let isInstalled = await hasHealthyOpenClawGateway()
        openClawExistingInstallDetected = isInstalled
        return isInstalled
    }

    private func hasHealthyOpenClawGateway() async -> Bool {
        appendLog("Checking OpenClaw process...")
        let processResult = await runOpenClawCommand(
            "pgrep -f '[o]penclaw' >/dev/null 2>&1",
            timeoutSeconds: 20
        )
        guard processResult.exitCode == 0 else {
            return false
        }

        appendLog("Checking existing OpenClaw gateway status...")
        let gatewayStatusResult = await runOpenClawCommand(
            "openclaw gateway status",
            timeoutSeconds: 120
        )
        guard gatewayStatusResult.exitCode == 0 else {
            return false
        }

        return isOpenClawGatewayHealthy(gatewayStatusResult.combinedOutput)
    }

    private func isOpenClawGatewayHealthy(_ output: String) -> Bool {
        let loweredOutput = output.lowercased()
        let unhealthySignals = ["not running", "down", "stopped", "inactive", "unhealthy", "failed", "error"]
        if unhealthySignals.contains(where: { loweredOutput.contains($0) }) {
            return false
        }

        let healthySignals = ["running", "normal", "healthy", "ready", "active", "ok"]
        return healthySignals.contains(where: { loweredOutput.contains($0) })
    }

    private func runOpenClawOnboard(auth: OpenClawAuthConfiguration, apiKey: String) async -> OpenClawCommandFailure? {
        let command = [
            "openclaw onboard --non-interactive --accept-risk",
            "--mode local",
            "--auth-choice \(auth.choice)",
            "\(auth.apiKeyFlag) \(ShellEscaping.singleQuoted(apiKey))",
        ].joined(separator: " ")
        let redactedCommand = [
            "openclaw onboard --non-interactive --accept-risk",
            "--mode local",
            "--auth-choice \(auth.choice)",
            "\(auth.apiKeyFlag) '<redacted>'",
        ].joined(separator: " ")

        let result = await runOpenClawCommand(
            command,
            redactedCommand: redactedCommand,
            timeoutSeconds: 300,
            containsSensitiveData: true
        )
        guard result.exitCode == 0 else {
            return OpenClawCommandFailure(
                userMessage: "OpenClaw onboarding failed.",
                commandLabel: "openclaw_onboard",
                command: redactedCommand,
                result: result
            )
        }
        return nil
    }

    private func configureOpenClawChannelsIfNeeded() async -> OpenClawCommandFailure? {
        let selectedChannels = OpenClawChannel.allCases.filter {
            openClawSelectedChannels.contains($0) && !isOpenClawChannelConfigured($0)
        }
        guard !selectedChannels.isEmpty else {
            if openClawSelectedChannels.isEmpty {
                appendLog("No channels selected. Skipping channel configuration.")
            } else {
                appendLog("Selected channels are already configured. Existing channel settings are read-only and were not modified.")
            }
            return nil
        }

        for channel in selectedChannels {
            let pluginCommand = "openclaw plugins enable \(channel.pluginName)"
            let pluginResult = await runOpenClawCommand(
                pluginCommand,
                timeoutSeconds: 120
            )
            if pluginResult.exitCode != 0 {
                return OpenClawCommandFailure(
                    userMessage: "Failed to enable OpenClaw plugin for \(channel.displayName).",
                    commandLabel: "plugins_enable_\(channel.rawValue)",
                    command: pluginCommand,
                    result: pluginResult
                )
            }

            guard let configJSON = openClawChannelConfigJSON(for: channel) else {
                return OpenClawCommandFailure(
                    userMessage: "Failed to build channel configuration JSON for \(channel.displayName).",
                    commandLabel: "config_payload_\(channel.rawValue)",
                    command: "openclaw config set --json \(channel.configPath) '<redacted>'",
                    result: ShellExecutionResult(
                        exitCode: -1,
                        stdout: "",
                        stderr: "Unable to encode channel configuration.",
                        timedOut: false
                    )
                )
            }

            let configCommand = "openclaw config set --json \(channel.configPath) \(ShellEscaping.singleQuoted(configJSON))"
            let redactedConfigCommand = "openclaw config set --json \(channel.configPath) '<redacted>'"
            let configResult = await runOpenClawCommand(
                configCommand,
                redactedCommand: redactedConfigCommand,
                timeoutSeconds: 120,
                containsSensitiveData: true
            )
            if configResult.exitCode != 0 {
                return OpenClawCommandFailure(
                    userMessage: "Failed to apply channel config for \(channel.displayName).",
                    commandLabel: "config_set_\(channel.rawValue)",
                    command: redactedConfigCommand,
                    result: configResult
                )
            }
        }

        let restartCommand = "openclaw gateway restart"
        let restartResult = await runOpenClawCommand(
            restartCommand,
            timeoutSeconds: 180
        )
        if restartResult.exitCode != 0 {
            return OpenClawCommandFailure(
                userMessage: "OpenClaw gateway restart failed after channel configuration.",
                commandLabel: "gateway_restart",
                command: restartCommand,
                result: restartResult
            )
        }

        let probeCommand = "openclaw channels status --probe"
        let probeResult = await runOpenClawCommand(
            probeCommand,
            timeoutSeconds: 120
        )
        if probeResult.exitCode != 0 {
            return OpenClawCommandFailure(
                userMessage: "Channel probe failed after configuration.",
                commandLabel: "channels_status_probe",
                command: probeCommand,
                result: probeResult
            )
        }

        return nil
    }

    private func detectConfiguredOpenClawChannels() async -> Set<OpenClawChannel> {
        let configuredFromConfig = await detectConfiguredOpenClawChannelsFromConfig()
        let configuredFromStatus = await detectConfiguredOpenClawChannelsFromStatus()
        return configuredFromConfig.union(configuredFromStatus)
    }

    private func detectConfiguredOpenClawChannelsFromConfig() async -> Set<OpenClawChannel> {
        var configuredChannels: Set<OpenClawChannel> = []

        for channel in OpenClawChannel.allCases {
            let command = "openclaw config get --json \(channel.configPath)"
            let result = await runOpenClawCommand(
                command,
                redactedCommand: command,
                timeoutSeconds: 120,
                containsSensitiveData: true
            )
            guard result.exitCode == 0 else {
                continue
            }
            if isOpenClawChannelConfiguredFromConfig(channel, output: result.stdout) {
                configuredChannels.insert(channel)
            }
        }

        return configuredChannels
    }

    private func detectConfiguredOpenClawChannelsFromStatus() async -> Set<OpenClawChannel> {
        let statusResult = await runOpenClawCommand(
            "openclaw channels status --probe",
            timeoutSeconds: 120
        )
        guard statusResult.exitCode == 0 else {
            return []
        }

        let output = statusResult.combinedOutput.lowercased()
        let healthyTokens = ["enabled", "ready", "running", "connected", "healthy", "active", "ok"]
        let unhealthyTokens = ["disabled", "not configured", "unconfigured", "missing", "error", "failed", "down", "inactive", "stopped"]
        var configuredChannels: Set<OpenClawChannel> = []

        for channel in OpenClawChannel.allCases {
            let linesForChannel = output
                .split(whereSeparator: \.isNewline)
                .filter { $0.contains(channel.rawValue) }
            guard !linesForChannel.isEmpty else {
                continue
            }

            let mergedLine = linesForChannel.map(String.init).joined(separator: " ")
            if unhealthyTokens.contains(where: { mergedLine.contains($0) }) {
                continue
            }
            if healthyTokens.contains(where: { mergedLine.contains($0) }) {
                configuredChannels.insert(channel)
            }
        }

        return configuredChannels
    }

    private func isOpenClawChannelConfiguredFromConfig(_ channel: OpenClawChannel, output: String) -> Bool {
        switch channel {
        case .telegram:
            guard let config: TelegramChannelConfigSnapshot = decodeOpenClawChannelConfig(from: output) else {
                return false
            }
            guard config.enabled == true else {
                return false
            }
            return !(config.botToken?.isEmpty ?? true)
        case .slack:
            guard let config: SlackChannelConfigSnapshot = decodeOpenClawChannelConfig(from: output) else {
                return false
            }
            guard config.enabled == true else {
                return false
            }
            guard !(config.botToken?.isEmpty ?? true) else {
                return false
            }
            if !(config.appToken?.isEmpty ?? true) {
                return true
            }
            if !(config.signingSecret?.isEmpty ?? true) {
                return true
            }
            return config.mode?.lowercased() != "http"
        case .feishu:
            guard let config: FeishuChannelConfigSnapshot = decodeOpenClawChannelConfig(from: output) else {
                return false
            }
            guard config.enabled == true else {
                return false
            }
            return !(config.appId?.isEmpty ?? true) &&
                !(config.appSecret?.isEmpty ?? true) &&
                !(config.domain?.isEmpty ?? true)
        }
    }

    private func decodeOpenClawChannelConfig<T: Decodable>(from output: String) -> T? {
        guard let payload = openClawJSONPayload(from: output),
              let data = payload.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func openClawJSONPayload(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "{", trimmed.last == "}" {
            return trimmed
        }
        guard let firstBrace = trimmed.firstIndex(of: "{"),
              let lastBrace = trimmed.lastIndex(of: "}"),
              firstBrace <= lastBrace else {
            return nil
        }
        return String(trimmed[firstBrace...lastBrace])
    }

    private func openClawChannelConfigJSON(for channel: OpenClawChannel) -> String? {
        switch channel {
        case .telegram:
            return encodedOpenClawJSON(
                TelegramChannelConfig(
                    enabled: true,
                    botToken: normalizedOpenClawValue(openClawTelegramBotToken)
                )
            )
        case .slack:
            let botToken = normalizedOpenClawValue(openClawSlackBotToken)
            switch openClawSlackMode {
            case .socket:
                return encodedOpenClawJSON(
                    SlackChannelConfig(
                        enabled: true,
                        botToken: botToken,
                        appToken: normalizedOpenClawValue(openClawSlackAppToken),
                        mode: nil,
                        signingSecret: nil
                    )
                )
            case .http:
                return encodedOpenClawJSON(
                    SlackChannelConfig(
                        enabled: true,
                        botToken: botToken,
                        appToken: nil,
                        mode: openClawSlackMode.rawValue,
                        signingSecret: normalizedOpenClawValue(openClawSlackSigningSecret)
                    )
                )
            }
        case .feishu:
            return encodedOpenClawJSON(
                FeishuChannelConfig(
                    enabled: true,
                    appId: normalizedOpenClawValue(openClawFeishuAppID),
                    appSecret: normalizedOpenClawValue(openClawFeishuAppSecret),
                    domain: openClawFeishuDomain.rawValue
                )
            )
        }
    }

    private func encodedOpenClawJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func runOpenClawCommand(
        _ command: String,
        redactedCommand: String? = nil,
        timeoutSeconds: TimeInterval,
        containsSensitiveData: Bool = false
    ) async -> ShellExecutionResult {
        appendLog("$ \(redactedCommand ?? command)")
        let result = await shell.run(
            command: command,
            authMode: .standard,
            timeoutSeconds: timeoutSeconds
        )
        if containsSensitiveData {
            if result.exitCode == 0 {
                appendLog("Sensitive command completed. Output is redacted.")
            } else {
                appendLog("Sensitive command failed. Output is redacted.")
            }
        } else {
            appendLog(result.combinedOutput)
        }
        return result
    }

    private func handleOpenClawFailure(_ failure: OpenClawCommandFailure) async {
        openClawInstallStatus = .failed(failure.userMessage)
        userNotice = "\(failure.userMessage) You can retry or skip."
        await logger.log(level: .error, message: "openclaw_step_failed", metadata: [
            "label": failure.commandLabel,
            "command": failure.command,
            "exit_code": String(failure.result.exitCode),
        ])
    }

    private func normalizedOpenClawValue(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
