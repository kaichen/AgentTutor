import Testing
@testable import AgentTutor

struct InstallCatalogTests {

    @Test
    func allItemsHaveUniqueIDs() {
        let ids = InstallCatalog.allItems.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count, "Duplicate IDs found in catalog")
    }

    @Test
    func allDependenciesExistInCatalog() {
        let allIDs = Set(InstallCatalog.allItems.map(\.id))

        for item in InstallCatalog.allItems {
            for dep in item.dependencies {
                #expect(allIDs.contains(dep), "\(item.id) depends on '\(dep)' which is not in the catalog")
            }
        }
    }

    @Test
    func requiredItemsAreDefaultSelected() {
        for item in InstallCatalog.allItems where item.isRequired {
            #expect(item.defaultSelected, "Required item '\(item.id)' should be defaultSelected")
        }
    }

    @Test
    func allItemsHaveAtLeastOneCommand() {
        for item in InstallCatalog.allItems {
            #expect(!item.commands.isEmpty, "\(item.id) has no install commands")
        }
    }

    @Test
    func allItemsHaveVerificationCommand() {
        for item in InstallCatalog.allItems {
            #expect(!item.verificationCommand.isEmpty, "\(item.id) has no verification command")
        }
    }

    @Test
    func noCyclicDependencies() {
        let items = InstallCatalog.allItems
        let itemMap = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        for item in items {
            var visited = Set<String>()
            var stack = item.dependencies
            while let dep = stack.popLast() {
                if dep == item.id {
                    Issue.record("Cyclic dependency detected: \(item.id) → ... → \(item.id)")
                    break
                }
                guard !visited.contains(dep) else { continue }
                visited.insert(dep)
                if let depItem = itemMap[dep] {
                    stack.append(contentsOf: depItem.dependencies)
                }
            }
        }
    }

    @Test
    func catalogContainsExpectedCategories() {
        let categories = Set(InstallCatalog.allItems.map(\.category))
        #expect(categories.contains(.system))
        #expect(categories.contains(.cli))
        #expect(categories.contains(.runtimes))
        #expect(categories.contains(.apps))
        #expect(categories.contains(.auth))
    }

    @Test
    func allCommandTimeoutsArePositive() {
        for item in InstallCatalog.allItems {
            for cmd in item.commands {
                #expect(cmd.timeoutSeconds > 0, "\(item.id) has non-positive timeout")
            }
        }
    }
}
