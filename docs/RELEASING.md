# AgentTutor Releasing Guide

This project uses script-first build/release automation plus GitHub Actions for CI and tag-based publishing.

## Script Matrix

| Script | Purpose |
|---|---|
| `Scripts/build.sh` | Build app target (`Debug` default) |
| `Scripts/test.sh` | Run tests (`AgentTutorTests` default via `--unit`) |
| `Scripts/package_app.sh` | Archive + package `.app`, `.zip`, optional `dSYM.zip` |
| `Scripts/release.sh` | End-to-end local release flow with optional notarize and `gh` publish |

## Prerequisites

- macOS with Xcode CLI tools installed
- `xcodebuild`, `xcrun`, `ditto` available
- `gh` authenticated when using `--publish`
- Notarization credentials only when using `--notarize`

Notarization supports either mode:

1. `NOTARYTOOL_PROFILE=<profile-name>` (created via `xcrun notarytool store-credentials`)
2. App Store Connect API environment variables:
   - `APP_STORE_CONNECT_API_KEY_P8`
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`

## Daily Developer Commands

```bash
./Scripts/build.sh --configuration Debug
./Scripts/test.sh --unit
./Scripts/package_app.sh --configuration Release
```

Result bundles are written to `Build/TestResults/*.xcresult`.

## Local Release Flow

Run standard local release:

```bash
./Scripts/release.sh --configuration Release
```

Run with notarization:

```bash
NOTARYTOOL_PROFILE=agenttutor-notary ./Scripts/release.sh --configuration Release --notarize
```

Run with notarization and GitHub release publishing:

```bash
./Scripts/release.sh --configuration Release --notarize --publish --tag v1.0.0 --notes-file ./release-notes.md
```

Important behavior:

- `--publish` requires a clean git worktree
- If `--notes-file` is omitted, `gh --generate-notes` is used
- `--draft` is valid only together with `--publish`
- Notarized zip output is `AgentTutor-<version>-<build>-notarized.zip`

## Packaged Artifact Layout

`Scripts/package_app.sh` emits:

`Build/Artifacts/AgentTutor-<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>/`

Contents:

- `AgentTutor.app`
- `AgentTutor-<version>-<build>.zip`
- `AgentTutor-<version>-<build>.dSYM.zip` (if available)
- `metadata.env` (paths + version/build metadata)

## GitHub Actions

### CI workflow

File: `.github/workflows/ci.yml`

- Triggers: PR to `main`, push to `main`, manual dispatch
- Runs: shell syntax checks -> debug build -> unit tests -> packaging smoke test
- Uploads: `xcresult` bundle and packaging artifacts (when present)

### Tag Release workflow

File: `.github/workflows/tag-release.yml`

- Trigger: push tag matching `v*`
- Guard: tag must equal `v<MARKETING_VERSION>` from project build settings
- Runs: unit tests -> release packaging -> upload workflow artifacts -> publish GitHub Release assets
- Publishes: main zip and optional dSYM zip

## CI Signing Mode

Both workflows set:

`AGENTTUTOR_DISABLE_CODE_SIGNING=1`

This is intentional for hosted runners that do not have your local signing identities.  
For signed/notarized public releases, use local `Scripts/release.sh --notarize` (or provision certs/profiles in CI and remove the override).

## Troubleshooting

- `Path already exists` from packaging scripts:
  scripts are fail-fast and never overwrite artifact/archive paths; remove the old folder or bump version/build number.
- Notarization credential errors:
  confirm either `NOTARYTOOL_PROFILE` or all `APP_STORE_CONNECT_*` vars are set.
- CI reports missing packaging artifact after earlier failed step:
  check the first failing step (build/test); packaging upload is best-effort when files are absent.
