# Task Plan

## Goal
Build Milestone 1 of AgentTutor: a production-grade macOS app foundation with guided setup UI, manifest-driven install engine, local logging, and fail-fast workflow.

## Scope (Milestone 1)
- Multi-step SwiftUI onboarding/install flow.
- API key gating (required before start, not persisted).
- Deterministic install manifest with selectable items.
- Command execution engine with ordered steps and dependency checks.
- Fail-fast behavior and remediation suggestion pane.
- Local structured logs and export path.
- Unit tests for core manifest/validation logic.

## Phases
1. [completed] Project audit and architecture skeleton.
2. [completed] Implement domain models + install manifest source of truth.
3. [completed] Implement command runner, logging, and execution orchestration.
4. [completed] Implement SwiftUI flow and user interactions.
5. [in_progress] Add tests and run validation.
6. [pending] Summarize outcomes and next milestones.

## Decisions
- Platform: Apple Silicon + macOS 14/15.
- Stack: native SwiftUI/AppKit.
- AI key required before install; no persistence.
- Fixed package list + toggle selection.
- Fail-fast and stop on first failure.
- gh auth is mandatory.

## Errors Encountered
| Error | Attempt | Resolution |
|---|---:|---|
| `ObservableObject/@Published` compile failure due missing module | 1 | Added `import Combine` in `SetupViewModel.swift` |
| `xcodebuild test` hangs under UI test automation in this environment | 1 | Validated with successful app build; test execution remains blocked by runner behavior |

## 2026-02-09 Task: Delivery Scripts + Docs

### Goal
Add production-grade script pipeline for build/test/package/release (inspired by CodexBar), plus repository documentation for usage and release operations.

### Phases
1. [completed] Compare CodexBar script architecture and extract reusable patterns.
2. [completed] Implement `Scripts/common.sh`, `build.sh`, `test.sh`, `package_app.sh`, `release.sh`.
3. [completed] Document usage in `README.md` and create `docs/RELEASING.md`.
4. [completed] Validate scripts by executing build/test/package/release smoke runs.

### Decisions
- Keep script entrypoints under `Scripts/` to align with CodexBar conventions.
- Make unit-test-only execution the default in `Scripts/test.sh`; full scheme tests are opt-in via `--all`.
- Package outputs are versioned and fail-fast if artifact directories already exist to avoid accidental overwrites.
- Archive/result-bundle paths include UTC timestamps to allow repeatable release runs without manual cleanup.

### Errors Encountered
| Error | Attempt | Resolution |
|---|---:|---|
| `release.sh` failed when fixed archive path already existed | 1 | Changed default archive naming to `AgentTutor-<ver>-<build>-<timestamp>.xcarchive` |
| `release.sh` failed when fixed archive result bundle path already existed | 1 | Changed `ArchiveResults` bundle name to include timestamp |

## 2026-02-09 Task: GitHub Actions CI + Tag Release

### Goal
Create production-ready GitHub Actions for automated CI validation and automatic tag-based release publishing.

### Phases
1. [completed] Design workflow topology and trigger strategy (`CI`, `Tag Release`).
2. [completed] Implement workflows in `.github/workflows/`.
3. [completed] Make scripts CI-safe for unsigned runners via explicit code-signing override.
4. [completed] Validate with local dry runs and syntax checks.

### Decisions
- CI runs on macOS and executes canonical scripts (`build.sh`, `test.sh`, `package_app.sh`) to keep one source of truth.
- Tag release is triggered on `v*` tags and hard-gates tag/version consistency using `MARKETING_VERSION`.
- Workflow release uses GitHub CLI to create or update release assets idempotently.
- CI and tag release run with `AGENTTUTOR_DISABLE_CODE_SIGNING=1` to avoid hosted-runner certificate coupling.

### Errors Encountered
| Error | Attempt | Resolution |
|---|---:|---|
| Hosted CI runners may fail due missing signing identity | 1 | Added `AGENTTUTOR_DISABLE_CODE_SIGNING` support in scripts and enabled it in workflows |

## 2026-02-09 Task: Policy Clarification (Install Gating + Runtime Baseline)

### Goal
Record accepted product policy decisions from deep code review follow-up.

### Phases
1. [completed] Confirm decision on API key/base URL gating behavior.
2. [completed] Confirm decision on runtime baseline and `nvm` positioning.
3. [completed] Sync canonical documentation (`README`, V1 design plan).

### Decisions
- Installation start must be blocked unless API key and base URL validation succeed.
- Baseline runtime configuration is Homebrew `node@22` and Homebrew `python@3.10`.
- `nvm` is considered optional/future-development tooling rather than a baseline runtime requirement.

## 2026-02-09 Task: Brew Verification Cache Optimization

### Goal
Optimize CLI/Cask installation verification by preloading Homebrew package inventory once and reusing it across checks.

### Phases
1. [completed] Extend verification model to describe brew formula/cask package identity.
2. [completed] Implement one-time Homebrew inventory loading and cache-backed check path.
3. [completed] Update catalog/test coverage and validate with unit tests.

### Decisions
- Verify CLI/Cask package presence via cached `brew list --formula` and `brew list --cask` results.
- Fall back to command-based checks only when cache loading fails.
- Invalidate cache after successful install command execution to keep post-install verification accurate.

## 2026-02-12 Task: OpenClaw One-Click Initialization + Channel UI

### Goal
Implement the final OpenClaw setup phase: one-click non-interactive onboard (using selected LLM provider + API key) and UI-driven multi-channel configuration injection.

### Phases
1. [completed] Extend canonical setup models with OpenClaw provider/channel policy.
2. [completed] Implement end-to-end OpenClaw execution chain (install -> onboard -> plugin enable -> config set -> gateway restart/probe).
3. [completed] Add OpenClaw channel configuration UI (Telegram/Slack/Feishu).
4. [completed] Add/update unit tests and run validation.

### Decisions
- Non-interactive onboarding is enforced with `--non-interactive --accept-risk --mode local`.
- OpenAI provider is blocked for non-interactive OpenClaw onboard; supported providers remain OpenRouter/Kimi/MiniMax.
- Channel configuration uses `openclaw config set --json channels.<name> ...` as the canonical write path.
- Sensitive onboarding/channel commands are logged with redacted command/output to avoid key/token exposure.
