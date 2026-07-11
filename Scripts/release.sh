#!/usr/bin/env bash
# Build Capso DMG and publish a GitHub Release (with DMG + appcast.xml).
#
# Usage:
#   ./Scripts/release.sh                 # build DMG + create/update Release
#   ./Scripts/release.sh --skip-build    # reuse existing build/Capso-*.dmg
#   ./Scripts/release.sh --notarize      # build with notarization, then release
#   ./Scripts/release.sh --notes "..."   # custom release notes
#
# Env:
#   TEAM_ID / APPLE_ID / APPLE_APP_PASSWORD  (same as build-dmg.sh)
#   GH_TOKEN or `gh auth login` required for uploading
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

REPO="${REPO:-hoangnam714/Capso}"
SKIP_BUILD=0
NOTARIZE=0
NOTES=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --notarize) NOTARIZE=1; shift ;;
    --notes)
      NOTES="${2:-}"
      shift 2
      ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

GH_BIN="$(command -v gh || true)"
if [[ -z "$GH_BIN" && -x /opt/homebrew/bin/gh ]]; then
  GH_BIN=/opt/homebrew/bin/gh
fi
if [[ -z "$GH_BIN" ]]; then
  echo "error: GitHub CLI (gh) is required. Install with: brew install gh" >&2
  exit 1
fi

# Prefer an existing login; otherwise try SourceTree OAuth token from Keychain.
if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  if [[ -z "${GH_TOKEN:-}" ]]; then
    token="$(security find-generic-password -s "SourceTree (OAuth) for GitHub" -w 2>/dev/null || true)"
    if [[ "$token" == access_token=* ]]; then
      token="${token#access_token=}"
      token="${token%%&*}"
      export GH_TOKEN="$token"
    fi
  fi
fi
if ! "$GH_BIN" auth status >/dev/null 2>&1; then
  echo "error: not logged into GitHub. Run: gh auth login" >&2
  exit 1
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
TAG="v${VERSION}"
DMG_NAME="Capso-${VERSION}.dmg"
DMG_PATH="$ROOT/build/$DMG_NAME"
APPCAST_PATH="$ROOT/appcast.xml"

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "→ Building DMG…"
  if [[ "$NOTARIZE" -eq 1 ]]; then
    ./Scripts/build-dmg.sh --notarize
  else
    ./Scripts/build-dmg.sh
  fi
else
  echo "→ Skipping build (using existing DMG)"
fi

if [[ ! -f "$DMG_PATH" ]]; then
  echo "error: DMG not found at $DMG_PATH" >&2
  echo "Run without --skip-build, or build first with ./Scripts/build-dmg.sh" >&2
  exit 1
fi

DMG_BYTES="$(stat -f%z "$DMG_PATH")"
DMG_URL="https://github.com/${REPO}/releases/download/${TAG}/${DMG_NAME}"
PUB_DATE="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"

echo "→ Updating appcast.xml for ${TAG}…"
python3 - "$APPCAST_PATH" "$VERSION" "$BUILD" "$DMG_URL" "$DMG_BYTES" "$PUB_DATE" <<'PY'
import pathlib, sys
path, version, build, url, length, pub_date = sys.argv[1:]
pathlib.Path(path).write_text(f"""<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>Capso</title>
        <link>https://github.com/hoangnam714/Capso/releases</link>
        <description>Capso updates from GitHub Releases</description>
        <language>en</language>
        <item>
            <title>{version}</title>
            <pubDate>{pub_date}</pubDate>
            <sparkle:version>{build}</sparkle:version>
            <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h2>Capso {version}</h2>
                <p>Build {build}</p>
            ]]></description>
            <enclosure
                url="{url}"
                length="{length}"
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
""")
PY

if [[ -z "$NOTES" ]]; then
  NOTES="$(cat <<EOF
## Capso ${VERSION}

- Build: \`${BUILD}\`
- Download: \`${DMG_NAME}\`

Sparkle feed: https://github.com/${REPO}/releases/latest/download/appcast.xml
EOF
)"
fi

echo "→ Publishing GitHub Release ${TAG}…"
if "$GH_BIN" release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  # Replace assets on an existing release.
  "$GH_BIN" release upload "$TAG" "$DMG_PATH" "$APPCAST_PATH" \
    --repo "$REPO" \
    --clobber
  "$GH_BIN" release edit "$TAG" \
    --repo "$REPO" \
    --title "Capso ${VERSION}" \
    --notes "$NOTES"
else
  "$GH_BIN" release create "$TAG" \
    --repo "$REPO" \
    --title "Capso ${VERSION}" \
    --notes "$NOTES" \
    "$DMG_PATH" \
    "$APPCAST_PATH"
fi

echo
echo "✓ Release published: https://github.com/${REPO}/releases/tag/${TAG}"
echo "  DMG:     ${DMG_URL}"
echo "  Appcast: https://github.com/${REPO}/releases/latest/download/appcast.xml"
echo
echo "Note: for Sparkle to verify updates, sign the DMG with generate_appcast"
echo "and replace appcast.xml (empty edSignature is fine for download-only Releases)."
