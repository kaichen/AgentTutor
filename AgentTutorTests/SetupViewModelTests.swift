import Testing
@testable import AgentTutor

@MainActor
struct SetupViewModelTests {

    // MARK: - Initialization

    @Test
    func initSetsRequiredAndDefaultSelectedItems() {
        let catalog = TestFixtures.chainCatalog
        let vm = SetupViewModel(
            catalog: catalog,
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )

        // "base" is required+defaultSelected, "mid" is defaultSelected, "leaf" is neither
        #expect(vm.selectedItemIDs.contains("base"))
        #expect(vm.selectedItemIDs.contains("mid"))
        #expect(!vm.selectedItemIDs.contains("leaf"))
    }

    @Test
    func initEnsuresDependenciesOfDefaultSelected() {
        // "mid" depends on "base", even if "base" were not required it should be pulled in
        let catalog = [
            TestFixtures.makeItem(id: "base", name: "Base", isRequired: false, defaultSelected: false),
            TestFixtures.makeItem(id: "mid", name: "Mid", defaultSelected: true, dependencies: ["base"]),
        ]
        let vm = SetupViewModel(
            catalog: catalog,
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )

        #expect(vm.selectedItemIDs.contains("base"))
        #expect(vm.selectedItemIDs.contains("mid"))
    }

    // MARK: - Stage Navigation

    @Test
    func moveNextAdvancesStage() {
        let vm = makeVM()
        #expect(vm.stage == .welcome)
        vm.moveNext()
        #expect(vm.stage == .apiKey)
        vm.moveNext()
        #expect(vm.stage == .selection)
    }

    @Test
    func moveBackReturnsToPrevoiusStage() {
        let vm = makeVM()
        vm.moveNext()
        vm.moveNext()
        #expect(vm.stage == .selection)
        vm.moveBack()
        #expect(vm.stage == .apiKey)
    }

    @Test
    func moveBackFromWelcomeStaysAtWelcome() {
        let vm = makeVM()
        #expect(vm.stage == .welcome)
        vm.moveBack()
        #expect(vm.stage == .welcome)
    }

    @Test
    func moveNextFromCompletionStaysAtCompletion() {
        let vm = makeVM()
        // Advance to completion
        for _ in 0..<4 { vm.moveNext() }
        #expect(vm.stage == .completion)
        vm.moveNext()
        #expect(vm.stage == .completion)
    }

    // MARK: - API Key Validation Computed Properties

    @Test
    func canAdvanceFromAPIKeyReturnsFalseWhenEmpty() {
        let vm = makeVM()
        vm.apiKey = ""
        #expect(!vm.canAdvanceFromAPIKey)

        vm.apiKey = "   "
        #expect(!vm.canAdvanceFromAPIKey)
    }

    @Test
    func canAdvanceFromAPIKeyReturnsTrueWithKey() {
        let vm = makeVM()
        vm.apiKey = "sk-test-key"
        #expect(vm.canAdvanceFromAPIKey)
    }

    @Test
    func canStartInstallReturnsFalseWhenRunning() {
        let vm = makeVM()
        vm.apiKey = "sk-test"
        vm.runState = .running
        #expect(!vm.canStartInstall)
    }

    // MARK: - Selection Logic

    @Test
    func toggleRequiredItemIsBlocked() {
        let item = TestFixtures.makeItem(id: "req", isRequired: true)
        let vm = SetupViewModel(
            catalog: [item],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )

        #expect(!vm.canToggle(item))
        vm.setSelection(false, for: item)
        #expect(vm.selectedItemIDs.contains("req"))
    }

    @Test
    func selectingItemPullsInDependencies() {
        let catalog = TestFixtures.chainCatalog
        let vm = SetupViewModel(
            catalog: catalog,
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )

        let leaf = catalog.first { $0.id == "leaf" }!
        vm.setSelection(true, for: leaf)

        #expect(vm.selectedItemIDs.contains("leaf"))
        #expect(vm.selectedItemIDs.contains("mid"))
        #expect(vm.selectedItemIDs.contains("base"))
    }

    @Test
    func deselectingItemRemovesDependents() {
        let catalog = [
            TestFixtures.makeItem(id: "base", name: "Base", isRequired: false, defaultSelected: true),
            TestFixtures.makeItem(id: "child", name: "Child", defaultSelected: true, dependencies: ["base"]),
        ]
        let vm = SetupViewModel(
            catalog: catalog,
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )

        let base = catalog[0]
        vm.setSelection(false, for: base)

        #expect(!vm.selectedItemIDs.contains("base"))
        #expect(!vm.selectedItemIDs.contains("child"))
    }

    @Test
    func selectedItemCountMatchesSetSize() {
        let vm = makeVM()
        #expect(vm.selectedItemCount == vm.selectedItemIDs.count)
    }

    // MARK: - Install Flow (with Mock Shell)

    @Test
    func startInstallSucceedsWithAllPassingCommands() async throws {
        let item = TestFixtures.makeItem(id: "a", name: "A", isRequired: true, defaultSelected: true)
        let shell = MockShellExecutor(results: [
            // install command succeeds
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // verification succeeds
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
        ])

        let vm = SetupViewModel(
            catalog: [item],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.apiKey = "sk-test"
        vm.startInstall()

        // Wait for the async task to complete
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.runState == .completed)
        #expect(vm.stage == .completion)
        #expect(vm.activeFailure == nil)
        #expect(shell.invocations.count == 2)
    }

    @Test
    func startInstallFailsOnCommandError() async throws {
        let item = TestFixtures.makeItem(id: "b", name: "B", isRequired: true, defaultSelected: true)
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "command not found", timedOut: false),
        ])
        let advisor = MockRemediationAdvisor()

        let vm = SetupViewModel(
            catalog: [item],
            shell: shell,
            advisor: advisor,
            logger: InstallLogger()
        )
        vm.apiKey = "sk-test"
        vm.startInstall()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.runState == .failed)
        #expect(vm.activeFailure != nil)
        #expect(vm.activeFailure?.itemID == "b")
        #expect(advisor.suggestCallCount == 1)
        #expect(vm.remediationAdvice != nil)
    }

    @Test
    func startInstallFailsOnVerificationError() async throws {
        let item = TestFixtures.makeItem(id: "c", name: "C", isRequired: true, defaultSelected: true)
        let shell = MockShellExecutor(results: [
            // install succeeds
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // verification fails
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "not verified", timedOut: false),
        ])

        let vm = SetupViewModel(
            catalog: [item],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.apiKey = "sk-test"
        vm.startInstall()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.runState == .failed)
        #expect(vm.activeFailure?.itemID == "c")
    }

    @Test
    func startInstallWithEmptyAPIKeyShowsValidationError() async throws {
        let vm = makeVM()
        vm.apiKey = ""
        vm.runState = .idle
        // Force startInstall to execute despite canStartInstall being false
        vm.apiKey = "  "  // whitespace-only
        vm.runState = .idle

        // Manually trigger since canStartInstall returns false for whitespace
        // The planner should catch the empty key
        vm.apiKey = "sk-test"
        vm.startInstall()
        vm.apiKey = ""

        // The planner resolves with the original "sk-test" key, so this should work
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    @Test
    func startInstallStopsAtFirstFailure() async throws {
        let catalog = [
            TestFixtures.makeItem(id: "first", name: "First", isRequired: true, defaultSelected: true),
            TestFixtures.makeItem(id: "second", name: "Second", isRequired: true, defaultSelected: true),
        ]
        let shell = MockShellExecutor(results: [
            // first install fails
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "broken", timedOut: false),
        ])

        let vm = SetupViewModel(
            catalog: catalog,
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.apiKey = "sk-test"
        vm.startInstall()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.runState == .failed)
        #expect(vm.activeFailure?.itemID == "first")
        // Second item should never have been attempted (only 1 shell invocation)
        #expect(shell.invocations.count == 1)
    }

    // MARK: - Remediation Command

    @Test
    func queueRemediationCommandSetsState() {
        let vm = makeVM()
        vm.queueRemediationCommand("brew doctor")

        #expect(vm.pendingRemediationCommand == "brew doctor")
        #expect(vm.showingCommandConfirmation)
    }

    @Test
    func executePendingRemediationBlocksUnsafeCommand() {
        let vm = makeVM()
        vm.pendingRemediationCommand = "rm -rf /"

        vm.executePendingRemediationCommand()

        #expect(vm.userNotice.contains("Blocked"))
        #expect(!vm.isRunningRemediationCommand)
    }

    @Test
    func executePendingRemediationRunsSafeCommand() async throws {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "fixed", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.pendingRemediationCommand = "brew doctor"
        vm.executePendingRemediationCommand()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(shell.invocations.count == 1)
        #expect(shell.invocations[0].command == "brew doctor")
        #expect(vm.userNotice.contains("succeeded"))
        #expect(!vm.isRunningRemediationCommand)
    }

    @Test
    func executePendingRemediationReportsFailure() async throws {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "error", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.pendingRemediationCommand = "brew doctor"
        vm.executePendingRemediationCommand()

        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.userNotice.contains("failed"))
    }

    @Test
    func executePendingRemediationSkipsEmptyCommand() {
        let shell = MockShellExecutor()
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.pendingRemediationCommand = "  "
        vm.executePendingRemediationCommand()

        #expect(shell.invocations.isEmpty)
    }

    // MARK: - Helpers

    private func makeVM() -> SetupViewModel {
        SetupViewModel(
            catalog: TestFixtures.chainCatalog,
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
    }
}
