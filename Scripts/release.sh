#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: Scripts/release.sh [options]

Options:
  --configuration <Release|Debug>  Build configuration (default: Release)
  --output-dir <path>              Artifact root directory (default: Build/Artifacts)
  --skip-tests                     Skip test step
  --all-tests                      Run full scheme tests instead of unit tests only
  --notarize                       Submit zip for notarization and staple app
  --publish                        Create GitHub release via gh
  --draft                          Create release as draft (only with --publish)
  --tag <tag>                      Release tag (default: v<MARKETING_VERSION>)
  --notes-file <path>              Release notes file (default: gh --generate-notes)
  --help                           Show this message
EOF
}

configuration="Release"
output_dir="$ARTIFACTS_ROOT"
run_tests=1
test_scope="unit"
notarize=0
publish=0
draft_release=0
release_tag=""
notes_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            [[ $# -ge 2 ]] || fail "--configuration requires a value."
            configuration="$2"
            shift 2
            ;;
        --output-dir)
            [[ $# -ge 2 ]] || fail "--output-dir requires a value."
            output_dir="$2"
            shift 2
            ;;
        --skip-tests)
            run_tests=0
            shift
            ;;
        --all-tests)
            test_scope="all"
            shift
            ;;
        --notarize)
            notarize=1
            shift
            ;;
        --publish)
            publish=1
            shift
            ;;
        --draft)
            draft_release=1
            shift
            ;;
        --tag)
            [[ $# -ge 2 ]] || fail "--tag requires a value."
            release_tag="$2"
            shift 2
            ;;
        --notes-file)
            [[ $# -ge 2 ]] || fail "--notes-file requires a value."
            notes_file="$2"
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

if [[ "$draft_release" == "1" && "$publish" != "1" ]]; then
    fail "--draft can only be used together with --publish."
fi

if [[ -n "$notes_file" ]]; then
    notes_file="$(resolve_path "$notes_file")"
    [[ -f "$notes_file" ]] || fail "Notes file not found: ${notes_file}"
fi

if [[ "$publish" == "1" ]]; then
    ensure_clean_git_worktree
fi

require_cmd xcrun
require_cmd ditto

run_cmd "${SCRIPT_DIR}/build.sh" --configuration "$configuration"

if [[ "$run_tests" == "1" ]]; then
    if [[ "$test_scope" == "all" ]]; then
        run_cmd "${SCRIPT_DIR}/test.sh" --configuration "$configuration" --all
    else
        run_cmd "${SCRIPT_DIR}/test.sh" --configuration "$configuration" --unit
    fi
fi

output_root="$(resolve_path "$output_dir")"
run_cmd "${SCRIPT_DIR}/package_app.sh" --configuration "$configuration" --output-dir "$output_root"

release_id="$(release_identifier "$configuration")"
version="$(marketing_version "$configuration")"
artifact_dir="${output_root}/${release_id}"
app_path="${artifact_dir}/${APP_NAME}.app"
zip_path="${artifact_dir}/${release_id}.zip"
dsym_zip_path="${artifact_dir}/${release_id}.dSYM.zip"
publish_zip_path="$zip_path"

[[ -d "$app_path" ]] || fail "Packaged app not found: ${app_path}"
[[ -f "$zip_path" ]] || fail "Packaged zip not found: ${zip_path}"

temp_notary_key=""
cleanup() {
    if [[ -n "$temp_notary_key" && -f "$temp_notary_key" ]]; then
        rm -f "$temp_notary_key"
    fi
}
trap cleanup EXIT

submit_for_notarization() {
    local input_zip="$1"

    if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
        run_cmd xcrun notarytool submit "$input_zip" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
        return 0
    fi

    if [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
        temp_notary_key="$(mktemp "${TMPDIR:-/tmp}/agenttutor-notary-api.XXXXXX.p8")"
        printf '%s' "${APP_STORE_CONNECT_API_KEY_P8}" | sed 's/\\n/\n/g' > "$temp_notary_key"
        run_cmd xcrun notarytool submit "$input_zip" \
            --key "$temp_notary_key" \
            --key-id "$APP_STORE_CONNECT_KEY_ID" \
            --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
            --wait
        return 0
    fi

    fail "Notarization requested, but credentials are missing. Set NOTARYTOOL_PROFILE or APP_STORE_CONNECT_* env vars."
}

if [[ "$notarize" == "1" ]]; then
    submit_for_notarization "$zip_path"
    run_cmd xcrun stapler staple "$app_path"
    run_cmd xcrun stapler validate "$app_path"
    run_cmd spctl -a -t exec -vv "$app_path"

    notarized_zip="${artifact_dir}/${release_id}-notarized.zip"
    assert_path_absent "$notarized_zip"
    run_cmd ditto -c -k --sequesterRsrc --keepParent "$app_path" "$notarized_zip"
    publish_zip_path="$notarized_zip"
    log "Notarized package generated: ${notarized_zip}"
fi

if [[ "$publish" == "1" ]]; then
    require_cmd gh

    if [[ -z "$release_tag" ]]; then
        release_tag="v${version}"
    fi

    if gh release view "$release_tag" >/dev/null 2>&1; then
        fail "GitHub release already exists for tag '${release_tag}'."
    fi

    release_cmd=(
        gh release create "$release_tag"
        "$publish_zip_path"
        --title "${APP_NAME} ${version}"
    )

    if [[ -f "$dsym_zip_path" ]]; then
        release_cmd+=("$dsym_zip_path")
    fi

    if [[ -n "$notes_file" ]]; then
        release_cmd+=(--notes-file "$notes_file")
    else
        release_cmd+=(--generate-notes)
    fi

    if [[ "$draft_release" == "1" ]]; then
        release_cmd+=(--draft)
    fi

    run_cmd "${release_cmd[@]}"
    log "GitHub release created: ${release_tag}"
fi

log "Release workflow completed."
printf 'Artifact directory: %s\n' "$artifact_dir"
printf 'Primary zip: %s\n' "$publish_zip_path"
if [[ -f "$dsym_zip_path" ]]; then
    printf 'dSYM zip: %s\n' "$dsym_zip_path"
fi
