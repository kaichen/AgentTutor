# Repository Guidelines

## Project Structure & Module Organization
- `AgentTutor/` contains app source code.
- `AgentTutor/Core/Install/` holds install domain logic (`InstallCatalog`, planner, shell executor, logger).
- `AgentTutor/Core/AI/` contains remediation/advice logic.
- `AgentTutor/Features/Setup/` contains SwiftUI flow/state (`SetupFlowView`, `SetupViewModel`).
- `AgentTutor/Assets.xcassets/` stores app icons and color assets.
- `AgentTutorTests/` contains unit tests using Swift Testing (`@Test`, `#expect`).
- `AgentTutorUITests/` contains UI tests using XCTest.
- `docs/plans/` stores design and planning documents.

## Build, Test, and Development Commands
- `open AgentTutor.xcodeproj` opens the project in Xcode for local run/debug.
- `xcodebuild -project AgentTutor.xcodeproj -scheme AgentTutor -configuration Debug -destination 'platform=macOS' build` builds from CLI.
- `xcodebuild -project AgentTutor.xcodeproj -scheme AgentTutor -destination 'platform=macOS' test` runs the shared scheme’s tests.
- `xcodebuild -project AgentTutor.xcodeproj -scheme AgentTutor -destination 'platform=macOS' -only-testing:AgentTutorTests test` runs only unit tests for faster iteration.

## Coding Style & Naming Conventions
- Use Swift/SwiftUI conventions with 4-space indentation and clear, small types.
- Use `UpperCamelCase` for types/protocols and `lowerCamelCase` for functions, properties, and enum cases.
- Name test files with `*Tests.swift`.
- Keep business rules centralized: installation catalog in `AgentTutor/Core/Install/InstallCatalog.swift`, validation in planner/safety types, not UI views.
- No repo-level SwiftLint/SwiftFormat config is committed; use Xcode formatting/re-indent before commit.

## Testing Guidelines
- Add unit tests for validation, dependency resolution, and command safety changes.
- Cover both success and failure paths, especially in install/remediation flows.
- For UI behavior changes in `Features/Setup`, add or update `AgentTutorUITests` checks.

## Commit & Pull Request Guidelines
- Git history is currently minimal (`Initial Commit`), so use Conventional Commits going forward (for example, `feat: add install retry notice`).
- Keep PRs focused and include: **Why**, **How**, and **Tests** (commands plus results).
- Link related issues and include screenshots when UI behavior or layout changes.

## Security & Configuration Tips
- Never commit API keys or secrets; use environment/runtime configuration only.
- Treat shell commands as untrusted input and gate execution through command safety checks.
- Validate inputs early and fail fast on invalid configuration.
