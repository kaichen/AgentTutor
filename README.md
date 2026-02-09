# AgentTutor

A macOS desktop setup assistant that automates development environment installation for Apple Silicon Macs. Built with SwiftUI, it guides users through a multi-step onboarding flow — from selecting packages to executing installs — with AI-powered remediation when things go wrong.

## Features

- **Manifest-driven install engine** — 8 curated packages (Xcode CLI Tools, Homebrew, Node.js, Python, VS Code, etc.) with dependency resolution
- **Fail-fast execution** — stops immediately on failure and provides actionable remediation
- **AI-powered remediation** — heuristics-first, with optional OpenAI fallback (`gpt-4.1-mini`) for unrecognized errors
- **Human-approval gates** — every remediation command requires explicit user confirmation before execution
- **Command safety** — blocklist prevents dangerous shell commands (e.g., `rm -rf /`, `diskutil erase`)
- **Structured logging** — JSONL session logs written to `~/Library/Application Support/AgentTutor/logs/`
- **No persistence** — API key is session-only and never written to disk

## Requirements

- macOS 14+
- Apple Silicon (M1+)
- Xcode 15+
- OpenAI API key (entered at runtime, optional but recommended for full remediation)

## Architecture

```
AgentTutor/
├── Core/
│   ├── SetupModels.swift          # Domain types
│   ├── Install/
│   │   ├── InstallCatalog.swift   # Package manifest (source of truth)
│   │   ├── InstallPlanner.swift   # Dependency resolution & validation
│   │   ├── ShellExecutor.swift    # Process execution + safety checks
│   │   └── InstallLogger.swift    # JSONL logging
│   └── AI/
│       └── RemediationAdvisor.swift  # Heuristics + OpenAI fallback
├── Features/
│   └── Setup/
│       ├── SetupFlowView.swift    # 5-stage SwiftUI wizard
│       └── SetupViewModel.swift   # State management & orchestration
├── AgentTutorApp.swift            # App entry point
└── ContentView.swift              # Root view
```

**Key design decisions:**

- Core domain logic isolated from SwiftUI views
- All major services injected for testability
- Swift Structured Concurrency (async/await) throughout
- Sandbox disabled in build settings to allow system-level shell commands

## Build & Run

```bash
# Open in Xcode
open AgentTutor.xcodeproj

# Or build from command line
xcodebuild -project AgentTutor.xcodeproj -scheme AgentTutor \
  -configuration Debug -destination 'platform=macOS' build
```

## Testing

```bash
# Unit tests (recommended)
xcodebuild -project AgentTutor.xcodeproj -scheme AgentTutor \
  -destination 'platform=macOS' -only-testing:AgentTutorTests test
```

Unit tests cover dependency resolution (`InstallPlannerTests`) and command safety validation (`CommandSafetyTests`) using the Swift Testing framework.

## Install Catalog

| Package | Required | Category |
|---------|----------|----------|
| Xcode Command Line Tools | Yes | system |
| Homebrew | Yes | system |
| Core CLI Tools (rg, fd, jq, yq, gh, uv, nvm) | Yes | cli |
| Node.js LTS (via nvm) | No | runtime |
| Python 3 (via Homebrew) | No | runtime |
| Visual Studio Code | No | app |
| Codex CLI | No | app |
| GitHub CLI Login | Yes | auth |

## License

Private project.
