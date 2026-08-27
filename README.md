# Arcade spill

Arkademaskin på Raspberry Pi 3B+ uten desktop: en Godot-launchpad er eneste GUI
og laster spillene som `.pck`-filer. Se [PLAN.md](PLAN.md) for hele planen.

**Godot-versjon: 3.6 LTS (GLES2)** — Pi 3B+ støtter ikke Godot 4.
Editoren ligger i `tools/Godot3.app`.

## Struktur

```
launcher/        Launchpad-prosjektet (åpnes i Godot 3.6)
games/dummy/     Testspill — mal for nye spill
shared-kopi:     launcher/shared/arcade_api.gd == games/*/shared/arcade_api.gd
dist/games/      Bygde .pck-filer + manifester (lages av build.sh)
tools/           Godot 3.6 for macOS
```

## Vanlige kommandoer

Bygg alle spill til `dist/games/`:

```bash
./build.sh
```

Kjør launcheren (leser spill fra `dist/games/`):

```bash
tools/Godot3.app/Contents/MacOS/Godot --path launcher
```

Automatisk ende-til-ende-test (starter første spill, går tilbake, avslutter):

```bash
ARCADE_SMOKE_TEST=1 tools/Godot3.app/Contents/MacOS/Godot --path launcher
```

Åpne et prosjekt i editoren:

```bash
tools/Godot3.app/Contents/MacOS/Godot --editor --path launcher
```

## Lage et nytt spill

1. Kopier `games/dummy/` til `games/<id>/`.
2. Gi filene nytt navnerom: alt innhold skal ligge i `res://games/<id>/`
   (unikt navnerom er kritisk — .pck-filene blandes inn i launcherens `res://`).
3. Oppdater `project.godot` (navn + hovedscene) og `manifest.json`.
4. Spillet skal aldri kalle `get_tree().quit()` — bruk `Arcade.quit_to_launcher()`.
5. Input: bruk actionene `p1_up/down/left/right`, `p1_a`, `p1_b`,
   `arcade_start`, `arcade_back` (defineres av `shared/arcade_api.gd`).
6. Kjør `./build.sh`.

## Regler

- Alle `.pck`-er må bygges med samme Godot-versjon som launcheren (3.6).
- `shared/arcade_api.gd` skal være identisk i alle prosjekter — endrer du den,
  kopier til launcher og alle spill.
- Launcheren finner spill i `dist/games/` under utvikling, og i `games/` ved
  siden av binæren på Pi-en.
