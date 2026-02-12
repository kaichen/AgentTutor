import SwiftUI

struct OpenClawSetupView: View {
    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Install OpenClaw (Optional)")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("Final step. Install OpenClaw CLI and desktop app, or skip for now.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                commandCard(
                    title: "CLI",
                    command: "brew install openclaw-cli"
                )
                commandCard(
                    title: "Desktop App",
                    command: "brew install --cask openclaw"
                )

                statusCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 4)
        }
    }

    private func commandCard(title: String, command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            switch viewModel.openClawInstallStatus {
            case .idle:
                Text("Ready to install OpenClaw.")
                    .foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Installing OpenClaw...")
                        .foregroundStyle(.secondary)
                }
            case .succeeded:
                Label("OpenClaw installed.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .failed(message):
                Text(message)
                    .foregroundStyle(.red)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
