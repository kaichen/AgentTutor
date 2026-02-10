import Foundation
import Testing
@testable import AgentTutor

struct GitSSHServiceTests {

    @Test
    func writeGlobalGitIdentityEscapesShellArguments() async {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "Kai O'Connor\n", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "kai.o'connor@example.com\n", stderr: "", timedOut: false),
        ])
        let service = GitSSHService(shell: shell, homeDirectoryURL: URL(fileURLWithPath: "/tmp/mock-home", isDirectory: true))

        let identity = GitIdentity(name: "Kai O'Connor", email: "kai.o'connor@example.com")
        let result = await service.writeGlobalGitIdentity(identity)

        switch result {
        case let .success(written):
            #expect(written == identity)
        case let .failure(error):
            Issue.record("Expected success, got error: \(error)")
        }

        #expect(shell.invocations.count == 4)
        #expect(shell.invocations[0].command.contains("git config --global user.name"))
        #expect(shell.invocations[0].command.contains(ShellEscaping.singleQuoted(identity.name)))
        #expect(shell.invocations[1].command.contains("git config --global user.email"))
        #expect(shell.invocations[1].command.contains(ShellEscaping.singleQuoted(identity.email)))
    }

    @Test
    func loadExistingSSHKeyMaterialReturnsMissingWhenFilesAbsent() async throws {
        let tempHome = makeTempHomeDirectory()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let shell = MockShellExecutor()
        let service = GitSSHService(shell: shell, homeDirectoryURL: tempHome)
        let result = await service.loadExistingSSHKeyMaterial()

        switch result {
        case .success(nil):
            #expect(true)
        case .success:
            Issue.record("Expected nil SSH key material for missing files")
        case let .failure(error):
            Issue.record("Expected missing SSH key to be non-fatal, got: \(error)")
        }

        #expect(shell.invocations.isEmpty)
    }

    @Test
    func loadExistingSSHKeyMaterialReadsFingerprint() async throws {
        let tempHome = makeTempHomeDirectory()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let sshDirectory = tempHome.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let privatePath = sshDirectory.appendingPathComponent("id_ed25519")
        let publicPath = sshDirectory.appendingPathComponent("id_ed25519.pub")
        try "PRIVATE".write(to: privatePath, atomically: true, encoding: .utf8)
        try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest me@example.com\n".write(to: publicPath, atomically: true, encoding: .utf8)

        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "256 SHA256:abc me@example.com (ED25519)\n", stderr: "", timedOut: false),
        ])
        let service = GitSSHService(shell: shell, homeDirectoryURL: tempHome)
        let result = await service.loadExistingSSHKeyMaterial()

        switch result {
        case let .success(material?):
            #expect(material.privateKeyPath == privatePath.path)
            #expect(material.publicKeyPath == publicPath.path)
            #expect(material.publicKey.contains("ssh-ed25519"))
            #expect(material.fingerprint.contains("SHA256:abc"))
        case .success(nil):
            Issue.record("Expected existing SSH key material")
        case let .failure(error):
            Issue.record("Unexpected error: \(error)")
        }

        #expect(shell.invocations.count == 1)
        #expect(shell.invocations[0].command.contains("ssh-keygen -lf"))
    }

    @Test
    func generateSSHKeyUsesExpectedCommandFlags() async throws {
        let tempHome = makeTempHomeDirectory()
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let sshDirectory = tempHome.appendingPathComponent(".ssh", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDirectory, withIntermediateDirectories: true)
        let privatePath = sshDirectory.appendingPathComponent("id_ed25519")
        let publicPath = sshDirectory.appendingPathComponent("id_ed25519.pub")
        try "PRIVATE".write(to: privatePath, atomically: true, encoding: .utf8)
        try "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest me@example.com\n".write(to: publicPath, atomically: true, encoding: .utf8)

        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "generated", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 0, stdout: "256 SHA256:new me@example.com (ED25519)\n", stderr: "", timedOut: false),
        ])
        let service = GitSSHService(shell: shell, homeDirectoryURL: tempHome)
        let result = await service.generateSSHKey(comment: "me@example.com")

        switch result {
        case .success:
            #expect(true)
        case let .failure(error):
            Issue.record("Expected generation success, got: \(error)")
        }

        #expect(shell.invocations.count == 3)
        #expect(shell.invocations[0].command.contains("mkdir -p"))
        #expect(shell.invocations[0].command.contains("chmod 700"))
        #expect(shell.invocations[1].command.contains("ssh-keygen -t ed25519"))
        #expect(shell.invocations[1].command.contains("-N ''"))
        #expect(shell.invocations[1].command.contains(ShellEscaping.singleQuoted(privatePath.path)))
    }

    @Test
    func uploadPublicKeyHandlesAlreadyExistsAsSuccess() async {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false),
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "key is already in use", timedOut: false),
        ])
        let service = GitSSHService(shell: shell, homeDirectoryURL: URL(fileURLWithPath: "/tmp/mock-home", isDirectory: true))
        let result = await service.uploadPublicKeyToGitHub(publicKeyPath: "/tmp/mock-home/.ssh/id_ed25519.pub", title: "AgentTutor-key")

        #expect(result == .success(.alreadyExists))
        #expect(shell.invocations.count == 2)
        #expect(shell.invocations[0].command == GitHubAuthPolicy.statusCommand)
        #expect(shell.invocations[1].command.contains("gh ssh-key add"))
    }

    @Test
    func uploadPublicKeyFailsWhenGitHubAuthMissing() async {
        let shell = MockShellExecutor(results: [
            ShellExecutionResult(exitCode: 1, stdout: "", stderr: "not logged in", timedOut: false),
        ])
        let service = GitSSHService(shell: shell, homeDirectoryURL: URL(fileURLWithPath: "/tmp/mock-home", isDirectory: true))
        let result = await service.uploadPublicKeyToGitHub(publicKeyPath: "/tmp/mock-home/.ssh/id_ed25519.pub", title: "AgentTutor-key")

        switch result {
        case .success:
            Issue.record("Expected notAuthenticated failure")
        case let .failure(error):
            #expect(error == .notAuthenticated("not logged in"))
        }
    }

    private func makeTempHomeDirectory() -> URL {
        let root = FileManager.default.temporaryDirectory
        let directory = root.appendingPathComponent("AgentTutor-GitSSHServiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
