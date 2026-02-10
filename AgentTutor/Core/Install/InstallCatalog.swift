import Foundation

enum InstallCatalog {
    private static func singleVerificationCheck(name: String, command: String, timeoutSeconds: TimeInterval = 120) -> [InstallVerificationCheck] {
        [InstallVerificationCheck(name, command: command, timeoutSeconds: timeoutSeconds)]
    }

    static let allItems: [InstallItem] = [
        InstallItem(
            id: "xcode-cli-tools",
            name: "Xcode Command Line Tools",
            summary: "Installs compiler toolchain required by Homebrew and developer tooling.",
            category: .system,
            isRequired: true,
            defaultSelected: true,
            dependencies: [],
            commands: [
                InstallCommand("/usr/bin/xcode-select -p >/dev/null 2>&1 || /usr/bin/xcode-select --install", timeoutSeconds: 120)
            ],
            verificationChecks: singleVerificationCheck(
                name: "xcode-select",
                command: "/usr/bin/xcode-select -p >/dev/null 2>&1"
            ),
            remediationHints: [
                "Open System Settings > General > Software Update and finish Command Line Tools installation.",
                "After installation completes, return and retry."
            ]
        ),
        InstallItem(
            id: "homebrew",
            name: "Homebrew",
            summary: "Installs Homebrew package manager used for all remaining components.",
            category: .system,
            isRequired: true,
            defaultSelected: true,
            dependencies: ["xcode-cli-tools"],
            commands: [
                InstallCommand(
                    "command -v brew >/dev/null 2>&1 || NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"",
                    authMode: .sudoAskpass,
                    timeoutSeconds: 1800
                )
            ],
            verificationChecks: singleVerificationCheck(
                name: "homebrew",
                command: "command -v brew >/dev/null 2>&1"
            ),
            remediationHints: [
                "Ensure network access to githubusercontent.com and git repositories.",
                "If installer asks for admin permission, approve it and rerun."
            ]
        ),
        InstallItem(
            id: "core-cli",
            name: "Core CLI Tools",
            summary: "Installs ripgrep, fd, jq, yq, gh, nvm, and uv.",
            category: .cli,
            isRequired: true,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew update && brew install ripgrep fd jq yq gh nvm uv", timeoutSeconds: 1800)
            ],
            verificationChecks: [
                InstallVerificationCheck(
                    "ripgrep (rg)",
                    command: "brew list ripgrep >/dev/null 2>&1 || command -v rg >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("ripgrep")
                ),
                InstallVerificationCheck(
                    "fd",
                    command: "brew list fd >/dev/null 2>&1 || command -v fd >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("fd")
                ),
                InstallVerificationCheck(
                    "jq",
                    command: "brew list jq >/dev/null 2>&1 || command -v jq >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("jq")
                ),
                InstallVerificationCheck(
                    "yq",
                    command: "brew list yq >/dev/null 2>&1 || command -v yq >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("yq")
                ),
                InstallVerificationCheck(
                    "gh",
                    command: "brew list gh >/dev/null 2>&1 || command -v gh >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("gh")
                ),
                InstallVerificationCheck(
                    "nvm",
                    command: "brew list nvm >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("nvm")
                ),
                InstallVerificationCheck(
                    "uv",
                    command: "brew list uv >/dev/null 2>&1 || command -v uv >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("uv")
                )
            ],
            remediationHints: [
                "Run brew doctor and resolve reported issues.",
                "Rerun this step after network/proxy restrictions are cleared."
            ]
        ),
        InstallItem(
            id: "node-lts",
            name: "Node.js 22 LTS",
            summary: "Installs Node.js 22 LTS via Homebrew and links it to PATH.",
            category: .runtimes,
            isRequired: false,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew install node@22 && brew link --overwrite --force node@22", timeoutSeconds: 1200)
            ],
            verificationChecks: [
                InstallVerificationCheck(
                    "node@22 installed",
                    command: "brew list node@22 >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("node@22")
                ),
                InstallVerificationCheck("node in PATH", command: "node --version >/dev/null 2>&1")
            ],
            remediationHints: [
                "Run `brew unlink node` if another Node version conflicts, then retry.",
                "Ensure Homebrew is healthy (`brew doctor`) and retry."
            ]
        ),
        InstallItem(
            id: "python3",
            name: "Python 3.10",
            summary: "Installs Python 3.10 via Homebrew and links it to PATH.",
            category: .runtimes,
            isRequired: false,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew install python@3.10 && brew link --overwrite --force python@3.10", timeoutSeconds: 1200)
            ],
            verificationChecks: [
                InstallVerificationCheck(
                    "python@3.10 installed",
                    command: "brew list python@3.10 >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("python@3.10")
                ),
                InstallVerificationCheck("python3 in PATH", command: "python3 --version >/dev/null 2>&1")
            ],
            remediationHints: [
                "Run `brew unlink python` if another Python version conflicts, then retry.",
                "Ensure Homebrew is healthy (`brew doctor`) and retry."
            ]
        ),
        InstallItem(
            id: "vscode",
            name: "Visual Studio Code",
            summary: "Installs Visual Studio Code desktop app using Homebrew Cask.",
            category: .apps,
            isRequired: false,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew install --cask visual-studio-code", timeoutSeconds: 1200)
            ],
            verificationChecks: [
                InstallVerificationCheck(
                    "visual-studio-code cask",
                    command: "brew list --cask visual-studio-code >/dev/null 2>&1 || [ -d '/Applications/Visual Studio Code.app' ] || [ -d \"$HOME/Applications/Visual Studio Code.app\" ]",
                    brewPackage: BrewPackageReference("visual-studio-code", kind: .cask)
                )
            ],
            remediationHints: [
                "Close existing Visual Studio Code installers and retry.",
                "Grant any macOS permission prompts if shown."
            ]
        ),
        InstallItem(
            id: "codex-cli",
            name: "Codex CLI",
            summary: "Installs OpenAI Codex CLI via Homebrew Cask.",
            category: .apps,
            isRequired: false,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew install --cask codex", timeoutSeconds: 1200)
            ],
            verificationChecks: [
                InstallVerificationCheck(
                    "codex cask",
                    command: "brew list --cask codex >/dev/null 2>&1 || command -v codex >/dev/null 2>&1",
                    brewPackage: BrewPackageReference("codex", kind: .cask)
                ),
                InstallVerificationCheck("codex responds", command: "codex -m gpt-5.1-codex-mini --version >/dev/null 2>&1", timeoutSeconds: 15)
            ],
            remediationHints: [
                "Confirm your system can download from GitHub release endpoints.",
                "If Gatekeeper blocks execution, allow the binary in Privacy & Security and retry."
            ]
        ),
        InstallItem(
            id: "gh-auth",
            name: "GitHub CLI Login",
            summary: "Requires completing GitHub authentication in browser before setup can finish.",
            category: .auth,
            isRequired: true,
            defaultSelected: true,
            dependencies: ["core-cli"],
            commands: [
                InstallCommand("\(GitHubAuthPolicy.statusCommand) || \(GitHubAuthPolicy.loginCommand)", timeoutSeconds: 1500)
            ],
            verificationChecks: singleVerificationCheck(
                name: "gh auth",
                command: GitHubAuthPolicy.statusCommand
            ),
            remediationHints: [
                "Complete the browser authorization flow and return.",
                "If `gh auth login` opens no browser, run `gh auth login --web` manually once."
            ]
        )
    ]
}
