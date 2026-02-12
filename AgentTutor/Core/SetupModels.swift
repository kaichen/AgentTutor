import Darwin
import Foundation

enum SetupStage: Int, CaseIterable {
    case welcome
    case apiKey
    case selection
    case install
    case gitSSH
    case openClaw
    case completion

    var title: String {
        switch self {
        case .welcome:
            return "Welcome"
        case .apiKey:
            return "LLM Key"
        case .selection:
            return "Choose Components"
        case .install:
            return "Install"
        case .gitSSH:
            return "Git & SSH"
        case .openClaw:
            return "OpenClaw"
        case .completion:
            return "Complete"
        }
    }
}

enum LLMProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case openai
    case openrouter
    case kimi
    case minimax

    struct EndpointPreset: Identifiable, Equatable, Sendable {
        let id: String
        let label: String
        let baseURL: String

        init(label: String, baseURL: String) {
            self.id = label.lowercased()
            self.label = label
            self.baseURL = baseURL
        }
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openai:
            return "OpenAI"
        case .openrouter:
            return "OpenRouter"
        case .kimi:
            return "Kimi"
        case .minimax:
            return "MiniMax"
        }
    }

    // Keep provider defaults centralized and aligned with onboarding defaults.
    var defaultBaseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com/v1"
        case .openrouter:
            return "https://openrouter.ai/api/v1"
        case .kimi:
            return "https://api.moonshot.ai/v1"
        case .minimax:
            return "https://api.minimax.io/v1"
        }
    }

    var endpointPresets: [EndpointPreset] {
        switch self {
        case .kimi:
            return [
                EndpointPreset(label: "Global", baseURL: "https://api.moonshot.ai/v1"),
                EndpointPreset(label: "CN", baseURL: "https://api.kimi.com/coding/v1"),
            ]
        case .minimax:
            return [
                EndpointPreset(label: "Global", baseURL: "https://api.minimax.io/v1"),
                EndpointPreset(label: "CN", baseURL: "https://api.minimaxi.com/v1"),
            ]
        default:
            return []
        }
    }

    var defaultModelName: String {
        switch self {
        case .openai:
            return "gpt-5.1-codex-mini"
        case .openrouter:
            return "openai/gpt-5.1-codex-mini"
        case .kimi:
            return "kimi-for-coding"
        case .minimax:
            return "MiniMax-M2.1"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openrouter:
            return "sk-or-..."
        default:
            return "sk-..."
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

enum MacSystemArchitecture: String, CaseIterable, Codable, Sendable {
    case arm64
    case x86_64

    static var current: MacSystemArchitecture {
        var isArm64Hardware: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let status = sysctlbyname("hw.optional.arm64", &isArm64Hardware, &size, nil, 0)
        if status == 0, isArm64Hardware == 1 {
            return .arm64
        }
        return .x86_64
    }
}

enum CommandAuthMode: String, Codable, Sendable {
    case standard
    case adminAppleScript
    case sudoAskpass
}

enum BrewPackageKind: String, Codable, Sendable {
    case formula
    case cask
}

struct BrewPackageReference: Hashable, Codable, Sendable {
    let name: String
    let kind: BrewPackageKind

    init(_ name: String, kind: BrewPackageKind = .formula) {
        self.name = name
        self.kind = kind
    }
}

struct InstallCommand: Hashable, Codable, Sendable {
    let shell: String
    let authMode: CommandAuthMode
    let timeoutSeconds: TimeInterval

    init(_ shell: String, authMode: CommandAuthMode = .standard, timeoutSeconds: TimeInterval = 900) {
        self.shell = shell
        self.authMode = authMode
        self.timeoutSeconds = timeoutSeconds
    }
}

struct InstallVerificationCheck: Hashable, Codable, Sendable {
    let name: String
    let command: String
    let timeoutSeconds: TimeInterval
    let brewPackage: BrewPackageReference?

    init(
        _ name: String,
        command: String,
        timeoutSeconds: TimeInterval = 120,
        brewPackage: BrewPackageReference? = nil
    ) {
        self.name = name
        self.command = command
        self.timeoutSeconds = timeoutSeconds
        self.brewPackage = brewPackage
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
    let verificationChecks: [InstallVerificationCheck]
    let remediationHints: [String]
    let supportedArchitectures: Set<MacSystemArchitecture>

    init(
        id: String,
        name: String,
        summary: String,
        category: InstallCategory,
        isRequired: Bool,
        defaultSelected: Bool,
        dependencies: [String],
        commands: [InstallCommand],
        verificationChecks: [InstallVerificationCheck],
        remediationHints: [String],
        supportedArchitectures: Set<MacSystemArchitecture> = Set(MacSystemArchitecture.allCases)
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.category = category
        self.isRequired = isRequired
        self.defaultSelected = defaultSelected
        self.dependencies = dependencies
        self.commands = commands
        self.verificationChecks = verificationChecks
        self.remediationHints = remediationHints
        self.supportedArchitectures = supportedArchitectures
    }

    func supports(_ architecture: MacSystemArchitecture) -> Bool {
        supportedArchitectures.contains(architecture)
    }
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

struct GitIdentity: Equatable, Sendable {
    var name: String
    var email: String
}

enum ActionStatus: Equatable, Sendable {
    case idle
    case running
    case succeeded
    case failed(String)
}

struct SSHKeyMaterial: Equatable, Sendable {
    let privateKeyPath: String
    let publicKeyPath: String
    let publicKey: String
    let fingerprint: String
}

enum SSHKeyState: Equatable, Sendable {
    case checking
    case missing
    case existing(SSHKeyMaterial)
    case generated(SSHKeyMaterial)
    case failed(String)
}
