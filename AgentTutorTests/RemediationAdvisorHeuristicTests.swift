import Testing
@testable import AgentTutor

struct RemediationAdvisorHeuristicTests {

    private let advisor = RemediationAdvisor()

    // MARK: - Heuristic Paths (no API key → pure heuristic)

    @Test
    func homebrewNotFoundTriggersBrewHeuristic() async {
        let failure = TestFixtures.makeFailure(
            itemID: "core-cli",
            failedCommand: "brew install jq",
            output: "zsh: command not found: brew"
        )

        let advice = await advisor.suggest(failure: failure, hints: ["Run brew doctor"], apiKey: "", baseURL: "")

        #expect(advice.source == .heuristics)
        #expect(advice.summary.lowercased().contains("homebrew"))
        #expect(advice.commands.contains { $0.contains("brew") })
    }

    @Test
    func xcodeSelectTriggersXcodeHeuristic() async {
        let failure = TestFixtures.makeFailure(
            itemID: "xcode-cli-tools",
            failedCommand: "xcode-select -p",
            output: "xcode-select: error: unable to get active developer directory"
        )

        let advice = await advisor.suggest(failure: failure, hints: [], apiKey: "", baseURL: "")

        #expect(advice.source == .heuristics)
        #expect(advice.summary.lowercased().contains("xcode"))
        #expect(advice.commands.contains("xcode-select --install"))
    }

    @Test
    func ghAuthTriggersGitHubHeuristic() async {
        let failure = TestFixtures.makeFailure(
            itemID: "gh-auth",
            failedCommand: "gh auth status",
            output: "You are not logged into any GitHub hosts."
        )

        let advice = await advisor.suggest(failure: failure, hints: ["Complete browser flow"], apiKey: "", baseURL: "")

        #expect(advice.source == .heuristics)
        #expect(advice.summary.lowercased().contains("github"))
        #expect(advice.commands.contains(GitHubAuthPolicy.loginCommand))
        #expect(advice.commands.contains(GitHubAuthPolicy.statusCommand))
    }

    @Test
    func unknownFailureFallsBackToGenericAdvice() async {
        let failure = TestFixtures.makeFailure(
            itemID: "unknown-item",
            failedCommand: "some-tool --setup",
            output: "mysterious error"
        )

        let advice = await advisor.suggest(failure: failure, hints: ["Check docs"], apiKey: "", baseURL: "")

        #expect(advice.source == .heuristics)
        #expect(advice.summary.contains("failed"))
        #expect(advice.commands.contains("some-tool --setup"))
        #expect(advice.notes.contains("Check docs"))
    }

    @Test
    func heuristicAdviceJoinsHintsInNotes() async {
        let failure = TestFixtures.makeFailure(
            itemID: "gh-auth",
            failedCommand: "gh auth status",
            output: "not logged in"
        )

        let advice = await advisor.suggest(failure: failure, hints: ["Hint A", "Hint B"], apiKey: "", baseURL: "")

        #expect(advice.notes.contains("Hint A"))
        #expect(advice.notes.contains("Hint B"))
    }

    // MARK: - Empty API Key Falls Back

    @Test
    func whitespaceOnlyAPIKeyFallsBackToHeuristics() async {
        let failure = TestFixtures.makeFailure(
            itemID: "core-cli",
            failedCommand: "brew install jq",
            output: "not found"
        )

        let advice = await advisor.suggest(failure: failure, hints: [], apiKey: "   ", baseURL: "https://api.openai.com")

        #expect(advice.source == .heuristics)
    }
}
