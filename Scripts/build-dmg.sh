#!/usr/bin/env bash
# Build a signed + notarized Capso.dmg in one command.
#
# Usage:
#   ./Scripts/build-dmg.sh                 # signed + notarized (default)
#   ./Scripts/build-dmg.sh --skip-notarize # signed only (local / no Gatekeeper)
#   TEAM_ID=H26VXS6A6Y ./Scripts/build-dmg.sh
#
# Required env for notarization (default):
#   APPLE_ID=you@example.com
#   APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx   # app-specific password
#   TEAM_ID=H26VXS6A6Y                       # optional; defaults below
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TEAM_ID="${TEAM_ID:-H26VXS6A6Y}"
SCHEME="Capso"
CONFIG="Release"
BUILD_DIR="$ROOT/build"
ARCHIVE_PATH="$BUILD_DIR/Capso.xcarchive"
STAGE_DIR="$BUILD_DIR/dmg-root"
NOTARIZE=1

for arg in "$@"; do
  case "$arg" in
    --notarize) NOTARIZE=1 ;;
    --skip-notarize) NOTARIZE=0 ;;
    -h|--help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "→ Installing xcodegen…"
  brew install xcodegen
fi

VERSION="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
m = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
print(m.group(1) if m else "0.0.0")
PY
)"
BUILD="$(python3 - <<'PY'
import re, pathlib
text = pathlib.Path("project.yml").read_text()
m = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
print(m.group(1) if m else "0")
PY
)"
DMG_NAME="Capso-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

pick_identity() {
  local identities kind
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"

  # Notarized public builds must use Developer ID Application only.
  if [[ "$NOTARIZE" -eq 1 ]]; then
    if echo "$identities" | grep -q "Developer ID Application: .* (${TEAM_ID})"; then
      echo "$identities" | sed -n "s/.*\"\(Developer ID Application: .* (${TEAM_ID})\)\".*/\1/p" | head -1
      return
    fi
    echo ""
    return
  fi

  for kind in \
    "Developer ID Application" \
    "Apple Development" \
    "Apple Distribution"
  do
    if echo "$identities" | grep -q "${kind}: .* (${TEAM_ID})"; then
      echo "$identities" | sed -n "s/.*\"\\(${kind}: .* (${TEAM_ID})\\)\".*/\\1/p" | head -1
      return
    fi
  done

  echo ""
}

IDENTITY="$(pick_identity)"
if [[ -z "$IDENTITY" ]]; then
  if [[ "$NOTARIZE" -eq 1 ]]; then
    echo "error: notarization requires a Developer ID Application certificate for team ${TEAM_ID}." >&2
    echo "Available identities:" >&2
    security find-identity -v -p codesigning >&2 || true
    echo >&2
    echo "Create one at https://developer.apple.com/account/resources/certificates/list" >&2
    echo "Or pass --skip-notarize for a local signed-only build." >&2
  else
    echo "error: no codesigning identity found for team ${TEAM_ID}" >&2
    echo "Available identities:" >&2
    security find-identity -v -p codesigning >&2 || true
    echo >&2
    echo "Create an Apple Development or Developer ID Application certificate for team ${TEAM_ID}:" >&2
    echo "https://developer.apple.com/account/resources/certificates/list" >&2
  fi
  exit 1
fi

if [[ "$NOTARIZE" -eq 1 ]]; then
  if [[ -z "${APPLE_ID:-}" || -z "${APPLE_APP_PASSWORD:-}" ]]; then
    echo "error: set APPLE_ID and APPLE_APP_PASSWORD to notarize (default)." >&2
    echo "  Or pass --skip-notarize for a local signed-only build." >&2
    exit 1
  fi
fi

echo "→ Team:     ${TEAM_ID}"
echo "→ Identity: ${IDENTITY}"
echo "→ Version:  ${VERSION} (${BUILD})"
echo "→ Notarize: $([[ "$NOTARIZE" -eq 1 ]] && echo yes || echo no)"

echo "→ Generating Xcode project…"
xcodegen generate

echo "→ Cleaning build folder…"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Automatic + DEVELOPMENT_TEAM lets Xcode/SPM packages use a cert that
# actually belongs to this team. Forcing a mismatched CODE_SIGN_IDENTITY
# (e.g. another person's Apple Development) breaks package resource bundles.
SIGN_ARGS=(
  DEVELOPMENT_TEAM="$TEAM_ID"
  CODE_SIGN_STYLE=Automatic
  OTHER_CODE_SIGN_FLAGS="--timestamp"
)

if [[ "$IDENTITY" == Developer\ ID\ Application:* ]]; then
  # Prefer explicit Developer ID for public DMG distribution / notarization.
  SIGN_ARGS+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$IDENTITY"
    ENABLE_HARDENED_RUNTIME=YES
  )
fi

echo "→ Archiving Release…"
set +e
if command -v xcpretty >/dev/null 2>&1; then
  xcodebuild archive \
    -project Capso.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    "${SIGN_ARGS[@]}" \
    | xcpretty
  status=${PIPESTATUS[0]}
else
  xcodebuild archive \
    -project Capso.xcodeproj \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    "${SIGN_ARGS[@]}"
  status=$?
fi
set -e
if [[ "$status" -ne 0 ]]; then
  echo "error: xcodebuild archive failed (exit $status)" >&2
  exit "$status"
fi

APP_SRC="$ARCHIVE_PATH/Products/Applications/Capso.app"
if [[ ! -d "$APP_SRC" ]]; then
  echo "error: Capso.app missing from archive at $APP_SRC" >&2
  exit 1
fi

echo "→ Staging DMG contents…"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_SRC" "$STAGE_DIR/Capso.app"
ln -s /Applications "$STAGE_DIR/Applications"

echo "→ Creating ${DMG_NAME}…"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Capso ${VERSION}" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$NOTARIZE" -eq 1 ]]; then
  echo "→ Submitting to notary service…"
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --wait

  echo "→ Stapling ticket…"
  xcrun stapler staple "$DMG_PATH"

  echo "→ Verifying Gatekeeper…"
  # Assess the app inside the stapled DMG (quarantine-style check).
  VERIFY_MOUNT="$(mktemp -d)"
  hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$VERIFY_MOUNT" >/dev/null
  if ! spctl -a -vv -t exec "$VERIFY_MOUNT/Capso.app"; then
    hdiutil detach "$VERIFY_MOUNT" >/dev/null || true
    rmdir "$VERIFY_MOUNT" 2>/dev/null || true
    echo "error: Gatekeeper still rejects Capso.app after notarization." >&2
    exit 1
  fi
  hdiutil detach "$VERIFY_MOUNT" >/dev/null
  rmdir "$VERIFY_MOUNT" 2>/dev/null || true
fi

echo
echo "✓ Done: $DMG_PATH"
echo "  Publish with: ./Scripts/release.sh --skip-build"
echo "  Or build+release: ./Scripts/release.sh"
if [[ "$NOTARIZE" -eq 0 && "$IDENTITY" != Developer\ ID\ Application:* ]]; then
  echo
  echo "⚠ Signed with '${IDENTITY}' (notarization skipped)."
  echo "  For public Gatekeeper distribution, use default notarized build with a Developer ID Application cert."
fi
