# AgentTutor Release Guide

This repository now ships a script-based release pipeline inspired by CodexBar's `Scripts/` workflow, but adapted for this Xcode project.

## Script Matrix

| Script | Purpose |
|---|---|
| `Scripts/build.sh` | Build app target (`Debug` by default) |
| `Scripts/test.sh` | Run tests (`AgentTutorTests` by default) |
| `Scripts/package_app.sh` | Archive and package `.app` + `.zip` (+ optional dSYM zip) |
| `Scripts/release.sh` | End-to-end flow: build, test, package, optional notarize, optional GitHub release |

## Prerequisites

- macOS with Xcode CLI tools
- `xcodebuild`, `xcrun`, `ditto` available
- `gh` authenticated if you use `--publish`
- Notarization credentials only when using `--notarize`

Notarization auth is supported in either mode:

1. `NOTARYTOOL_PROFILE=<profile-name>` (keychain profile from `xcrun notarytool store-credentials`)
2. App Store Connect API env vars:
   - `APP_STORE_CONNECT_API_KEY_P8`
   - `APP_STORE_CONNECT_KEY_ID`
   - `APP_STORE_CONNECT_ISSUER_ID`

## Local Build/Test

```bash
./Scripts/build.sh --configuration Debug
./Scripts/test.sh --unit
./Scripts/test.sh --all   # includes UI tests
```

`Scripts/test.sh` stores result bundles under `Build/TestResults/`.

## Package Release Artifacts

```bash
./Scripts/package_app.sh --configuration Release
```

Generated artifacts are placed under:

`Build/Artifacts/AgentTutor-<MARKETING_VERSION>-<CURRENT_PROJECT_VERSION>/`

The folder includes:

- `AgentTutor.app`
- `AgentTutor-<version>-<build>.zip`
- `AgentTutor-<version>-<build>.dSYM.zip` (if dSYM exists)
- `metadata.env` (machine-readable paths and version metadata)

## Release Flow

Run the full pipeline:

```bash
./Scripts/release.sh --configuration Release
```

With notarization:

```bash
NOTARYTOOL_PROFILE=agenttutor-notary ./Scripts/release.sh --notarize
```

Create GitHub release after packaging:

```bash
./Scripts/release.sh --notarize --publish --tag v1.0.0 --notes-file ./release-notes.md
```

Notes:

- `--publish` requires a clean git worktree.
- If `--notes-file` is omitted, `gh --generate-notes` is used.
- `--draft` can be combined with `--publish` to create draft releases.
- Notarized output is emitted as `AgentTutor-<version>-<build>-notarized.zip`.

## GitHub Actions Automation

Two workflows are defined:

1. `CI` (`.github/workflows/ci.yml`)
2. `Tag Release` (`.github/workflows/tag-release.yml`)

`Tag Release` behavior:

- Trigger: push tag matching `v*`
- Gate: tag name must exactly match `v<MARKETING_VERSION>`
- Steps: unit test -> release packaging -> publish assets to GitHub Release
- Assets: app zip + dSYM zip (if present)

## CI Signing Mode

Both workflows run with:

`AGENTTUTOR_DISABLE_CODE_SIGNING=1`

This disables code-signing requirements for hosted runners so CI and tag release can run without local signing certificates. For notarized/public distribution, keep using local release flow (or provision signing identities in CI and remove this override).

## Troubleshooting

- `Path already exists`: scripts are fail-fast and do not overwrite archives/artifacts. Bump version/build or remove old artifact folders manually.
- Notarization credential error: ensure either `NOTARYTOOL_PROFILE` or all `APP_STORE_CONNECT_*` vars are set.
- UI tests hanging in CI/local automation: use `Scripts/test.sh --unit` for deterministic unit-test runs.
