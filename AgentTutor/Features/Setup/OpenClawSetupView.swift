import SwiftUI

struct OpenClawSetupView: View {
    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                providerSection
                installSection
                channelsSection
                validationSection
                statusCard
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.vertical, 4)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Initialize OpenClaw (Optional)")
                .font(.title3)
                .fontWeight(.semibold)
            Text("One-click flow installs OpenClaw, runs non-interactive onboarding, and applies selected channel configuration.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Onboarding Provider (API Key Step)")
                    .font(.headline)
                Spacer()
                Text(viewModel.apiProvider.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Label(viewModel.openClawProviderSupportMessage, systemImage: providerIconName)
                .font(.footnote)
                .foregroundStyle(viewModel.isOpenClawProviderConfigured ? .green : .red)

            Text("Credential source: `key1` from API Key step.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("Command mode: `openclaw onboard --non-interactive --accept-risk --mode local`")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var installSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Install Targets")
                .font(.headline)

            commandSnippet("brew install openclaw-cli")
            commandSnippet("brew install --cask openclaw")
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Channels")
                .font(.headline)
            Text("Select channels to enable and configure. Leave all unchecked to onboard without channel setup.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            channelToggle(.telegram)
            if viewModel.isOpenClawChannelSelected(.telegram) {
                SecureField("Telegram Bot Token", text: $viewModel.openClawTelegramBotToken)
                    .textFieldStyle(.roundedBorder)
            }

            Divider()

            channelToggle(.slack)
            if viewModel.isOpenClawChannelSelected(.slack) {
                Picker("Slack Mode", selection: $viewModel.openClawSlackMode) {
                    ForEach(OpenClawSlackMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                SecureField("Slack Bot Token", text: $viewModel.openClawSlackBotToken)
                    .textFieldStyle(.roundedBorder)

                switch viewModel.openClawSlackMode {
                case .socket:
                    SecureField("Slack App Token", text: $viewModel.openClawSlackAppToken)
                        .textFieldStyle(.roundedBorder)
                case .http:
                    SecureField("Slack Signing Secret", text: $viewModel.openClawSlackSigningSecret)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            channelToggle(.feishu)
            if viewModel.isOpenClawChannelSelected(.feishu) {
                TextField("Feishu App ID", text: $viewModel.openClawFeishuAppID)
                    .textFieldStyle(.roundedBorder)
                SecureField("Feishu App Secret", text: $viewModel.openClawFeishuAppSecret)
                    .textFieldStyle(.roundedBorder)

                Picker("Domain", selection: $viewModel.openClawFeishuDomain) {
                    ForEach(OpenClawFeishuDomain.allCases) { domain in
                        Text(domain.rawValue).tag(domain)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var validationSection: some View {
        if !viewModel.openClawValidationErrors.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Before Initialize")
                    .font(.headline)
                ForEach(viewModel.openClawValidationErrors, id: \.self) { error in
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            .background(.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func channelToggle(_ channel: OpenClawChannel) -> some View {
        Toggle(
            channel.displayName,
            isOn: Binding(
                get: { viewModel.isOpenClawChannelSelected(channel) },
                set: { viewModel.setOpenClawChannel(channel, selected: $0) }
            )
        )
        .toggleStyle(.checkbox)
    }

    private func commandSnippet(_ command: String) -> some View {
        Text(command)
            .font(.system(size: 12, design: .monospaced))
            .textSelection(.enabled)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var providerIconName: String {
        viewModel.isOpenClawProviderConfigured ? "checkmark.circle.fill" : "xmark.circle.fill"
    }

    @ViewBuilder
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Status")
                .font(.headline)

            switch viewModel.openClawInstallStatus {
            case .idle:
                Text("Ready to initialize OpenClaw.")
                    .foregroundStyle(.secondary)
            case .running:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Initializing OpenClaw...")
                        .foregroundStyle(.secondary)
                }
            case .succeeded:
                Label("OpenClaw initialized.", systemImage: "checkmark.circle.fill")
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
