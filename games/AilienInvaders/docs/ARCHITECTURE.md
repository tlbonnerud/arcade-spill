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
│   ├── formations.gd       ✅ 9 formasjoner: rows, v_shape, ring, checkerboard,
│   │                          two_groups, diamond, arrow, columns, x_shape
│   ├── entry_patterns.gd   ✅ 8 innflyginger: from_top, from_sides, spiral, swoop,
│   │                          rain, crossover, loop, snake
│   ├── movement_patterns.gd✅ 7 bevegelser: classic, sine, figure8, split, rock,
│   │                          orbit, pulse (dykk ligger i wave_manager)
│   └── boss/
│       ├── boss.gd         ⬜ Bossen med faser
│       └── boss.tscn       ⬜ (scene, fordi bossen bør kunne pusses på i editoren)
├── waves/
│   └── waves.gd            ✅ De 10 bølgene som data (se format under)
├── upgrades/
│   ├── upgrades.gd         ⬜ Katalog: id, navn, sjeldenhet, apply()
│   └── upgrade_screen.gd   ⬜ "Velg 1 av 3"-skjermen
├── ui/
│   ├── hud.gd              ⬜ Poeng, liv, bølge, aktive oppgraderinger
│   └── transitions.gd      ⬜ Bølgebanner, ADVARSEL, fade, victory
├── sprites/                Grafikk
├── docs/                   Disse dokumentene (eksporteres ikke til .pck)
└── tests/                  Automatiske tester (ekskludert fra .pck)
    ├── play_waves.tscn/.gd     Spiller gjennom alle bølgene uten skjerm
    ├── check_patterns.tscn/.gd Kontrakter for mønstre og bølgedata
    ├── sim_waves.tscn/.gd      Bot som måler hvor vanskelige bølgene er
    ├── screenshots.tscn/.gd    Tar bilder av hvert mønster
    └── contact_sheets.py       Setter bildene sammen til oversiktsark
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
3. Bevegelse: `movement_patterns.gd` eier en tilstand. `step()` flytter
   tiden fram én gang per frame, og `place(state, slot)` sier hvor hver
   enkelt plass er akkurat nå. Fordi posisjonen regnes ut per fiende kan et
   mønster rotere formasjonen (rock, orbit), dele den i to (split) eller la
   den puste (pulse), ikke bare skyve den. `place()` allokerer ingenting:
   alt tungt (sin/cos, trygge utslag) regnes ut i `start()`/`step()`.
   Nedstigningen styres av bølgens `descent_time`, uavhengig av formasjonens
   bredde, og alt går fortere jo flere som er døde (`dead_frac`).
4. Dykk: hvis bølgen har `dives`, forlater en fiende plassen sin hvert
   `dive_interval` sekund (opptil `max_divers` samtidig, typer fra
   `dive_types` eller `can_dive`), stuper i en bue mot spilleren og flyr
   tilbake til plassen sin (som kan ha flyttet seg). Faren er kroppen:
   dykkeren skyter ikke, for en kule avfyrt i spillerens rad er enten ufarlig
   eller umulig å unngå. Plassen til en dykker teller fortsatt med i
   formasjonens kanter, ellers vandrer formasjonen ut mens den er borte.
5. Skyting: vektet trekning (`fire_weight`) blant fiender i formasjonen.
   `aimed` gir retning mot spilleren, ellers rett ned. Fiender som står så
   lavt at kula når spilleren på under `MIN_FIRE_WINDOW` (0,4 s) holder ilden,
   så hvert skudd kan unngås.

Typene i `enemies`-lista fyller formasjonen ovenfra og ned, og innenfor en
rad fra midten og ut. Da blir fargebåndene speilsymmetriske også når en type
tar slutt midt i en rad.

## Kontrakter for mønstre

Hver mønsterfil har en `NAMES`-liste og en KONTRAKT-kommentar øverst.
`tests/check_patterns.tscn` sjekker dem for alle navn:

- **Formasjoner** (8–40 fiender): nøyaktig antall plasser, innenfor
  skjermen og over `MAX_Y`, minst 28 px mellom plasser, sentrert.
- **Innflyginger:** starter utenfor skjermen, ender på plassen, flyr aldri
  gjennom spillerens rad, og hele innflygingen tar maks 4,5 s.
- **Bevegelser:** sømløs start, aldri utenfor skjermen (mønsteret må dempe
  seg på brede formasjoner), når bunnen etter ca. `descent_time`, ingen hopp.
- **Bølgene:** alt de refererer til finnes, og hver kombinasjon poolene kan
  trekke holder kontraktene over med bølgens egne tall.

Nytt mønster: skriv funksjonen, legg navnet i `NAMES` og `match`-blokken,
kjør testen. Da vet du at det virker med alle formasjoner og antall.

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

Avslutter med kode 0 når alt er grønt. De andre testene kjøres på samme måte:

| Test | Hva den gjør |
|---|---|
| `play_waves.tscn` | Spiller gjennom alle bølgene: antall, typer, innflyging, hp, overganger, bonusliv, VICTORY, seed-determinisme. Pluss regresjonssjekker: formasjonen hopper ikke når en kantfiende dykker, `max_divers` virker, lave fiender holder ilden. |
| `check_patterns.tscn` | Kontraktene over. `AILIEN_CHECK=formations\|entries\|movements\|waves\|all`. |
| `sim_waves.tscn` | En bot med menneskelige svakheter (reaksjonstid, begrenset blikk, overser kuler, sikter litt feil) spiller hver bølge mange ganger i hurtigtid og rapporterer klareringsrate, tid, tapte liv (kule/dykker) og verste kombinasjon. Brukes til å stille tallene i `waves.gd`. `AILIEN_SIM_SKILL=average\|good\|perfect`, `AILIEN_SIM_RUNS`, `AILIEN_SIM_WAVES="4-6"`. |
| `screenshots.tscn` + `contact_sheets.py` | Bilder av hvert mønster, satt sammen til oversiktsark. `AILIEN_SHOTS=/sti`. |

Testene er skrevet for å feile høyt. I Godot 3 avbryter en skriptfeil bare
funksjonen den skjer i, og den som kalte fortsetter med `null`. Derfor
returnerer hver delsjekk `true` til slutt, "ikke true" teller som feil, spillets
skript lastes med `load()` + `can_instance()` i stedet for `preload`, og en
vaktbikkje avslutter med kode 1 hvis testen stopper opp. Uten dette kunne en
parsefeil i et mønster gi "OK" eller en Godot-prosess som aldri avslutter.
Ett hull gjenstår og kan ikke tettes innenfra: har *testskriptet selv* en
parsefeil, får noden ikke noe skript, og Godot blir stående. Kjør derfor
testene med tidsavbrudd i skript og CI (`timeout 600 Godot ...`).

`AILIEN_WAVES_JSON=/sti/waves.json` får `check_patterns` og `sim_waves` til
å bruke bølgerader fra en JSON-fil i stedet for `waves.gd`, så man kan prøve
ut nye bølger uten å endre spillet.

Krokene testene bruker i spillet: `main.save_scores = false` (ikke lagre
highscore), `main.wave_rows` (egne bølgerader), `player.autopilot`
(`{"dir", "fire"}` i stedet for input; også tenkt til attract-modus) og
`swarm.spawn_data()` (tving fram bestemte mønstre).
