import Foundation

enum InstallCatalog {
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
            verificationCommand: "/usr/bin/xcode-select -p >/dev/null 2>&1",
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
                InstallCommand("command -v brew >/dev/null 2>&1 || NONINTERACTIVE=1 /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"", timeoutSeconds: 1800)
            ],
            verificationCommand: "command -v brew >/dev/null 2>&1",
            remediationHints: [
                "Ensure network access to githubusercontent.com and git repositories.",
                "If installer asks for admin permission, approve it and rerun."
            ]
        ),
        InstallItem(
            id: "core-cli",
            name: "Core CLI Tools",
            summary: "Installs ripgrep, fd, jq, yq, gh, uv, and nvm.",
            category: .cli,
            isRequired: true,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew update && brew install ripgrep fd jq yq gh uv nvm", timeoutSeconds: 1800)
            ],
            verificationCommand: "command -v rg >/dev/null 2>&1 && command -v fd >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 && command -v yq >/dev/null 2>&1 && command -v gh >/dev/null 2>&1 && command -v uv >/dev/null 2>&1 && test -s \"$(brew --prefix nvm)/nvm.sh\"",
            remediationHints: [
                "Run brew doctor and resolve reported issues.",
                "Rerun this step after network/proxy restrictions are cleared."
            ]
        ),
        InstallItem(
            id: "node-lts",
            name: "Node.js LTS",
            summary: "Installs latest Node LTS using nvm and sets it as default.",
            category: .runtimes,
            isRequired: false,
            defaultSelected: true,
            dependencies: ["core-cli"],
            commands: [
                InstallCommand("export NVM_DIR=\"$HOME/.nvm\"; mkdir -p \"$NVM_DIR\"; [ -s \"$(brew --prefix nvm)/nvm.sh\" ] && . \"$(brew --prefix nvm)/nvm.sh\"; nvm install --lts && nvm alias default 'lts/*'", timeoutSeconds: 1200)
            ],
            verificationCommand: "export NVM_DIR=\"$HOME/.nvm\"; [ -s \"$(brew --prefix nvm)/nvm.sh\" ] && . \"$(brew --prefix nvm)/nvm.sh\"; nvm which --lts >/dev/null 2>&1",
            remediationHints: [
                "Verify that nvm was installed by Homebrew and retry.",
                "If shell initialization is customized heavily, run the command manually once in Terminal."
            ]
        ),
        InstallItem(
            id: "python3",
            name: "Python 3",
            summary: "Installs latest stable Python via Homebrew.",
            category: .runtimes,
            isRequired: false,
            defaultSelected: true,
            dependencies: ["homebrew"],
            commands: [
                InstallCommand("brew install python", timeoutSeconds: 1200)
            ],
            verificationCommand: "python3 --version >/dev/null 2>&1",
            remediationHints: [
                "Ensure Homebrew is healthy (`brew doctor`) and retry.",
                "If another Python manager conflicts, remove conflicting PATH overrides."
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
            verificationCommand: "test -d \"/Applications/Visual Studio Code.app\"",
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
            verificationCommand: "command -v codex >/dev/null 2>&1",
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
                InstallCommand("gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --web --git-protocol https", timeoutSeconds: 1500)
            ],
            verificationCommand: "gh auth status >/dev/null 2>&1",
            remediationHints: [
                "Complete the browser authorization flow and return.",
                "If `gh auth login` opens no browser, run `gh auth login --web` manually once."
            ]
        )
    ]
}
