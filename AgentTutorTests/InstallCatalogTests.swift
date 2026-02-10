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
    func allItemsHaveVerificationChecks() {
        for item in InstallCatalog.allItems {
            #expect(!item.verificationChecks.isEmpty, "\(item.id) has no verification checks")
            for check in item.verificationChecks {
                #expect(!check.command.isEmpty, "\(item.id) has empty verification check command")
                #expect(!check.name.isEmpty, "\(item.id) has unnamed verification check")
            }
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

    @Test
    func codexAndCaskVerificationChecksUseBrewPackageMetadata() {
        guard let vscode = InstallCatalog.allItems.first(where: { $0.id == "vscode" }) else {
            Issue.record("vscode item missing from catalog")
            return
        }

        let vscodeCaskCheck = vscode.verificationChecks.first { $0.name == "visual-studio-code cask" }
        #expect(vscodeCaskCheck?.command.contains("brew list --cask visual-studio-code") == true)
        #expect(vscodeCaskCheck?.command.contains("/Applications/Visual Studio Code.app") == true)
        #expect(vscodeCaskCheck?.brewPackage?.name == "visual-studio-code")
        #expect(vscodeCaskCheck?.brewPackage?.kind == .cask)

        let vscodeApplicationsCheck = vscode.verificationChecks.first { $0.name == "visual-studio-code in /Applications" }
        #expect(vscodeApplicationsCheck?.command == "[ -d '/Applications/Visual Studio Code.app' ]")
        #expect(vscodeApplicationsCheck?.brewPackage == nil)

        guard let codexCLI = InstallCatalog.allItems.first(where: { $0.id == "codex-cli" }) else {
            Issue.record("codex-cli item missing from catalog")
            return
        }

        let codexFormulaCheck = codexCLI.verificationChecks.first { $0.name == "codex formula" }
        #expect(codexFormulaCheck?.brewPackage?.name == "codex")
        #expect(codexFormulaCheck?.brewPackage?.kind == .formula)

        guard let claudeCodeCLI = InstallCatalog.allItems.first(where: { $0.id == "claude-code-cli" }) else {
            Issue.record("claude-code-cli item missing from catalog")
            return
        }

        let claudeCodeFormulaCheck = claudeCodeCLI.verificationChecks.first { $0.name == "claude-code formula" }
        #expect(claudeCodeFormulaCheck?.brewPackage?.name == "claude-code")
        #expect(claudeCodeFormulaCheck?.brewPackage?.kind == .formula)

        let claudeRespondsCheck = claudeCodeCLI.verificationChecks.first { $0.name == "claude responds" }
        #expect(claudeRespondsCheck?.command == "claude --version >/dev/null 2>&1")

        guard let codexApp = InstallCatalog.allItems.first(where: { $0.id == "codex-app" }) else {
            Issue.record("codex-app item missing from catalog")
            return
        }

        let codexAppCaskCheck = codexApp.verificationChecks.first { $0.name == "codex-app cask" }
        #expect(codexAppCaskCheck?.command.contains("brew list --cask codex-app") == true)
        #expect(codexAppCaskCheck?.command.contains("/Applications/Codex.app") == true)
        #expect(codexAppCaskCheck?.brewPackage?.name == "codex-app")
        #expect(codexAppCaskCheck?.brewPackage?.kind == .cask)

        let codexAppApplicationsCheck = codexApp.verificationChecks.first { $0.name == "codex-app in /Applications" }
        #expect(codexAppApplicationsCheck?.command == "[ -d '/Applications/Codex.app' ]")
        #expect(codexAppApplicationsCheck?.brewPackage == nil)
    }

    @Test
    func coreCLIVerificationChecksEachPackageIndividually() {
        guard let coreCLI = InstallCatalog.allItems.first(where: { $0.id == "core-cli" }) else {
            Issue.record("core-cli item missing from catalog")
            return
        }

        let checkNames = Set(coreCLI.verificationChecks.map(\.name))
        #expect(checkNames.contains("ripgrep (rg)"))
        #expect(checkNames.contains("fd"))
        #expect(checkNames.contains("jq"))
        #expect(checkNames.contains("yq"))
        #expect(checkNames.contains("gh"))
        #expect(checkNames.contains("nvm"))
        #expect(checkNames.contains("uv"))

        let missingBrewMetadata = coreCLI.verificationChecks.filter { $0.brewPackage == nil }
        #expect(missingBrewMetadata.isEmpty, "Core CLI checks should declare brew package metadata")
    }

    @Test
    func nodeLTSVerificationChecksBrewAndPath() {
        guard let nodeLTS = InstallCatalog.allItems.first(where: { $0.id == "node-lts" }) else {
            Issue.record("node-lts item missing from catalog")
            return
        }

        let checkNames = Set(nodeLTS.verificationChecks.map(\.name))
        #expect(checkNames.contains("node@22 installed"))
        #expect(checkNames.contains("node in PATH"))

        let brewCheck = nodeLTS.verificationChecks.first { $0.name == "node@22 installed" }
        #expect(brewCheck?.command.contains("brew list node@22") == true)
        #expect(brewCheck?.brewPackage?.name == "node@22")
        #expect(brewCheck?.brewPackage?.kind == .formula)
    }

    @Test
    func ghAuthUsesSshProtocolPolicy() {
        guard let ghAuth = InstallCatalog.allItems.first(where: { $0.id == "gh-auth" }) else {
            Issue.record("gh-auth item missing from catalog")
            return
        }

        #expect(ghAuth.commands.count == 1)
        #expect(ghAuth.commands[0].shell.contains("--git-protocol ssh"))
        #expect(ghAuth.commands[0].shell.contains(GitHubAuthPolicy.loginCommand))
        #expect(ghAuth.verificationChecks.first?.command == GitHubAuthPolicy.statusCommand)
    }

    @Test
    func homebrewInstallUsesSudoAskpassAuthMode() {
        guard let homebrew = InstallCatalog.allItems.first(where: { $0.id == "homebrew" }) else {
            Issue.record("homebrew item missing from catalog")
            return
        }

        #expect(homebrew.commands.count == 1)
        #expect(homebrew.commands[0].authMode == .sudoAskpass)
    }
}
