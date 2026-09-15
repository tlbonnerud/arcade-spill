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
│   └── wave_manager.gd     ⬜ Leser bølgedata, spawner, kjører inn/ut-animasjon,
│                              sier fra når bølgen er ferdig
├── player/
│   ├── player.gd           ✅ Bevegelse, skyting, treff, usårbarhet
│   └── player_stats.gd     ⬜ Basisstats + oppgraderingsmodifikatorer
├── enemies/
│   ├── swarm.gd            ✅ Dagens grid-sverm (blir til wave_manager + enemy)
│   ├── enemy.gd            ⬜ Én fiende: type, hp, poeng, animasjon, skytemønster
│   ├── enemy_types.gd      ⬜ Tabell: grunt/soldat/skytter/elite
│   ├── formations.gd       ⬜ Grid, V, ring, sjakkbrett → liste med posisjoner
│   ├── movement_patterns.gd⬜ Klassisk, sinus, dykk
│   ├── entry_patterns.gd   ⬜ Innflyging: fra toppen, sidene, spiral
│   └── boss/
│       ├── boss.gd         ⬜ Bossen med faser
│       └── boss.tscn       ⬜ (scene, fordi bossen bør kunne pusses på i editoren)
├── waves/
│   └── waves.gd            ⬜ De 10 bølgene som data (se format under)
├── upgrades/
│   ├── upgrades.gd         ⬜ Katalog: id, navn, sjeldenhet, apply()
│   └── upgrade_screen.gd   ⬜ "Velg 1 av 3"-skjermen
├── ui/
│   ├── hud.gd              ⬜ Poeng, liv, bølge, aktive oppgraderinger
│   └── transitions.gd      ⬜ Bølgebanner, ADVARSEL, fade, victory
├── sprites/                Grafikk
└── docs/                   Disse dokumentene (eksporteres ikke til .pck)
```

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
 ├── swarm (swarm.gd)
 │     fire_requested(pos, kind) ──► bullets.spawn_enemy_bullet
 │     enemy_killed(pts)   ──► main → poeng
 │     cleared             ──► main → neste bølge
 │     reached_bottom      ──► main._set_game_over
 └── bullets (bullets.gd)
       kaller swarm.try_hit(pos) og player.hit_test(pos)/take_hit()
```

Regelen: **delene kjenner ikke hverandre**, bare main gjør det. Player vet
ikke hva en fiende er. Swarm vet ikke hva en kule er. Bullets får referanser
via `setup()` og bruker bare `try_hit`/`hit_test`/`take_hit`.

Hver frame kaller main `step(delta)` på delene i fast rekkefølge:
spiller, sverm, kuler. (Ikke `update()`: det navnet er opptatt av
`CanvasItem` og betyr "tegn på nytt".)

## Planlagt tilstandsmaskin i main.gd

```gdscript
enum State { INTRO, WAVE_INTRO, WAVE, WAVE_CLEAR, UPGRADE, BOSS_INTRO, BOSS, VICTORY, GAME_OVER }
var state := State.INTRO

func _set_state(next):
	# avslutt gammel, start ny (banner, tween, vis/skjul skjermer)
```

`_process` gjør bare det tilstanden tillater: i UPGRADE stepper vi ikke
sverm og kuler, i WAVE_INTRO stepper vi spilleren men ikke fiendenes skyting.

## Dataformat: bølger

Ren GDScript i `waves/waves.gd`. Ingen Resource-klasser (se fallgruver).

```gdscript
const WAVES := [
	{ # bølge 1
		"enemies": [["grunt", 16]],
		"formations": ["rows_2"],
		"movements": ["classic"],
		"entries": ["from_top"],
		"fire_rate_mult": 1.0,
		"hp_mult": 1.0,
	},
	{ # bølge 5
		"enemies": [["elite", 8], ["grunt", 16]],
		"formations": ["ring", "v_shape"],
		"movements": ["classic", "dive"],
		"entries": ["from_sides", "spiral"],
		"fire_rate_mult": 1.4,
		"hp_mult": 1.6,
		"banner": "ELITE-BØLGE",
	},
	# ...
	{ "boss": "boss_1" }, # bølge 10
]
```

`wave_manager.gd` trekker én verdi fra hver liste (med run-seeden) og bygger
bølgen. Formasjonene i `formations.gd` er funksjoner som tar antall fiender
og returnerer posisjoner, så samme formasjon virker med 16 eller 40.

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

`ARCADE_SMOKE_TEST=1` starter spillet og går ut etter et halvt sekund. For
logikk er det bedre med et skript som kjøres med `-s` og driver spillet via
API-et (`swarm.try_hit`, `bullets.spawn_enemy_bullet`, `main._start_run`).
Legg slike tester i `tests/` når de blir mer enn én.
