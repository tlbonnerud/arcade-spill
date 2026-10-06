extends Node

# Automatisk spilltest: spiller gjennom alle bølgene uten skjerm.
#
#   cd games/AilienInvaders
#   ../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/play_waves.tscn
#
# Kjøres som scene (ikke -s), fordi Arcade-autoloaden bare lastes når
# prosjektet starter normalt.
#
# Sjekker at hver bølge spawner riktig antall og typer, at innflygingen
# starter utenfor skjermen og ender på plass, at hp-skalering virker,
# at bølgene går over i hverandre og at runnet ender i VICTORY.
# Avslutter med kode 0 (OK) eller 1 (feil).

# Skript lastes med load() i _ready, ikke preload: et skript med parsefeil
# ville ellers hindre denne fila i å laste, og da blir Godot stående for alltid.
const MAIN_SCENE := "res://games/ailien_invaders/main.tscn"
const WAVES_SCRIPT := "res://games/ailien_invaders/waves/waves.gd"

const TIMEOUT := 240.0  # vaktbikkje: sekunder før testen gir opp
const DT := 1.0 / 60.0

var Waves
var main: Node2D
var failures := 0
var elapsed := 0.0


func _ready() -> void:
	Waves = load(WAVES_SCRIPT)
	var scene = load(MAIN_SCENE)
	if Waves == null or not Waves.can_instance() or scene == null:
		print("FEIL: waves.gd eller main.tscn lar seg ikke laste")
		get_tree().quit(1)
		return
	main = scene.instance()
	add_child(main)
	if main.get_script() == null or not main.has_method("wave_count"):
		print("FEIL: main.gd kompilerte ikke")
		get_tree().quit(1)
		return
	main.save_scores = false  # ikke fyll highscore-lista med testpoeng
	call_deferred("_run")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > TIMEOUT:
		print("FEIL: testen tok mer enn %d s" % int(TIMEOUT))
		get_tree().quit(1)


func _run() -> void:
	yield(get_tree(), "idle_frame")
	main._start_run(12345)  # fast seed, så en feil kan gjenskapes
	_check(main.state == main.State.WAVE_INTRO, "starter i WAVE_INTRO")
	_check(main.wave == 1, "starter på bølge 1")

	for n in range(1, Waves.count() + 1):
		yield(_play_wave(n), "completed")

	_check(main.state == main.State.VICTORY, "VICTORY etter siste bølge (state=%d)" % main.state)
	_check(main.score > 0, "poeng er talt opp (%d)" % main.score)

	# Samme seed skal gi samme bølge, også det som trekkes med rng (pooler,
	# og forsinkelsene i "rain"). Bølge 9 og 10 har mest å trekke i.
	for n in [9, 10]:
		if n > Waves.count():
			continue
		main.rng.seed = 4242
		main._start_wave(n)
		var a := _wave_fingerprint()
		main.rng.seed = 4242
		main._start_wave(n)
		var b := _wave_fingerprint()
		_check(a == b, "bølge %d: samme seed gir samme bølge" % n)
		var differs := false
		for other_seed in range(1, 12):
			main.rng.seed = other_seed
			main._start_wave(n)
			if _wave_fingerprint() != a:
				differs = true
		_check(differs, "bølge %d: andre seeds gir andre bølger" % n)

	# En skriptfeil avbryter bare funksjonen den skjer i, så hver delsjekk
	# returnerer true til slutt og "ikke true" teller som feil.
	main.set_process(false)
	_check(_check_diver_bounds() == true, "dykkergrenser: sjekken fullførte")
	_check(_check_multiple_divers() == true, "flere dykkere: sjekken fullførte")
	_check(_check_low_enemies_hold_fire() == true, "lav ild: sjekken fullførte")

	if failures == 0:
		print("OK: alle %d bølger spilt gjennom" % Waves.count())
		get_tree().quit(0)
	else:
		print("FEIL: %d sjekker feilet" % failures)
		get_tree().quit(1)


func _play_wave(n: int) -> void:
	var swarm = main.swarm
	var data: Dictionary = Waves.get_wave(n)
	var expected: int = Waves.enemy_count(data)
	var lives_at_start: int = main.player.lives
	main.player.invuln = 999.0  # testen handler om bølgene, ikke om å overleve
	_check(main.wave == n, "bølge %d er aktiv" % n)
	_check(swarm.alive_count() == expected, "bølge %d: %d fiender (fikk %d)" % [n, expected, swarm.alive_count()])
	_check(_types_match(swarm.enemies, data["enemies"]), "bølge %d: riktig fiendemiks" % n)
	_check(swarm.is_entering(), "bølge %d: innflyging pågår (%s)" % [n, _wave_signature()])
	_check(_all_offscreen(swarm), "bølge %d: fiendene starter utenfor skjermen" % n)

	# HP-skalering: første fiende (øverst, sterkeste type) skal ha skalert hp.
	var first: Dictionary = swarm.enemies[0]
	var base_hp: int = swarm.EnemyTypes.get_type(first["type"])["hp"]
	var want_hp := int(max(1, round(base_hp * data["hp_mult"])))
	_check(first["hp"] == want_hp, "bølge %d: hp %d for %s (fikk %d)" % [n, want_hp, first["type"], first["hp"]])

	# Vent til innflygingen er ferdig (maks 6 s spilletid).
	var waited := 0.0
	while swarm.is_entering() and waited < 6.0:
		yield(get_tree(), "idle_frame")
		waited += _delta()
	_check(not swarm.is_entering(), "bølge %d: innflyging ferdig" % n)
	_check(main.state == main.State.WAVE, "bølge %d: WAVE etter innflyging" % n)
	_check(_all_on_slots(swarm), "bølge %d: alle på plassen sin" % n)

	# La formasjonen bevege seg litt, så skyt alle med try_hit rett i posisjonen.
	for _i in 30:
		yield(get_tree(), "idle_frame")
	var shots := 0
	while swarm.alive_count() > 0 and shots < expected * 6:
		var e: Dictionary = _first_alive(swarm)
		swarm.try_hit(e["sprite"].position)
		shots += 1
		if shots % 4 == 0:
			yield(get_tree(), "idle_frame")
	var lives_before: int = main.player.lives
	# (try_hit over har allerede utløst cleared, så bonuslivet er delt ut.)
	_check(swarm.alive_count() == 0, "bølge %d: alle drept" % n)
	_check(main.state == main.State.WAVE_CLEAR, "bølge %d: WAVE_CLEAR" % n)
	# Bonusliv fra bølgen pluss helbredelse fra oppgraderingene, opp til maks.
	var gain := int(main.stats.current["heal_per_wave"]) + (1 if data["bonus_life"] else 0)
	var want_lives := int(min(main.player.max_lives(), lives_at_start + gain))
	_check(main.player.lives == want_lives, "bølge %d: liv etter bølgen %d (fikk %d)" % [n, want_lives, lives_before])

	# Vent på oppgraderingsskjermen / victory.
	waited = 0.0
	while main.state == main.State.WAVE_CLEAR and waited < 3.0:
		yield(get_tree(), "idle_frame")
		waited += _delta()
	yield(get_tree(), "idle_frame")

	if n < Waves.count():
		_check(main.state == main.State.UPGRADE, "bølge %d: UPGRADE etter WAVE_CLEAR (state=%d)" % [n, main.state])
		var offer: Array = main.upgrade_screen.offer
		_check(offer.size() == 3, "bølge %d: tre kort (fikk %d)" % [n, offer.size()])
		_check(_unique(offer), "bølge %d: tre ulike kort %s" % [n, str(offer)])
		var before: int = main.stats.taken.size()
		main.upgrade_screen.choose(0)
		_check(main.stats.taken.size() == before + 1, "bølge %d: oppgradering tatt (%s)" % [n, offer[0]])
		_check(main.wave == n + 1 and main.state == main.State.WAVE_INTRO,
				"bølge %d: neste bølge starter etter valget" % n)
		yield(get_tree(), "idle_frame")


# Alt rng-avhengig ved en nyspawnet bølge: valgte mønstre og hver bane inn.
func _wave_fingerprint() -> String:
	var parts := [_wave_signature()]
	for e in main.swarm.enemies:
		parts.append("%s %s %.3f" % [e["type"], str(e["entry"]["start"]), e["entry"]["delay"]])
	return PoolStringArray(parts).join("|")


# Regresjon: mens en kantfiende dykker hører plassen dens fortsatt til
# formasjonen. Før vandret formasjonen ut av skjermen og rykket tilbake i ett
# hopp når dykkeren landet (klassisk bevegelse + dykk = bølge 10).
func _check_diver_bounds():
	var swarm = main.swarm
	var M = swarm.Movements
	var row := {"enemies": [["elite", 8], ["grunt", 8]], "formations": ["rows"], "entries": ["from_top"],
			"movements": ["classic"], "dives": true, "dive_interval": 0.5, "speed_mult": 1.6}
	main.rng.seed = 99
	swarm.spawn_data(1, Waves.with_defaults(row, 1), main.rng)
	_step_swarm(6.0)
	# Behold bare to: en elite helt til høyre (dykker) og en grunt helt til venstre.
	var keep_right: Dictionary = {}
	var keep_left: Dictionary = {}
	for e in swarm.enemies:
		if e["type"] == "elite" and (keep_right.empty() or e["slot"].x > keep_right["slot"].x):
			keep_right = e
		if e["type"] == "grunt" and (keep_left.empty() or e["slot"].x < keep_left["slot"].x):
			keep_left = e
	for e in swarm.enemies:
		if e != keep_right and e != keep_left:
			e["alive"] = false
			e["sprite"].visible = false
	var prev: Vector2 = keep_left["sprite"].position
	var worst_step := 0.0
	var off_screen := 0
	var dives := 0
	var was_diving := false
	for _i in int(20.0 / DT):
		swarm.step(DT, false, Vector2(320, 330))
		var p: Vector2 = keep_left["sprite"].position
		worst_step = max(worst_step, p.distance_to(prev))
		prev = p
		if keep_right["diving"] and not was_diving:
			dives += 1
		was_diving = keep_right["diving"]
		for e in [keep_left, keep_right]:
			if not e["diving"] and (e["sprite"].position.x < M.X_MIN or e["sprite"].position.x > M.X_MAX):
				off_screen += 1
	_check(dives >= 3, "dykkergrenser: eliten dykket (%d ganger)" % dives)
	_check(worst_step <= M.MAX_STEP, "dykkergrenser: formasjonen hopper ikke (største steg %.1f px)" % worst_step)
	_check(off_screen == 0, "dykkergrenser: ingen i formasjonen utenfor skjermen (%d frames)" % off_screen)
	return true


# max_divers > 1 brukes ikke av bølgene akkurat nå, så motoren testes her.
func _check_multiple_divers():
	var swarm = main.swarm
	var row := {"enemies": [["elite", 8]], "formations": ["rows"], "entries": ["from_top"],
			"dives": true, "dive_interval": 0.4, "max_divers": 2}
	main.rng.seed = 5
	swarm.spawn_data(1, Waves.with_defaults(row, 1), main.rng)
	_step_swarm(4.0)
	var most := 0
	for _i in int(8.0 / DT):
		swarm.step(DT, false, Vector2(320, 330))
		most = int(max(most, swarm.diver_positions().size()))
	_check(most == 2, "flere dykkere: to samtidig med max_divers 2 (fikk %d)" % most)
	return true


# Fiender som står så lavt at kula ikke kan unngås, holder ilden.
func _check_low_enemies_hold_fire():
	var swarm = main.swarm
	var row := {"enemies": [["soldat", 8]], "formations": ["rows"], "entries": ["from_top"],
			"descent_time": 20.0, "fire_rate_mult": 4.0}
	main.rng.seed = 5
	swarm.spawn_data(1, Waves.with_defaults(row, 1), main.rng)
	_step_swarm(4.0)
	var lowest_shot := [0.0]
	swarm.connect("fire_requested", self, "_on_test_fire", [lowest_shot])
	var t := 0.0
	var reached := [false]
	swarm.connect("reached_bottom", self, "_on_test_bottom", [reached])
	while t < 30.0 and not reached[0]:
		swarm.step(DT, true, Vector2(320, 330))
		t += DT
	swarm.disconnect("fire_requested", self, "_on_test_fire")
	swarm.disconnect("reached_bottom", self, "_on_test_bottom")
	var limit: float = swarm.DIVE_TARGET_Y - swarm.MIN_FIRE_WINDOW * swarm.ENEMY_BULLET_SPEED
	_check(reached[0], "lav ild: formasjonen kom helt ned (%.1f s)" % t)
	_check(lowest_shot[0] > 100.0 and lowest_shot[0] <= limit + 0.5,
			"lav ild: laveste skudd fra y=%.0f (grense %.0f)" % [lowest_shot[0], limit])
	return true


func _on_test_fire(pos: Vector2, _kind: String, _dir: Vector2, lowest: Array) -> void:
	lowest[0] = max(lowest[0], pos.y)


func _on_test_bottom(reached: Array) -> void:
	reached[0] = true


func _step_swarm(seconds: float) -> void:
	for _i in int(seconds / DT):
		main.swarm.step(DT, false, Vector2(320, 330))


func _wave_signature() -> String:
	var c: Dictionary = main.swarm.wave_data["chosen"]
	return "%s/%s/%s" % [c["formation"], c["entry"], c["movement"]]


func _types_match(enemies: Array, spec: Array) -> bool:
	var counts := {}
	for e in enemies:
		counts[e["type"]] = counts.get(e["type"], 0) + 1
	for pair in spec:
		if counts.get(pair[0], 0) != int(pair[1]):
			return false
	return true


# Bruker banens startpunkt, ikke spritens posisjon akkurat nå: da avhenger
# ikke sjekken av hvor lang den første framen tilfeldigvis ble.
func _all_offscreen(swarm) -> bool:
	for e in swarm.enemies:
		var p: Vector2 = e["entry"]["start"]
		if p.x >= 0 and p.x <= 640 and p.y >= 0 and p.y <= 360:
			return false
	return true


func _all_on_slots(swarm) -> bool:
	for e in swarm.enemies:
		if e["alive"] and e["sprite"].position.distance_to(swarm.slot_position(e)) > 1.0:
			return false
	return true


func _unique(ids: Array) -> bool:
	var seen := {}
	for id in ids:
		if seen.has(id):
			return false
		seen[id] = true
	return true


func _first_alive(swarm) -> Dictionary:
	for e in swarm.enemies:
		if e["alive"]:
			return e
	return {}


func _delta() -> float:
	return get_process_delta_time()


func _check(ok: bool, what: String) -> void:
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FEIL ", what)
