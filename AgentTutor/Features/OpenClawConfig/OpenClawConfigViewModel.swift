import Combine
import Foundation

struct ToolConfig: Identifiable {
    let id: String
    let name: String
    let icon: String
    let description: String
    var isEnabled: Bool = false
    var fields: [ToolField]
}

struct ToolField: Identifiable {
    let id: String
    let label: String
    let placeholder: String
    var value: String = ""
    let isSecure: Bool
    let fieldType: FieldType

    enum FieldType {
        case text
        case toggle
        case number
    }

    init(id: String, label: String, placeholder: String = "", value: String = "", isSecure: Bool = false, fieldType: FieldType = .text) {
        self.id = id
        self.label = label
        self.placeholder = placeholder
        self.value = value
        self.isSecure = isSecure
        self.fieldType = fieldType
    }
}

@MainActor
final class OpenClawConfigViewModel: ObservableObject {
    @Published var tools: [ToolConfig]
    @Published var saveStatus: SaveStatus = .idle

    enum SaveStatus: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    init() {
        self.tools = Self.defaultTools()
    }

    func toggleTool(_ toolID: String) {
        guard let index = tools.firstIndex(where: { $0.id == toolID }) else { return }
        tools[index].isEnabled.toggle()
    }

    func updateField(toolID: String, fieldID: String, value: String) {
        guard let toolIndex = tools.firstIndex(where: { $0.id == toolID }),
              let fieldIndex = tools[toolIndex].fields.firstIndex(where: { $0.id == fieldID }) else { return }
        tools[toolIndex].fields[fieldIndex].value = value
    }

    func saveConfiguration() {
        saveStatus = .saving
        // Placeholder: will implement actual save logic later
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            saveStatus = .saved
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveStatus == .saved {
                saveStatus = .idle
            }
        }
    }

    var enabledToolCount: Int {
        tools.filter(\.isEnabled).count
    }

    private static func defaultTools() -> [ToolConfig] {
        [
            ToolConfig(
                id: "search",
                name: "Search",
                icon: "magnifyingglass",
                description: "Web search capability for retrieving real-time information.",
                fields: [
                    ToolField(id: "search-api-key", label: "API Key", placeholder: "Enter your search API key", isSecure: true),
                    ToolField(id: "search-provider", label: "Provider", placeholder: "google"),
                    ToolField(id: "search-max-results", label: "Max Results", placeholder: "10", fieldType: .number),
                ]
            ),
            ToolConfig(
                id: "browser",
                name: "Browser",
                icon: "globe",
                description: "Browser automation for web interaction and content extraction.",
                fields: [
                    ToolField(id: "browser-path", label: "Browser Path", placeholder: "/Applications/Google Chrome.app"),
                    ToolField(id: "browser-headless", label: "Headless Mode", value: "true", fieldType: .toggle),
                    ToolField(id: "browser-timeout", label: "Page Timeout (s)", placeholder: "30", fieldType: .number),
                ]
            ),
            ToolConfig(
                id: "skills-finder",
                name: "Skills Finder",
                icon: "sparkle.magnifyingglass",
                description: "Discover and install skills from the OpenClaw skill registry.",
                fields: [
                    ToolField(id: "skills-endpoint", label: "Registry Endpoint", placeholder: "https://registry.openclaw.dev/v1"),
                    ToolField(id: "skills-max-results", label: "Max Results", placeholder: "20", fieldType: .number),
                ]
            ),
            ToolConfig(
                id: "note-taker",
                name: "Note Taker",
                icon: "note.text",
                description: "Persistent note-taking for capturing insights and context.",
                fields: [
                    ToolField(id: "notes-path", label: "Storage Path", placeholder: "~/openclaw/notes"),
                ]
            ),
        ]
    }
}
