# Raspberry Pi-oppsett

Pi-en bygger ingenting selv — den kjører de ferdige `.pck`-filene fra `dist/`
med FRT, en Godot 3.6-motor for Pi som tegner rett på skjermen (KMS/DRM).
Derfor trengs ingen desktop.

## Første gang

```bash
cd ~/Documents/arcade-spill
git pull
./pi/install.sh
```

## Test (via SSH eller på Pi-en)

FRT trenger skjermen for seg selv, så desktopen må av først:

```bash
sudo systemctl isolate multi-user.target   # desktop av til neste boot
./pi/run.sh                                # launcheren vises på HDMI
```

Automatisk test uten å røre skjermen fysisk (spillene åpnes og lukkes selv):

```bash
ARCADE_SMOKE_TEST=1 ./pi/run.sh
```

Tilbake til desktop: `sudo systemctl isolate graphical.target`

## Autostart ved boot (arkademodus)

```bash
./pi/enable-autostart.sh                          # systemd-tjeneste
sudo raspi-config nonint do_boot_behaviour B2     # boot til konsoll, ikke desktop
sudo reboot
```

Etter dette booter Pi-en rett inn i launcheren, og systemd starter den på nytt
om den krasjer. Styring:

```bash
sudo systemctl stop arcade     # stopp (f.eks. for å jobbe over SSH)
sudo systemctl start arcade
journalctl -u arcade -f        # logg
```

## Oppdatere spill senere

På Mac: `./build.sh`, commit og push. På Pi-en:

```bash
cd ~/Documents/arcade-spill && git pull && sudo systemctl restart arcade
```

## Feilsøking

- **Svart skjerm / DRM-feil:** desktopen kjører fortsatt — kjør
  `sudo systemctl isolate multi-user.target` først.
- **Ingen tilgang til /dev/dri eller /dev/input:** brukeren må være i gruppene
  `video`, `render` og `input`: `sudo usermod -aG video,render,input $USER`
  og logg inn på nytt.
- **Joystick reagerer ikke:** sjekk at USB-encoderen synes med `ls /dev/input/js*`.
