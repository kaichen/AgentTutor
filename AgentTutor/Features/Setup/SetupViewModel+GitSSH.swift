import AppKit
import Foundation

extension SetupViewModel {
    var canApplyGitIdentity: Bool {
        !isActionRunning(gitConfigStatus)
    }

    var canGenerateSSHKey: Bool {
        if isActionRunning(githubUploadStatus) {
            return false
        }
        if case .checking = sshKeyState {
            return false
        }
        return true
    }

    var canUploadSSHKey: Bool {
        currentSSHKeyMaterial != nil && !isActionRunning(githubUploadStatus)
    }

    var currentSSHKeyMaterial: SSHKeyMaterial? {
        switch sshKeyState {
        case let .existing(material), let .generated(material):
            return material
        default:
            return nil
        }
    }

    func prepareGitSSHStep(force: Bool = false) {
        guard stage == .gitSSH else { return }
        guard force || !didPrepareGitSSHStep else { return }
        didPrepareGitSSHStep = true

        gitConfigStatus = .idle
        githubUploadStatus = .idle
        sshKeyState = .checking

        Task {
            await logger.log(level: .info, message: "git_ssh_step_entered")

            let identityResult = await gitSSHService.readGlobalGitIdentity()
            switch identityResult {
            case let .success(identity):
                gitUserName = identity.name
                gitUserEmail = identity.email
            case let .failure(error):
                gitConfigStatus = .failed(error.localizedDescription)
                await logGitSSHFailure(error, fallbackAction: "read_git_identity")
            }

            let keyResult = await gitSSHService.loadExistingSSHKeyMaterial()
            switch keyResult {
            case let .success(material?):
                sshKeyState = .existing(material)
                await logger.log(level: .info, message: "ssh_key_reused", metadata: ["public_key_path": material.publicKeyPath])
            case .success(nil):
                sshKeyState = .missing
            case let .failure(error):
                sshKeyState = .failed(error.localizedDescription)
                await logGitSSHFailure(error, fallbackAction: "read_ssh_key_state")
            }
        }
    }

    func applyGitIdentity() {
        guard !isActionRunning(gitConfigStatus) else { return }

        let name = gitUserName.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            gitConfigStatus = .failed("Git user.name is required.")
            return
        }
        guard name.count <= 100 else {
            gitConfigStatus = .failed("Git user.name must be 100 characters or fewer.")
            return
        }
        guard isValidEmail(email) else {
            gitConfigStatus = .failed("Enter a valid email address for Git user.email.")
            return
        }

        gitConfigStatus = .running

        Task {
            let writeResult = await gitSSHService.writeGlobalGitIdentity(
                GitIdentity(name: name, email: email)
            )
            switch writeResult {
            case let .success(identity):
                gitUserName = identity.name
                gitUserEmail = identity.email
                gitConfigStatus = .succeeded
                userNotice = "Git identity saved globally."
                await logger.log(level: .info, message: "git_identity_applied", metadata: [
                    "user_name_length": String(identity.name.count),
                    "has_email": String(!identity.email.isEmpty)
                ])
            case let .failure(error):
                gitConfigStatus = .failed(error.localizedDescription)
                userNotice = "Failed to apply Git identity."
                await logGitSSHFailure(error, fallbackAction: "apply_git_identity")
            }
        }
    }

    func generateSSHKeyIfNeeded() {
        guard canGenerateSSHKey else { return }

        switch sshKeyState {
        case let .existing(material), let .generated(material):
            userNotice = "SSH key is already available at \(material.publicKeyPath)."
            return
        default:
            break
        }

        sshKeyState = .checking

        Task {
            let existingResult = await gitSSHService.loadExistingSSHKeyMaterial()
            switch existingResult {
            case let .success(material?):
                sshKeyState = .existing(material)
                userNotice = "Existing SSH key reused."
                await logger.log(level: .info, message: "ssh_key_reused", metadata: ["public_key_path": material.publicKeyPath])
                return
            case .success(nil):
                break
            case let .failure(error):
                sshKeyState = .failed(error.localizedDescription)
                userNotice = "Unable to inspect SSH key state."
                await logGitSSHFailure(error, fallbackAction: "read_ssh_key_state")
                return
            }

            let comment = preferredSSHKeyComment()
            let generateResult = await gitSSHService.generateSSHKey(comment: comment)
            switch generateResult {
            case let .success(material):
                sshKeyState = .generated(material)
                userNotice = "SSH key generated at \(material.publicKeyPath)."
                await logger.log(level: .info, message: "ssh_key_generated", metadata: [
                    "public_key_path": material.publicKeyPath,
                    "fingerprint": material.fingerprint
                ])
            case let .failure(error):
                sshKeyState = .failed(error.localizedDescription)
                userNotice = "SSH key generation failed."
                await logGitSSHFailure(error, fallbackAction: "generate_ssh_key")
            }
        }
    }

    func copyPublicKey() {
        guard let material = currentSSHKeyMaterial else {
            userNotice = "Generate or reuse an SSH key first."
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(material.publicKey, forType: .string)
        userNotice = copied ? "Public key copied to clipboard." : "Unable to copy public key."
    }

    func uploadPublicKeyToGitHub() {
        guard let material = currentSSHKeyMaterial else {
            githubUploadStatus = .failed("No SSH public key is available yet.")
            return
        }
        guard !isActionRunning(githubUploadStatus) else { return }

        githubUploadStatus = .running
        let keyTitle = gitSSHService.defaultGitHubKeyTitle()

        Task {
            let uploadResult = await gitSSHService.uploadPublicKeyToGitHub(
                publicKeyPath: material.publicKeyPath,
                title: keyTitle
            )
            switch uploadResult {
            case let .success(outcome):
                githubUploadStatus = .succeeded
                switch outcome {
                case .uploaded:
                    userNotice = "SSH key uploaded to GitHub."
                    await logger.log(level: .info, message: "ssh_key_uploaded", metadata: [
                        "public_key_path": material.publicKeyPath,
                        "title": keyTitle,
                        "result": "uploaded"
                    ])
                case .alreadyExists:
                    userNotice = "This SSH key already exists on GitHub."
                    await logger.log(level: .info, message: "ssh_key_uploaded", metadata: [
                        "public_key_path": material.publicKeyPath,
                        "title": keyTitle,
                        "result": "already_exists"
                    ])
                }
            case let .failure(error):
                githubUploadStatus = .failed(error.localizedDescription)
                userNotice = "Failed to upload SSH key to GitHub."
                await logGitSSHFailure(error, fallbackAction: "upload_ssh_key")
            }
        }
    }

    func skipGitSSHStep() {
        guard stage == .gitSSH else { return }
        navigationDirection = .forward
        stage = .completion
        userNotice = "Skipped Git and SSH configuration."

        Task {
            await logger.log(level: .warning, message: "git_ssh_step_skipped")
        }
    }

    func finishGitSSHStep() {
        guard stage == .gitSSH else { return }
        navigationDirection = .forward
        stage = .completion
        if userNotice.isEmpty {
            userNotice = "Setup complete."
        }
    }

    private func isActionRunning(_ status: ActionStatus) -> Bool {
        if case .running = status {
            return true
        }
        return false
    }

    private func preferredSSHKeyComment() -> String {
        let trimmedEmail = gitUserEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        if isValidEmail(trimmedEmail) {
            return trimmedEmail
        }

        let fallbackFromSystem = "\(NSUserName())@\(Host.current().name ?? "local")"
        if isValidEmail(fallbackFromSystem) {
            return fallbackFromSystem
        }
        return "agenttutor@local"
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func gitSSHErrorMetadata(_ error: GitSSHServiceError, fallbackAction: String) -> [String: String] {
        var metadata: [String: String] = ["action": fallbackAction]

        switch error {
        case let .commandFailed(action, command, exitCode, output):
            metadata["action"] = action
            metadata["command"] = command
            metadata["exit_code"] = String(exitCode)
            metadata["stderr_summary"] = output
        case let .invalidSSHState(message),
             let .ioFailure(message),
             let .notAuthenticated(message):
            metadata["stderr_summary"] = message
        }

        return metadata
    }

    private func logGitSSHFailure(_ error: GitSSHServiceError, fallbackAction: String) async {
        await logger.log(
            level: .error,
            message: "git_ssh_action_failed",
            metadata: gitSSHErrorMetadata(error, fallbackAction: fallbackAction)
        )
    }
}
