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
