import Foundation

enum GitHubKeyUploadOutcome: Equatable, Sendable {
    case uploaded
    case alreadyExists
}

enum GitSSHServiceError: LocalizedError, Equatable, Sendable {
    case commandFailed(action: String, command: String, exitCode: Int32, output: String)
    case invalidSSHState(String)
    case ioFailure(String)
    case notAuthenticated(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(action, _, _, output):
            return "\(action) failed. \(output)"
        case let .invalidSSHState(message):
            return message
        case let .ioFailure(message):
            return message
        case let .notAuthenticated(message):
            if message.isEmpty {
                return "GitHub CLI is not authenticated. Run `gh auth login` first."
            }
            return "GitHub CLI is not authenticated. \(message)"
        }
    }
}

protocol GitSSHServicing: Sendable {
    var privateKeyPath: String { get }
    var publicKeyPath: String { get }

    func readGlobalGitIdentity() async -> Result<GitIdentity, GitSSHServiceError>
    func writeGlobalGitIdentity(_ identity: GitIdentity) async -> Result<GitIdentity, GitSSHServiceError>
    func loadExistingSSHKeyMaterial() async -> Result<SSHKeyMaterial?, GitSSHServiceError>
    func generateSSHKey(comment: String) async -> Result<SSHKeyMaterial, GitSSHServiceError>
    func uploadPublicKeyToGitHub(publicKeyPath: String, title: String) async -> Result<GitHubKeyUploadOutcome, GitSSHServiceError>
    func defaultGitHubKeyTitle() -> String
}

final class GitSSHService: GitSSHServicing {
    private let shell: ShellExecuting
    private let fileManager: FileManager
    private let homeDirectoryURL: URL
    private let hostNameProvider: @Sendable () -> String

    init(
        shell: ShellExecuting = ShellExecutor(),
        fileManager: FileManager = .default,
        homeDirectoryURL: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        hostNameProvider: @escaping @Sendable () -> String = { ProcessInfo.processInfo.hostName }
    ) {
        self.shell = shell
        self.fileManager = fileManager
        self.homeDirectoryURL = homeDirectoryURL
        self.hostNameProvider = hostNameProvider
    }

    var privateKeyPath: String {
        sshDirectoryURL.appendingPathComponent("id_ed25519", isDirectory: false).path
    }

    var publicKeyPath: String {
        sshDirectoryURL.appendingPathComponent("id_ed25519.pub", isDirectory: false).path
    }

    private var sshDirectoryURL: URL {
        homeDirectoryURL.appendingPathComponent(".ssh", isDirectory: true)
    }

    func readGlobalGitIdentity() async -> Result<GitIdentity, GitSSHServiceError> {
        let nameResult = await readGlobalGitValue(for: "user.name")
        let emailResult = await readGlobalGitValue(for: "user.email")

        switch (nameResult, emailResult) {
        case let (.success(name), .success(email)):
            return .success(GitIdentity(name: name, email: email))
        case let (.failure(error), _):
            return .failure(error)
        case let (_, .failure(error)):
            return .failure(error)
        }
    }

    func writeGlobalGitIdentity(_ identity: GitIdentity) async -> Result<GitIdentity, GitSSHServiceError> {
        let setNameCommand = "git config --global user.name \(ShellEscaping.singleQuoted(identity.name))"
        let setNameResult = await run(command: setNameCommand, timeoutSeconds: 30)
        guard setNameResult.exitCode == 0 else {
            return .failure(commandFailure(action: "set_git_user_name", command: setNameCommand, result: setNameResult))
        }

        let setEmailCommand = "git config --global user.email \(ShellEscaping.singleQuoted(identity.email))"
        let setEmailResult = await run(command: setEmailCommand, timeoutSeconds: 30)
        guard setEmailResult.exitCode == 0 else {
            return .failure(commandFailure(action: "set_git_user_email", command: setEmailCommand, result: setEmailResult))
        }

        let readBackResult = await readGlobalGitIdentity()
        switch readBackResult {
        case let .success(readBack):
            if readBack.name == identity.name && readBack.email == identity.email {
                return .success(readBack)
            }
            return .failure(.invalidSSHState("Git identity write verification failed. Please retry."))
        case let .failure(error):
            return .failure(error)
        }
    }

    func loadExistingSSHKeyMaterial() async -> Result<SSHKeyMaterial?, GitSSHServiceError> {
        let hasPrivateKey = fileManager.fileExists(atPath: privateKeyPath)
        let hasPublicKey = fileManager.fileExists(atPath: publicKeyPath)

        if !hasPrivateKey && !hasPublicKey {
            return .success(nil)
        }

        guard hasPrivateKey && hasPublicKey else {
            return .failure(.invalidSSHState("Detected partial SSH key files. Keep both id_ed25519 and id_ed25519.pub together."))
        }

        let materialResult = await readSSHKeyMaterial()
        switch materialResult {
        case let .success(material):
            return .success(material)
        case let .failure(error):
            return .failure(error)
        }
    }

    func generateSSHKey(comment: String) async -> Result<SSHKeyMaterial, GitSSHServiceError> {
        let prepareDirectoryCommand = "mkdir -p \(ShellEscaping.singleQuoted(sshDirectoryURL.path)) && chmod 700 \(ShellEscaping.singleQuoted(sshDirectoryURL.path))"
        let prepareDirectoryResult = await run(command: prepareDirectoryCommand, timeoutSeconds: 30)
        guard prepareDirectoryResult.exitCode == 0 else {
            return .failure(commandFailure(action: "prepare_ssh_directory", command: prepareDirectoryCommand, result: prepareDirectoryResult))
        }

        let generateCommand = "ssh-keygen -t ed25519 -C \(ShellEscaping.singleQuoted(comment)) -f \(ShellEscaping.singleQuoted(privateKeyPath)) -N ''"
        let generateResult = await run(command: generateCommand, timeoutSeconds: 90)
        guard generateResult.exitCode == 0 else {
            return .failure(commandFailure(action: "generate_ssh_key", command: generateCommand, result: generateResult))
        }

        let loadResult = await loadExistingSSHKeyMaterial()
        switch loadResult {
        case let .success(material?):
            return .success(material)
        case .success(nil):
            return .failure(.invalidSSHState("ssh-keygen reported success but key files are missing."))
        case let .failure(error):
            return .failure(error)
        }
    }

    func uploadPublicKeyToGitHub(publicKeyPath: String, title: String) async -> Result<GitHubKeyUploadOutcome, GitSSHServiceError> {
        let authStatusResult = await run(command: GitHubAuthPolicy.statusCommand, timeoutSeconds: 30)
        guard authStatusResult.exitCode == 0 else {
            return .failure(.notAuthenticated(normalized(output: authStatusResult.combinedOutput)))
        }

        let uploadCommand = "gh ssh-key add \(ShellEscaping.singleQuoted(publicKeyPath)) --title \(ShellEscaping.singleQuoted(title))"
        let uploadResult = await run(command: uploadCommand, timeoutSeconds: 120)
        if uploadResult.exitCode == 0 {
            return .success(.uploaded)
        }

        let output = normalized(output: uploadResult.combinedOutput).lowercased()
        if output.contains("already in use") || output.contains("already exists") || output.contains("key is already") {
            return .success(.alreadyExists)
        }

        return .failure(commandFailure(action: "upload_ssh_key", command: uploadCommand, result: uploadResult))
    }

    func defaultGitHubKeyTitle() -> String {
        let user = sanitizeTitleComponent(NSUserName())
        let host = sanitizeTitleComponent(hostNameProvider())
        return "AgentTutor-\(user)-\(host)-ed25519"
    }

    private func readGlobalGitValue(for key: String) async -> Result<String, GitSSHServiceError> {
        let command = "git config --global --get \(key)"
        let result = await run(command: command, timeoutSeconds: 30)
        if result.exitCode == 0 {
            return .success(normalized(output: result.stdout))
        }
        if result.exitCode == 1 {
            return .success("")
        }
        return .failure(commandFailure(action: "read_\(key.replacingOccurrences(of: ".", with: "_"))", command: command, result: result))
    }

    private func readSSHKeyMaterial() async -> Result<SSHKeyMaterial, GitSSHServiceError> {
        do {
            let publicKeyRaw = try String(contentsOfFile: publicKeyPath, encoding: .utf8)
            let publicKey = normalized(output: publicKeyRaw)
            guard !publicKey.isEmpty else {
                return .failure(.invalidSSHState("SSH public key file is empty."))
            }

            let fingerprintCommand = "ssh-keygen -lf \(ShellEscaping.singleQuoted(publicKeyPath))"
            let fingerprintResult = await run(command: fingerprintCommand, timeoutSeconds: 30)
            guard fingerprintResult.exitCode == 0 else {
                return .failure(commandFailure(action: "read_ssh_fingerprint", command: fingerprintCommand, result: fingerprintResult))
            }

            let fingerprintLine = fingerprintResult.stdout
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first ?? normalized(output: fingerprintResult.combinedOutput)
            let fingerprint = normalized(output: fingerprintLine)
            guard !fingerprint.isEmpty else {
                return .failure(.invalidSSHState("SSH fingerprint is unavailable."))
            }

            return .success(
                SSHKeyMaterial(
                    privateKeyPath: privateKeyPath,
                    publicKeyPath: publicKeyPath,
                    publicKey: publicKey,
                    fingerprint: fingerprint
                )
            )
        } catch {
            return .failure(.ioFailure("Unable to read SSH key files: \(error.localizedDescription)"))
        }
    }

    private func run(command: String, timeoutSeconds: TimeInterval) async -> ShellExecutionResult {
        await shell.run(command: command, requiresAdmin: false, timeoutSeconds: timeoutSeconds)
    }

    private func commandFailure(action: String, command: String, result: ShellExecutionResult) -> GitSSHServiceError {
        .commandFailed(
            action: action,
            command: command,
            exitCode: result.exitCode,
            output: normalized(output: result.combinedOutput)
        )
    }

    private func normalized(output: String) -> String {
        output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sanitizeTitleComponent(_ value: String) -> String {
        let replaced = value.replacingOccurrences(
            of: "[^A-Za-z0-9._-]+",
            with: "-",
            options: .regularExpression
        )
        let trimmed = replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "unknown" : trimmed
    }
}
