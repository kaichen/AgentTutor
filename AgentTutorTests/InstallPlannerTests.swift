import Testing
@testable import AgentTutor

struct InstallPlannerTests {

    @Test
    func missingAPIKeyFailsValidation() {
        let planner = InstallPlanner(catalog: InstallCatalog.allItems)

        do {
            _ = try planner.resolvedPlan(selectedIDs: [], apiKey: "   ")
            Issue.record("Expected missing API key validation error")
        } catch let error as PlanValidationError {
            #expect(error == .missingAPIKey)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func requiredItemsAlwaysIncluded() throws {
        let planner = InstallPlanner(catalog: InstallCatalog.allItems)
        let plan = try planner.resolvedPlan(selectedIDs: [], apiKey: "sk-test")

        let plannedIDs = Set(plan.map(\.id))
        let requiredIDs = Set(InstallCatalog.allItems.filter { $0.isRequired }.map(\.id))

        #expect(requiredIDs.isSubset(of: plannedIDs))
    }

    @Test
    func selectedItemPullsDependencies() throws {
        let planner = InstallPlanner(catalog: InstallCatalog.allItems)
        let plan = try planner.resolvedPlan(selectedIDs: ["node-lts"], apiKey: "sk-test")

        let plannedIDs = Set(plan.map(\.id))
        #expect(plannedIDs.contains("node-lts"))
        #expect(plannedIDs.contains("core-cli"))
        #expect(plannedIDs.contains("homebrew"))
        #expect(plannedIDs.contains("xcode-cli-tools"))
    }

    @Test
    func unknownDependencyThrowsConfigurationError() {
        let brokenCatalog = [
            InstallItem(
                id: "demo",
                name: "Demo",
                summary: "Broken",
                category: .cli,
                isRequired: true,
                defaultSelected: true,
                dependencies: ["missing"],
                commands: [InstallCommand("echo demo")],
                verificationCommand: "echo ok",
                remediationHints: []
            )
        ]

        let planner = InstallPlanner(catalog: brokenCatalog)

        do {
            _ = try planner.resolvedPlan(selectedIDs: ["demo"], apiKey: "sk-test")
            Issue.record("Expected unknown dependency error")
        } catch let error as PlanValidationError {
            #expect(error == .unknownDependency(parent: "demo", dependencyID: "missing"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
