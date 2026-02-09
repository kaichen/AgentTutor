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
