# Progress Log

## 2026-02-08
- Initialized planning files.
- Implemented setup domain models (`SetupStage`, install catalog types, failure/advice models).
- Added manifest-driven install catalog for V1 scope (Xcode CLI tools, Homebrew, CLI tools, Node LTS, Python3, VSCode, Codex CLI, GH auth).
- Added dependency-aware planner with API key validation.
- Implemented shell executor with timeout handling and admin AppleScript execution path.
- Implemented local JSONL logger in Application Support and log folder opening support.
- Implemented remediation advisor with heuristics + OpenAI Responses API fallback.
- Implemented `SetupViewModel` orchestration with fail-fast install behavior and remediation command confirmation.
- Replaced template UI with full guided flow (`welcome -> key -> selection -> install -> completion`).
- Added unit tests for planner and command safety.
- Validation status:
  - `xcodebuild build -project AgentTutor.xcodeproj -scheme AgentTutor -destination 'platform=macOS'` ✅
  - `xcodebuild test ...` repeatedly hangs in this environment due UI-test automation/runtime behavior; unit tests compile but full test execution could not complete end-to-end.

## 2026-02-09
- Added script pipeline:
  - `Scripts/common.sh`
  - `Scripts/build.sh`
  - `Scripts/test.sh`
  - `Scripts/package_app.sh`
  - `Scripts/release.sh`
- Added release documentation: `docs/RELEASING.md`.
- Updated README with script-driven build/test/package/release commands.
- Validation status:
  - `./Scripts/build.sh --configuration Debug` ✅
  - `./Scripts/test.sh --unit` ✅
  - `./Scripts/package_app.sh --configuration Release` ✅
  - `./Scripts/release.sh --skip-tests --output-dir Build/ArtifactsReleaseSmoke3` ✅
- Bugfixes during validation:
  - Changed default archive naming to include timestamp to avoid rerun collisions.
  - Changed archive result bundle naming to include timestamp to avoid rerun collisions.

## 2026-02-09 (GitHub Actions)
- Added `.github/workflows/ci.yml`:
  - PR/main/workflow_dispatch triggers
  - syntax checks + debug build + unit tests + packaging smoke test
  - uploads xcresult and packaging artifacts
- Added `.github/workflows/tag-release.yml`:
  - `v*` tag trigger
  - verifies tag/version alignment
  - runs unit tests and release packaging
  - publishes zip/dSYM assets to GitHub Release
- Updated script infrastructure for CI:
  - introduced `AGENTTUTOR_DISABLE_CODE_SIGNING=1` support in `common.sh`
  - applied override args to `build.sh`, `test.sh`, `package_app.sh`
- Updated docs:
  - `README.md` (GitHub Actions section)
  - `docs/RELEASING.md` (automation + CI signing mode)
- Validation status:
  - `bash -n Scripts/*.sh` ✅
  - `ruby -ryaml` parse on both workflow YAMLs ✅
  - `AGENTTUTOR_DISABLE_CODE_SIGNING=1 ./Scripts/build.sh --configuration Debug` ✅
  - `AGENTTUTOR_DISABLE_CODE_SIGNING=1 ./Scripts/test.sh --unit` ✅
  - `AGENTTUTOR_DISABLE_CODE_SIGNING=1 ./Scripts/package_app.sh --configuration Release --output-dir Build/ArtifactsCISignedOff` ✅
  - `AGENTTUTOR_DISABLE_CODE_SIGNING=1 ./Scripts/release.sh --configuration Release --skip-tests --output-dir Build/ArtifactsReleaseWorkflowSmoke` ✅

## 2026-02-09 (Deep Review follow-up policy logging)
- Recorded accepted policy decisions in canonical docs:
  - `README.md` (`Policy Decisions`, requirements wording, runtime catalog wording)
  - `docs/plans/2026-02-08-agenttutor-v1-design.md` (scope + runtime policy note)
  - `task_plan.md` / `findings.md` (decision log)
- Confirmed policy:
  - Installation start should be directly blocked unless API key/base URL validation succeeds.
  - Runtime baseline is Homebrew `node@22` + `python@3.10`; `nvm` is optional future-development tooling.

## 2026-02-09 (Brew verification cache optimization)
- Added brew package identity metadata to verification checks (`formula` / `cask` + package name).
- Updated install catalog so CLI/Cask checks (`core-cli`, `node@22`, `python@3.10`, `vscode`, `codex-cli`) can use cache-backed verification.
- Implemented SetupViewModel cache-backed verification flow:
  - load Homebrew inventory once per run (`brew list --formula` + `brew list --cask`)
  - reuse cached sets for all brew-package checks
  - invalidate cache after successful install command to keep post-install verification correct
  - fall back to command checks if cache cannot be loaded
- Added/updated tests:
  - `InstallCatalogTests` for cask metadata and brew metadata completeness
  - `SetupViewModelTests.startInstallUsesSingleBrewCacheForAllBrewPackageChecks`
- Validation status:
  - `./Scripts/test.sh --unit` ✅
