# Findings

## 2026-02-08
- Repository is fresh SwiftUI macOS template.
- Existing app has no product logic yet.
- Homebrew package checks:
  - Formulae exist: ripgrep, fd, jq, yq, gh, uv, nvm, node, python@3.12.
  - Casks: visual-studio-code exists.
  - `codex` cask resolves to Codex CLI binary, not GUI app.
  - `craft` cask exists but user chose not to include in V1.
- User confirmed V1 decisions and approved start.

## Build/Runtime validation
- Debug app target builds successfully after implementation.
- Xcode test invocation in this machine hangs when UI test target is in the scheme lifecycle (no deterministic test completion in CLI run).
- The issue is environmental/runner-related (automation mode/UITest harness), not a compile failure in app code.

## 2026-02-09 Scripts/Release research
- CodexBar script architecture uses a clear separation:
  - build/run loop (`compile_and_run.sh`)
  - packaging (`package_app.sh`)
  - signing/notarization (`sign-and-notarize.sh`)
  - end-to-end release orchestration (`release.sh`)
- Useful reusable patterns from CodexBar:
  - strict argument/env validation and fail-fast behavior (`set -euo pipefail`)
  - single source of truth for project constants in one script
  - release script composes lower-level scripts instead of duplicating logic
  - output artifacts include machine-readable metadata for automation
- AgentTutor adaptation choices:
  - use `xcodebuild archive` (Xcode project workflow) instead of SwiftPM-only build paths
  - default tests to `AgentTutorTests` for stable automation, with `--all` override for UI tests
  - publish/notarize are explicit release flags, not implicit behavior

## 2026-02-09 GitHub Actions design findings
- Workflow split is optimal as two pipelines:
  - `CI` for PR/main validation
  - `Tag Release` for artifact publishing on version tags
- Tag-to-version guard is critical:
  - comparing `GITHUB_REF_NAME` to `v$(MARKETING_VERSION)` prevents accidental wrong-tag releases.
- GitHub-hosted macOS runners cannot be assumed to have project signing identities.
  - scripts now support `AGENTTUTOR_DISABLE_CODE_SIGNING=1`, allowing deterministic CI builds/tests/archives without certificates.
- Release publishing strategy:
  - build release artifacts via project scripts
  - publish assets with `gh release create/upload` for idempotent reruns (`--clobber`).

## 2026-02-09 Deep review follow-up decisions
- Product policy was confirmed to directly block installation start when API key/base URL validation fails.
- Runtime policy was confirmed to use Homebrew `node@22` and Homebrew `python@3.10` as baseline environment targets.
- `nvm` is treated as optional future-development tooling, not baseline environment requirement.

## 2026-02-09 Brew verification optimization findings
- `brew list` default output does not include casks, so reliable package inventory needs two queries:
  - `brew list --formula`
  - `brew list --cask`
- CLI/Cask verification can be mapped to a stable package identity (`formula`/`cask` + package name) and validated against cached inventory sets.
- Cache invalidation is required after successful install commands, otherwise post-install verification may read stale package state.

## 2026-02-12 OpenClaw init + channel configuration findings
- OpenClaw non-interactive onboard must include `--non-interactive --accept-risk` and cannot use OAuth in this mode.
- Current product provider list includes `OpenAI`, but non-interactive OpenClaw onboard supports only API-key providers (`OpenRouter`, `Kimi`, `MiniMax` in current UI scope), so provider compatibility must be validated before running commands.
- Channel setup is best implemented with direct `openclaw plugins enable <channel>` + `openclaw config set --json channels.<channel> <json>` rather than manual file writes, which keeps a single canonical command path.
- Secrets can leak through command logging if commands are echoed directly; redacted command/output handling is required for onboarding and channel config commands.
