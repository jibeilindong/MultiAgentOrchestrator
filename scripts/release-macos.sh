#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Multi-Agent-Flow.xcodeproj"
SCHEME="Multi-Agent-Flow"
APP_NAME="Multi-Agent-Flow"
CONFIGURATION="${CONFIGURATION:-Release}"
TEAM_ID="${TEAM_ID:-4TPD585PDN}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application}"
NOTARIZE="${NOTARIZE:-1}"
NOTARY_TIMEOUT="${NOTARY_TIMEOUT:-30m}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
APPLE_ID="${NOTARY_APPLE_ID:-}"
APPLE_ID_PASSWORD="${NOTARY_PASSWORD:-}"
APPLE_TEAM_ID="${NOTARY_TEAM_ID:-$TEAM_ID}"
API_KEY_PATH="${NOTARY_API_KEY_PATH:-}"
API_KEY_ID="${NOTARY_API_KEY_ID:-}"
API_KEY_ISSUER="${NOTARY_API_ISSUER:-}"

BUILD_ROOT="$ROOT_DIR/.build/release"
ARCHIVE_PATH="$BUILD_ROOT/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_ROOT/export"
EXPORT_OPTIONS_PLIST="$BUILD_ROOT/ExportOptions.plist"
NOTARY_ZIP_PATH="$BUILD_ROOT/$APP_NAME-notary.zip"
DMG_STAGING_DIR="$BUILD_ROOT/dmg"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP_PATH="$DIST_DIR/$APP_NAME.app"
DIST_ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
DIST_DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"
EXPORTED_APP_PATH="$EXPORT_DIR/$APP_NAME.app"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/release-macos.sh
  ./scripts/release-macos.sh --preflight

Environment variables:
  TEAM_ID                   Apple Developer Team ID. Default: 4TPD585PDN
  DEVELOPER_ID_APPLICATION  Signing certificate selector or exact name.
                            Default: Developer ID Application
  CONFIGURATION             Xcode build configuration. Default: Release
  NOTARIZE                  1 to notarize and staple, 0 to skip. Default: 1
  NOTARY_TIMEOUT            Wait timeout for notarytool. Default: 30m
  NOTARY_KEYCHAIN_PROFILE   Preferred notarytool keychain profile
  NOTARY_APPLE_ID           Apple ID for notarytool
  NOTARY_PASSWORD           App-specific password for NOTARY_APPLE_ID
  NOTARY_TEAM_ID            Team ID for Apple ID auth. Defaults to TEAM_ID
  NOTARY_API_KEY_PATH       App Store Connect API key path (.p8)
  NOTARY_API_KEY_ID         App Store Connect API key ID
  NOTARY_API_ISSUER         App Store Connect API issuer ID
EOF
}

log() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required tool: $1"
}

find_developer_id_identity() {
  security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' \
    | head -n 1
}

detect_notary_mode() {
  if [[ -n "$KEYCHAIN_PROFILE" ]]; then
    printf 'keychain-profile'
    return
  fi

  if [[ -n "$API_KEY_PATH" && -n "$API_KEY_ID" ]]; then
    printf 'api-key'
    return
  fi

  if [[ -n "$APPLE_ID" && -n "$APPLE_ID_PASSWORD" && -n "$APPLE_TEAM_ID" ]]; then
    printf 'apple-id'
    return
  fi

  printf 'missing'
}

run_notarytool_submit() {
  local file_path="$1"
  local mode
  mode="$(detect_notary_mode)"

  case "$mode" in
    keychain-profile)
      xcrun notarytool submit "$file_path" \
        --keychain-profile "$KEYCHAIN_PROFILE" \
        --wait \
        --timeout "$NOTARY_TIMEOUT"
      ;;
    api-key)
      if [[ -n "$API_KEY_ISSUER" ]]; then
        xcrun notarytool submit "$file_path" \
          --key "$API_KEY_PATH" \
          --key-id "$API_KEY_ID" \
          --issuer "$API_KEY_ISSUER" \
          --wait \
          --timeout "$NOTARY_TIMEOUT"
      else
        xcrun notarytool submit "$file_path" \
          --key "$API_KEY_PATH" \
          --key-id "$API_KEY_ID" \
          --wait \
          --timeout "$NOTARY_TIMEOUT"
      fi
      ;;
    apple-id)
      xcrun notarytool submit "$file_path" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait \
        --timeout "$NOTARY_TIMEOUT"
      ;;
    *)
      fail "Notary credentials are missing. Set NOTARY_KEYCHAIN_PROFILE, or NOTARY_APPLE_ID/NOTARY_PASSWORD/NOTARY_TEAM_ID, or NOTARY_API_KEY_PATH/NOTARY_API_KEY_ID[/NOTARY_API_ISSUER]."
      ;;
  esac
}

create_export_options_plist() {
  local identity="$1"

  identity="${identity//&/&amp;}"
  identity="${identity//</&lt;}"
  identity="${identity//>/&gt;}"
  identity="${identity//\"/&quot;}"
  identity="${identity//\'/&apos;}"

  cat >"$EXPORT_OPTIONS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingCertificate</key>
  <string>$identity</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>teamID</key>
  <string>$TEAM_ID</string>
</dict>
</plist>
EOF
}

create_dmg() {
  local app_path="$1"
  local dmg_path="$2"

  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$app_path" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$dmg_path" \
    >/dev/null
}

preflight() {
  local identity
  local notary_mode

  identity="$(find_developer_id_identity)"
  notary_mode="$(detect_notary_mode)"

  printf 'Project: %s\n' "$PROJECT_PATH"
  printf 'Scheme: %s\n' "$SCHEME"
  printf 'Team ID: %s\n' "$TEAM_ID"
  printf 'Build configuration: %s\n' "$CONFIGURATION"

  if [[ -n "$identity" ]]; then
    printf 'Developer ID certificate: %s\n' "$identity"
  else
    printf 'Developer ID certificate: missing\n'
  fi

  if [[ "$notary_mode" == "missing" ]]; then
    printf 'Notary credentials: missing\n'
  else
    printf 'Notary credentials: %s\n' "$notary_mode"
  fi

  if [[ -z "$identity" || "$notary_mode" == "missing" ]]; then
    exit 1
  fi
}

cleanup() {
  rm -rf "$DMG_STAGING_DIR"
}

main() {
  local developer_id_identity

  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  if [[ "${1:-}" == "--preflight" ]]; then
    preflight
    exit 0
  fi

  if [[ $# -gt 0 ]]; then
    usage
    fail "Unknown argument: $1"
  fi

  require_tool xcodebuild
  require_tool xcrun
  require_tool security
  require_tool ditto
  require_tool hdiutil
  require_tool codesign
  require_tool spctl

  developer_id_identity="$(find_developer_id_identity)"
  [[ -n "$developer_id_identity" ]] || fail "No 'Developer ID Application' certificate was found in the keychain."

  if [[ "$NOTARIZE" != "0" ]]; then
    [[ "$(detect_notary_mode)" != "missing" ]] || fail "Notary credentials are required when NOTARIZE=1."
  fi

  trap cleanup EXIT

  rm -rf "$BUILD_ROOT" "$DIST_DIR"
  mkdir -p "$BUILD_ROOT" "$DIST_DIR"

  log "Archiving $APP_NAME"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    archive

  log "Exporting Developer ID signed app"
  mkdir -p "$EXPORT_DIR"
  create_export_options_plist "$DEVELOPER_ID_APPLICATION"
  xcodebuild \
    -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

  [[ -d "$EXPORTED_APP_PATH" ]] || fail "Export succeeded but app bundle was not found at $EXPORTED_APP_PATH"

  log "Verifying code signature"
  codesign --verify --deep --strict --verbose=2 "$EXPORTED_APP_PATH"

  log "Preparing app for notarization"
  ditto -c -k --sequesterRsrc --keepParent "$EXPORTED_APP_PATH" "$NOTARY_ZIP_PATH"

  if [[ "$NOTARIZE" != "0" ]]; then
    log "Submitting app archive to Apple notarization service"
    run_notarytool_submit "$NOTARY_ZIP_PATH"

    log "Stapling notarization ticket to app"
    xcrun stapler staple "$EXPORTED_APP_PATH"
    xcrun stapler validate "$EXPORTED_APP_PATH"
  fi

  log "Creating distributable artifacts"
  cp -R "$EXPORTED_APP_PATH" "$DIST_APP_PATH"
  ditto -c -k --sequesterRsrc --keepParent "$DIST_APP_PATH" "$DIST_ZIP_PATH"
  create_dmg "$DIST_APP_PATH" "$DIST_DMG_PATH"

  if [[ "$NOTARIZE" != "0" ]]; then
    log "Submitting dmg to Apple notarization service"
    run_notarytool_submit "$DIST_DMG_PATH"

    log "Stapling notarization ticket to dmg"
    xcrun stapler staple "$DIST_DMG_PATH"
    xcrun stapler validate "$DIST_DMG_PATH"
  fi

  log "Running final Gatekeeper assessment"
  spctl -a -vv "$DIST_APP_PATH" || true

  find "$DIST_DIR" -name ".DS_Store" -delete 2>/dev/null || true

  printf '\nArtifacts:\n'
  printf '  App: %s\n' "$DIST_APP_PATH"
  printf '  Zip: %s\n' "$DIST_ZIP_PATH"
  printf '  Dmg: %s\n' "$DIST_DMG_PATH"
}

main "$@"
