import Foundation
import Testing
@testable import AgentTutor

struct InstallLoggerTests {

    /// Each test uses a unique `now` to avoid file-name collisions when tests run concurrently.
    private func uniqueLogger() -> InstallLogger {
        let uniqueDate = Date(timeIntervalSinceReferenceDate: .random(in: 1_000_000..<2_000_000_000))
        return InstallLogger(now: uniqueDate)
    }

    @Test
    func logFileIsCreatedOnInit() {
        let logger = uniqueLogger()
        #expect(FileManager.default.fileExists(atPath: logger.logFileURL.path))
    }

    @Test
    func logWritesJSONLEntries() async {
        let logger = uniqueLogger()

        await logger.log(level: .info, message: "test entry", metadata: ["key": "value"])

        let contents = await logger.readLogContents()
        #expect(contents.contains("test entry"))
        #expect(contents.contains("\"level\":\"info\""))
        #expect(contents.contains("\"key\":\"value\""))
    }

    @Test
    func multipleLogsAppendAsLines() async {
        let logger = uniqueLogger()

        await logger.log(level: .info, message: "line1")
        await logger.log(level: .warning, message: "line2")
        await logger.log(level: .error, message: "line3")

        let contents = await logger.readLogContents()
        let lines = contents.split(separator: "\n")
        #expect(lines.count == 3)
    }

    @Test
    func logLevelsAreRecordedCorrectly() async {
        let logger = uniqueLogger()

        await logger.log(level: .info, message: "info msg")
        await logger.log(level: .warning, message: "warn msg")
        await logger.log(level: .error, message: "err msg")

        let contents = await logger.readLogContents()
        #expect(contents.contains("\"level\":\"info\""))
        #expect(contents.contains("\"level\":\"warning\""))
        #expect(contents.contains("\"level\":\"error\""))
    }

    @Test
    func readLogContentsReturnsEmptyForNewLogger() async {
        let logger = uniqueLogger()
        let contents = await logger.readLogContents()
        #expect(contents.isEmpty)
    }

    @Test
    func logEntryContainsTimestamp() async {
        let logger = uniqueLogger()
        await logger.log(level: .info, message: "ts test")

        let contents = await logger.readLogContents()
        #expect(contents.contains("\"timestamp\""))
    }

    @Test
    func logFileNameContainsSession() {
        let logger = uniqueLogger()
        let filename = logger.logFileURL.lastPathComponent
        #expect(filename.hasPrefix("session-"))
        #expect(filename.hasSuffix(".jsonl"))
    }
}
