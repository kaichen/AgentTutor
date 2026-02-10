import Foundation
@testable import AgentTutor

// MARK: - Mock ShellExecuting

final class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    struct Invocation: Sendable {
        let command: String
        let authMode: CommandAuthMode
        let timeoutSeconds: TimeInterval
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private var _results: [ShellExecutionResult]
    private var _resultIndex = 0

    var invocations: [Invocation] {
        lock.withLock { _invocations }
    }

    /// Supply a sequence of results to return in order. Cycles back to the last one if exhausted.
    init(results: [ShellExecutionResult] = []) {
        _results = results.isEmpty
            ? [ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false)]
            : results
    }

    func run(command: String, authMode: CommandAuthMode, timeoutSeconds: TimeInterval) async -> ShellExecutionResult {
        lock.withLock {
            _invocations.append(Invocation(command: command, authMode: authMode, timeoutSeconds: timeoutSeconds))
            let result = _results[min(_resultIndex, _results.count - 1)]
            _resultIndex += 1
            return result
        }
    }
}

// MARK: - Mock RemediationAdvising

final class MockRemediationAdvisor: RemediationAdvising, @unchecked Sendable {
    private let lock = NSLock()
    private var _suggestCallCount = 0
    var fixedAdvice: RemediationAdvice

    var suggestCallCount: Int {
        lock.withLock { _suggestCallCount }
    }

    init(advice: RemediationAdvice = RemediationAdvice(
        summary: "Mock advice",
        commands: ["echo fix"],
        notes: "Mock notes",
        source: .heuristics
    )) {
        fixedAdvice = advice
    }

    func suggest(failure: InstallFailure, hints: [String], apiKey: String, baseURL: String) async -> RemediationAdvice {
        lock.withLock { _suggestCallCount += 1 }
        return fixedAdvice
    }
}

// MARK: - Mock GitSSHServicing

final class MockGitSSHService: GitSSHServicing, @unchecked Sendable {
    private let lock = NSLock()

    var privateKeyPath: String
    var publicKeyPath: String
    var readGlobalGitIdentityResult: Result<GitIdentity, GitSSHServiceError>
    var writeGlobalGitIdentityResult: Result<GitIdentity, GitSSHServiceError>
    var loadExistingSSHKeyMaterialResult: Result<SSHKeyMaterial?, GitSSHServiceError>
    var generateSSHKeyResult: Result<SSHKeyMaterial, GitSSHServiceError>
    var uploadPublicKeyResult: Result<GitHubKeyUploadOutcome, GitSSHServiceError>
    var defaultKeyTitle = "AgentTutor-test-key"

    private(set) var writeRequests: [GitIdentity] = []
    private(set) var loadSSHKeyCallCount = 0
    private(set) var generateCallComments: [String] = []
    private(set) var uploadRequests: [(publicKeyPath: String, title: String)] = []

    init(
        privateKeyPath: String = "/tmp/mock/id_ed25519",
        publicKeyPath: String = "/tmp/mock/id_ed25519.pub",
        readGlobalGitIdentityResult: Result<GitIdentity, GitSSHServiceError> = .success(GitIdentity(name: "", email: "")),
        writeGlobalGitIdentityResult: Result<GitIdentity, GitSSHServiceError> = .success(GitIdentity(name: "Test User", email: "test@example.com")),
        loadExistingSSHKeyMaterialResult: Result<SSHKeyMaterial?, GitSSHServiceError> = .success(nil),
        generateSSHKeyResult: Result<SSHKeyMaterial, GitSSHServiceError> = .success(
            SSHKeyMaterial(
                privateKeyPath: "/tmp/mock/id_ed25519",
                publicKeyPath: "/tmp/mock/id_ed25519.pub",
                publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestKey test@example.com",
                fingerprint: "256 SHA256:mockfingerprint test@example.com (ED25519)"
            )
        ),
        uploadPublicKeyResult: Result<GitHubKeyUploadOutcome, GitSSHServiceError> = .success(.uploaded)
    ) {
        self.privateKeyPath = privateKeyPath
        self.publicKeyPath = publicKeyPath
        self.readGlobalGitIdentityResult = readGlobalGitIdentityResult
        self.writeGlobalGitIdentityResult = writeGlobalGitIdentityResult
        self.loadExistingSSHKeyMaterialResult = loadExistingSSHKeyMaterialResult
        self.generateSSHKeyResult = generateSSHKeyResult
        self.uploadPublicKeyResult = uploadPublicKeyResult
    }

    func readGlobalGitIdentity() async -> Result<GitIdentity, GitSSHServiceError> {
        lock.withLock {
            readGlobalGitIdentityResult
        }
    }

    func writeGlobalGitIdentity(_ identity: GitIdentity) async -> Result<GitIdentity, GitSSHServiceError> {
        lock.withLock {
            writeRequests.append(identity)
            return writeGlobalGitIdentityResult
        }
    }

    func loadExistingSSHKeyMaterial() async -> Result<SSHKeyMaterial?, GitSSHServiceError> {
        lock.withLock {
            loadSSHKeyCallCount += 1
            return loadExistingSSHKeyMaterialResult
        }
    }

    func generateSSHKey(comment: String) async -> Result<SSHKeyMaterial, GitSSHServiceError> {
        lock.withLock {
            generateCallComments.append(comment)
            return generateSSHKeyResult
        }
    }

    func uploadPublicKeyToGitHub(publicKeyPath: String, title: String) async -> Result<GitHubKeyUploadOutcome, GitSSHServiceError> {
        lock.withLock {
            uploadRequests.append((publicKeyPath: publicKeyPath, title: title))
            return uploadPublicKeyResult
        }
    }

    func defaultGitHubKeyTitle() -> String {
        defaultKeyTitle
    }
}

// MARK: - Test Fixtures

enum TestFixtures {
    static func makeItem(
        id: String = "test-item",
        name: String = "Test Item",
        category: InstallCategory = .cli,
        isRequired: Bool = false,
        defaultSelected: Bool = false,
        dependencies: [String] = [],
        commands: [InstallCommand] = [InstallCommand("echo install")],
        verificationChecks: [InstallVerificationCheck] = [InstallVerificationCheck("default", command: "echo ok")],
        remediationHints: [String] = ["Try again"]
    ) -> InstallItem {
        InstallItem(
            id: id,
            name: name,
            summary: "Test item: \(name)",
            category: category,
            isRequired: isRequired,
            defaultSelected: defaultSelected,
            dependencies: dependencies,
            commands: commands,
            verificationChecks: verificationChecks,
            remediationHints: remediationHints
        )
    }

    static func makeFailure(
        itemID: String = "test-item",
        itemName: String = "Test Item",
        failedCommand: String = "echo fail",
        output: String = "error occurred",
        exitCode: Int32 = 1,
        timedOut: Bool = false
    ) -> InstallFailure {
        InstallFailure(
            itemID: itemID,
            itemName: itemName,
            failedCommand: failedCommand,
            output: output,
            exitCode: exitCode,
            timedOut: timedOut
        )
    }

    /// A minimal catalog with dependency chain: base -> mid -> leaf
    static var chainCatalog: [InstallItem] {
        [
            makeItem(id: "base", name: "Base", isRequired: true, defaultSelected: true),
            makeItem(id: "mid", name: "Mid", defaultSelected: true, dependencies: ["base"]),
            makeItem(id: "leaf", name: "Leaf", dependencies: ["mid"]),
        ]
    }
}
