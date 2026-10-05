#!/usr/bin/env bash
# Runs a command with a private headless GNOME display, so the app gets frames and focus without
# opening a window on your desktop: Linux/scripts/headless.sh <command> [args…]
set -euo pipefail

display="skillscout-headless-$$"
mutter --headless --wayland --no-x11 --wayland-display "$display" --virtual-monitor 1280x820 >/dev/null 2>&1 &
mutter=$!
trap 'kill "$mutter" 2>/dev/null || true' EXIT

for _ in $(seq 50); do
  [ -S "${XDG_RUNTIME_DIR:?}/$display" ] && break
  sleep 0.1
done

WAYLAND_DISPLAY="$display" "$@"
