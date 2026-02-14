import SwiftUI

struct SetupFlowView: View {
    @StateObject private var viewModel = SetupViewModel()

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                StepIndicator(currentStage: viewModel.stage)
            }
            Divider()
            ZStack {
                contentView
                    .id(viewModel.stage)
                    .transition(.asymmetric(
                        insertion: .move(edge: viewModel.navigationDirection == .forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: viewModel.navigationDirection == .forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .clipped()
            .animation(.spring(duration: 0.35, bounce: 0.1), value: viewModel.stage)
            Divider()
            footer
        }
        .padding(24)
        .alert("Run remediation command in Terminal?", isPresented: $viewModel.showingCommandConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Open Terminal") {
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
            APIKeyView(
                provider: $viewModel.apiProvider,
                apiKey: $viewModel.apiKey,
                baseURL: $viewModel.apiBaseURL,
                validationStatus: viewModel.apiKeyValidationStatus,
                onProviderChanged: { viewModel.onProviderChanged() },
                onKeyChanged: { viewModel.onAPIKeyChanged() },
                onBaseURLChanged: { viewModel.onBaseURLChanged() }
            )
        case .selection:
            SelectionView(viewModel: viewModel)
        case .install:
            InstallView(viewModel: viewModel)
        case .gitSSH:
            GitSSHSetupView(viewModel: viewModel)
        case .openClaw:
            OpenClawSetupView(viewModel: viewModel)
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
            } else if viewModel.stage == .gitSSH {
                Button("Skip for now") {
                    viewModel.skipGitSSHStep()
                }
                .buttonStyle(.bordered)
            } else if viewModel.stage == .openClaw {
                Button("Skip for now") {
                    viewModel.skipOpenClawStep()
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canSkipOpenClawStep)
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
            } else if viewModel.stage == .gitSSH {
                Button("Continue") {
                    viewModel.finishGitSSHStep()
                }
                .buttonStyle(.borderedProminent)
            } else if viewModel.stage == .openClaw {
                if viewModel.shouldShowOpenClawInitializeButton {
                    Button(openClawPrimaryButtonTitle) {
                        viewModel.installOpenClawStep()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canInstallOpenClaw)
                }
            }
        }
    }

    private var openClawPrimaryButtonTitle: String {
        switch viewModel.openClawInstallStatus {
        case .idle:
            return "Initialize OpenClaw"
        case .running:
            return "Initializing..."
        case .succeeded:
            return "Initialize OpenClaw"
        case .failed:
            return "Retry Initialize"
        }
    }
}

// MARK: - Step Indicator

private struct StepIndicator: View {
    let currentStage: SetupStage
    private let stages = SetupStage.allCases

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(stages, id: \.rawValue) { stage in
                VStack(spacing: 5) {
                    ZStack {
                        Circle()
                            .fill(circleColor(for: stage))
                            .frame(width: 20, height: 20)

                        if stage.rawValue < currentStage.rawValue || (stage == currentStage && currentStage == .completion) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .transition(.scale.combined(with: .opacity))
                        } else if stage == currentStage {
                            Circle()
                                .fill(.white)
                                .frame(width: 6, height: 6)
                                .phaseAnimator([false, true]) { content, phase in
                                    content
                                        .scaleEffect(phase ? 1.5 : 1.0)
                                        .opacity(phase ? 0.5 : 1.0)
                                } animation: { _ in
                                    .easeInOut(duration: 1.2)
                                }
                        }
                    }

                    Text(label(for: stage))
                        .font(.caption2)
                        .foregroundStyle(stage == currentStage ? .primary : .secondary)
                }
                .frame(width: 76)

                if stage.rawValue < stages.count - 1 {
                    Rectangle()
                        .fill(stage.rawValue < currentStage.rawValue ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 1.5)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 9)
                }
            }
        }
        .padding(.horizontal, 60)
        .animation(.easeInOut(duration: 0.35), value: currentStage)
    }

    private func label(for stage: SetupStage) -> String {
        switch stage {
        case .welcome: "Welcome"
        case .apiKey: "API Key"
        case .selection: "Select"
        case .install: "Install"
        case .gitSSH: "Git/SSH"
        case .openClaw: "OpenClaw"
        case .completion: "Done"
        }
    }

    private func circleColor(for stage: SetupStage) -> Color {
        if stage.rawValue <= currentStage.rawValue {
            return .accentColor
        }
        return Color.secondary.opacity(0.3)
    }
}

// MARK: - Welcome

private struct FeatureInfo: Identifiable {
    let id: String
    let icon: String
    let title: String
    let description: String

    init(_ icon: String, _ title: String, _ description: String) {
        self.id = title
        self.icon = icon
        self.title = title
        self.description = description
    }
}

private struct WelcomeView: View {
    private let features = [
        FeatureInfo("checkmark.shield", "Apple Silicon Ready", "Full support for macOS 14 & 15 on Apple Silicon"),
        FeatureInfo("key", "LLM Provider Support", "Works with OpenAI, OpenRouter, Kimi, and MiniMax keys"),
        FeatureInfo("wrench.and.screwdriver", "Fail-Fast Recovery", "Every failure stops immediately with fix commands"),
        FeatureInfo("doc.text", "Diagnostic Logs", "Structured logs kept locally for troubleshooting"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Prepare your Mac for development")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Guided, automated environment setup with intelligent error recovery.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(features) { feature in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: feature.icon)
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 36)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - API Key

private struct APIKeyView: View {
    @Binding var provider: LLMProvider
    @Binding var apiKey: String
    @Binding var baseURL: String
    let validationStatus: APIKeyValidationStatus
    let onProviderChanged: () -> Void
    let onKeyChanged: () -> Void
    let onBaseURLChanged: () -> Void
    @State private var isBaseURLExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LLM API Configuration")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Provider")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Picker("Provider", selection: $provider) {
                ForEach(LLMProvider.allCases) { item in
                    Text(item.displayName).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: provider) {
                onProviderChanged()
                syncBaseURLDisclosureState(for: provider)
            }

            HStack(spacing: 6) {
                Text("Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(provider.defaultModelName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
            }

            DisclosureGroup(isExpanded: $isBaseURLExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Base URL")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(provider.defaultBaseURL, text: $baseURL)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: baseURL) { onBaseURLChanged() }

                    if !provider.endpointPresets.isEmpty {
                        HStack(spacing: 8) {
                            Text("Endpoint")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            ForEach(provider.endpointPresets) { preset in
                                endpointPresetButton(for: preset)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack {
                    Text("Base URL")
                    Spacer()
                    Text(baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text("API Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(provider.apiKeyPlaceholder, text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: apiKey) { onKeyChanged() }

                ZStack {
                    switch validationStatus {
                    case .idle:
                        EmptyView()
                    case .validating:
                        ProgressView()
                            .controlSize(.small)
                            .transition(.opacity)
                    case .valid:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.title2)
                            .transition(.scale.combined(with: .opacity))
                    case .invalid:
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.title2)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.3), value: validationStatus)
            }

            if case .invalid(let message) = validationStatus {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Text("Base URL auto-switches with provider. Expand Base URL only if you need a custom endpoint.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("The key is kept in memory for this session only. It is never saved to disk.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .onAppear {
            syncBaseURLDisclosureState(for: provider)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func syncBaseURLDisclosureState(for provider: LLMProvider) {
        isBaseURLExpanded = !provider.endpointPresets.isEmpty
    }

    private func applyEndpointPreset(_ preset: LLMProvider.EndpointPreset) {
        baseURL = preset.baseURL
        onBaseURLChanged()
    }

    @ViewBuilder
    private func endpointPresetButton(for preset: LLMProvider.EndpointPreset) -> some View {
        if isPresetSelected(preset) {
            Button(preset.label) {
                applyEndpointPreset(preset)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        } else {
            Button(preset.label) {
                applyEndpointPreset(preset)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func isPresetSelected(_ preset: LLMProvider.EndpointPreset) -> Bool {
        normalizedBaseURL(baseURL) == normalizedBaseURL(preset.baseURL)
    }

    private func normalizedBaseURL(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

// MARK: - Selection

private struct SelectionView: View {
    @ObservedObject var viewModel: SetupViewModel

    private var groupedItems: [InstallCategory: [InstallItem]] {
        Dictionary(grouping: viewModel.catalog, by: { $0.category })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose what to install")
                    .font(.title2)
                    .fontWeight(.semibold)

                ForEach(InstallCategory.allCases, id: \.rawValue) { category in
                    if let items = groupedItems[category] {
                        Divider()
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.rawValue)
                                .font(.headline)

                            ForEach(items, id: \.id) { item in
                                Toggle(isOn: Binding(
                                    get: { viewModel.isItemSelected(item) },
                                    set: { viewModel.setSelection($0, for: item) }
                                )) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 6) {
                                            Text(item.name)
                                                .font(.body)
                                            if item.isRequired {
                                                Text("Required")
                                                    .font(.caption2)
                                                    .fontWeight(.medium)
                                                    .foregroundStyle(.white)
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.orange)
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        Text(item.summary)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(!viewModel.canToggle(item))
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }

                HStack {
                    Spacer()
                    Text("\(viewModel.selectedItemCount) of \(viewModel.catalog.count) selected")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

// MARK: - Install

private struct InstallView: View {
    @ObservedObject var viewModel: SetupViewModel

    private var groupedSteps: [(category: InstallCategory, steps: [InstallStepState])] {
        let grouped = Dictionary(grouping: viewModel.stepStates, by: { $0.item.category })
        return InstallCategory.allCases.compactMap { category in
            guard let steps = grouped[category], !steps.isEmpty else { return nil }
            return (category: category, steps: steps)
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Progress")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(viewModel.successfulStepCount)/\(viewModel.stepStates.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.medium)
                }

                ProgressView(value: viewModel.installProgress)
                    .progressViewStyle(.linear)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedSteps, id: \.category.rawValue) { group in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(group.category.rawValue.uppercased())
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tertiary)
                                    .tracking(0.5)

                                ForEach(group.steps) { state in
                                    HStack(spacing: 10) {
                                        Image(systemName: itemIcon(for: state.item.id))
                                            .font(.system(size: 16))
                                            .foregroundStyle(Color.accentColor)
                                            .frame(width: 24, height: 24)

                                        Text(state.item.name)
                                            .font(.body)

                                        Spacer()

                                        if state.status == .running {
                                            ProgressView()
                                                .controlSize(.small)
                                        }

                                        statusLabel(for: state.status)
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
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

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: viewModel.liveLog.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .textSelection(.enabled)
                                .lineSpacing(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear
                                .frame(height: 1)
                                .id("logBottom")
                        }
                    }
                    .onChange(of: viewModel.liveLog.count) {
                        proxy.scrollTo("logBottom", anchor: .bottom)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.quaternary, lineWidth: 0.5)
                )

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

    private func itemIcon(for itemID: String) -> String {
        switch itemID {
        case "xcode-cli-tools": "hammer.fill"
        case "homebrew": "shippingbox.fill"
        case "core-cli": "terminal.fill"
        case "node-lts": "cube.fill"
        case "python3": "curlybraces"
        case "vscode": "chevron.left.forwardslash.chevron.right"
        case "codex-cli": "sparkles"
        case "claude-code-cli": "message.badge.waveform"
        case "codex-app": "app.badge.sparkles"
        case "gh-auth": "person.badge.key"
        default: "app"
        }
    }

    @ViewBuilder
    private func statusLabel(for status: StepExecutionStatus) -> some View {
        HStack(spacing: 4) {
            switch status {
            case .pending:
                Image(systemName: "circle.dotted")
                Text("Pending")
            case .running:
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Running")
            case .succeeded:
                Image(systemName: "checkmark.circle.fill")
                Text("Done")
            case .failed:
                Image(systemName: "xmark.circle.fill")
                Text("Failed")
            }
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(statusColor(for: status))
    }

    private func statusColor(for status: StepExecutionStatus) -> Color {
        switch status {
        case .pending: .secondary
        case .running: .orange
        case .succeeded: .green
        case .failed: .red
        }
    }
}

// MARK: - Failure Advice

private struct FailureAdviceView: View {
    let failure: InstallFailure
    let advice: RemediationAdvice
    let onRun: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Failure: \(failure.itemName)")
                    .font(.headline)
                    .foregroundStyle(.red)
            }

            Text(advice.summary)
                .font(.subheadline)
            Text("Source: \(advice.source.rawValue)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            ForEach(advice.commands, id: \.self) { command in
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(2)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Button {
                        onRun(command)
                    } label: {
                        Label("Open Terminal", systemImage: "terminal")
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
