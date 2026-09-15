# Ailien Invaders — Arkitektur

Hvordan koden er organisert, og hvorfor. Spilldesignet står i
[DESIGN.md](DESIGN.md), rekkefølgen i [ROADMAP.md](ROADMAP.md).

## Mappestruktur

Alt ligger under `res://games/ailien_invaders/` (unikt navnerom, kreves av
.pck-opplegget, se rot-README).

```
games/ailien_invaders/
├── main.tscn / main.gd     Orkestrering: bygger scenen, kobler signaler,
│                           eier tilstandsmaskinen. Ingen spillregler her.
├── core/                   Ting som ikke er spiller eller fiende
│   ├── bullets.gd          ✅ Kulelag: flytter, tegner, sjekker treff
│   ├── run_state.gd        ⬜ Poeng, bølge, valgte oppgraderinger, seed
│   └── wave_manager.gd     ✅ Leser bølgedata, spawner, kjører innflyging,
│                              bevegelse, dykk og skyting, sier fra via signaler
├── player/
│   ├── player.gd           ✅ Bevegelse, skyting, treff, usårbarhet
│   └── player_stats.gd     ⬜ Basisstats + oppgraderingsmodifikatorer
├── enemies/
│   ├── enemy_types.gd      ✅ Tabell: grunt/soldat/skytter/elite (hp, poeng, kule, sikting)
│   ├── formations.gd       ✅ rows, v_shape, ring, checkerboard → liste med plasser
│   ├── entry_patterns.gd   ✅ Innflyging: from_top, from_sides, spiral, swoop
│   ├── movement_patterns.gd✅ classic, sine (dykk ligger i wave_manager)
│   └── boss/
│       ├── boss.gd         ⬜ Bossen med faser
│       └── boss.tscn       ⬜ (scene, fordi bossen bør kunne pusses på i editoren)
├── waves/
│   └── waves.gd            ✅ Bølgene som data (3 av 10 så langt, se format under)
├── upgrades/
│   ├── upgrades.gd         ⬜ Katalog: id, navn, sjeldenhet, apply()
│   └── upgrade_screen.gd   ⬜ "Velg 1 av 3"-skjermen
├── ui/
│   ├── hud.gd              ⬜ Poeng, liv, bølge, aktive oppgraderinger
│   └── transitions.gd      ⬜ Bølgebanner, ADVARSEL, fade, victory
├── sprites/                Grafikk
├── docs/                   Disse dokumentene (eksporteres ikke til .pck)
└── tests/                  Automatiske tester (ekskludert fra .pck)
    ├── play_waves.tscn/.gd Spiller gjennom alle bølgene uten skjerm
    └── screenshots.tscn/.gd Tar bilder av hver formasjon og innflyging
```

(`tests/` ligger i prosjektrota, ikke under `games/ailien_invaders/`, så den
aldri blir med i .pck-en.)

## Hvorfor ikke én mappe per level

Ti level-mapper høres ryddig ut, men levelene deler nesten all logikk.
Med en mappe per level får du ti kopier av samme kode, og hver regelendring
må gjøres ti steder. Det som faktisk skiller bølgene er **data**: hvilke
fiender, hvor mange, hvilken formasjon, hvilket mønster, hvor raskt.
Derfor er en bølge én rad i `waves/waves.gd`, og `wave_manager.gd` er den
ene motoren som kjører alle ti.

Unntaket er **bossen**. Den har unik logikk (faser) og egne assets, så den
får sin egen mappe under `enemies/boss/`.

Trenger en vanlig bølge noe helt spesielt senere (for eksempel en asteroide-
regn i bølge 6), legges det som et valgfritt `modifier`-skript i bølgedataene,
ikke som en egen mappe.

## Scener eller kode?

I dag bygges alt i kode (`Sprite.new()`), uten `.tscn`-filer for delene.
Det er bevisst: enkelt å lese i git, ingen editor nødvendig, og det passer
bra for prosedyrelt innhold som formasjoner.

Bruk `.tscn` der noe skal **pusses på visuelt** i editoren: bossen,
oppgraderingsskjermen, victory-skjermen. Logikk holdes uansett i `.gd`.

## Ansvar og signaler (slik det er nå)

```
main.gd
 ├── player (player.gd)
 │     fire_requested(pos) ──► bullets.spawn_player_bullet
 │     lives_changed(n)    ──► main → HUD
 │     died                ──► main._set_game_over
 ├── swarm (core/wave_manager.gd)
 │     fire_requested(pos, kind, dir) ──► bullets.spawn_enemy_bullet
 │     enemy_killed(pts)   ──► main → poeng
 │     entry_finished      ──► main → WAVE_INTRO → WAVE
 │     cleared             ──► main → WAVE_CLEAR → neste bølge / VICTORY
 │     reached_bottom      ──► main._set_game_over
 └── bullets (bullets.gd)
       kaller swarm.try_hit(pos) og player.hit_test(pos)/take_hit()
```

Regelen: **delene kjenner ikke hverandre**, bare main gjør det. Player vet
ikke hva en fiende er. Wave manager vet ikke hva en kule er, den får bare
spillerens posisjon (for sikting og dykk) via `step()`. Bullets får
referanser via `setup()` og bruker bare `try_hit`/`hit_test`/`take_hit`.
Kontakt mellom dykkende fiender og spilleren sjekker main selv med
`swarm.diver_positions()` og `player.hit_test()`.

Hver frame kaller main `step(delta)` på delene i fast rekkefølge:
spiller, sverm, kuler. (Ikke `update()`: det navnet er opptatt av
`CanvasItem` og betyr "tegn på nytt".)

## Tilstandsmaskin i main.gd

```gdscript
enum State { WAVE_INTRO, WAVE, WAVE_CLEAR, VICTORY, GAME_OVER }
```

| Tilstand | Stepper | Går videre når |
|---|---|---|
| WAVE_INTRO | spiller, sverm (innflyging, ingen skyting), kuler | `entry_finished` → WAVE, eller `cleared` → WAVE_CLEAR |
| WAVE | alt, pluss dykker-kontakt | `cleared` → WAVE_CLEAR |
| WAVE_CLEAR | spiller, kuler; bakgrunnen scroller fortere | 1,2 s → neste bølge, eller VICTORY etter siste |
| VICTORY / GAME_OVER | ingenting (svermen animeres) | START → nytt run |

Kommer: INTRO, UPGRADE, BOSS_INTRO, BOSS (se DESIGN.md).

## Slik kjører wave_manager en bølge

1. `spawn(n, rng)` henter rad n fra `waves.gd`, trekker **én** formasjon,
   **én** innflyging og **én** bevegelse fra poolene med run-RNG-en, bygger
   plassene (`formations.gd`) og banene inn (`entry_patterns.gd`), og lager
   én `Sprite` per fiende utenfor skjermen. Valgene lagres i
   `wave_data["chosen"]`.
2. Innflyging: hver fiende følger en kvadratisk bezier fra startpunkt via
   kontrollpunkt til plassen sin, med forsinkelse per fiende. Regnes ut per
   frame i `_step_entry()`, ingen tweens (billigere på Pi-en, og testbart
   uten skjerm). Fiender kan treffes underveis, men skyter ikke.
3. Bevegelse: `movement_patterns.gd` eier en tilstand og returnerer
   formasjonens *offset* hver frame; fiendens posisjon er `slot + offset`.
   Alt går fortere jo flere som er døde (`dead_frac`).
4. Dykk: hvis bølgen har `dives`, forlater én fiende med `can_dive` plassen
   sin hvert `dive_interval` sekund, stuper i en bue mot spilleren, skyter i
   bunnen og flyr tilbake til `slot + offset` (som kan ha flyttet seg).
5. Skyting: vektet trekning (`fire_weight`) blant fiender i formasjonen.
   `aimed` gir retning mot spilleren, ellers rett ned.

## Dataformat: bølger

Ren GDScript i `waves/waves.gd`. Ingen Resource-klasser (se fallgruver).
Felt som mangler fylles fra `DEFAULTS` i samme fil.

```gdscript
const WAVES := [
	{ # bølge 1
		"enemies": [["grunt", 16]],          # første type havner øverst
		"formations": ["rows"],
		"entries": ["from_top"],
		"movements": ["classic"],
		"max_bullets": 3,
	},
	{ # bølge 3
		"enemies": [["elite", 4], ["skytter", 8], ["soldat", 16]],
		"formations": ["ring", "checkerboard"],
		"entries": ["spiral", "swoop"],
		"movements": ["sine", "classic"],
		"dives": true, "dive_interval": 3.0,
		"hp_mult": 1.3, "fire_rate_mult": 1.5,
		"speed_mult": 1.3, "bullet_speed_mult": 1.2,
		"max_bullets": 5,
		"banner": "BØLGE 3 — ELITE",
	},
	# ...
	{ "boss": "boss_1" }, # bølge 10 (kommer)
]
```

`wave_manager.gd` trekker én verdi fra hver liste (med run-seeden) og bygger
bølgen. Formasjonene i `formations.gd` er funksjoner som tar antall fiender
og returnerer plasser sortert ovenfra og ned, så samme formasjon virker med
16 eller 40, og de sterkeste typene alltid står bakerst.

Ny bølge = ny rad. Nytt mønster = ny `static func` i riktig fil under
`enemies/` pluss navnet i `match`-blokken der, så kan bølgene bruke det.

## Dataformat: oppgraderinger

```gdscript
const UPGRADES := {
	"rapid_fire": {
		"name": "HURTIGSKUDD",
		"desc": "+1 KULE I LUFTA",
		"rarity": "common",     # common / rare / epic
		"max_stacks": 3,
		"apply": "_apply_rapid_fire",  # metodenavn i upgrades.gd
	},
}

func _apply_rapid_fire(stats: Dictionary) -> void:
	stats["max_bullets"] += 1
```

`player_stats.gd` holder `base` og en liste med tatte oppgraderinger, og
regner ut `current` ved å starte fra `base` og kjøre alle `apply` på nytt.
Da er det umulig å få stats "ut av synk".

## Fallgruver med Godot 3.6 og .pck

Disse er ikke åpenbare, og koster timer hvis man går på dem:

- **Ingen `class_name`.** Globale klasser registreres i `project.godot` til
  prosjektet som starter. Når launcheren laster spillets .pck er det
  launcherens `project.godot` som gjelder, så `class_name Enemy` i spillet
  finnes ikke. Bruk alltid `preload("res://games/ailien_invaders/...")`.
- **Ingen nye autoloads.** Samme grunn. Trenger du noe globalt i spillet,
  legg det som en node under main.
- **Ingen egne `Resource`-klasser (`.tres` med skript).** De trenger
  `class_name` for å lastes trygt. Bølger og oppgraderinger er derfor
  vanlige dictionaries i `.gd`-filer.
- **Absolutte stier.** Alltid `res://games/ailien_invaders/...`, aldri
  relative stier, siden .pck-en blandes inn i launcherens `res://`.
- **`create_tween()` finnes** (3.5+), så inn/ut-animasjoner trenger ikke
  `Tween`-noder. Husk at en SceneTreeTween dør med noden den er bundet til.
- **Ikke overstyr `update()`, `draw()`, `hide()`** osv. på Node2D/Sprite.
- **`Arcade`-autoloaden** kommer fra launcheren. Spillets kopi i
  `shared/arcade_api.gd` brukes bare når spillet kjøres alene.
  Input-actions og hele API-et er beskrevet i rotas `ARCADE_API.md`.

## Ytelsesregler for Pi 3B+

- Ingen fysikk, ingen `Area2D`, ingen `KinematicBody2D`. Manuell AABB.
- Kuler tegnes i ett lag med `draw_texture_rect_region` fra sprite-ark
  (`Projectile_*.png`, 10×10-ruter). Aldri én node per kule.
- Fiender er én `Sprite` hver, det er greit opp til ~40.
- Unngå `load()` i `_process`. Alle teksturer preloades én gang.
- Ikke lag nye `Label`-noder per frame. HUD oppdaterer `.text`.

## Testing

`ARCADE_SMOKE_TEST=1` starter spillet og går ut etter et halvt sekund.

Logikktestene i `tests/` er scener med et skript som instansierer
`main.tscn` og driver spillet via API-et (`swarm.try_hit`, `main._start_wave`).
De kjøres som hovedscene, **ikke** med `-s`: i skriptmodus lastes ikke
`Arcade`-autoloaden, og da kan ikke main.gd parses.

```bash
cd games/AilienInvaders
../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/play_waves.tscn
```

Avslutter med kode 0 når alt er grønt. `tests/screenshots.tscn` lagrer ett
bilde per formasjon/innflyging (midt i og på plass) i `AILIEN_SHOTS` eller
`user://shots/`, for å se at mønstrene ser riktige ut.
