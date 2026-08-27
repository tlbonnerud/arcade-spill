# Arcade-spill — Plan

Mål: En Raspberry Pi uten desktop som booter rett inn i en Godot-launchpad.
Launchpadden viser spillene, og spillene lastes som separate `.pck`-filer.
Styring med arkadeknapper/joystick (USB-encoder).

## ⚠️ Beslutning som må tas først: Pi 3B+ og Godot-versjon

Pi 3B+ har en VideoCore IV-GPU som bare støtter OpenGL ES 2.0.
**Godot 4 (som prosjektet bruker nå, 4.5 med Forward+) kan ikke kjøre på Pi 3B+** —
selv Compatibility-rendereren krever GLES 3.0.

To alternativer:

| | Alternativ A: Behold Pi 3B+ | Alternativ B: Oppgrader til Pi 4/5 |
|---|---|---|
| Godot-versjon | **Godot 3.6 LTS** (GLES2) | Godot 4.5 (Compatibility-renderer) |
| Kjøring uten desktop | FRT-binær (kjører rett på KMS/DRM, ingen X11 — perfekt for kiosk) | `cage` (Wayland-kiosk) + offisiell ARM64-binær |
| Konsekvens | Vi lager prosjektene på nytt i Godot 3.6 på Mac-en (lite tapt — prosjektet er nesten tomt) | Koster en ny Pi, men moderne Godot og enklere vei |
| Ytelse | OK for 2D-spill som Snake/Invaders i 1080p/720p | God |

**Anbefaling:** Bestem dette før fase 1, og test på ekte Pi så tidlig som mulig.
Planen under er skrevet slik at den fungerer for begge, med A som utgangspunkt.

## Arkitektur

```
Arcade spill/
├── launcher/            # Launchpad-prosjektet (Godot)
├── games/
│   ├── snake/           # Eget Godot-prosjekt → eksporteres til snake.pck
│   └── invaders/        # Eget Godot-prosjekt → invaders.pck
├── shared/              # Felles kode/tema som kopieres inn i hvert prosjekt
│   └── arcade_api.gd    # "Kontrakten" alle spill følger
├── dist/                # Ferdig bygget: launcher-binær + games/*.pck + manifester
└── pi/                  # systemd-service, installasjonsskript, config for Pi-en
```

### Slik virker .pck-opplegget

1. Hvert spill er sitt eget Godot-prosjekt, men **alt innhold ligger i en unik
   undermappe** (`res://games/snake/...`). Dette er kritisk: når en .pck lastes
   med `ProjectSettings.load_resource_pack()` blandes filene inn i launcherens
   `res://`, så uten navnerom kolliderer filer.
2. Hvert spill eksporteres som `snake.pck` + en `snake.json`-manifest:
   `{ "name": "Snake", "main_scene": "res://games/snake/main.tscn", "cover": "..." }`
3. Launchpadden skanner `games/`-mappa ved oppstart, viser ett kort per manifest,
   laster valgt .pck og bytter til spillets hovedscene.
4. Spillet avslutter ved å kalle `Arcade.quit_to_launcher()` (autoload-singleton
   i launcheren) — aldri `get_tree().quit()`.
5. **Alle .pck-er må bygges med samme Godot-versjon som launcher-binæren.**

### Arcade-API (kontrakten spillene følger)

- `Arcade.quit_to_launcher()` — tilbake til menyen
- `Arcade.save_highscore(game_id, score)` / `Arcade.get_highscores(game_id)` — JSON på disk (`user://`)
- Felles InputMap-actions: `p1_up/down/left/right`, `p1_a`, `p1_b`, `ui_back`
  (USB-encoder vises som gamepad; tastatur mappes til samme actions for testing på Mac)
- Exit-kombinasjon (f.eks. hold to knapper i 2 sek) håndteres globalt av launcheren

## Fase 1 — Teknisk pilot (bevis at alt virker ende-til-ende)

Mål: tommel opp/ned på hele konseptet før vi bruker tid på design.

1. **På Mac:** Minimal launcher (en liste med spillnavn) + ett dummy-spill
   («trykk A for å avslutte»-scene) som eget prosjekt → eksporter til .pck →
   launcher laster den, bytter scene, og kommer tilbake. Test hele løkka.
2. **Eksporter til Pi:** Bygg Linux ARM-eksport av launcheren, kopier til Pi-en
   (Raspberry Pi OS **Lite**, ingen desktop).
3. **Kiosk-oppstart:** systemd-service som starter launcheren ved boot, med
   `Restart=always` (krasjer et spill, kommer menyen tilbake av seg selv).
4. **Input:** Verifiser at USB-encoderen dukker opp som gamepad i Godot og at
   knappene kan mappes. (Har du ikke encoderen ennå: test med tastatur.)
5. **Ytelsestest:** en scene med en del bevegelige sprites — sjekk at vi holder
   60 fps i valgt oppløsning. Vurder 720p hvis 1080p sliter (særlig på 3B+).

**Exit-kriterium:** Pi booter → launcher → start dummy-spill → avslutt → tilbake
i launcher, uten tastatur/SSH involvert.

## Fase 2 — Design og smooth funksjonalitet

- **Launcher-UI:** horisontal karusell med spillkort (cover-bilde, tittel,
  highscore), wraparound, lyd-feedback på navigasjon, tween-animasjoner på
  valg/start (fade/zoom inn i spillet).
- **Attract mode:** etter X min inaktivitet ruller menyen selv / viser demo.
- **Overganger:** fade til svart ved lasting av .pck så det aldri «hakker» synlig.
- **Highscore-visning** på hvert spillkort + «ny rekord»-skjerm med
  initialer-inntasting (tre bokstaver, joystick opp/ned — klassisk arkade).
- **Robusthet:** launcheren overlever korrupt/manglende .pck (viser feilkort i
  stedet for å krasje).

## Fase 3 — Spillene

1. **Snake** først — enklest (grid-logikk, ingen fysikk), perfekt for å teste
   Arcade-API-et og .pck-flyten i praksis.
2. **Space Invaders** — fiendebølger, skudd, skjold, lyd. Gjenbruker mønstrene
   fra Snake (highscore, quit, input).
3. Felles visuelt tema (font, fargepalett, lydeffekt-stil) fra `shared/`.

## Fase 4 — Kiosk-herding (når alt virker)

- Kortere boot-tid (slå av unødvendige tjenester), skjul boot-tekst/splash.
- Slå av skjermsparing/blanking.
- Trygg strømkutt-håndtering: vurder read-only filsystem med skrivbar partisjon
  for highscores.
- Ett `install.sh`-skript i `pi/` som setter opp en fersk Pi fra bunnen.

## Rekkefølge / neste steg

1. ✅ Plan
2. ✅ Valgt alternativ A: Godot 3.6 LTS på Pi 3B+ (2026-08-25)
3. ✅ Fase 1: pilot på Mac — røyktest grønn (launcher → dummy.pck → tilbake)
4. ⬜ Fase 1: pilot på Pi
5. ⬜ Fase 2: design
6. ⬜ Fase 3: Snake → Invaders
7. ⬜ Fase 4: herding
