#!/usr/bin/env bash
# Setter opp systemd slik at launcheren starter automatisk ved boot
# og alltid startes på nytt om den skulle krasje. Kjøres PÅ Pi-en.
# Bruker sudo — du blir bedt om passord.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN_USER="$(whoami)"

sudo tee /etc/systemd/system/arcade.service >/dev/null <<EOF
[Unit]
Description=Arcade launcher (Godot/FRT)
After=systemd-user-sessions.service

[Service]
User=$RUN_USER
SupplementaryGroups=video render input audio
WorkingDirectory=$ROOT
ExecStart=$ROOT/pi/run.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable arcade.service

echo
echo "arcade.service er aktivert."
echo "VIKTIG: Desktopen må slås av permanent, ellers krangler de om skjermen:"
echo "  sudo raspi-config nonint do_boot_behaviour B2   # boot til konsoll (autologin)"
echo "  sudo reboot"
echo
echo "Nyttig etterpå:"
echo "  sudo systemctl start|stop|status arcade   # styr launcheren"
echo "  journalctl -u arcade -f                   # se loggen"
