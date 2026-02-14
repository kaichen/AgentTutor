import AppKit
import Combine
import Foundation

enum NavigationDirection: Sendable {
    case forward, backward
}

@MainActor
final class SetupViewModel: ObservableObject {
    @Published var stage: SetupStage = .welcome
    @Published var navigationDirection: NavigationDirection = .forward
    @Published var apiProvider: LLMProvider = .openai
    @Published var apiKey: String = ""
    @Published var apiBaseURL: String = LLMProvider.openai.defaultBaseURL
    @Published var selectedItemIDs: Set<String>
    @Published var stepStates: [InstallStepState] = []
    @Published var runState: InstallRunState = .idle
    @Published var liveLog: [String] = []
    @Published var activeFailure: InstallFailure?
    @Published var remediationAdvice: RemediationAdvice?
    @Published var userNotice: String = ""
    @Published var showingCommandConfirmation: Bool = false
    @Published var pendingRemediationCommand: String = ""
    @Published var apiKeyValidationStatus: APIKeyValidationStatus = .idle
    @Published var gitUserName: String = ""
    @Published var gitUserEmail: String = ""
    @Published var gitConfigStatus: ActionStatus = .idle
    @Published var sshKeyState: SSHKeyState = .checking
    @Published var githubUploadStatus: ActionStatus = .idle
    @Published var openClawInstallStatus: ActionStatus = .idle
    @Published var openClawExistingInstallDetected = false
    @Published var openClawGatewayHealthy = false
    @Published var isCheckingOpenClawExistingInstall = false
    @Published var openClawPrecheckCompleted = false
    @Published var openClawConfiguredChannels: Set<OpenClawChannel> = []
    @Published var openClawSelectedChannels: Set<OpenClawChannel> = []
    @Published var openClawTelegramBotToken: String = ""
    @Published var openClawSlackBotToken: String = ""
    @Published var openClawSlackAppToken: String = ""
    @Published var openClawSlackMode: OpenClawSlackMode = .socket
    @Published var openClawSlackSigningSecret: String = ""
    @Published var openClawFeishuAppID: String = ""
    @Published var openClawFeishuAppSecret: String = ""
    @Published var openClawFeishuDomain: OpenClawFeishuDomain = .feishu
    @Published private(set) var installStartTime: Date?
    @Published private(set) var installEndTime: Date?

    let catalog: [InstallItem]
    let logger: InstallLogger

    private let planner: InstallPlanner
    let shell: ShellExecuting
    private let advisor: RemediationAdvising
    let gitSSHService: GitSSHServicing
    private let remediationCommandLauncherOverride: ((String) -> Bool)?
    private var apiKeyValidationTask: Task<Void, Never>?
    var openClawInstallDetectionTask: Task<Void, Never>?
    private var brewPackageCache: BrewPackageCache?
    private var brewPackageCacheLoaded = false
    var didPrepareGitSSHStep = false
    private let terminalPathPrefix = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\"; "

    convenience init() {
        let shell = ShellExecutor()
        self.init(
            catalog: InstallCatalog.items(for: .current),
            shell: shell,
            advisor: RemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: GitSSHService(shell: shell)
        )
    }

    init(
        catalog: [InstallItem],
        shell: ShellExecuting,
        advisor: RemediationAdvising,
        logger: InstallLogger,
        gitSSHService: GitSSHServicing? = nil,
        remediationCommandLauncher: ((String) -> Bool)? = nil
    ) {
        self.catalog = catalog
        self.shell = shell
        self.advisor = advisor
        self.logger = logger
        self.gitSSHService = gitSSHService ?? GitSSHService(shell: shell)
        self.remediationCommandLauncherOverride = remediationCommandLauncher
        self.planner = InstallPlanner(catalog: catalog)
        self.selectedItemIDs = Set(catalog.filter { $0.defaultSelected || $0.isRequired }.map(\.id))
        ensureDependenciesAndRequireds()
    }

    var selectedItemCount: Int {
        selectedItemIDs.count
    }

    var canAdvanceFromAPIKey: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canStartInstall: Bool {
        canAdvanceFromAPIKey && runState != .running
    }

    var logFilePath: String {
        logger.logFileURL.path
    }

    var installProgress: Double {
        guard !stepStates.isEmpty else { return 0 }
        let done = stepStates.filter { $0.status == .succeeded || $0.status == .failed }.count
        return Double(done) / Double(stepStates.count)
    }

    var successfulStepCount: Int {
        stepStates.filter { $0.status == .succeeded }.count
    }

    var installDurationFormatted: String {
        guard let start = installStartTime else { return "--" }
        let end = installEndTime ?? Date()
        let seconds = Int(end.timeIntervalSince(start))
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        }
        return "\(secs)s"
    }

    var completedWithoutIssues: Bool {
        runState == .completed &&
        activeFailure == nil &&
        stepStates.allSatisfy { $0.status == .succeeded }
    }

    var shouldShowCompletionLogFolderButton: Bool {
        !completedWithoutIssues
    }

    func moveNext() {
        guard let currentIndex = SetupStage.allCases.firstIndex(of: stage) else { return }
        let nextIndex = SetupStage.allCases.index(after: currentIndex)
        if nextIndex < SetupStage.allCases.endIndex {
            navigationDirection = .forward
            stage = SetupStage.allCases[nextIndex]
        }
    }

    func moveBack() {
        guard let currentIndex = SetupStage.allCases.firstIndex(of: stage), currentIndex > 0 else { return }
        navigationDirection = .backward
        stage = SetupStage.allCases[SetupStage.allCases.index(before: currentIndex)]
    }

    func isItemSelected(_ item: InstallItem) -> Bool {
        selectedItemIDs.contains(item.id)
    }

    func canToggle(_ item: InstallItem) -> Bool {
        !item.isRequired && runState != .running
    }

    func setSelection(_ selected: Bool, for item: InstallItem) {
        guard canToggle(item) else { return }
        if selected {
            selectedItemIDs.insert(item.id)
            addDependenciesRecursively(for: item.id)
        } else {
            removeItemAndDependents(item.id)
        }
        ensureDependenciesAndRequireds()
    }

    func startInstall() {
        guard canStartInstall else { return }

        runState = .validating
        userNotice = ""
        activeFailure = nil
        remediationAdvice = nil
        liveLog = []
        gitConfigStatus = .idle
        githubUploadStatus = .idle
        openClawInstallStatus = .idle
        openClawExistingInstallDetected = false
        openClawGatewayHealthy = false
        isCheckingOpenClawExistingInstall = false
        openClawPrecheckCompleted = false
        openClawConfiguredChannels = []
        openClawInstallDetectionTask?.cancel()
        sshKeyState = .checking
        didPrepareGitSSHStep = false
        navigationDirection = .forward
        installStartTime = Date()
        installEndTime = nil
        invalidateBrewPackageCache()

        Task {
            await logger.log(level: .info, message: "Install session started", metadata: ["selected_items": String(selectedItemIDs.count)])

            do {
                let plan = try planner.resolvedPlan(selectedIDs: selectedItemIDs, apiKey: apiKey)
                stepStates = plan.map { InstallStepState(item: $0) }
                runState = .running
                stage = .install
                await logger.log(level: .info, message: "Plan resolved", metadata: ["steps": String(plan.count)])

                for index in plan.indices {
                    let item = plan[index]
                    updateStep(itemID: item.id, status: .running, output: "")
                    appendLog("Starting: \(item.name)")

                    if let failure = await execute(item: item) {
                        updateStep(itemID: item.id, status: .failed, output: failure.output)
                        runState = .failed
                        installEndTime = Date()
                        activeFailure = failure
                        appendLog("Failed: \(item.name)")
                        if let authFailureMessage = adminAuthenticationFailureMessage(from: failure.output) {
                            userNotice = authFailureMessage
                        }
                        await logger.log(level: .error, message: "Step failed", metadata: [
                            "item": item.id,
                            "command": failure.failedCommand,
                            "exit_code": String(failure.exitCode)
                        ])

                        remediationAdvice = await advisor.suggest(
                            failure: failure,
                            hints: item.remediationHints,
                            apiKey: apiKey,
                            baseURL: apiBaseURL
                        )
                        return
                    }

                    updateStep(itemID: item.id, status: .succeeded, output: "Completed")
                    appendLog("Completed: \(item.name)")
                    await logger.log(level: .info, message: "Step completed", metadata: ["item": item.id])
                }

                runState = .completed
                installEndTime = Date()
                await logger.log(level: .info, message: "Install session completed")
                stage = .gitSSH
            } catch {
                runState = .failed
                userNotice = error.localizedDescription
                await logger.log(level: .error, message: "Validation failed", metadata: ["error": error.localizedDescription])
            }
        }
    }

    func restartInstall() {
        guard runState != .running else { return }
        startInstall()
    }

    func queueRemediationCommand(_ command: String) {
        pendingRemediationCommand = command
        showingCommandConfirmation = true
    }

    func executePendingRemediationCommand() {
        let command = pendingRemediationCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        guard CommandSafety.isAllowed(command) else {
            userNotice = "Blocked an unsafe command. Please review manually."
            return
        }
        showingCommandConfirmation = false

        Task {
            await logger.log(
                level: .warning,
                message: "Running user-approved remediation command in Terminal",
                metadata: ["command": command]
            )
            let launched = remediationCommandLauncherOverride?(command)
                ?? launchCommandInSystemTerminal(command)
            appendLog("$ \(command)")
            if launched {
                userNotice = "Remediation command succeeded. You can retry installation now."
                await logger.log(level: .info, message: "Remediation command launched in terminal", metadata: ["command": command])
            } else {
                userNotice = "Unable to launch Terminal for remediation command."
                await logger.log(level: .error, message: "Failed to launch terminal for remediation command", metadata: ["command": command])
            }
        }
    }

    func openOpenClawDashboard() {
        guard shouldShowOpenClawDashboardButton else {
            return
        }
        let command = "openclaw dashboard"
        let launched = remediationCommandLauncherOverride?(command)
            ?? launchCommandInSystemTerminal(command)
        appendLog("$ \(command)")
        if launched {
            userNotice = "Opening OpenClaw dashboard..."
        } else {
            userNotice = "Unable to launch Terminal for OpenClaw dashboard."
        }
    }

    private func launchCommandInSystemTerminal(_ command: String) -> Bool {
        let script = systemTerminalScript(for: terminalPathPrefix + command)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            appendLog("Failed to launch Terminal: \(error.localizedDescription)")
            return false
        }
    }

    private func systemTerminalScript(for command: String) -> String {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        return """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
    }

    func openLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([logger.logFileURL.deletingLastPathComponent()])
    }

    func onAPIKeyChanged() {
        revalidateAPIKey()
    }

    func onProviderChanged() {
        apiBaseURL = apiProvider.defaultBaseURL
        revalidateAPIKey()
    }

    func onBaseURLChanged() {
        revalidateAPIKey()
    }

    private func revalidateAPIKey() {
        apiKeyValidationTask?.cancel()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            apiKeyValidationStatus = .idle
            return
        }
        apiKeyValidationStatus = .validating
        apiKeyValidationTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            let status = await Self.checkAPIKey(key, baseURL: base)
            guard !Task.isCancelled else { return }
            apiKeyValidationStatus = status
        }
    }

    private static func checkAPIKey(_ key: String, baseURL: String) async -> APIKeyValidationStatus {
        guard let url = endpointURL(baseURL: baseURL, path: "/models") else {
            return .invalid("Invalid base URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .invalid("No response")
            }
            if http.statusCode == 200 {
                return .valid
            } else if http.statusCode == 401 {
                return .invalid("Invalid API key")
            } else {
                return .invalid("HTTP \(http.statusCode)")
            }
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    private static func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func endpointURL(baseURL: String, path: String) -> URL? {
        let normalizedBase = normalizedBaseURL(baseURL)
        guard !normalizedBase.isEmpty else {
            return nil
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: normalizedBase + normalizedPath)
    }

    private struct VerificationFailureDetail {
        let check: InstallVerificationCheck
        let result: ShellExecutionResult
    }

    private struct BrewPackageCache {
        let formulas: Set<String>
        let casks: Set<String>

        func contains(_ package: BrewPackageReference) -> Bool {
            switch package.kind {
            case .formula:
                return formulas.contains(package.name)
            case .cask:
                return casks.contains(package.name)
            }
        }
    }

    private func runVerificationChecks(for item: InstallItem, phase: String) async -> VerificationFailureDetail? {
        var firstFailure: VerificationFailureDetail?

        for check in item.verificationChecks {
            appendLog("\(phase): \(item.name) - \(check.name)")

            if let brewPackage = check.brewPackage,
               let installed = await cachedBrewPackageInstalledStatus(for: brewPackage) {
                if installed {
                    appendLog("$ \(check.command)  # skipped (cached brew list hit)")
                    appendLog("Check passed: \(check.name) (cached brew list)")
                    continue
                }
                let kindLabel = brewPackage.kind == .formula ? "formula" : "cask"
                appendLog("Cached brew list miss for \(kindLabel) '\(brewPackage.name)'. Running explicit verification command.")
            }

            appendLog("$ \(check.command)")
            let result = await shell.run(
                command: check.command,
                authMode: .standard,
                timeoutSeconds: check.timeoutSeconds
            )

            appendLog(result.combinedOutput)

            if result.exitCode != 0 {
                appendLog("Check failed: \(check.name)")
                if firstFailure == nil {
                    firstFailure = VerificationFailureDetail(check: check, result: result)
                }
                continue
            }

            appendLog("Check passed: \(check.name)")
        }

        return firstFailure
    }

    private func execute(item: InstallItem) async -> InstallFailure? {
        guard !item.verificationChecks.isEmpty else {
            return InstallFailure(
                itemID: item.id,
                itemName: item.name,
                failedCommand: "(missing verification checks)",
                output: "Configuration error: \(item.id) has no verification checks.",
                exitCode: -1,
                timedOut: false
            )
        }

        let preflightFailure = await runVerificationChecks(for: item, phase: "Check")
        if preflightFailure == nil {
            for command in item.commands {
                appendLog("$ \(command.shell)  # skipped (already installed)")
            }
            appendLog("Already installed: \(item.name). Skipping install command.")
            return nil
        }

        for command in item.commands {
            appendLog("$ \(command.shell)")
            let result = await shell.run(
                command: command.shell,
                authMode: command.authMode,
                timeoutSeconds: command.timeoutSeconds
            )

            appendLog(result.combinedOutput)

            if result.exitCode != 0 {
                return InstallFailure(
                    itemID: item.id,
                    itemName: item.name,
                    failedCommand: command.shell,
                    output: result.combinedOutput,
                    exitCode: result.exitCode,
                    timedOut: result.timedOut
                )
            }

            // Installation commands can change Homebrew package state; refresh cache for post-verify.
            invalidateBrewPackageCache()
        }

        if let verificationFailure = await runVerificationChecks(for: item, phase: "Verify") {
            return InstallFailure(
                itemID: item.id,
                itemName: item.name,
                failedCommand: verificationFailure.check.command,
                output: "[\(verificationFailure.check.name)] \(verificationFailure.result.combinedOutput)",
                exitCode: verificationFailure.result.exitCode,
                timedOut: verificationFailure.result.timedOut
            )
        }

        return nil
    }

    private func addDependenciesRecursively(for itemID: String) {
        guard let item = catalog.first(where: { $0.id == itemID }) else { return }
        for dependency in item.dependencies {
            selectedItemIDs.insert(dependency)
            addDependenciesRecursively(for: dependency)
        }
    }

    private func removeItemAndDependents(_ itemID: String) {
        selectedItemIDs.remove(itemID)

        let dependentIDs = catalog
            .filter { $0.dependencies.contains(itemID) && !$0.isRequired }
            .map(\.id)

        for dependent in dependentIDs {
            removeItemAndDependents(dependent)
        }
    }

    private func ensureDependenciesAndRequireds() {
        let required = catalog.filter { $0.isRequired }.map(\.id)
        selectedItemIDs.formUnion(required)

        var changed = true
        while changed {
            changed = false
            for item in catalog where selectedItemIDs.contains(item.id) {
                for dependency in item.dependencies where !selectedItemIDs.contains(dependency) {
                    selectedItemIDs.insert(dependency)
                    changed = true
                }
            }
        }
    }

    private func updateStep(itemID: String, status: StepExecutionStatus, output: String) {
        guard let index = stepStates.firstIndex(where: { $0.item.id == itemID }) else { return }
        stepStates[index].status = status
        if !output.isEmpty {
            stepStates[index].latestOutput = output
        }
    }

    func appendLog(_ line: String) {
        liveLog.append(line)
        Task {
            await logger.log(level: .info, message: line)
        }
    }

    private func invalidateBrewPackageCache() {
        brewPackageCache = nil
        brewPackageCacheLoaded = false
    }

    private func cachedBrewPackageInstalledStatus(for package: BrewPackageReference) async -> Bool? {
        guard let cache = await loadBrewPackageCacheIfNeeded() else {
            return nil
        }
        return cache.contains(package)
    }

    private func loadBrewPackageCacheIfNeeded() async -> BrewPackageCache? {
        if brewPackageCacheLoaded {
            return brewPackageCache
        }
        brewPackageCacheLoaded = true

        let formulaListCommand = "command -v brew >/dev/null 2>&1 && brew list --formula"
        let caskListCommand = "command -v brew >/dev/null 2>&1 && brew list --cask"

        appendLog("$ \(formulaListCommand)")
        let formulaResult = await shell.run(
            command: formulaListCommand,
            authMode: .standard,
            timeoutSeconds: 120
        )
        appendLog("$ \(caskListCommand)")
        let caskResult = await shell.run(
            command: caskListCommand,
            authMode: .standard,
            timeoutSeconds: 120
        )

        guard formulaResult.exitCode == 0, caskResult.exitCode == 0 else {
            appendLog("Brew cache unavailable. Falling back to command checks.")
            await logger.log(level: .warning, message: "Unable to load Homebrew package cache", metadata: [
                "formula_exit_code": String(formulaResult.exitCode),
                "cask_exit_code": String(caskResult.exitCode)
            ])
            brewPackageCache = nil
            return nil
        }

        let cache = BrewPackageCache(
            formulas: parseBrewPackageNames(from: formulaResult.stdout),
            casks: parseBrewPackageNames(from: caskResult.stdout)
        )
        brewPackageCache = cache
        appendLog("Loaded brew cache: \(cache.formulas.count) formulae, \(cache.casks.count) casks.")
        return cache
    }

    private func adminAuthenticationFailureMessage(from output: String) -> String? {
        let normalized = output.lowercased()
        let indicators = [
            "no password was provided",
            "a password is required",
            "authentication failed",
        ]
        guard indicators.contains(where: { normalized.contains($0) }) else {
            return nil
        }
        return "Administrator authentication was canceled or failed. Retry and complete password authentication."
    }

    private func parseBrewPackageNames(from output: String) -> Set<String> {
        Set(
            output
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }
}
