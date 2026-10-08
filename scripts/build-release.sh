#!/bin/sh
# Builds a universal (Apple silicon and Intel) Skill Cabinet.app, with the skillscout command
# inside. Signs with Flavio's Developer ID when the certificate is in the keychain, ad hoc
# everywhere else (CI, forks). Developer ID builds are notarized, stapled, and zipped into
# dist/Skill Cabinet-<version>.zip. The name and version come from project.yml.
# Usage: scripts/build-release.sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$ROOT"
NAME="Skill Cabinet"
TARGET="Skillscout"
VERSION=$(sed -n 's/^ *MARKETING_VERSION: "\(.*\)"$/\1/p' project.yml)
BUILD="$ROOT/build/release"
APP="$BUILD/Release/$NAME.app"
ZIP="$ROOT/dist/$NAME-$VERSION.zip"
CHECK=$(mktemp -d)

cleanup() {
  rm -rf "$CHECK"
}
trap cleanup EXIT

sign_one() {
  target=$1
  ent=$(mktemp)
  has_ent=0
  if codesign -d --entitlements - --xml "$target" 2>/dev/null >"$ent"; then
    if [ -s "$ent" ] && plutil -lint "$ent" >/dev/null 2>&1; then
      has_ent=1
    fi
  fi
  if [ "$has_ent" -eq 1 ]; then
    if grep -Fq com.apple.security.get-task-allow "$ent"; then
      /usr/libexec/PlistBuddy -c "Delete :com.apple.security.get-task-allow" "$ent" 2>/dev/null || true
    fi
    if grep -Fq com.apple.security.get-task-allow "$ent"; then
      echo "Release must not include com.apple.security.get-task-allow ($target)." >&2
      rm -f "$ent"
      exit 1
    fi
    if grep -q '<key>' "$ent"; then
      codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ent" "$target"
    else
      codesign --force --options runtime --timestamp --sign "$IDENTITY" "$target"
    fi
  else
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$target"
  fi
  rm -f "$ent"
}

resign_app() {
  list=$(mktemp)
  find "$APP" -depth -type f -print >"$list"
  while IFS= read -r f; do
    case $(file -b "$f") in
      Mach-O*) sign_one "$f" ;;
    esac
  done <"$list"
  rm -f "$list"
  sign_one "$APP"
}

rm -rf "$BUILD" "$ZIP"
mkdir -p dist
xcodebuild -project "$TARGET.xcodeproj" -target "$TARGET" -configuration Release \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO SYMROOT="$BUILD" -quiet build

lipo "$APP/Contents/MacOS/$NAME" -verify_arch arm64 x86_64
lipo "$APP/Contents/Helpers/skillscout" -verify_arch arm64 x86_64

IDENTITY=$(security find-identity -v -p codesigning | awk '/"Developer ID Application: Flavio Copes \(DGFKNTAG99\)"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
  resign_app
  SIGNATURE="Developer ID"
else
  SIGNATURE="ad-hoc"
fi

codesign --verify --deep --strict "$APP"

if [ "$SIGNATURE" = "Developer ID" ]; then
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile notary --wait --output-format json)
  status=$(printf '%s' "$result" | plutil -extract status raw -o - -)
  if [ "$status" != "Accepted" ]; then
    echo "$result" >&2
    submission_id=$(printf '%s' "$result" | plutil -extract id raw -o - -)
    xcrun notarytool log "$submission_id" --keychain-profile notary >&2
    exit 1
  fi
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
else
  ditto -c -k --keepParent "$APP" "$ZIP"
fi

ditto -x -k "$ZIP" "$CHECK"
codesign --verify --deep --strict "$CHECK/$NAME.app"

if [ "$SIGNATURE" = "Developer ID" ]; then
  spctl --assess --type execute --verbose "$APP"
fi

echo "Built $APP $VERSION for $(lipo -archs "$APP/Contents/MacOS/$NAME"), $SIGNATURE signed"
echo "$ZIP"
shasum -a 256 "$ZIP"
