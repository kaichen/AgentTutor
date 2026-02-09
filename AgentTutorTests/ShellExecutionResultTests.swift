import Testing
@testable import AgentTutor

struct ShellExecutionResultTests {

    @Test
    func combinedOutputJoinsStdoutAndStderr() {
        let result = ShellExecutionResult(exitCode: 0, stdout: "hello", stderr: "warn", timedOut: false)
        #expect(result.combinedOutput == "hello\nwarn")
    }

    @Test
    func combinedOutputTrimsWhitespace() {
        let result = ShellExecutionResult(exitCode: 0, stdout: "  output  ", stderr: "  err  ", timedOut: false)
        #expect(result.combinedOutput == "output\nerr")
    }

    @Test
    func combinedOutputReturnsNoOutputPlaceholder() {
        let result = ShellExecutionResult(exitCode: 0, stdout: "", stderr: "", timedOut: false)
        #expect(result.combinedOutput == "(no output)")
    }

    @Test
    func combinedOutputExcludesEmptyStderr() {
        let result = ShellExecutionResult(exitCode: 0, stdout: "data", stderr: "", timedOut: false)
        #expect(result.combinedOutput == "data")
    }

    @Test
    func combinedOutputExcludesEmptyStdout() {
        let result = ShellExecutionResult(exitCode: 1, stdout: "", stderr: "error msg", timedOut: false)
        #expect(result.combinedOutput == "error msg")
    }

    @Test
    func combinedOutputExcludesWhitespaceOnlyFields() {
        let result = ShellExecutionResult(exitCode: 0, stdout: "   ", stderr: "   ", timedOut: false)
        #expect(result.combinedOutput == "(no output)")
    }
}
