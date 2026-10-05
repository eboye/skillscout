#!/usr/bin/env bash
# Clicks through the GNOME app over the accessibility bus, against a made-up home, and checks what
# each action changes on disk. The AI features go through a fake Codex CLI, so nothing leaves the
# machine. Needs mutter and uv; PyGObject gets built into uv's cache the first time.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
swift build --product skillscout-gnome
swift build --product skillscout
Linux/scripts/demo-home.sh >/dev/null
Linux/scripts/headless.sh uv run --quiet Linux/scripts/ui-test.py
