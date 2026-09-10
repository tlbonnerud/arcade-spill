# Arcade-API og input

Hvordan knappene på arkaden ender opp som `p1_a` i et spill, og hva
`Arcade`-singletonen tilbyr. Gjelder launcheren og alle spill.

Kildefila er `shared/arcade_api.gd`. Den **skal være identisk** i
`launcher/shared/` og i `games/<id>/shared/`. Endrer du den ett sted, kopier
til alle de andre. Sjekk med:

```bash
for g in games/*/; do diff -q launcher/shared/arcade_api.gd "$g/shared/arcade_api.gd"; done
```

## Slik henger det sammen

```
Arkadeknapper ──USB──► DragonRise-encoder ──► Linux /dev/input/js0
                                                     │
                                            Godot ser en joypad
                                                     │
                       shared/arcade_api.gd: _register_inputs()
                       (kjører ved oppstart, i kode, ikke i project.godot)
                                                     │
                       InputMap-actions: p1_up, p1_a, arcade_start, ...
                                                     │
                       Spillet: Input.is_action_pressed("p1_a")
```

Poenget med å registrere actions i **kode** i stedet for i `project.godot`:
når launcheren laster et spill som `.pck`, er det launcherens `project.godot`
som gjelder, ikke spillets. Med kode i den delte fila er mappingen garantert
lik overalt, og hvert spill kan også kjøres alene under utvikling.

`Arcade` er en autoload (singleton). I launcheren kommer den fra
`launcher/shared/arcade_api.gd`. Når et spill kjøres **alene** på Mac-en,
kommer den fra spillets egen kopi. Når spillet kjøres **via launcheren** er
det launcherens instans som lever videre, og spillets kopi brukes ikke.

## Actions

| Action | Tastatur (Mac) | Arkade (DragonRise) | Vanlig gamepad | Bruk |
|---|---|---|---|---|
| `p1_up` | Pil opp | Spak opp (akse 1 −) | D-pad opp | Meny/bevegelse |
| `p1_down` | Pil ned | Spak ned (akse 1 +) | D-pad ned | |
| `p1_left` | Pil venstre | Spak venstre (akse 0 −) | D-pad venstre | |
| `p1_right` | Pil høyre | Spak høyre (akse 0 +) | D-pad høyre | |
| `p1_a` | Z | Knapp 0 | A / Cross | Primær: skyt, velg |
| `p1_b` | X | Knapp 1 | B / Circle | Sekundær: bombe, avbryt |
| `arcade_start` | Enter | Knapp 3 (START) | Start | Start spill, nytt spill |
| `arcade_back` | Escape | Knapp 2 (RESET) | Select/Back | Tilbake til menyen |

Deadzone er 0,5 på alle actions, så spaken må presses tydelig før den
teller. Aksene gir også `Input.get_action_strength()`, men på arkaden er
spaken digital, så verdien er alltid 0 eller 1.

DragonRise-encoderen har ingen standard-mapping i Godot, så START og RESET
er funnet manuelt med input-testmodus (se under). Skal du bytte encoder,
kjør testmodus på nytt og oppdater indeksene i `_register_inputs()`.

## Hvordan et spill skal bruke input

```gdscript
# Bevegelse: bruk strength, så det virker likt for spak, d-pad og piltaster.
var dir := Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")

# Trykk: just_pressed for ting som skal skje én gang per trykk.
if Input.is_action_just_pressed("p1_a"):
	shoot()

# Hold: is_action_pressed for kontinuerlig (f.eks. laser-oppgradering).
if Input.is_action_pressed("p1_a"):
	laser_on()
```

Regler:

- Bruk **bare** actionene over. Aldri `KEY_SPACE`, `JOY_BUTTON_0` eller
  andre rå koder i spillkode.
- `arcade_back` skal spillet **ikke** håndtere selv. Den fanges globalt av
  `Arcade._input()` og går alltid tilbake til menyen. (Blir en
  holde-kombinasjon i fase 2, så det ikke skjer ved et uhell.)
- `arcade_start` brukes til "nytt spill" på game over-skjermen, og kan
  brukes som pause hvis spillet vil.
- Menyer i spillet (f.eks. oppgraderingsvalg) styres med
  `p1_left`/`p1_right` og bekreftes med `p1_a`. Aldri krev tekstinntasting.

## Arcade-API: funksjoner

### Scenebytte

| Funksjon | Hvem kaller | Hva den gjør |
|---|---|---|
| `Arcade.start_game(main_scene)` | Launcheren | Setter `in_game = true`, fjerner pause og bytter til spillets hovedscene. |
| `Arcade.quit_to_launcher()` | Spillet, eller `arcade_back` | Setter `in_game = false`, `returned_from_game = true` og bytter tilbake til launcher-scenen. Kjøres spillet alene finnes ikke launcheren, og da avsluttes programmet i stedet. |

Et spill skal **aldri** kalle `get_tree().quit()`. På Pi-en ville det drept
launcheren, og systemd måtte starte alt på nytt.

### Highscore

Lagres i `user://highscores.json` (utenfor `.pck`-ene, så det overlever
oppdateringer). Maks 10 per spill, sortert synkende.

| Funksjon | Returnerer |
|---|---|
| `Arcade.save_highscore(game_id, player, score)` | Ingenting. Legger inn og kutter lista til 10. |
| `Arcade.get_highscores(game_id)` | `Array` av `{"name": String, "score": int}` |
| `Arcade.get_best_score(game_id)` | `int`, 0 hvis ingen |

`game_id` må være det samme som `"id"` i spillets `manifest.json`. Launcheren
bruker `get_best_score` for å vise "rekord: N" under hver spillknapp.
`player` er foreløpig alltid `"P1"`; initialer-inntasting kommer i fase 2.

### Tilstand

| Variabel | Betydning |
|---|---|
| `Arcade.in_game` | `true` mens et spill kjører. Styrer om `arcade_back` går til menyen. |
| `Arcade.returned_from_game` | Launcheren hopper rett til spillvalget hvis `true`. |
| `Arcade.smoke_test` | `true` når `ARCADE_SMOKE_TEST=1`. Spillet skal da avslutte seg selv etter kort tid. |
| `Arcade.smoke_index` | Neste spill røyktesten skal starte. Brukes bare av launcheren. |

## Minste mulige spill

```gdscript
extends Node2D

const GAME_ID := "mitt_spill"  # == "id" i manifest.json
var score := 0

func _ready() -> void:
	if Arcade.smoke_test:
		yield(get_tree().create_timer(0.5), "timeout")
		Arcade.quit_to_launcher()

func _process(delta: float) -> void:
	if Input.is_action_just_pressed("p1_a"):
		score += 1

func _game_over() -> void:
	Arcade.save_highscore(GAME_ID, "P1", score)
	# Vis "START = nytt spill", vent på arcade_start. Ikke quit.
```

## Miljøvariabler

Alle leses ved oppstart. Ingen av dem settes på arkaden i normal drift,
bortsett fra `ARCADE_GAMES_DIR` som `pi/run.sh` setter.

| Variabel | Effekt |
|---|---|
| `ARCADE_SMOKE_TEST=1` | Launcheren starter hvert spill etter tur, spillene går ut selv, og programmet avslutter med kode 0 hvis alt gikk. |
| `ARCADE_INPUT_DEBUG=1` | Launcheren viser rå knapp-, akse- og tastehendelser på skjermen og i terminalen, med hvilke actions de traff. Bruk denne for å finne indekser på en ny encoder. |
| `ARCADE_GAMES_DIR=/sti` | Hvor launcheren leter etter `.pck` og `.json`. Standard: `dist/games` fra editor, `games/` ved siden av binæren ellers. |
| `ARCADE_SCREENSHOT=/sti/prefiks` | Lagrer start- og valgskjermen som PNG og avslutter. Dev-verktøy. |

## Teste input

På Mac, med tastatur eller en vanlig gamepad:

```bash
ARCADE_INPUT_DEBUG=1 tools/Godot3.app/Contents/MacOS/Godot --path launcher
```

På Pi-en med arkadeknappene (stopp autostart først):

```bash
sudo systemctl stop arcade
ARCADE_INPUT_DEBUG=1 ./pi/run.sh
```

Trykk på hver knapp og les av. En linje som `KNAPP 3 (enhet 0) -> arcade_start`
betyr at knappen er bundet riktig. `(ikke bundet)` betyr at indeksen må
legges til i `_register_inputs()`.

## Legge til en ny action

1. Legg til én linje i `_register_inputs()` i `shared/arcade_api.gd` med
   tastatur-, arkade- og gamepad-binding.
2. Kopier fila til launcheren og alle spill.
3. Legg actionen til i lista i `_debug_actions()` i `launcher/scenes/launcher.gd`,
   så testmodus viser den.
4. Oppdater tabellen i dette dokumentet.
