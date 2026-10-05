#!/usr/bin/env bash
# Takes screenshots of the GNOME app in build/shots, light and dark, from the made-up home in
# build/demo-home and a private headless display. Each one starts the app with SKILLSCOUT_SCREENSHOT,
# which saves the window once the skills and chats load, and quits (see Linux/App/Screenshot.swift).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
swift build --product skillscout-gnome
app="$(swift build --show-bin-path)/skillscout-gnome"
shots="$root/build/shots"
mkdir -p "$shots"

shoot() {
  local name="$1" sidebar="$2" select="$3" open="${4:-}"
  for dark in 0 1; do
    local style=light file
    [ "$dark" = 1 ] && style=dark
    file="$shots/$name-$style.png"
    Linux/scripts/demo-home.sh >/dev/null
    env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u DISPLAY HOME="$root/build/demo-home" \
      SKILLSCOUT_SCREENSHOT="$file" SKILLSCOUT_SIDEBAR="$sidebar" SKILLSCOUT_SELECT="$select" \
      SKILLSCOUT_OPEN="$open" SKILLSCOUT_DARK="$dark" timeout 30 "$app" >/dev/null 2>&1
    echo "$file"
  done
}

export -f shoot
export root app shots
Linux/scripts/headless.sh bash -c '
  shoot skill all code-review
  shoot similar similar email-style
  shoot suggestions suggestions link-check
  shoot uninstall all release-notes uninstall
  shoot preferences all - preferences
'
