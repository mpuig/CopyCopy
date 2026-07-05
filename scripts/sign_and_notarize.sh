#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/version.env"

APP_NAME="${APP_NAME:-CopyCopy}"
APP_BUNDLE="${ROOT_DIR}/dist/${APP_NAME}.app"
APP_IDENTITY="${APP_IDENTITY:-}"

log()  { printf '%s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -d "$APP_BUNDLE" ]] || fail "Missing app bundle: $APP_BUNDLE (run ./build.sh first)"
[[ -n "$APP_IDENTITY" ]] || fail "APP_IDENTITY is required (e.g. 'Developer ID Application: Your Name (TEAMID)')"

TMP_ZIP="/tmp/${APP_NAME}Notarize.zip"
trap 'rm -f "$TMP_ZIP" /tmp/copycopy-api-key.p8' EXIT

codesign_one() {
  codesign --force --timestamp --options runtime --sign "$APP_IDENTITY" "$1"
}

resign_sparkle_if_present() {
  local sparkle="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  [[ -d "$sparkle" ]] || return 0

  log "Signing Sparkle.framework components"
  local inner=()
  if [[ -x "$sparkle/Versions/Current/Sparkle" ]]; then inner+=("$sparkle/Versions/Current/Sparkle"); fi
  if [[ -x "$sparkle/Versions/Current/Autoupdate" ]]; then inner+=("$sparkle/Versions/Current/Autoupdate"); fi
  if [[ -x "$sparkle/Versions/Current/Updater.app/Contents/MacOS/Updater" ]]; then inner+=("$sparkle/Versions/Current/Updater.app/Contents/MacOS/Updater"); fi
  if [[ -x "$sparkle/Versions/Current/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" ]]; then inner+=("$sparkle/Versions/Current/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"); fi
  if [[ -x "$sparkle/Versions/Current/XPCServices/Installer.xpc/Contents/MacOS/Installer" ]]; then inner+=("$sparkle/Versions/Current/XPCServices/Installer.xpc/Contents/MacOS/Installer"); fi

  for bin in "${inner[@]}"; do
    codesign_one "$bin"
  done

  if [[ -d "$sparkle/Versions/Current/Updater.app" ]]; then codesign_one "$sparkle/Versions/Current/Updater.app"; fi
  if [[ -d "$sparkle/Versions/Current/XPCServices/Downloader.xpc" ]]; then codesign_one "$sparkle/Versions/Current/XPCServices/Downloader.xpc"; fi
  if [[ -d "$sparkle/Versions/Current/XPCServices/Installer.xpc" ]]; then codesign_one "$sparkle/Versions/Current/XPCServices/Installer.xpc"; fi

  codesign_one "$sparkle"
}

# build.sh ad-hoc signs the whole bundle (no APP_IDENTITY in that step), and the
# app-bundle sign below is not --deep, so nested frameworks keep their ad-hoc
# signature unless we re-sign them inside-out here. An ad-hoc-signed nested
# framework (no Developer ID, no secure timestamp, no hardened runtime) makes
# notarization come back Invalid — so llama.framework must be re-signed too.
resign_llama_if_present() {
  local llama="$APP_BUNDLE/Contents/Frameworks/llama.framework"
  [[ -d "$llama" ]] || return 0

  log "Signing llama.framework"
  if [[ -f "$llama/Versions/Current/llama" ]]; then
    codesign_one "$llama/Versions/Current/llama"
  fi
  codesign_one "$llama"
}

log "==> Ensuring app contents won't break code sealing"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
find "$APP_BUNDLE" -name '._*' -delete 2>/dev/null || true

log "==> Signing"
resign_sparkle_if_present
resign_llama_if_present
codesign_one "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

log "==> Creating notarization zip"
DITTO_BIN=${DITTO_BIN:-/usr/bin/ditto}
"$DITTO_BIN" --norsrc -c -k --keepParent "$APP_BUNDLE" "$TMP_ZIP"

log "==> Submitting to Apple notary service"
# Build the credential args once so both `submit` and `log` reuse them.
NOTARY_CRED=()
if [[ -n "${NOTARYTOOL_KEYCHAIN_PROFILE:-}" ]]; then
  NOTARY_CRED=(--keychain-profile "$NOTARYTOOL_KEYCHAIN_PROFILE")
elif [[ -n "${APP_STORE_CONNECT_API_KEY_P8:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" && -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]]; then
  echo "$APP_STORE_CONNECT_API_KEY_P8" | sed 's/\\n/\n/g' > /tmp/copycopy-api-key.p8
  NOTARY_CRED=(--key /tmp/copycopy-api-key.p8 --key-id "$APP_STORE_CONNECT_KEY_ID" --issuer "$APP_STORE_CONNECT_ISSUER_ID")
else
  fail "Missing notarization credentials: set NOTARYTOOL_KEYCHAIN_PROFILE or APP_STORE_CONNECT_API_KEY_P8 + APP_STORE_CONNECT_KEY_ID + APP_STORE_CONNECT_ISSUER_ID"
fi

# Capture output so we can inspect the final status. notarytool submit --wait
# exits 0 even when the result is Invalid/Rejected, so we must parse it ourselves
# and fetch the detailed log — otherwise we'd blindly try to staple a bundle that
# was never notarized (which fails later with an opaque "Record not found").
SUBMIT_OUTPUT="$(xcrun notarytool submit "$TMP_ZIP" "${NOTARY_CRED[@]}" --wait 2>&1)" || true
printf '%s\n' "$SUBMIT_OUTPUT"

SUBMISSION_ID="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk '/^[[:space:]]*id:/{print $2; exit}')"
FINAL_STATUS="$(printf '%s\n' "$SUBMIT_OUTPUT" | awk -F': ' '/^[[:space:]]*status:/{s=$2} END{print s}')"

if [[ "$FINAL_STATUS" != "Accepted" ]]; then
  log "==> Notarization did not succeed (status: ${FINAL_STATUS:-unknown}); fetching detailed log"
  if [[ -n "$SUBMISSION_ID" ]]; then
    xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_CRED[@]}" || true
  fi
  fail "Notarization failed (status: ${FINAL_STATUS:-unknown}). See the issues log above."
fi

log "==> Stapling notarization ticket"
xcrun stapler staple "$APP_BUNDLE"

log "==> Best-effort Gatekeeper validation"
spctl -a -t exec -vv "$APP_BUNDLE" || true
xcrun stapler validate "$APP_BUNDLE" || true

log "OK: signed + notarized + stapled: $APP_BUNDLE"
