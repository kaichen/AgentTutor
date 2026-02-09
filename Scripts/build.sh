#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: Scripts/build.sh [options]

Options:
  --configuration <Debug|Release>  Build configuration (default: Debug)
  --clean                          Run clean before build
  --help                           Show this message
EOF
}

configuration="Debug"
clean=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            [[ $# -ge 2 ]] || fail "--configuration requires a value."
            configuration="$2"
            shift 2
            ;;
        --clean)
            clean=1
            shift
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

xcode_args=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$configuration"
    -destination "$DEFAULT_DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
)

if [[ "$DISABLE_CODE_SIGNING" == "1" ]]; then
    xcode_args+=(
        "$XCODEBUILD_CODE_SIGNING_ALLOWED_ARG"
        "$XCODEBUILD_CODE_SIGNING_REQUIRED_ARG"
        "$XCODEBUILD_CODE_SIGN_IDENTITY_ARG"
    )
fi

if [[ "$clean" == "1" ]]; then
    run_cmd "${xcode_args[@]}" clean build
else
    run_cmd "${xcode_args[@]}" build
fi

log "Build completed for configuration '${configuration}'."
