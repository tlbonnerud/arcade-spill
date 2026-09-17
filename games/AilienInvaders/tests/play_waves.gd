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

const MainScene := preload("res://games/ailien_invaders/main.tscn")
const Waves := preload("res://games/ailien_invaders/waves/waves.gd")

const TIMEOUT := 90.0  # vaktbikkje: sekunder før testen gir opp

var main: Node2D
var failures := 0
var elapsed := 0.0


func _ready() -> void:
	main = MainScene.instance()
	add_child(main)
	main.save_scores = false  # ikke fyll highscore-lista med testpoeng
	call_deferred("_run")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed > TIMEOUT:
		print("FEIL: testen tok mer enn %d s" % int(TIMEOUT))
		get_tree().quit(1)


func _run() -> void:
	yield(get_tree(), "idle_frame")
	_check(main.state == main.State.WAVE_INTRO, "starter i WAVE_INTRO")
	_check(main.wave == 1, "starter på bølge 1")

	for n in range(1, Waves.count() + 1):
		yield(_play_wave(n), "completed")

	_check(main.state == main.State.VICTORY, "VICTORY etter siste bølge (state=%d)" % main.state)
	_check(main.score > 0, "poeng er talt opp (%d)" % main.score)

	# Samme seed skal gi samme valg fra poolene (bølge 2 har flere å velge i).
	main.rng.seed = 4242
	main._start_wave(2)
	var a := _wave_signature()
	main.rng.seed = 4242
	main._start_wave(2)
	var b := _wave_signature()
	_check(a == b, "samme seed gir samme bølge (%s vs %s)" % [a, b])
	main.rng.seed = 4243
	main._start_wave(2)
	print("  info seed 4243 gir ", _wave_signature())

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
	_check(swarm.alive_count() == 0, "bølge %d: alle drept" % n)
	_check(main.state == main.State.WAVE_CLEAR, "bølge %d: WAVE_CLEAR" % n)

	# Vent på neste bølge / victory.
	waited = 0.0
	while main.state == main.State.WAVE_CLEAR and waited < 3.0:
		yield(get_tree(), "idle_frame")
		waited += _delta()
	yield(get_tree(), "idle_frame")


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


func _all_offscreen(swarm) -> bool:
	for e in swarm.enemies:
		var p: Vector2 = e["sprite"].position
		if p.x >= 0 and p.x <= 640 and p.y >= 0 and p.y <= 360:
			return false
	return true


func _all_on_slots(swarm) -> bool:
	for e in swarm.enemies:
		if e["alive"] and e["sprite"].position.distance_to(swarm.slot_position(e)) > 1.0:
			return false
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
