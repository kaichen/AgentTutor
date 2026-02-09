import Foundation

enum SetupStage: Int, CaseIterable {
    case welcome
    case apiKey
    case selection
    case install
    case completion

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .apiKey:
            return "OpenAI Key"
        case .selection:
            return "Choose Components"
        case .install:
            return "Install"
        case .completion:
            return "Complete"
        }
    }
}

enum InstallCategory: String, CaseIterable, Codable, Sendable {
    case system = "System"
    case runtimes = "Runtimes"
    case cli = "CLI Tools"
    case apps = "Desktop Apps"
    case auth = "Authentication"
}

struct InstallCommand: Hashable, Codable, Sendable {
    let shell: String
    let requiresAdmin: Bool
    let timeoutSeconds: TimeInterval

    init(_ shell: String, requiresAdmin: Bool = false, timeoutSeconds: TimeInterval = 900) {
        self.shell = shell
        self.requiresAdmin = requiresAdmin
        self.timeoutSeconds = timeoutSeconds
    }
}

struct InstallItem: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let summary: String
    let category: InstallCategory
    let isRequired: Bool
    let defaultSelected: Bool
    let dependencies: [String]
    let commands: [InstallCommand]
    let verificationCommand: String
    let remediationHints: [String]
}

enum StepExecutionStatus: String, Sendable {
    case pending
    case running
    case succeeded
    case failed
}

struct InstallStepState: Identifiable, Sendable {
    let id: String
    let item: InstallItem
    var status: StepExecutionStatus
    var latestOutput: String

    init(item: InstallItem, status: StepExecutionStatus = .pending, latestOutput: String = "") {
        self.id = item.id
        self.item = item
        self.status = status
        self.latestOutput = latestOutput
    }
}

struct InstallFailure: Identifiable, Equatable, Sendable {
    let id = UUID()
    let itemID: String
    let itemName: String
    let failedCommand: String
    let output: String
    let exitCode: Int32
    let timedOut: Bool
}

enum AdviceSource: String, Sendable {
    case heuristics
    case openAI
}

struct RemediationAdvice: Equatable, Sendable {
    let summary: String
    let commands: [String]
    let notes: String
    let source: AdviceSource
}

enum InstallRunState: Equatable, Sendable {
    case idle
    case validating
    case running
    case failed
    case completed
}

enum APIKeyValidationStatus: Equatable, Sendable {
    case idle
    case validating
    case valid
    case invalid(String)
}
