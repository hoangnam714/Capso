# Capso release commands

## 1) Build DMG (signed + notarized, default)

```bash
cd /Users/aland/Documents/freelancer/Capso

export TEAM_ID=H26VXS6A6Y
export APPLE_ID="huynhvohoangnam714@gmail.com"
export APPLE_APP_PASSWORD="xyuv-bine-qwbs-zauf"

./Scripts/build-dmg.sh
```

## 2) Build + publish GitHub Release

```bash
cd /Users/aland/Documents/freelancer/Capso

export TEAM_ID=H26VXS6A6Y
export APPLE_ID="your-apple-id@email.com"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"

./Scripts/release.sh
```

## 3) Reuse existing DMG (skip rebuild)

```bash
cd /Users/aland/Documents/freelancer/Capso
./Scripts/release.sh --skip-build
```

## 4) Local signed-only build (no notarize / Gatekeeper will reject downloads)

```bash
cd /Users/aland/Documents/freelancer/Capso
./Scripts/build-dmg.sh --skip-notarize
```

## Notes

- `APPLE_APP_PASSWORD` = [App-Specific Password](https://appleid.apple.com/account/manage) (not your Apple ID login password).
- Need a **Developer ID Application** cert for team `H26VXS6A6Y` in Keychain.
- After build, verify:

```bash
spctl -a -vv -t exec /Volumes/Capso*/Capso.app
# expect: accepted
```

export TEAM_ID=H26VXS6A6Y
export APPLE_ID="huynhvohoangnam714@gmail.com"
export APPLE_APP_PASSWORD="xyuv-bine-qwbs-zauf"
./Scripts/release.sh
