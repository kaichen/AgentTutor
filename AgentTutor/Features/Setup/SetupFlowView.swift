import SwiftUI

struct SetupFlowView: View {
    @StateObject private var viewModel = SetupViewModel()

    var body: some View {
        VStack(spacing: 16) {
            StageHeader(stage: viewModel.stage)
            Divider()
            contentView
            Divider()
            footer
        }
        .padding(24)
        .frame(minWidth: 960, minHeight: 680)
        .alert("Run remediation command?", isPresented: $viewModel.showingCommandConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Run") {
                viewModel.executePendingRemediationCommand()
            }
        } message: {
            Text(viewModel.pendingRemediationCommand)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch viewModel.stage {
        case .welcome:
            WelcomeView()
        case .apiKey:
            APIKeyView(apiKey: $viewModel.apiKey, validationStatus: viewModel.apiKeyValidationStatus) {
                viewModel.onAPIKeyChanged()
            }
        case .selection:
            SelectionView(viewModel: viewModel)
        case .install:
            InstallView(viewModel: viewModel)
        case .completion:
            CompletionView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            if viewModel.stage == .apiKey || viewModel.stage == .selection {
                Button("Back") {
                    viewModel.moveBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Text(viewModel.userNotice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if viewModel.stage == .welcome {
                Button("Get Started") {
                    viewModel.moveNext()
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.stage == .apiKey {
                Button("Continue") {
                    viewModel.moveNext()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canAdvanceFromAPIKey)
            } else if viewModel.stage == .selection {
                Button("Start Installation") {
                    viewModel.startInstall()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.canStartInstall)
            } else if viewModel.stage == .install && viewModel.runState == .failed {
                Button("Retry") {
                    viewModel.restartInstall()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct StageHeader: View {
    let stage: SetupStage

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("AgentTutor Setup")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Spacer()
            Text(stage.title)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Prepare your Mac development environment with guided, fail-fast setup.")
                .font(.title3)
            Label("Apple Silicon + macOS 14/15 support", systemImage: "checkmark.shield")
            Label("OpenAI key required before installation", systemImage: "key")
            Label("Every failure stops immediately and includes fix commands", systemImage: "wrench.and.screwdriver")
            Label("Structured logs are kept locally for diagnostics", systemImage: "doc.text")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct APIKeyView: View {
    @Binding var apiKey: String
    let validationStatus: APIKeyValidationStatus
    let onChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Enter OpenAI API Key")
                .font(.title3)
                .fontWeight(.semibold)

            HStack(spacing: 8) {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { onChanged() }

                switch validationStatus {
                case .idle:
                    EmptyView()
                case .validating:
                    ProgressView()
                        .controlSize(.small)
                case .valid:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                case .invalid:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.title2)
                }
            }

            if case .invalid(let message) = validationStatus {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("The key is kept in memory for this session only. It is never saved to disk.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct SelectionView: View {
    @ObservedObject var viewModel: SetupViewModel

    private var groupedItems: [InstallCategory: [InstallItem]] {
        Dictionary(grouping: viewModel.catalog, by: { $0.category })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose what to install")
                    .font(.title3)
                    .fontWeight(.semibold)

                ForEach(InstallCategory.allCases, id: \.rawValue) { category in
                    if let items = groupedItems[category] {
                        Section {
                            VStack(spacing: 8) {
                                ForEach(items, id: \.id) { item in
                                    Toggle(isOn: Binding(
                                        get: { viewModel.isItemSelected(item) },
                                        set: { viewModel.setSelection($0, for: item) }
                                    )) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name)
                                            Text(item.summary)
                                                .font(.footnote)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .disabled(!viewModel.canToggle(item))
                                }
                            }
                        } header: {
                            Text(category.rawValue)
                                .font(.headline)
                        }
                    }
                }

                Text("Selected: \(viewModel.selectedItemCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct InstallView: View {
    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Progress")
                    .font(.title3)
                    .fontWeight(.semibold)

                List(viewModel.stepStates) { state in
                    HStack {
                        Text(state.item.name)
                        Spacer()
                        Text(state.status.rawValue.capitalized)
                            .foregroundStyle(color(for: state.status))
                            .fontWeight(.medium)
                    }
                }

                if let failure = viewModel.activeFailure, let advice = viewModel.remediationAdvice {
                    FailureAdviceView(failure: failure, advice: advice) { command in
                        viewModel.queueRemediationCommand(command)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Live Log")
                    .font(.title3)
                    .fontWeight(.semibold)

                ScrollView {
                    Text(viewModel.liveLog.joined(separator: "\n\n"))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(.quaternary.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack {
                    Text("Log file: \(viewModel.logFilePath)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button("Open Log Folder") {
                        viewModel.openLogFolder()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func color(for status: StepExecutionStatus) -> Color {
        switch status {
        case .pending:
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

private struct FailureAdviceView: View {
    let failure: InstallFailure
    let advice: RemediationAdvice
    let onRun: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Failure: \(failure.itemName)")
                .font(.headline)
                .foregroundStyle(.red)
            Text(advice.summary)
                .font(.subheadline)
            Text("Advice Source: \(advice.source.rawValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(advice.commands, id: \.self) { command in
                HStack {
                    Text(command)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(2)
                    Spacer()
                    Button("Run") {
                        onRun(command)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if !advice.notes.isEmpty {
                Text(advice.notes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct CompletionView: View {
    @ObservedObject var viewModel: SetupViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Setup Completed")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Your selected development environment has been installed and verified.")
            Text("Diagnostics log: \(viewModel.logFilePath)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Log Folder") {
                    viewModel.openLogFolder()
                }
                .buttonStyle(.bordered)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
