# AgentTutor V1 Design

## Product Scope

AgentTutor V1 is a macOS desktop setup assistant for non-technical users on Apple Silicon with macOS 14/15.

Confirmed scope:
- API key is mandatory before installation starts.
- API key is session-only (no persistence).
- Fixed install catalog with user toggles.
- Fail-fast execution (stop on first failure).
- Human approval required before any remediation command execution.
- Local-only logging.
- Distribution target is signed + notarized DMG.

## Catalog (Single Source of Truth)

The install catalog is defined in code as a manifest with dependencies and verification commands.

V1 catalog:
- Xcode Command Line Tools
- Homebrew
- Core CLI: ripgrep, fd, jq, yq, gh, uv, nvm
- Node.js LTS (nvm)
- Python 3
- Visual Studio Code
- Codex CLI
- GitHub CLI login (required)

Each item contains:
- user-visible metadata
- dependencies
- executable commands
- verification command
- remediation hints

## Execution Model

Execution is orchestrated by `SetupViewModel`:
1. Validate API key and selection.
2. Resolve dependency-complete plan in deterministic order.
3. Execute command sequence per item.
4. Verify installation via explicit verification command.
5. On first failure, stop and collect remediation advice.

The shell execution layer includes:
- command timeout handling
- stdout/stderr capture
- optional admin execution path via AppleScript
- basic safety guard for remediation commands

## Remediation Design

Remediation combines:
- deterministic heuristics (offline fallback)
- OpenAI-generated suggestions (Responses API)

Safety rules:
- AI-generated commands are filtered by denylist.
- User must explicitly confirm before command execution.

## UI Flow

The primary flow is staged:
1. Welcome
2. OpenAI key input
3. Install selection
4. Installation + live logs + failure remediation
5. Completion

UX goals:
- no hidden state transitions
- explicit progress and failure visibility
- one-click access to local logs

## Observability

Session logs are written as JSONL to Application Support (`AgentTutor/logs/`).
Each line includes timestamp, level, message, and metadata.

## Security and Platform Constraints

- App sandbox is disabled in project build settings to permit required system command execution for setup tasks.
- API key is held in memory only and never persisted.
- Untrusted AI commands are reviewed and user-approved before execution.

## Current Validation Status

- App target builds successfully in Debug.
- Automated CLI test execution is currently blocked by local UI-test harness behavior in this environment; unit test files are in place and compile within the test target.

## Next Milestone (M2)

- Improve privileged-step UX with explicit admin-script preview and approval flow.
- Add richer preflight checks (network, disk, shell profile conflicts).
- Improve retry model (resume from failed step after successful remediation).
- Add exportable diagnostic bundle (log + environment snapshot).
