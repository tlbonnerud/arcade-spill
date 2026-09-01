#!/usr/bin/env bash
# Kjøres PÅ Raspberry Pi-en. Laster ned FRT (Godot 3.6-motor for Pi,
# tegner rett på skjermen via KMS/DRM — ingen desktop nødvendig)
# og legger den i pi/bin/frt-godot3.
set -euo pipefail

FRT_VERSION="3.6.3-1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN_DIR="$ROOT/pi/bin"

# Velg riktig binær ut fra OS-arkitektur og Debian-versjon
ARCH="$(dpkg --print-architecture)"     # armhf eller arm64
CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"

if [ "$CODENAME" = "trixie" ]; then
	TAG="${FRT_VERSION}-trixie"
	case "$ARCH" in
		arm64) FILE="frt_${TAG}_arm64_release.xz" ;;
		armhf) FILE="frt_${TAG}_armhf_release.xz" ;;
		*) echo "Ukjent arkitektur: $ARCH" >&2; exit 1 ;;
	esac
else
	TAG="$FRT_VERSION"
	case "$ARCH" in
		arm64) FILE="frt_${TAG}_arm64_release.xz" ;;
		armhf) FILE="frt_${TAG}_arm32_release.xz" ;;
		*) echo "Ukjent arkitektur: $ARCH" >&2; exit 1 ;;
	esac
fi

URL="https://github.com/efornara/frt/releases/download/${TAG}/${FILE}"

echo "OS: ${CODENAME:-ukjent}  arkitektur: $ARCH"
echo "Laster ned: $URL"
mkdir -p "$BIN_DIR"
curl -fL -o "$BIN_DIR/frt-godot3.xz" "$URL"
xz -df "$BIN_DIR/frt-godot3.xz"
chmod +x "$BIN_DIR/frt-godot3"

echo
echo "OK! Motor installert: $BIN_DIR/frt-godot3"
echo
echo "Test nå (desktopen må være av, se pi/README.md):"
echo "  sudo systemctl isolate multi-user.target   # slå av desktopen midlertidig"
echo "  $ROOT/pi/run.sh"
echo
echo "Autostart ved boot:  $ROOT/pi/enable-autostart.sh"
