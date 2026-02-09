import Foundation
@testable import AgentTutor

// MARK: - Mock ShellExecuting

final class MockShellExecutor: ShellExecuting, @unchecked Sendable {
    struct Invocation: Sendable {
        let command: String
        let requiresAdmin: Bool
        let timeoutSeconds: TimeInterval
    }

    private let lock = NSLock()
    private var _invocations: [Invocation] = []
    private var _results: [ShellExecutionResult]
    private var _resultIndex = 0

    var invocations: [Invocation] {
        lock.withLock { _invocations }
    }

    /// Supply a sequence of results to return in order. Cycles back to the last one if exhausted.
    init(results: [ShellExecutionResult] = []) {
        _results = results.isEmpty
            ? [ShellExecutionResult(exitCode: 0, stdout: "ok", stderr: "", timedOut: false)]
            : results
    }

    func run(command: String, requiresAdmin: Bool, timeoutSeconds: TimeInterval) async -> ShellExecutionResult {
        lock.withLock {
            _invocations.append(Invocation(command: command, requiresAdmin: requiresAdmin, timeoutSeconds: timeoutSeconds))
            let result = _results[min(_resultIndex, _results.count - 1)]
            _resultIndex += 1
            return result
        }
    }
}

// MARK: - Mock RemediationAdvising

final class MockRemediationAdvisor: RemediationAdvising, @unchecked Sendable {
    private let lock = NSLock()
    private var _suggestCallCount = 0
    var fixedAdvice: RemediationAdvice

    var suggestCallCount: Int {
        lock.withLock { _suggestCallCount }
    }

    init(advice: RemediationAdvice = RemediationAdvice(
        summary: "Mock advice",
        commands: ["echo fix"],
        notes: "Mock notes",
        source: .heuristics
    )) {
        fixedAdvice = advice
    }

    func suggest(failure: InstallFailure, hints: [String], apiKey: String, baseURL: String) async -> RemediationAdvice {
        lock.withLock { _suggestCallCount += 1 }
        return fixedAdvice
    }
}

// MARK: - Test Fixtures

enum TestFixtures {
    static func makeItem(
        id: String = "test-item",
        name: String = "Test Item",
        category: InstallCategory = .cli,
        isRequired: Bool = false,
        defaultSelected: Bool = false,
        dependencies: [String] = [],
        commands: [InstallCommand] = [InstallCommand("echo install")],
        verificationChecks: [InstallVerificationCheck] = [InstallVerificationCheck("default", command: "echo ok")],
        remediationHints: [String] = ["Try again"]
    ) -> InstallItem {
        InstallItem(
            id: id,
            name: name,
            summary: "Test item: \(name)",
            category: category,
            isRequired: isRequired,
            defaultSelected: defaultSelected,
            dependencies: dependencies,
            commands: commands,
            verificationChecks: verificationChecks,
            remediationHints: remediationHints
        )
    }

    static func makeFailure(
        itemID: String = "test-item",
        itemName: String = "Test Item",
        failedCommand: String = "echo fail",
        output: String = "error occurred",
        exitCode: Int32 = 1,
        timedOut: Bool = false
    ) -> InstallFailure {
        InstallFailure(
            itemID: itemID,
            itemName: itemName,
            failedCommand: failedCommand,
            output: output,
            exitCode: exitCode,
            timedOut: timedOut
        )
    }

    /// A minimal catalog with dependency chain: base -> mid -> leaf
    static var chainCatalog: [InstallItem] {
        [
            makeItem(id: "base", name: "Base", isRequired: true, defaultSelected: true),
            makeItem(id: "mid", name: "Mid", defaultSelected: true, dependencies: ["base"]),
            makeItem(id: "leaf", name: "Leaf", dependencies: ["mid"]),
        ]
    }
}
