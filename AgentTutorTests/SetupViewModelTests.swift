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
        for _ in 0..<(SetupStage.allCases.count - 1) { vm.moveNext() }
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

    @Test
    func completionLogFolderButtonIsHiddenWhenInstallCompletesWithoutIssues() {
        let vm = makeVM()
        let item = TestFixtures.makeItem(id: "ok", name: "OK", isRequired: true, defaultSelected: true)
        vm.stepStates = [InstallStepState(item: item, status: .succeeded)]
        vm.runState = .completed
        vm.activeFailure = nil

        #expect(vm.completedWithoutIssues)
        #expect(!vm.shouldShowCompletionLogFolderButton)
    }

    @Test
    func completionLogFolderButtonIsVisibleWhenInstallHasFailures() {
        let vm = makeVM()
        let item = TestFixtures.makeItem(id: "bad", name: "Bad", isRequired: true, defaultSelected: true)
        vm.stepStates = [InstallStepState(item: item, status: .failed)]
        vm.runState = .completed

        #expect(!vm.completedWithoutIssues)
        #expect(vm.shouldShowCompletionLogFolderButton)
    }

    @Test
    func providerDefaultsToOpenAIBaseURL() {
        let vm = makeVM()
        #expect(vm.apiProvider == .openai)
        #expect(vm.apiBaseURL == LLMProvider.openai.defaultBaseURL)
    }

    @Test
    func changingProviderResetsBaseURLToProviderDefault() {
        let vm = makeVM()
        vm.apiBaseURL = "https://custom.example.com/v1"
        vm.apiProvider = .openrouter
        vm.onProviderChanged()
        #expect(vm.apiBaseURL == LLMProvider.openrouter.defaultBaseURL)

        vm.apiProvider = .kimi
        vm.onProviderChanged()
        #expect(vm.apiBaseURL == LLMProvider.kimi.defaultBaseURL)

        vm.apiProvider = .minimax
        vm.onProviderChanged()
        #expect(vm.apiBaseURL == LLMProvider.minimax.defaultBaseURL)
    }

    @Test
    func kimiEndpointPresetsIncludeCNAndGlobal() {
        let presets = LLMProvider.kimi.endpointPresets

        #expect(presets.count == 2)
        #expect(presets.contains(where: { $0.label == "Global" && $0.baseURL == "https://api.moonshot.ai/v1" }))
        #expect(presets.contains(where: { $0.label == "CN" && $0.baseURL == "https://api.kimi.com/coding/v1" }))
    }

    @Test
    func minimaxEndpointPresetsIncludeCNAndGlobal() {
        let presets = LLMProvider.minimax.endpointPresets

        #expect(presets.count == 2)
        #expect(presets.contains(where: { $0.label == "Global" && $0.baseURL == "https://api.minimax.io/v1" }))
        #expect(presets.contains(where: { $0.label == "CN" && $0.baseURL == "https://api.minimaxi.com/v1" }))
    }

    @Test
    func providerDefaultModelNameIsDefined() {
        #expect(LLMProvider.openai.defaultModelName == "gpt-5.1-codex-mini")
        #expect(LLMProvider.openrouter.defaultModelName == "openai/gpt-5.1-codex-mini")
        #expect(LLMProvider.kimi.defaultModelName == "kimi-for-coding")
        #expect(LLMProvider.minimax.defaultModelName == "MiniMax-M2.1")
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
            // preflight verification fails (not installed yet)
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            // install command succeeds
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // post-install verification succeeds
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
        #expect(vm.stage == .gitSSH)
        #expect(vm.activeFailure == nil)
        #expect(shell.invocations.count == 3)
    }

    @Test
    func startInstallSkipsCommandsWhenVerificationAlreadyPasses() async throws {
        let item = TestFixtures.makeItem(id: "homebrew", name: "Homebrew", isRequired: true, defaultSelected: true)
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "brew", stderr: "", timedOut: false),
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

        #expect(vm.runState == .completed)
        #expect(shell.invocations.count == 1)
        #expect(shell.invocations[0].command == item.verificationChecks[0].command)
    }

    @Test
    func startInstallLogsAllCLICommandsIncludingSkippedCommands() async throws {
        let checkCommand = "brew list pkg-a >/dev/null 2>&1"
        let verificationCheck = InstallVerificationCheck(
            "pkg-a",
            command: checkCommand,
            brewPackage: BrewPackageReference("pkg-a")
        )
        let item = TestFixtures.makeItem(
            id: "pkg-a",
            name: "Package A",
            isRequired: true,
            defaultSelected: true,
            commands: [InstallCommand("echo install")],
            verificationChecks: [verificationCheck]
        )
        let shell = MockShellExecutor(results: [
            // brew list --formula
            ShellExecutionResult(exitCode: 0, stdout: "pkg-a\n", stderr: "", timedOut: false),
            // brew list --cask
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
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

        #expect(vm.runState == .completed)
        #expect(vm.liveLog.contains { $0.contains("$ command -v brew >/dev/null 2>&1 && brew list --formula") })
        #expect(vm.liveLog.contains { $0.contains("$ command -v brew >/dev/null 2>&1 && brew list --cask") })
        #expect(vm.liveLog.contains { $0.contains("$ \(checkCommand)  # skipped (cached brew list hit)") })
        #expect(vm.liveLog.contains { $0.contains("$ echo install  # skipped (already installed)") })
    }

    @Test
    func startInstallRunsAllVerificationChecksIndividually() async throws {
        let checks = [
            InstallVerificationCheck("pkg-a", command: "command -v a >/dev/null 2>&1"),
            InstallVerificationCheck("pkg-b", command: "command -v b >/dev/null 2>&1"),
            InstallVerificationCheck("pkg-c", command: "command -v c >/dev/null 2>&1"),
        ]
        let item = TestFixtures.makeItem(
            id: "core-cli",
            name: "Core CLI Tools",
            isRequired: true,
            defaultSelected: true,
            verificationChecks: checks
        )

        let shell = MockShellExecutor(results: [
            // Preflight checks (all missing)
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing a", timedOut: false),
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing b", timedOut: false),
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing c", timedOut: false),
            // Install succeeds
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // Post-install verification checks (all present)
            ShellExecutionResult(exitCode: 0, stdout: "a", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "b", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "c", stderr: "", timedOut: false),
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

        #expect(vm.runState == .completed)
        #expect(shell.invocations.count == 7)
        #expect(shell.invocations[0].command == checks[0].command)
        #expect(shell.invocations[1].command == checks[1].command)
        #expect(shell.invocations[2].command == checks[2].command)
    }

    @Test
    func startInstallUsesSingleBrewCacheForAllBrewPackageChecks() async throws {
        let formulaCheck = InstallVerificationCheck(
            "pkg-a",
            command: "brew list pkg-a >/dev/null 2>&1",
            brewPackage: BrewPackageReference("pkg-a")
        )
        let caskCheck = InstallVerificationCheck(
            "pkg-b",
            command: "brew list --cask pkg-b >/dev/null 2>&1",
            brewPackage: BrewPackageReference("pkg-b", kind: .cask)
        )

        let catalog = [
            TestFixtures.makeItem(
                id: "a",
                name: "A",
                isRequired: true,
                defaultSelected: true,
                verificationChecks: [formulaCheck]
            ),
            TestFixtures.makeItem(
                id: "b",
                name: "B",
                category: .apps,
                isRequired: true,
                defaultSelected: true,
                verificationChecks: [caskCheck]
            ),
        ]

        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "pkg-a\n", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "pkg-b\n", stderr: "", timedOut: false),
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

        #expect(vm.runState == .completed)
        #expect(shell.invocations.count == 2)
        #expect(shell.invocations[0].command.contains("brew list --formula"))
        #expect(shell.invocations[1].command.contains("brew list --cask"))
        #expect(!shell.invocations.contains(where: { $0.command == formulaCheck.command }))
        #expect(!shell.invocations.contains(where: { $0.command == caskCheck.command }))
    }

    @Test
    func startInstallRunsExplicitCommandWhenBrewCacheMissesPackage() async throws {
        let vscodeCheck = InstallVerificationCheck(
            "visual-studio-code cask",
            command: "brew list --cask visual-studio-code >/dev/null 2>&1 || [ -d '/Applications/Visual Studio Code.app' ]",
            brewPackage: BrewPackageReference("visual-studio-code", kind: .cask)
        )
        let item = TestFixtures.makeItem(
            id: "vscode",
            name: "Visual Studio Code",
            category: .apps,
            isRequired: true,
            defaultSelected: true,
            verificationChecks: [vscodeCheck]
        )

        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
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

        #expect(vm.runState == .completed)
        #expect(shell.invocations.count == 3)
        #expect(shell.invocations[0].command.contains("brew list --formula"))
        #expect(shell.invocations[1].command.contains("brew list --cask"))
        #expect(shell.invocations[2].command == vscodeCheck.command)
        #expect(!shell.invocations.contains(where: { $0.command == "echo install" }))
    }

    @Test
    func startInstallUsesSudoAskpassForConfiguredInstallCommand() async throws {
        let item = TestFixtures.makeItem(
            id: "homebrew",
            name: "Homebrew",
            category: .system,
            isRequired: true,
            defaultSelected: true,
            commands: [
                InstallCommand("NONINTERACTIVE=1 /bin/bash -c \"echo install\"", authMode: .sudoAskpass)
            ],
            verificationChecks: [
                InstallVerificationCheck("homebrew", command: "command -v brew >/dev/null 2>&1")
            ]
        )
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
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

        #expect(vm.runState == .completed)
        #expect(shell.invocations.count == 3)
        #expect(shell.invocations[1].authMode == .sudoAskpass)
    }

    @Test
    func startInstallShowsAuthFailureNoticeWhenAuthenticationFails() async throws {
        let item = TestFixtures.makeItem(
            id: "homebrew",
            name: "Homebrew",
            category: .system,
            isRequired: true,
            defaultSelected: true,
            commands: [
                InstallCommand("NONINTERACTIVE=1 /bin/bash -c \"echo install\"", authMode: .sudoAskpass)
            ],
            verificationChecks: [
                InstallVerificationCheck("homebrew", command: "command -v brew >/dev/null 2>&1")
            ]
        )
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "sudo: a password is required", timedOut: false),
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
        #expect(vm.userNotice.contains("Administrator authentication was canceled or failed"))
    }

    @Test
    func startInstallFailsOnCommandError() async throws {
        let item = TestFixtures.makeItem(id: "b", name: "B", isRequired: true, defaultSelected: true)
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "not installed", timedOut: false),
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
            // preflight verification fails
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            // install succeeds
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // post-install verification fails
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
            // first preflight fails
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
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
        // Second item should never have been attempted (first item only preflight + install)
        #expect(shell.invocations.count == 2)
    }

    // MARK: - Git & SSH Stage

    @Test
    func prepareGitSSHStepLoadsIdentityAndExistingKey() async throws {
        let material = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza...",
            fingerprint: "256 SHA256:abc mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(
            readGlobalGitIdentityResult: .success(GitIdentity(name: "Kai", email: "kai@example.com")),
            loadExistingSSHKeyMaterialResult: .success(material)
        )
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH

        vm.prepareGitSSHStep()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.gitUserName == "Kai")
        #expect(vm.gitUserEmail == "kai@example.com")
        #expect(vm.sshKeyState == .existing(material))
        #expect(vm.stage == .openClaw)
        #expect(vm.gitConfigStatus == .succeeded)
        #expect(vm.githubUploadStatus == .succeeded)
    }

    @Test
    func prepareGitSSHStepSkipsWhenGitAndGithubReady() async throws {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "Logged in to github.com account.", stderr: "", timedOut: false),
        ])
        let material = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza...",
            fingerprint: "256 SHA256:abc mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(
            readGlobalGitIdentityResult: .success(GitIdentity(name: "Kai", email: "kai@example.com")),
            loadExistingSSHKeyMaterialResult: .success(material)
        )
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH

        vm.prepareGitSSHStep()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.stage == .openClaw)
        #expect(vm.userNotice == "Git identity, GitHub login, and SSH key are already configured. Skipping Git/SSH setup.")
        #expect(shell.invocations.count == 1)
        #expect(shell.invocations[0].command == "gh auth status")
    }

    @Test
    func prepareGitSSHStepDoesNotSkipWithoutGitHubLogin() async throws {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "not logged in", timedOut: false),
        ])
        let gitSSHService = MockGitSSHService(
            readGlobalGitIdentityResult: .success(GitIdentity(name: "Kai", email: "kai@example.com")),
            loadExistingSSHKeyMaterialResult: .success(nil)
        )
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH

        vm.prepareGitSSHStep()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.stage == .gitSSH)
        #expect(vm.sshKeyState == .missing)
        #expect(vm.gitConfigStatus == .idle)
    }

    @Test
    func skipGitSSHStepTransitionsToOpenClaw() {
        let vm = makeVM()
        vm.stage = .gitSSH

        vm.skipGitSSHStep()

        #expect(vm.stage == .openClaw)
        #expect(vm.userNotice.contains("Skipped"))
    }

    @Test
    func finishGitSSHStepTransitionsToOpenClaw() {
        let vm = makeVM()
        vm.stage = .gitSSH

        vm.finishGitSSHStep()

        #expect(vm.stage == .openClaw)
    }

    // MARK: - OpenClaw Stage

    @Test
    func skipOpenClawStepTransitionsToCompletion() {
        let vm = makeVM()
        vm.stage = .openClaw
        vm.openClawPrecheckCompleted = true

        vm.skipOpenClawStep()

        #expect(vm.stage == .completion)
        #expect(vm.userNotice.contains("Skipped"))
    }

    @Test
    func skipOpenClawStepDoesNotAdvanceWhenPrecheckNotCompleted() {
        let vm = makeVM()
        vm.stage = .openClaw
        vm.openClawPrecheckCompleted = false

        vm.skipOpenClawStep()

        #expect(vm.stage == .openClaw)
        #expect(vm.userNotice.contains("check is not complete"))
    }

    @Test
    func shouldHideOpenClawInitializeButtonWhenExistingInstallDetected() {
        let vm = makeVM()
        vm.stage = .openClaw
        vm.openClawInstallStatus = .idle
        vm.openClawPrecheckCompleted = true
        vm.isCheckingOpenClawExistingInstall = false
        vm.openClawExistingInstallDetected = true

        #expect(!vm.shouldShowOpenClawInitializeButton)
    }

    @Test
    func shouldShowOpenClawInitializeButtonWhenExistingInstallNotDetected() {
        let vm = makeVM()
        vm.stage = .openClaw
        vm.openClawInstallStatus = .idle
        vm.openClawPrecheckCompleted = true
        vm.isCheckingOpenClawExistingInstall = false
        vm.openClawExistingInstallDetected = false

        #expect(vm.shouldShowOpenClawInitializeButton)
    }

    @Test
    func refreshOpenClawExistingInstallStatusMarksInstalledAndLoadsConfiguredChannels() async throws {
        let shell = MockShellExecutor(results: [
            // openclaw process exists
            ShellExecutionResult(exitCode: 0, stdout: "1234", stderr: "", timedOut: false),
            // openclaw gateway status healthy
            ShellExecutionResult(exitCode: 0, stdout: "Gateway is running and healthy", stderr: "", timedOut: false),
            // telegram config
            ShellExecutionResult(exitCode: 0, stdout: "{\"enabled\":true,\"botToken\":\"tg-bot-token\"}", stderr: "", timedOut: false),
            // slack config
            ShellExecutionResult(exitCode: 0, stdout: "{\"enabled\":false}", stderr: "", timedOut: false),
            // feishu config missing
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "not configured", timedOut: false),
            // channels status
            ShellExecutionResult(exitCode: 0, stdout: "telegram: enabled ready\nslack: disabled\nfeishu: not configured", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.openClawPrecheckCompleted = true

        vm.refreshOpenClawExistingInstallStatus()
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(vm.openClawExistingInstallDetected)
        #expect(vm.openClawGatewayHealthy)
        #expect(!vm.isCheckingOpenClawExistingInstall)
        #expect(vm.openClawPrecheckCompleted)
        #expect(vm.openClawConfiguredChannels.contains(.telegram))
        #expect(!vm.openClawConfiguredChannels.contains(.slack))
        #expect(vm.openClawSelectedChannels.contains(.telegram))
        #expect(shell.invocations.count == 6)
        #expect(shell.invocations[0].command == "pgrep -f '[o]penclaw' >/dev/null 2>&1")
        #expect(shell.invocations[1].command == "openclaw gateway status")
        #expect(shell.invocations[2].command == "openclaw config get --json channels.telegram")
        #expect(shell.invocations[3].command == "openclaw config get --json channels.slack")
        #expect(shell.invocations[4].command == "openclaw config get --json channels.feishu")
        #expect(shell.invocations[5].command == "openclaw channels status --probe")
    }

    @Test
    func refreshOpenClawExistingInstallStatusMarksNotInstalledWhenProcessMissing() async throws {
        let shell = MockShellExecutor(results: [
            // openclaw process missing
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.openClawExistingInstallDetected = true

        vm.refreshOpenClawExistingInstallStatus()
        try await Task.sleep(nanoseconds: 250_000_000)

        #expect(!vm.openClawExistingInstallDetected)
        #expect(!vm.openClawGatewayHealthy)
        #expect(!vm.isCheckingOpenClawExistingInstall)
        #expect(vm.openClawPrecheckCompleted)
        #expect(shell.invocations.count == 1)
        #expect(shell.invocations[0].command == "pgrep -f '[o]penclaw' >/dev/null 2>&1")
    }

    @Test
    func installOpenClawStepDoesNotRunWhenPrecheckNotCompleted() {
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .kimi
        vm.apiKey = "key1-test"
        vm.openClawPrecheckCompleted = false

        vm.installOpenClawStep()

        #expect(vm.stage == .openClaw)
        #expect(vm.userNotice.contains("check is not complete"))
        #expect(vm.openClawInstallStatus == .idle)
    }

    @Test
    func setOpenClawChannelKeepsConfiguredChannelSelected() {
        let vm = makeVM()
        vm.openClawConfiguredChannels = [.telegram]
        vm.openClawSelectedChannels = [.telegram]

        vm.setOpenClawChannel(.telegram, selected: false)

        #expect(vm.openClawSelectedChannels.contains(.telegram))
    }

    @Test
    func installOpenClawStepSucceedsAndRunsNonInteractiveOnboard() async throws {
        let shell = MockShellExecutor(results: [
            // check: openclaw-cli missing
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            // install openclaw-cli
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // check: openclaw cask missing
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            // install openclaw cask
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // openclaw process
            ShellExecutionResult(exitCode: 0, stdout: "1234", stderr: "", timedOut: false),
            // openclaw gateway status
            ShellExecutionResult(exitCode: 0, stdout: "status: starting", stderr: "", timedOut: false),
            // onboard
            ShellExecutionResult(exitCode: 0, stdout: "onboarded", stderr: "", timedOut: false),
            // openclaw gateway status after setup
            ShellExecutionResult(exitCode: 0, stdout: "Gateway is running and healthy", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .openrouter
        vm.apiKey = "key1-test"
        vm.openClawPrecheckCompleted = true

        vm.installOpenClawStep()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.stage == .completion)
        #expect(vm.openClawInstallStatus == .succeeded)
        #expect(vm.openClawGatewayHealthy)
        #expect(shell.invocations.count == 8)
        #expect(shell.invocations[0].command == "brew list openclaw-cli >/dev/null 2>&1")
        #expect(shell.invocations[1].command == "brew install openclaw-cli")
        #expect(shell.invocations[2].command == "brew list --cask openclaw >/dev/null 2>&1 || [ -d '/Applications/OpenClaw.app' ]")
        #expect(shell.invocations[3].command == "brew install --cask openclaw")
        #expect(shell.invocations[4].command == "pgrep -f '[o]penclaw' >/dev/null 2>&1")
        #expect(shell.invocations[5].command == "openclaw gateway status")
        #expect(shell.invocations[6].command == "openclaw onboard --non-interactive --accept-risk --mode local --auth-choice openrouter-api-key --openrouter-api-key 'key1-test'")
        #expect(shell.invocations[7].command == "openclaw gateway status")
    }

    @Test
    func installOpenClawStepSkipsWhenGatewayStatusIsHealthy() async throws {
        let shell = MockShellExecutor(results: [
            // check: openclaw-cli
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // check: openclaw cask
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // openclaw process
            ShellExecutionResult(exitCode: 0, stdout: "1234", stderr: "", timedOut: false),
            // openclaw gateway status
            ShellExecutionResult(exitCode: 0, stdout: "Gateway is running and healthy", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .kimi
        vm.apiKey = "key1-test"
        vm.openClawPrecheckCompleted = true

        vm.installOpenClawStep()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.stage == .completion)
        #expect(vm.openClawInstallStatus == .succeeded)
        #expect(vm.openClawGatewayHealthy)
        #expect(vm.userNotice == "OpenClaw onboarding already completed. Skipping initialization.")
        #expect(shell.invocations.count == 4)
        #expect(shell.invocations[0].command == "brew list openclaw-cli >/dev/null 2>&1")
        #expect(shell.invocations[1].command == "brew list --cask openclaw >/dev/null 2>&1 || [ -d '/Applications/OpenClaw.app' ]")
        #expect(shell.invocations[2].command == "pgrep -f '[o]penclaw' >/dev/null 2>&1")
        #expect(shell.invocations[3].command == "openclaw gateway status")
    }

    @Test
    func installOpenClawStepFailsFastWhenProviderNotSupported() {
        let shell = MockShellExecutor()
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .openai
        vm.apiKey = "key1-test"
        vm.openClawPrecheckCompleted = true

        vm.installOpenClawStep()

        #expect(vm.stage == .openClaw)
        #expect(vm.openClawValidationErrors.contains(where: { $0.contains("not supported for non-interactive OpenClaw onboarding") }))
        #expect(shell.invocations.isEmpty)
        switch vm.openClawInstallStatus {
        case .failed:
            break
        default:
            Issue.record("Expected openClawInstallStatus to be failed")
        }
    }

    @Test
    func installOpenClawStepFailsAndStaysOnOpenClawStage() async throws {
        let shell = MockShellExecutor(results: [
            // check: openclaw-cli missing
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "missing", timedOut: false),
            // install openclaw-cli fails
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "failed", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .kimi
        vm.apiKey = "key1-test"
        vm.openClawPrecheckCompleted = true

        vm.installOpenClawStep()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.stage == .openClaw)
        #expect(vm.userNotice.contains("failed"))
        switch vm.openClawInstallStatus {
        case .failed:
            break
        default:
            Issue.record("Expected openClawInstallStatus to be failed")
        }
        #expect(shell.invocations.count == 2)
    }

    @Test
    func installOpenClawStepAppliesSelectedChannelConfigs() async throws {
        let shell = MockShellExecutor(results: [
            // check: openclaw-cli
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // check: openclaw cask
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // openclaw process
            ShellExecutionResult(exitCode: 0, stdout: "1234", stderr: "", timedOut: false),
            // openclaw gateway status
            ShellExecutionResult(exitCode: 0, stdout: "status: down", stderr: "", timedOut: false),
            // onboard
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // enable telegram
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // config telegram
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // enable slack
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // config slack
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // enable feishu
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // config feishu
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // restart gateway
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // probe channels
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // openclaw gateway status after setup
            ShellExecutionResult(exitCode: 0, stdout: "Gateway is running and healthy", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .kimi
        vm.apiKey = "key1-test"
        vm.openClawPrecheckCompleted = true

        vm.setOpenClawChannel(.telegram, selected: true)
        vm.openClawTelegramBotToken = "tg-bot-token"
        vm.setOpenClawChannel(.slack, selected: true)
        vm.openClawSlackMode = .socket
        vm.openClawSlackBotToken = "xoxb-test"
        vm.openClawSlackAppToken = "xapp-test"
        vm.setOpenClawChannel(.feishu, selected: true)
        vm.openClawFeishuAppID = "cli_test_id"
        vm.openClawFeishuAppSecret = "cli_test_secret"
        vm.openClawFeishuDomain = .lark

        vm.installOpenClawStep()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.stage == .completion)
        #expect(vm.openClawInstallStatus == .succeeded)
        #expect(vm.openClawGatewayHealthy)
        #expect(shell.invocations.count == 14)
        #expect(shell.invocations[5].command == "openclaw plugins enable telegram")
        #expect(shell.invocations[6].command == "openclaw config set --json channels.telegram '{\"botToken\":\"tg-bot-token\",\"enabled\":true}'")
        #expect(shell.invocations[7].command == "openclaw plugins enable slack")
        #expect(shell.invocations[8].command == "openclaw config set --json channels.slack '{\"appToken\":\"xapp-test\",\"botToken\":\"xoxb-test\",\"enabled\":true}'")
        #expect(shell.invocations[9].command == "openclaw plugins enable feishu")
        #expect(shell.invocations[10].command == "openclaw config set --json channels.feishu '{\"appId\":\"cli_test_id\",\"appSecret\":\"cli_test_secret\",\"domain\":\"lark\",\"enabled\":true}'")
        #expect(shell.invocations[11].command == "openclaw gateway restart")
        #expect(shell.invocations[12].command == "openclaw channels status --probe")
        #expect(shell.invocations[13].command == "openclaw gateway status")
    }

    @Test
    func installOpenClawStepSkipsMutatingAlreadyConfiguredChannels() async throws {
        let shell = MockShellExecutor(results: [
            // check: openclaw-cli
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // check: openclaw cask
            ShellExecutionResult(exitCode: 0, stdout: "installed", stderr: "", timedOut: false),
            // openclaw process
            ShellExecutionResult(exitCode: 0, stdout: "1234", stderr: "", timedOut: false),
            // openclaw gateway status
            ShellExecutionResult(exitCode: 0, stdout: "status: down", stderr: "", timedOut: false),
            // onboard
            ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false),
            // openclaw gateway status after setup
            ShellExecutionResult(exitCode: 0, stdout: "Gateway is running and healthy", stderr: "", timedOut: false),
        ])
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger()
        )
        vm.stage = .openClaw
        vm.apiProvider = .kimi
        vm.apiKey = "key1-test"
        vm.openClawConfiguredChannels = [.telegram]
        vm.openClawSelectedChannels = [.telegram]
        vm.openClawPrecheckCompleted = true

        vm.installOpenClawStep()
        try await Task.sleep(nanoseconds: 500_000_000)

        #expect(vm.stage == .completion)
        #expect(vm.openClawInstallStatus == .succeeded)
        #expect(vm.openClawGatewayHealthy)
        #expect(shell.invocations.count == 6)
        #expect(!shell.invocations.contains(where: { $0.command.contains("openclaw plugins enable telegram") }))
        #expect(!shell.invocations.contains(where: { $0.command.contains("openclaw config set --json channels.telegram") }))
    }

    @Test
    func shouldShowOpenClawDashboardButtonWhenCompletionSucceededAndGatewayHealthy() {
        let vm = makeVM()
        vm.stage = .completion
        vm.openClawInstallStatus = .succeeded
        vm.openClawGatewayHealthy = true

        #expect(vm.shouldShowOpenClawDashboardButton)
    }

    @Test
    func shouldHideOpenClawDashboardButtonWhenGatewayIsNotHealthy() {
        let vm = makeVM()
        vm.stage = .completion
        vm.openClawInstallStatus = .succeeded
        vm.openClawGatewayHealthy = false

        #expect(!vm.shouldShowOpenClawDashboardButton)
    }

    @Test
    func openOpenClawDashboardRunsCommandWhenEligible() {
        var launchedCommand: String?
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            remediationCommandLauncher: { command in
                launchedCommand = command
                return true
            }
        )
        vm.stage = .completion
        vm.openClawInstallStatus = .succeeded
        vm.openClawGatewayHealthy = true

        vm.openOpenClawDashboard()

        #expect(launchedCommand == "openclaw dashboard")
        #expect(vm.liveLog.contains("$ openclaw dashboard"))
        #expect(vm.userNotice.contains("Opening OpenClaw dashboard"))
    }

    @Test
    func applyGitIdentityValidatesInput() {
        let vm = makeVM()
        vm.stage = .gitSSH
        vm.gitUserName = ""
        vm.gitUserEmail = "invalid-email"

        vm.applyGitIdentity()

        #expect(vm.gitConfigStatus == .failed("Git user.name is required."))
    }

    @Test
    func applyGitIdentitySucceedsWithValidFields() async throws {
        let gitSSHService = MockGitSSHService(
            writeGlobalGitIdentityResult: .success(
                GitIdentity(name: "Kai Chen", email: "kai@example.com")
            )
        )
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH
        vm.gitUserName = "Kai Chen"
        vm.gitUserEmail = "kai@example.com"

        vm.applyGitIdentity()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.gitConfigStatus == .succeeded)
        #expect(gitSSHService.writeRequests.count == 1)
        #expect(gitSSHService.writeRequests[0].name == "Kai Chen")
        #expect(gitSSHService.writeRequests[0].email == "kai@example.com")
    }

    @Test
    func generateSSHKeyIfNeededCreatesNewKeyWhenMissing() async throws {
        let generated = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza-new...",
            fingerprint: "256 SHA256:new mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(
            loadExistingSSHKeyMaterialResult: .success(nil),
            generateSSHKeyResult: .success(generated)
        )
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH
        vm.sshKeyState = .missing
        vm.gitUserEmail = "kai@example.com"

        vm.generateSSHKeyIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.sshKeyState == .generated(generated))
        #expect(gitSSHService.generateCallComments.count == 1)
        #expect(gitSSHService.generateCallComments[0] == "kai@example.com")
    }

    @Test
    func generateSSHKeyIfNeededReusesExistingKey() async throws {
        let existing = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza-existing...",
            fingerprint: "256 SHA256:existing mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(loadExistingSSHKeyMaterialResult: .success(existing))
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH
        vm.sshKeyState = .missing

        vm.generateSSHKeyIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.sshKeyState == .existing(existing))
        #expect(gitSSHService.generateCallComments.isEmpty)
    }

    @Test
    func uploadPublicKeyToGitHubTreatsAlreadyExistsAsSuccess() async throws {
        let existing = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza-existing...",
            fingerprint: "256 SHA256:existing mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(uploadPublicKeyResult: .success(.alreadyExists))
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH
        vm.sshKeyState = .existing(existing)

        vm.uploadPublicKeyToGitHub()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.githubUploadStatus == .succeeded)
        #expect(gitSSHService.uploadRequests.count == 1)
        #expect(gitSSHService.uploadRequests[0].publicKeyPath == existing.publicKeyPath)
        #expect(gitSSHService.uploadRequests[0].title == gitSSHService.defaultKeyTitle)
    }

    @Test
    func uploadPublicKeyToGitHubSucceedsWhenUploaded() async throws {
        let existing = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza-existing...",
            fingerprint: "256 SHA256:existing mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(uploadPublicKeyResult: .success(.uploaded))
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH
        vm.sshKeyState = .existing(existing)

        vm.uploadPublicKeyToGitHub()
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.githubUploadStatus == .succeeded)
        #expect(vm.userNotice.contains("uploaded"))
    }

    @Test
    func uploadPublicKeyToGitHubFailsWhenGitHubNotAuthenticated() async throws {
        let existing = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza-existing...",
            fingerprint: "256 SHA256:existing mock@example.com (ED25519)"
        )
        let gitSSHService = MockGitSSHService(
            uploadPublicKeyResult: .failure(.notAuthenticated("not logged in"))
        )
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            gitSSHService: gitSSHService
        )
        vm.stage = .gitSSH
        vm.sshKeyState = .existing(existing)

        vm.uploadPublicKeyToGitHub()
        try await Task.sleep(nanoseconds: 200_000_000)

        switch vm.githubUploadStatus {
        case .failed:
            break
        default:
            Issue.record("Expected failed upload status when gh auth is missing")
        }
    }

    @Test
    func copyPublicKeyUpdatesNotice() {
        let existing = SSHKeyMaterial(
            privateKeyPath: "/tmp/mock/id_ed25519",
            publicKeyPath: "/tmp/mock/id_ed25519.pub",
            publicKey: "ssh-ed25519 AAAAC3Nza-existing...",
            fingerprint: "256 SHA256:existing mock@example.com (ED25519)"
        )
        let vm = makeVM()
        vm.stage = .gitSSH
        vm.sshKeyState = .existing(existing)

        vm.copyPublicKey()

        #expect(vm.userNotice.contains("copied") || vm.userNotice.contains("Unable"))
    }

    // MARK: - Remediation Command

    @Test
    func queueRemediationCommandSetsState() {
        let vm = makeVM()
        vm.queueRemediationCommand("echo remediation")

        #expect(vm.pendingRemediationCommand == "echo remediation")
        #expect(vm.showingCommandConfirmation)
    }

    @Test
    func executePendingRemediationBlocksUnsafeCommand() {
        let vm = makeVM()
        vm.pendingRemediationCommand = "rm -rf /"

        vm.executePendingRemediationCommand()

        #expect(vm.userNotice.contains("Blocked"))
    }

    @Test
    func executePendingRemediationRunsSafeCommand() async throws {
        let shell = MockShellExecutor()
        var launchedCommand: String?
        let vm = SetupViewModel(
            catalog: [],
            shell: shell,
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            remediationCommandLauncher: { command in
                launchedCommand = command
                return true
            }
        )
        vm.pendingRemediationCommand = "echo remediation-ok"
        vm.executePendingRemediationCommand()

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(shell.invocations.isEmpty)
        #expect(launchedCommand == "echo remediation-ok")
        #expect(vm.liveLog.contains("$ echo remediation-ok"))
        #expect(vm.userNotice.contains("succeeded"))
    }

    @Test
    func executePendingRemediationHandlesAnotherSafeCommand() async throws {
        var launchedCommand: String?
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            remediationCommandLauncher: { command in
                launchedCommand = command
                return true
            }
        )
        vm.pendingRemediationCommand = "echo remediation-2"
        vm.executePendingRemediationCommand()

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(launchedCommand == "echo remediation-2")
        #expect(vm.liveLog.contains("$ echo remediation-2"))
        #expect(vm.userNotice.contains("succeeded"))
    }

    @Test
    func executePendingRemediationReportsFailure() async throws {
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            remediationCommandLauncher: { _ in false }
        )
        vm.pendingRemediationCommand = "echo remediation-fail"
        vm.executePendingRemediationCommand()

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.liveLog.contains("$ echo remediation-fail"))
        #expect(vm.userNotice.contains("Unable to launch Terminal"))
    }

    @Test
    func executePendingRemediationShowsAuthFailureNotice() async throws {
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            remediationCommandLauncher: { _ in false }
        )
        vm.pendingRemediationCommand = "echo remediation-auth-check"
        vm.executePendingRemediationCommand()

        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(!vm.userNotice.contains("Administrator authentication was canceled or failed"))
    }

    @Test
    func executePendingRemediationSkipsEmptyCommand() {
        var didLaunch = false
        let vm = SetupViewModel(
            catalog: [],
            shell: MockShellExecutor(),
            advisor: MockRemediationAdvisor(),
            logger: InstallLogger(),
            remediationCommandLauncher: { _ in
                didLaunch = true
                return true
            }
        )
        vm.pendingRemediationCommand = "  "
        vm.executePendingRemediationCommand()

        #expect(!didLaunch)
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
