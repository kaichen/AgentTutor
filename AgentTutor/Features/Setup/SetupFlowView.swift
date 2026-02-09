import SwiftUI

struct SetupFlowView: View {
    @StateObject private var viewModel = SetupViewModel()

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 14) {
                HStack {
                    Text("AgentTutor Setup")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
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
            .animation(.easeInOut(duration: 0.3), value: viewModel.stage)
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
            APIKeyView(
                apiKey: $viewModel.apiKey,
                baseURL: $viewModel.apiBaseURL,
                validationStatus: viewModel.apiKeyValidationStatus,
                onKeyChanged: { viewModel.onAPIKeyChanged() },
                onBaseURLChanged: { viewModel.onBaseURLChanged() }
            )
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
                .frame(width: 70)

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
    }

    private func label(for stage: SetupStage) -> String {
        switch stage {
        case .welcome: "Welcome"
        case .apiKey: "API Key"
        case .selection: "Select"
        case .install: "Install"
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
        FeatureInfo("key", "OpenAI Integration", "API key required for AI-powered setup assistance"),
        FeatureInfo("wrench.and.screwdriver", "Fail-Fast Recovery", "Every failure stops immediately with fix commands"),
        FeatureInfo("doc.text", "Diagnostic Logs", "Structured logs kept locally for troubleshooting"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Prepare your Mac for development")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Guided, automated environment setup with intelligent error recovery.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(features) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(.headline)
                            Text(feature.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - API Key

private struct APIKeyView: View {
    @Binding var apiKey: String
    @Binding var baseURL: String
    let validationStatus: APIKeyValidationStatus
    let onKeyChanged: () -> Void
    let onBaseURLChanged: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenAI API Configuration")
                .font(.title3)
                .fontWeight(.semibold)

            Text("Base URL")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField("https://api.openai.com", text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .onChange(of: baseURL) { onBaseURLChanged() }

            Text("API Key")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField("sk-...", text: $apiKey)
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

            Text("The key is kept in memory for this session only. It is never saved to disk.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
            VStack(alignment: .leading, spacing: 16) {
                Text("Choose what to install")
                    .font(.title3)
                    .fontWeight(.semibold)

                ForEach(InstallCategory.allCases, id: \.rawValue) { category in
                    if let items = groupedItems[category] {
                        Divider()
                            .padding(.vertical, 2)

                        VStack(alignment: .leading, spacing: 8) {
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
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .disabled(!viewModel.canToggle(item))
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
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(viewModel.liveLog.joined(separator: "\n"))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear
                                .frame(height: 1)
                                .id("logBottom")
                        }
                    }
                    .onChange(of: viewModel.liveLog.count) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("logBottom", anchor: .bottom)
                        }
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
                        Label("Run", systemImage: "terminal")
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

// MARK: - Completion

private struct CompletionView: View {
    @ObservedObject var viewModel: SetupViewModel
    @State private var showTitle = false
    @State private var showStats = false
    @State private var showWhatsNext = false
    @State private var showButton = false

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()

                AnimatedCheckmark()

                VStack(spacing: 8) {
                    Text("Setup Complete!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Your development environment is ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 12)

                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("\(viewModel.successfulStepCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Components Installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text(viewModel.installDurationFormatted)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Total Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 15)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What's Next")
                        .font(.headline)

                    Label("Open a terminal and start coding", systemImage: "terminal")
                        .font(.subheadline)
                    Label("Check installed tool versions with your package manager", systemImage: "shippingbox")
                        .font(.subheadline)
                    Label("Review the diagnostic log for details", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
                .frame(maxWidth: 400, alignment: .leading)
                .opacity(showWhatsNext ? 1 : 0)
                .offset(y: showWhatsNext ? 0 : 15)

                Button("Open Log Folder") {
                    viewModel.openLogFolder()
                }
                .buttonStyle(.bordered)
                .opacity(showButton ? 1 : 0)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ConfettiView()
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
                showTitle = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.9)) {
                showStats = true
            }
            withAnimation(.easeOut(duration: 0.5).delay(1.2)) {
                showWhatsNext = true
            }
            withAnimation(.easeOut(duration: 0.3).delay(1.5)) {
                showButton = true
            }
        }
    }
}

// MARK: - Animated Checkmark

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.25))
        return path
    }
}

private struct AnimatedCheckmark: View {
    @State private var circleScale: CGFloat = 0
    @State private var checkmarkTrim: CGFloat = 0
    @State private var glowScale: CGFloat = 0.8
    @State private var glowOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.green.opacity(0.15), lineWidth: 6)
                .frame(width: 88, height: 88)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            Circle()
                .fill(.green.gradient)
                .frame(width: 76, height: 76)
                .scaleEffect(circleScale)
                .shadow(color: .green.opacity(0.25), radius: 12, y: 4)

            CheckmarkShape()
                .trim(from: 0, to: checkmarkTrim)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 32)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) {
                circleScale = 1
            }
            withAnimation(.easeInOut(duration: 0.35).delay(0.35)) {
                checkmarkTrim = 1
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                glowScale = 1.2
                glowOpacity = 1
            }
        }
    }
}

// MARK: - Confetti

private struct ConfettiPieceData: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let endRotation: Double
    let width: CGFloat
    let height: CGFloat
    let delay: Double
    let duration: Double

    static let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .pink, .purple, .mint, .cyan]

    init(index: Int) {
        self.id = index
        self.color = Self.colors[index % Self.colors.count]
        self.startX = CGFloat.random(in: -25...25)
        self.startY = CGFloat.random(in: -180...(-80))
        self.endX = CGFloat.random(in: -300...300)
        self.endY = CGFloat.random(in: 150...500)
        self.endRotation = Double.random(in: -360...360)
        self.width = CGFloat.random(in: 4...8)
        self.height = CGFloat.random(in: 8...14)
        self.delay = Double.random(in: 0...0.6)
        self.duration = Double.random(in: 2.5...4)
    }
}

private struct ConfettiView: View {
    @State private var pieces: [ConfettiPieceData] = (0..<60).map { ConfettiPieceData(index: $0) }
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.width, height: piece.height)
                    .offset(
                        x: animate ? piece.endX : piece.startX,
                        y: animate ? piece.endY : piece.startY
                    )
                    .rotationEffect(.degrees(animate ? piece.endRotation : 0))
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: piece.duration).delay(piece.delay),
                        value: animate
                    )
            }
        }
        .onAppear {
            animate = true
        }
    }
}
