import SwiftUI

struct OpenClawConfigView: View {
    @StateObject private var viewModel = OpenClawConfigViewModel()
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            toolsList
            Divider()
            footer
        }
        .padding(24)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Back")
                }
            }
            .buttonStyle(.bordered)

            Spacer()

            VStack(spacing: 2) {
                Text("OpenClaw Configuration")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(viewModel.enabledToolCount) of \(viewModel.tools.count) tools enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Balance the back button width
            Color.clear
                .frame(width: 70, height: 1)
        }
        .padding(.bottom, 16)
    }

    private var toolsList: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(viewModel.tools) { tool in
                    ToolCardView(tool: tool, viewModel: viewModel)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private var footer: some View {
        HStack {
            if case .saved = viewModel.saveStatus {
                Label("Configuration saved", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if case let .failed(message) = viewModel.saveStatus {
                Label(message, systemImage: "xmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            Spacer()

            Button("Save Configuration") {
                viewModel.saveConfiguration()
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.saveStatus == .saving)
        }
        .padding(.top, 16)
        .animation(.easeInOut(duration: 0.25), value: viewModel.saveStatus)
    }
}

// MARK: - Tool Card

private struct ToolCardView: View {
    let tool: ToolConfig
    @ObservedObject var viewModel: OpenClawConfigViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolHeader
            if tool.isEnabled {
                Divider()
                    .padding(.horizontal, 16)
                toolFields
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary.opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.quaternary.opacity(0.5), lineWidth: 0.5)
        )
        .animation(.easeInOut(duration: 0.25), value: tool.isEnabled)
    }

    private var toolHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tool.isEnabled ? AnyShapeStyle(Color.accentColor.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.5)))
                    .frame(width: 40, height: 40)
                Image(systemName: tool.icon)
                    .font(.system(size: 18))
                    .foregroundStyle(tool.isEnabled ? Color.accentColor : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(tool.name)
                    .font(.headline)
                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { tool.isEnabled },
                set: { _ in viewModel.toggleTool(tool.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(16)
    }

    private var toolFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(tool.fields) { field in
                ToolFieldView(
                    field: field,
                    toolID: tool.id,
                    viewModel: viewModel
                )
            }
        }
        .padding(16)
    }
}

// MARK: - Tool Field

private struct ToolFieldView: View {
    let field: ToolField
    let toolID: String
    @ObservedObject var viewModel: OpenClawConfigViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text(field.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .trailing)

            fieldInput
        }
    }

    @ViewBuilder
    private var fieldInput: some View {
        switch field.fieldType {
        case .text:
            if field.isSecure {
                SecureField(field.placeholder, text: fieldBinding)
                    .textFieldStyle(.roundedBorder)
            } else {
                TextField(field.placeholder, text: fieldBinding)
                    .textFieldStyle(.roundedBorder)
            }
        case .number:
            TextField(field.placeholder, text: fieldBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
        case .toggle:
            Toggle("", isOn: toggleBinding)
                .toggleStyle(.switch)
                .labelsHidden()
            Spacer()
        }
    }

    private var fieldBinding: Binding<String> {
        Binding(
            get: { field.value },
            set: { viewModel.updateField(toolID: toolID, fieldID: field.id, value: $0) }
        )
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { field.value.lowercased() == "true" },
            set: { viewModel.updateField(toolID: toolID, fieldID: field.id, value: $0 ? "true" : "false") }
        )
    }
}
