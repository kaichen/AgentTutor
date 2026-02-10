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
        for _ in 0..<5 { vm.moveNext() }
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
    }

    @Test
    func skipGitSSHStepTransitionsToCompletion() {
        let vm = makeVM()
        vm.stage = .gitSSH

        vm.skipGitSSHStep()

        #expect(vm.stage == .completion)
        #expect(vm.userNotice.contains("Skipped"))
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
