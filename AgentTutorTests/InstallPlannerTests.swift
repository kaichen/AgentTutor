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

    @Test
    func emptyCatalogReturnsEmptyPlan() throws {
        let planner = InstallPlanner(catalog: [])
        let plan = try planner.resolvedPlan(selectedIDs: ["nonexistent"], apiKey: "sk-test")
        #expect(plan.isEmpty)
    }

    @Test
    func planPreservesCatalogOrder() throws {
        let catalog = TestFixtures.chainCatalog  // base, mid, leaf
        let planner = InstallPlanner(catalog: catalog)
        let plan = try planner.resolvedPlan(selectedIDs: ["leaf"], apiKey: "sk-test")

        let ids = plan.map(\.id)
        // "base" is required so always included; mid and leaf via dependency/selection
        if let baseIdx = ids.firstIndex(of: "base"),
           let midIdx = ids.firstIndex(of: "mid"),
           let leafIdx = ids.firstIndex(of: "leaf") {
            #expect(baseIdx < midIdx)
            #expect(midIdx < leafIdx)
        }
    }

    @Test
    func transitiveDependenciesAreResolved() throws {
        let catalog = [
            TestFixtures.makeItem(id: "a", name: "A"),
            TestFixtures.makeItem(id: "b", name: "B", dependencies: ["a"]),
            TestFixtures.makeItem(id: "c", name: "C", dependencies: ["b"]),
        ]
        let planner = InstallPlanner(catalog: catalog)
        let plan = try planner.resolvedPlan(selectedIDs: ["c"], apiKey: "sk-test")
        let ids = Set(plan.map(\.id))

        #expect(ids.contains("a"))
        #expect(ids.contains("b"))
        #expect(ids.contains("c"))
    }

    @Test
    func duplicateSelectedIDsDoNotDuplicateItems() throws {
        let catalog = [TestFixtures.makeItem(id: "x", name: "X")]
        let planner = InstallPlanner(catalog: catalog)
        let plan = try planner.resolvedPlan(selectedIDs: ["x", "x", "x"], apiKey: "sk-test")

        #expect(plan.count == 1)
    }

    @Test
    func planValidationErrorDescriptions() {
        let missingKey = PlanValidationError.missingAPIKey
        #expect(missingKey.errorDescription?.contains("API key") == true)

        let unknownDep = PlanValidationError.unknownDependency(parent: "p", dependencyID: "d")
        #expect(unknownDep.errorDescription?.contains("p") == true)
        #expect(unknownDep.errorDescription?.contains("d") == true)
    }
}
