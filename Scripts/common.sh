#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${AGENTTUTOR_SCRIPT_LIB_LOADED:-}" ]]; then
    return 0
fi
readonly AGENTTUTOR_SCRIPT_LIB_LOADED=1

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly PROJECT_PATH="${ROOT_DIR}/AgentTutor.xcodeproj"
readonly SCHEME="AgentTutor"
readonly APP_NAME="AgentTutor"

readonly DEFAULT_DESTINATION="platform=macOS"
readonly DEFAULT_ARCHIVE_DESTINATION="generic/platform=macOS"
readonly DEFAULT_CONFIGURATION="Release"

readonly BUILD_ROOT="${ROOT_DIR}/Build"
readonly DERIVED_DATA_PATH="${BUILD_ROOT}/DerivedData"
readonly ARCHIVES_ROOT="${BUILD_ROOT}/Archives"
readonly ARTIFACTS_ROOT="${BUILD_ROOT}/Artifacts"
readonly TEST_RESULTS_ROOT="${BUILD_ROOT}/TestResults"
readonly DISABLE_CODE_SIGNING="${AGENTTUTOR_DISABLE_CODE_SIGNING:-0}"

readonly XCODEBUILD_CODE_SIGNING_ALLOWED_ARG="CODE_SIGNING_ALLOWED=NO"
readonly XCODEBUILD_CODE_SIGNING_REQUIRED_ARG="CODE_SIGNING_REQUIRED=NO"
readonly XCODEBUILD_CODE_SIGN_IDENTITY_ARG="CODE_SIGN_IDENTITY="

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

run_cmd() {
    log "$*"
    "$@"
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        fail "Required command not found: ${cmd}"
    fi
}

ensure_dir() {
    local dir="$1"
    mkdir -p "$dir"
}

resolve_path() {
    local input="$1"
    if [[ "$input" == /* ]]; then
        printf '%s\n' "$input"
    else
        printf '%s\n' "${ROOT_DIR}/${input}"
    fi
}

assert_path_absent() {
    local path="$1"
    if [[ -e "$path" ]]; then
        fail "Path already exists: ${path}. Remove it manually or bump version/build number."
    fi
}

timestamp_utc() {
    date -u +"%Y%m%dT%H%M%SZ"
}

build_setting() {
    local key="$1"
    local configuration="${2:-$DEFAULT_CONFIGURATION}"
    local value

    value="$(xcodebuild \
        -project "$PROJECT_PATH" \
        -scheme "$SCHEME" \
        -configuration "$configuration" \
        -showBuildSettings 2>/dev/null | awk -F ' = ' -v key="$key" '$1 ~ ("[[:space:]]" key "$") { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }')"

    if [[ -z "$value" ]]; then
        fail "Unable to resolve build setting '${key}' for configuration '${configuration}'."
    fi
    printf '%s\n' "$value"
}

marketing_version() {
    local configuration="${1:-$DEFAULT_CONFIGURATION}"
    build_setting "MARKETING_VERSION" "$configuration"
}

build_number() {
    local configuration="${1:-$DEFAULT_CONFIGURATION}"
    build_setting "CURRENT_PROJECT_VERSION" "$configuration"
}

release_identifier() {
    local configuration="${1:-$DEFAULT_CONFIGURATION}"
    local version
    local build
    version="$(marketing_version "$configuration")"
    build="$(build_number "$configuration")"
    printf '%s-%s-%s\n' "$APP_NAME" "$version" "$build"
}

ensure_clean_git_worktree() {
    local status
    require_cmd git
    status="$(git status --porcelain)"
    if [[ -n "$status" ]]; then
        fail "Git worktree is dirty. Commit or stash changes before publishing a release."
    fi
}
