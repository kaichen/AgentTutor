#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

usage() {
    cat <<'EOF'
Usage: Scripts/package_app.sh [options]

Options:
  --configuration <Release|Debug>  Archive configuration (default: Release)
  --output-dir <path>              Artifact root directory (default: Build/Artifacts)
  --archive-path <path>            Custom archive path (.xcarchive)
  --skip-dsym                      Skip dSYM zip packaging
  --help                           Show this message
EOF
}

configuration="Release"
output_dir="$ARTIFACTS_ROOT"
archive_path=""
include_dsym=1

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
        --archive-path)
            [[ $# -ge 2 ]] || fail "--archive-path requires a value."
            archive_path="$2"
            shift 2
            ;;
        --skip-dsym)
            include_dsym=0
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
require_cmd ditto

release_id="$(release_identifier "$configuration")"
version="$(marketing_version "$configuration")"
build="$(build_number "$configuration")"
output_root="$(resolve_path "$output_dir")"
run_stamp="$(timestamp_utc)"

if [[ -z "$archive_path" ]]; then
    archive_path="${ARCHIVES_ROOT}/${release_id}-${run_stamp}.xcarchive"
else
    archive_path="$(resolve_path "$archive_path")"
    assert_path_absent "$archive_path"
fi

artifact_dir="${output_root}/${release_id}"
app_path="${artifact_dir}/${APP_NAME}.app"
zip_path="${artifact_dir}/${release_id}.zip"
dsym_zip_path="${artifact_dir}/${release_id}.dSYM.zip"
archive_result_bundle="${BUILD_ROOT}/ArchiveResults/${release_id}-${run_stamp}.xcresult"

assert_path_absent "$artifact_dir"
assert_path_absent "$archive_result_bundle"

ensure_dir "$(dirname "$archive_path")"
ensure_dir "$output_root"
ensure_dir "$(dirname "$archive_result_bundle")"
ensure_dir "$DERIVED_DATA_PATH"
ensure_dir "$artifact_dir"

xcode_archive_args=(
    xcodebuild
    -project "$PROJECT_PATH"
    -scheme "$SCHEME"
    -configuration "$configuration"
    -destination "$DEFAULT_ARCHIVE_DESTINATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -archivePath "$archive_path"
    -resultBundlePath "$archive_result_bundle"
)
if [[ "$DISABLE_CODE_SIGNING" == "1" ]]; then
    xcode_archive_args+=(
        "$XCODEBUILD_CODE_SIGNING_ALLOWED_ARG"
        "$XCODEBUILD_CODE_SIGNING_REQUIRED_ARG"
        "$XCODEBUILD_CODE_SIGN_IDENTITY_ARG"
    )
fi
xcode_archive_args+=(archive)

run_cmd "${xcode_archive_args[@]}"

archive_app_path="${archive_path}/Products/Applications/${APP_NAME}.app"
[[ -d "$archive_app_path" ]] || fail "Archived app not found: ${archive_app_path}"

run_cmd ditto "$archive_app_path" "$app_path"
run_cmd xattr -cr "$app_path"
run_cmd ditto -c -k --sequesterRsrc --keepParent "$app_path" "$zip_path"

if [[ "$include_dsym" == "1" ]]; then
    archive_dsym_path="${archive_path}/dSYMs/${APP_NAME}.app.dSYM"
    if [[ -d "$archive_dsym_path" ]]; then
        run_cmd ditto -c -k --sequesterRsrc --keepParent "$archive_dsym_path" "$dsym_zip_path"
    else
        warn "dSYM not found at ${archive_dsym_path}; skipped dSYM package."
        dsym_zip_path=""
    fi
else
    dsym_zip_path=""
fi

metadata_path="${artifact_dir}/metadata.env"
{
    printf 'APP_NAME=%q\n' "$APP_NAME"
    printf 'CONFIGURATION=%q\n' "$configuration"
    printf 'VERSION=%q\n' "$version"
    printf 'BUILD_NUMBER=%q\n' "$build"
    printf 'RELEASE_ID=%q\n' "$release_id"
    printf 'ARCHIVE_PATH=%q\n' "$archive_path"
    printf 'APP_PATH=%q\n' "$app_path"
    printf 'ZIP_PATH=%q\n' "$zip_path"
    printf 'DSYM_ZIP_PATH=%q\n' "$dsym_zip_path"
    printf 'RESULT_BUNDLE_PATH=%q\n' "$archive_result_bundle"
} > "$metadata_path"

log "Packaging completed."
printf 'Version: %s (%s)\n' "$version" "$build"
printf 'Archive: %s\n' "$archive_path"
printf 'App: %s\n' "$app_path"
printf 'Zip: %s\n' "$zip_path"
if [[ -n "$dsym_zip_path" ]]; then
    printf 'dSYM Zip: %s\n' "$dsym_zip_path"
fi
printf 'Metadata: %s\n' "$metadata_path"
