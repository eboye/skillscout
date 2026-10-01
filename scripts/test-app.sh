#!/bin/sh
# Builds a test copy of Skillscout with its own bundle ID, resets the made-up home in
# build/test-home, and starts the copy on it, so you can drive it with skillscoutctl
# without touching your real skills, chats or settings.
#
#   scripts/test-app.sh
#   export HOME=build/test-home  # or prefix each command with HOME=...
#   build/test-app/Debug/Skillscout.app/Contents/Helpers/skillscoutctl state
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUT="$ROOT/build/test-app"
BUNDLE_ID=com.flaviocopes.skillscout.test
CTL="$OUT/Debug/Skillscout.app/Contents/Helpers/skillscoutctl"
TEST_HOME="$ROOT/build/test-home"

xcodebuild -project "$ROOT/Skillscout.xcodeproj" -target Skillscout -configuration Debug -quiet \
  ARCHS="$(uname -m)" SYMROOT="$OUT" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" INFOPLIST_KEY_CFBundleDisplayName="Skillscout Test" build

if [ -d "$TEST_HOME" ]; then
  HOME="$TEST_HOME" "$CTL" quit >/dev/null
  while HOME="$TEST_HOME" "$CTL" ping >/dev/null 2>&1; do sleep 0.2; done
fi
defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
"$ROOT/scripts/test-home.sh" >/dev/null

HOME="$TEST_HOME" "$CTL" launch >/dev/null
echo "Skillscout Test runs on $TEST_HOME. Drive it with:"
echo "HOME=$TEST_HOME $CTL state"
