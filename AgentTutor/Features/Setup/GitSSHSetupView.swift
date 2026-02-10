import SwiftUI

struct GitSSHSetupView: View {
    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Configure Git & SSH")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Set your global Git identity and prepare an SSH key for GitHub access.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                gitIdentitySection
                sshSection
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 4)
        }
        .task {
            viewModel.prepareGitSSHStep()
        }
    }

    private var gitIdentitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Git Identity")
                .font(.headline)

            TextField("Name", text: $viewModel.gitUserName)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $viewModel.gitUserEmail)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Apply Git Identity") {
                    viewModel.applyGitIdentity()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canApplyGitIdentity)

                StatusBadge(status: viewModel.gitConfigStatus, idleText: "Not applied")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sshSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SSH Key")
                .font(.headline)

            sshStateSummary

            if let material = viewModel.currentSSHKeyMaterial {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Fingerprint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(material.fingerprint)
                        .font(.system(size: 11, design: .monospaced))

                    Text("Public Key Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(material.publicKeyPath)
                        .font(.footnote)
                        .textSelection(.enabled)

                    Text("Public Key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(material.publicKey)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(minHeight: 52, maxHeight: 90)
                    .padding(8)
                    .background(Color.black.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            HStack(spacing: 12) {
                if viewModel.currentSSHKeyMaterial == nil {
                    Button("Generate SSH Key") {
                        viewModel.generateSSHKeyIfNeeded()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canGenerateSSHKey)
                } else {
                    Button("Copy Public Key") {
                        viewModel.copyPublicKey()
                    }
                    .buttonStyle(.bordered)

                    Button("Upload to GitHub") {
                        viewModel.uploadPublicKeyToGitHub()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canUploadSSHKey)
                }

                StatusBadge(status: viewModel.githubUploadStatus, idleText: "Not uploaded")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var sshStateSummary: some View {
        switch viewModel.sshKeyState {
        case .checking:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking SSH key state...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        case .missing:
            Text("No SSH key found at ~/.ssh/id_ed25519. Generate one to continue.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .existing:
            Label("Existing SSH key found and reused.", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case .generated:
            Label("New SSH key generated successfully.", systemImage: "checkmark.seal.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        case let .failed(message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

private struct StatusBadge: View {
    let status: ActionStatus
    let idleText: String

    var body: some View {
        Text(statusText)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
    }

    private var statusText: String {
        switch status {
        case .idle:
            return idleText
        case .running:
            return "Running..."
        case .succeeded:
            return "Done"
        case let .failed(message):
            return message
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle:
            return .secondary
        case .running:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}
