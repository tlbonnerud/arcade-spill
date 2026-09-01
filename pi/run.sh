#!/usr/bin/env bash
# Starter arkade-launcheren på Raspberry Pi (rett på skjermen, uten desktop).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export ARCADE_GAMES_DIR="$ROOT/dist/games"

exec "$ROOT/pi/bin/frt-godot3" --main-pack "$ROOT/dist/launcher.pck"
