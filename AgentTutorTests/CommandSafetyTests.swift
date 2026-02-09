import Testing
@testable import AgentTutor

struct CommandSafetyTests {

    @Test
    func blocksDangerousCommands() {
        #expect(CommandSafety.isAllowed("rm -rf /") == false)
        #expect(CommandSafety.isAllowed("sudo rm -rf /tmp/foo") == false)
        #expect(CommandSafety.isAllowed("diskutil eraseDisk APFS Test /dev/disk3") == false)
    }

    @Test
    func allowsTypicalSetupCommands() {
        #expect(CommandSafety.isAllowed("brew install jq") == true)
        #expect(CommandSafety.isAllowed("gh auth status") == true)
        #expect(CommandSafety.isAllowed("xcode-select -p") == true)
    }
}
