#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: Scripts/test.sh [options]

Options:
  --configuration <Debug|Release>  Test configuration (default: Debug)
  --unit                           Run only AgentTutor unit tests (default)
  --all                            Run full scheme tests (includes UI tests)
  --clean                          Run clean before test
  --result-bundle <path>           Custom xcresult path
  --help                           Show this message
EOF
}

configuration="Debug"
scope="unit"
clean=0
result_bundle=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            [[ $# -ge 2 ]] || fail "--configuration requires a value."
            configuration="$2"
            shift 2
            ;;
        --unit)
            scope="unit"
            shift
            ;;
        --all)
            scope="all"
            shift
            ;;
        --clean)
            clean=1
            shift
            ;;
        --result-bundle)
            [[ $# -ge 2 ]] || fail "--result-bundle requires a value."
            result_bundle="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
done

require_cmd xcodebuild
ensure_dir "$DERIVED_DATA_PATH"
ensure_dir "$TEST_RESULTS_ROOT"

if [[ -z "$result_bundle" ]]; then
    result_bundle="${TEST_RESULTS_ROOT}/${APP_NAME}-${scope}-$(timestamp_utc).xcresult"
else
    result_bundle="$(resolve_path "$result_bundle")"
    ensure_dir "$(dirname "$result_bundle")"
fi

xcode_args=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$configuration"
    -destination "$DEFAULT_DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -resultBundlePath "$result_bundle"
)

if [[ "$DISABLE_CODE_SIGNING" == "1" ]]; then
    xcode_args+=(
        "$XCODEBUILD_CODE_SIGNING_ALLOWED_ARG"
        "$XCODEBUILD_CODE_SIGNING_REQUIRED_ARG"
        "$XCODEBUILD_CODE_SIGN_IDENTITY_ARG"
    )
fi

if [[ "$scope" == "unit" ]]; then
    xcode_args+=(-only-testing:AgentTutorTests)
fi

if [[ "$clean" == "1" ]]; then
    run_cmd "${xcode_args[@]}" clean test
else
    run_cmd "${xcode_args[@]}" test
fi

log "Test run completed. Result bundle: ${result_bundle}"
