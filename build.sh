#!/usr/bin/env bash
# Bygger alle spill til .pck og legger dem + manifester i dist/games/.
# Bruk: ./build.sh          (bruker tools/Godot3.app)
#       GODOT3=/sti/til/godot ./build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT3:-$ROOT/tools/Godot3.app/Contents/MacOS/Godot}"

if [ ! -x "$GODOT" ]; then
	echo "Fant ikke Godot 3-binær: $GODOT" >&2
	exit 1
fi

mkdir -p "$ROOT/dist/games"

for game_dir in "$ROOT"/games/*/; do
	id="$(basename "$game_dir")"
	echo "=== Eksporterer $id ==="
	"$GODOT" --no-window --path "$game_dir" --export-pack "pck" "$ROOT/dist/games/$id.pck" >/dev/null
	cp "$game_dir/manifest.json" "$ROOT/dist/games/$id.json"
done

echo "OK — dist/games/:"
ls -la "$ROOT/dist/games"
