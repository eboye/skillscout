#!/usr/bin/env bash
# Runs Linux/scripts/ui-test.py against the Flatpak: builds it, installs it for your user from a
# local repo, clicks through it in the sandbox against the made-up home, then uninstalls it with
# its data and removes the repo. Stops first if a Skill Cabinet Flatpak from elsewhere is installed,
# since the test would replace and then delete it.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
id=com.flaviocopes.skillscout
remote=skillscout-ui-test

if flatpak --user info "$id" >/dev/null 2>&1 && [ "$(flatpak --user info --show-origin "$id")" != "$remote" ]; then
  echo "A Skill Cabinet Flatpak is already installed for your user, so the test leaves it alone." >&2
  exit 1
fi

cleanup() {
  flatpak --user uninstall -y --noninteractive --delete-data "$id" >/dev/null 2>&1 || true
  flatpak --user remote-delete --force "$remote" >/dev/null 2>&1 || true
}
trap cleanup EXIT

flatpak-builder --user --install-deps-from=flathub --force-clean --state-dir=build/flatpak-state \
  --repo=build/flatpak-repo build/flatpak Linux/packaging/flatpak/$id.yml >build/flatpak.log 2>&1
flatpak --user remote-add --if-not-exists --no-gpg-verify "$remote" "$root/build/flatpak-repo"
flatpak --user install -y --noninteractive --reinstall "$remote" "$id" >/dev/null

# A Flatpak keeps its data in ~/.var/app, whatever HOME says, so the made-up idea goes there.
Linux/scripts/demo-home.sh >/dev/null
data="$HOME/.var/app/$id/data/skillscout"
rm -rf "$HOME/.var/app/$id"
mkdir -p "$data"
cp build/demo-home/.local/share/skillscout/state.json "$data/"

demo="$root/build/demo-home"
SKILLSCOUT_STATE="$data/state.json" \
  SKILLSCOUT_APP="flatpak run --user --env=SKILLSCOUT_TEST=1 --env=HOME=$demo --env=SHELL=/bin/bash $id" \
  Linux/scripts/headless.sh uv run --quiet Linux/scripts/ui-test.py
