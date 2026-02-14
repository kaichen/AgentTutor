# AgentTutor Tauri + pi Migration Plan

## Goal

Rebuild AgentTutor as a cross-platform desktop app using:

- Tauri (UI + Rust backend)
- pi as the agent runtime (planning + loop)
- A single tool surface: `bash`
- System operations implemented via Bash-driven skills for Homebrew and GitHub CLI
- `gh auth login --web` for GitHub login, with explicit user guidance to complete browser flow

This plan assumes we are intentionally choosing the high-risk model: LLM can propose actions and the system executes them. The mitigation is to constrain what `bash` is allowed to do via strict, centralized policy and a small allowlist of vetted scripts.

## Non-Goals

- No general-purpose tools beyond `bash` (no browser automation tool, no file-edit tool, no arbitrary network tool).
- No “LLM writes arbitrary shell scripts” at runtime.
- No parallel implementations of the same policy in multiple places.

## Target Architecture

- Frontend: Tauri web UI
- Backend: Tauri Rust commands
- Agent runtime: pi running inside the backend process (or as a child process), calling only `bash`
- Skill execution: backend invokes `bash` with a fixed set of scripts in `Skills/` (canonical implementation)
- State and logs: append-only JSONL logs, plus structured run state for UI

## Canonical Policy (Single Source of Truth)

Create a single module (Rust) that defines:

- Allowed skills list and their argument schemas
- Risk tier per skill (low, medium, high)
- Human confirmation requirements (at least for high-risk operations)
- Allowed file and directory scopes (read/write)
- Allowed network domains (if any) and explicit prohibition of “download and execute” patterns
- Timeouts and retry rules

All executions must go through this policy gate. No other codepath may run `bash` directly.

## Skill Surface (Bash Only)

Define each skill as a Bash script with:

- `set -euo pipefail`
- Strict argument parsing (no `eval`, no unquoted expansions)
- No dynamic command construction from untrusted strings
- Structured JSON output to stdout, with consistent keys:
  - `ok` (bool)
  - `action` (string)
  - `summary` (string)
  - `stdout` (string)
  - `stderr` (string)
  - `exit_code` (number)
  - `next_steps` (array of string)

Initial skill set:

1. `brew.ensure_installed`
2. `brew.install_formula`
3. `brew.install_cask`
4. `brew.verify`
5. `gh.ensure_installed`
6. `gh.auth.status`
7. `gh.auth.login_web`
8. `git.configure_identity`
9. `ssh.ensure_key_ed25519`
10. `gh.ssh_key.add`

## Agent Loop

The loop runs as a deterministic state machine with strict invariants:

1. Validate inputs and current machine state
2. Plan (pi produces a structured action list referencing only allowed skills)
3. Execute actions sequentially, emitting events for UI
4. Verify after each stage using explicit checks
5. On failure:
   - Capture a normalized failure object
   - Ask pi for remediation plan using only allowed skills
   - Require user confirmation for high-risk actions
6. Finish with a summary and an exportable diagnostics bundle

## GitHub Auth UX (Web Flow)

Implement `gh.auth.login_web` as:

- Show an in-app modal explaining:
  - It will open the browser
  - The user must complete login in the browser
  - Return to the app and click “Continue”
- Execute `gh auth login --hostname github.com --web --git-protocol ssh`
- Poll `gh auth status` until success or a fixed timeout
- If timeout, present recovery options:
  - Retry login
  - Open GitHub device/browser instructions again
  - Continue without GitHub (if product permits)

## Homebrew Operations

Rules:

- `brew.ensure_installed` may require elevation
- Prefer a predictable install path and PATH setup for subsequent commands
- Use explicit verification checks after install
- Avoid “curl | sh” except for the official Homebrew installer, and treat it as high-risk with user confirmation

## Data and Logging

- Maintain per-run JSONL logs with stable event types:
  - `run_started`, `plan_generated`, `skill_started`, `skill_succeeded`, `skill_failed`, `user_confirm_requested`, `user_confirmed`, `run_completed`
- Store minimal configuration:
  - No API keys persisted unless explicitly requested by the user
  - If persisted, use OS keychain with clear UX consent

## Security Hard Requirements

- Never execute arbitrary shell strings produced by the model.
- The model can only select from:
  - Allowed skill IDs
  - Allowed arguments validated by schema
- Any skill that:
  - uses `sudo`
  - writes to `~/.ssh` or modifies git global config
  - installs system software
  must be “high risk” and require explicit user confirmation.
- Enforce a maximum execution time per skill and per run.
- Redact secrets from logs and UI.

## Project Layout Proposal

- `src-tauri/` (Rust)
- `src/` (frontend)
- `skills/` (bash skill scripts, canonical)
- `docs/` (design, policy, threat model, release)

## Delivery Milestones

### Milestone 0: Repo Preparation

1. Add new Tauri app directory without deleting the existing Swift app.
2. Document the migration and define end-of-life criteria for SwiftUI app.

Acceptance:

- Both apps can build independently.
- Shared “catalog/policy” exists in one place, referenced by Tauri implementation.

### Milestone 1: Minimal Tauri Shell + Logging

1. Tauri UI skeleton with:
   - Stage navigation
   - Live log viewer
   - User confirmation modal
2. Backend event stream for run updates.

Acceptance:

- User can start a run, see events, cancel safely, and export logs.

### Milestone 2: Brew + GH Skills

1. Implement `brew.*` and `gh.*` skills as vetted scripts.
2. Implement policy gate and schema validation.

Acceptance:

- Can install Homebrew (if missing), install `gh`, and complete `gh auth login --web`.

### Milestone 3: Agent Loop + pi Integration

1. Integrate pi runtime.
2. Define the structured plan format and enforce validation.
3. Implement failure -> remediation replanning with user confirmations.

Acceptance:

- On induced failures, the system produces a remediation plan that only calls allowed skills.

### Milestone 4: Feature Parity With Current Swift App

1. Install catalog parity (components, dependencies, verification).
2. Git identity + SSH key + GitHub SSH key upload flows.

Acceptance:

- Same user journey and outcomes as the existing app for macOS, with reproducible logs.

### Milestone 5: Hardening and Release

1. Threat model and security review.
2. Add automated tests:
   - Policy validation
   - Skill argument validation
   - Log redaction
3. Packaging, signing, notarization for macOS, plus Windows/Linux packaging strategy.

Acceptance:

- Release candidate that can handle 1000+ users with low support burden.

## Open Questions

1. Do we allow “continue without GitHub login” as a supported path? ANSWER: yes.
2. Do we ever persist API keys, or strictly session-only? ANSWER: session-only.
3. What is the minimum supported OS set for Windows/Linux, and do we support non-Homebrew package managers there? ANSWER: mac only.

