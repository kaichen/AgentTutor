import AppKit
import Combine
import Foundation

@MainActor
final class SetupViewModel: ObservableObject {
    @Published var stage: SetupStage = .welcome
    @Published var apiKey: String = ""
    @Published var apiBaseURL: String = "https://api.openai.com"
    @Published var selectedItemIDs: Set<String>
    @Published var stepStates: [InstallStepState] = []
    @Published var runState: InstallRunState = .idle
    @Published var liveLog: [String] = []
    @Published var activeFailure: InstallFailure?
    @Published var remediationAdvice: RemediationAdvice?
    @Published var userNotice: String = ""
    @Published var showingCommandConfirmation: Bool = false
    @Published var pendingRemediationCommand: String = ""
    @Published var isRunningRemediationCommand: Bool = false
    @Published var apiKeyValidationStatus: APIKeyValidationStatus = .idle

    let catalog: [InstallItem]
    let logger: InstallLogger

    private let planner: InstallPlanner
    private let shell: ShellExecuting
    private let advisor: RemediationAdvising
    private var apiKeyValidationTask: Task<Void, Never>?

    convenience init() {
        self.init(
            catalog: InstallCatalog.allItems,
            shell: ShellExecutor(),
            advisor: RemediationAdvisor(),
            logger: InstallLogger()
        )
    }

    init(
        catalog: [InstallItem],
        shell: ShellExecuting,
        advisor: RemediationAdvising,
        logger: InstallLogger
    ) {
        self.catalog = catalog
        self.shell = shell
        self.advisor = advisor
        self.logger = logger
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

    func moveNext() {
        guard let currentIndex = SetupStage.allCases.firstIndex(of: stage) else { return }
        let nextIndex = SetupStage.allCases.index(after: currentIndex)
        if nextIndex < SetupStage.allCases.endIndex {
            stage = SetupStage.allCases[nextIndex]
        }
    }

    func moveBack() {
        guard let currentIndex = SetupStage.allCases.firstIndex(of: stage), currentIndex > 0 else { return }
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
                        activeFailure = failure
                        appendLog("Failed: \(item.name)")
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
                stage = .completion
                await logger.log(level: .info, message: "Install session completed")
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

        isRunningRemediationCommand = true
        showingCommandConfirmation = false

        Task {
            await logger.log(level: .warning, message: "Running user-approved remediation command", metadata: ["command": command])
            let result = await shell.run(
                command: command,
                requiresAdmin: command.hasPrefix("sudo "),
                timeoutSeconds: 900
            )

            appendLog("Remediation command: \(command)")
            appendLog(result.combinedOutput)
            await logger.log(level: result.exitCode == 0 ? .info : .error, message: "Remediation command finished", metadata: ["exit_code": String(result.exitCode)])

            if result.exitCode == 0 {
                userNotice = "Remediation command succeeded. You can retry installation now."
            } else {
                userNotice = "Remediation command failed. Check logs before retrying."
            }

            isRunningRemediationCommand = false
        }
    }

    func openLogFolder() {
        NSWorkspace.shared.activateFileViewerSelecting([logger.logFileURL.deletingLastPathComponent()])
    }

    func onAPIKeyChanged() {
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
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(endpoint)/v1/models") else {
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

    private func execute(item: InstallItem) async -> InstallFailure? {
        for command in item.commands {
            let result = await shell.run(
                command: command.shell,
                requiresAdmin: command.requiresAdmin,
                timeoutSeconds: command.timeoutSeconds
            )

            appendLog("$ \(command.shell)")
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
        }

        let verification = await shell.run(
            command: item.verificationCommand,
            requiresAdmin: false,
            timeoutSeconds: 120
        )

        appendLog("Verify: \(item.name)")
        appendLog(verification.combinedOutput)

        if verification.exitCode != 0 {
            return InstallFailure(
                itemID: item.id,
                itemName: item.name,
                failedCommand: item.verificationCommand,
                output: verification.combinedOutput,
                exitCode: verification.exitCode,
                timedOut: verification.timedOut
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

    private func appendLog(_ line: String) {
        liveLog.append(line)
        Task {
            await logger.log(level: .info, message: line)
        }
    }
}
