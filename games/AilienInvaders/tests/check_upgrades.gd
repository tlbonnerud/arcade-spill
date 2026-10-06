extends Node

# Kontraktstest for oppgraderingene i upgrades/ og statblokken i player/.
#
#   cd games/AilienInvaders
#   ../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/check_upgrades.tscn
#
# Sjekker katalogen (ikon, tekst, sjeldenhet, stabling), trekkingen (tre
# ulike, aldri maks-stablet, første tilbud har en sjelden) og at hver
# oppgradering faktisk gjør det kortet sier, målt i spillet: flere kuler,
# skade, gjennomtrenging, eksplosjon, målsøking, skjold, liv, størrelse, fart
# og pigger. Avslutter med kode 0 (OK) eller 1 (feil).
#
# Som de andre testene: skript lastes med load(), hver delsjekk returnerer
# true til slutt, og "ikke true" teller som feil (en skriptfeil avbryter bare
# funksjonen den skjer i).

const BASE := "res://games/ailien_invaders/"
const DT := 1.0 / 60.0
const STALL_FRAMES := 600

var Upgrades
var PlayerStats
var Waves
var main: Node2D
var failures := 0
var checks := 0
var stalled_frames := 0


func _ready() -> void:
	Upgrades = load(BASE + "upgrades/upgrades.gd")
	PlayerStats = load(BASE + "player/player_stats.gd")
	Waves = load(BASE + "waves/waves.gd")
	var scene = load(BASE + "main.tscn")
	for script in [Upgrades, PlayerStats, Waves]:
		if script == null or not script.can_instance():
			_abort("et av spillets skript lar seg ikke laste")
			return
	main = scene.instance()
	add_child(main)
	if main.get_script() == null or not main.has_method("wave_count"):
		_abort("main.gd kompilerte ikke")
		return
	main.save_scores = false
	main.set_process(false)
	main.upgrade_screen.autopilot = true
	call_deferred("_run")


func _process(_delta: float) -> void:
	stalled_frames += 1
	if stalled_frames > STALL_FRAMES:
		_abort("testen stoppet opp (skriptfeil?)")


func _abort(why: String) -> void:
	print("FEIL: ", why)
	get_tree().quit(1)


func _run() -> void:
	yield(get_tree(), "idle_frame")
	_check(_check_catalog() == true, "katalog: sjekken fullførte")
	_check(_check_offers() == true, "trekking: sjekken fullførte")
	_check(_check_stats() == true, "statblokk: sjekken fullførte")
	_check(_check_attack_speed() == true, "hurtigskudd: sjekken fullførte")
	_check(_check_multishot() == true, "spredningsskudd: sjekken fullførte")
	_check(_check_damage() == true, "skarpt skyts: sjekken fullførte")
	_check(_check_piercing() == true, "gjennomtrenging: sjekken fullførte")
	_check(_check_big_bullets() == true, "store kuler: sjekken fullførte")
	_check(_check_explosion() == true, "eksplosjon: sjekken fullførte")
	_check(_check_homing() == true, "målsøking: sjekken fullførte")
	_check(_check_lives() == true, "liv: sjekken fullførte")
	_check(_check_shield() == true, "skjold: sjekken fullførte")
	_check(_check_thorns() == true, "pigger: sjekken fullførte")
	_check(_check_size_and_speed() == true, "størrelse/fart: sjekken fullførte")
	_check(_check_screen() == true, "skjerm: sjekken fullførte")
	if failures == 0:
		print("OK: %d sjekker" % checks)
		get_tree().quit(0)
	else:
		print("FEIL: %d av %d sjekker feilet" % [failures, checks])
		get_tree().quit(1)


# ---------------------------------------------------------------------------
# Katalog og trekking
# ---------------------------------------------------------------------------

func _check_catalog():
	_check(Upgrades.IDS.size() == Upgrades.CATALOG.size(), "katalog: IDS dekker alle (%d/%d)"
			% [Upgrades.IDS.size(), Upgrades.CATALOG.size()])
	for id in Upgrades.IDS:
		var u: Dictionary = Upgrades.get_upgrade(id)
		_check(not u.empty(), "%s: finnes" % id)
		if u.empty():
			continue
		_check(u["name"] != "" and u["name"] == u["name"].to_upper(), "%s: navn i store bokstaver" % id)
		_check(u["desc"] != "" and u["desc"].length() <= 32, "%s: beskrivelse kort nok (%d)" % [id, u["desc"].length()])
		_check(Upgrades.WEIGHTS.has(u["rarity"]), "%s: gyldig sjeldenhet" % id)
		_check(int(u["max_stacks"]) >= 1, "%s: max_stacks >= 1" % id)
		var icon = u["icon"]
		_check(icon != null and icon is Texture and icon.get_height() == Upgrades.ICON_SIZE.y
				and int(icon.get_width()) % int(Upgrades.ICON_SIZE.x) == 0, "%s: ikon 24x20-ruter" % id)
		# Hver apply skal endre noe i statblokken.
		var stats: Dictionary = PlayerStats.BASE.duplicate()
		Upgrades.apply(id, stats, 1)
		_check(stats.hash() != PlayerStats.BASE.hash(), "%s: apply endrer stats" % id)
	return true


func _check_offers():
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bad_dupes := 0
	var bad_size := 0
	var bad_first := 0
	var seen := {}
	for i in 400:
		var offer: Array = Upgrades.offer(rng, {}, 3, i % 2 == 0)
		if offer.size() != 3:
			bad_size += 1
		if not _unique(offer):
			bad_dupes += 1
		if i % 2 == 0 and not _has_rare(offer):
			bad_first += 1
		for id in offer:
			seen[id] = true
	_check(bad_size == 0, "trekking: alltid tre kort (%d feil)" % bad_size)
	_check(bad_dupes == 0, "trekking: aldri to like (%d feil)" % bad_dupes)
	_check(bad_first == 0, "trekking: første tilbud har alltid en sjelden (%d feil)" % bad_first)
	_check(seen.size() == Upgrades.IDS.size(), "trekking: alle %d kan dukke opp (så %d)" % [Upgrades.IDS.size(), seen.size()])

	# Maks-stablede trekkes ikke.
	var maxed := {}
	for id in Upgrades.IDS:
		maxed[id] = Upgrades.max_stacks(id)
	maxed.erase("thorns")
	maxed.erase("healing")
	var only: Array = Upgrades.offer(rng, maxed, 3, false)
	only.sort()
	_check(only == ["healing", "thorns"], "trekking: bare de som kan tas (%s)" % str(only))
	_check(Upgrades.offer(rng, maxed, 3, true).size() == 2, "trekking: færre enn tre når poolen er tom")
	return true


func _check_stats():
	var s = PlayerStats.new()
	s.reset()
	_check(s.current.hash() == PlayerStats.BASE.hash(), "statblokk: reset gir basis")
	s.take("multishot")
	s.take("multishot")
	s.take("damage")
	_check(s.current["shots"] == 3 and s.current["damage"] == 2, "statblokk: stabler (shots %d, damage %d)"
			% [s.current["shots"], s.current["damage"]])
	var counts: Dictionary = s.stack_counts()
	_check(s.stacks("multishot") == 2 and counts.size() == 2 and counts.get("multishot") == 2
			and counts.get("damage") == 1, "statblokk: teller riktig %s" % str(counts))
	s.take("homing")
	var one: float = s.current["homing"]
	s.take("homing")
	_check(s.current["homing"] > one, "statblokk: nivå 2 regnes fra antall (homing %.1f -> %.1f)" % [one, s.current["homing"]])
	s.reset()
	_check(s.taken.empty() and s.current["shots"] == 1, "statblokk: reset nullstiller")
	return true


# ---------------------------------------------------------------------------
# Mekanikk, målt i spillet
# ---------------------------------------------------------------------------

# Starter et nytt run med gitte oppgraderinger og en enkel bølge av `enemies`
# (rader, rett ned, klassisk, uten skyting), spilt fram til alle er på plass.
func _setup(ids: Array, enemies: Array, extra_row: Dictionary = {}) -> void:
	main.upgrades_enabled = false
	main._start_run(1)
	for id in ids:
		main.stats.take(id)
	main._apply_stats()
	var row := {"enemies": enemies, "formations": ["rows"], "entries": ["from_top"],
			"movements": ["classic"], "fire_rate_mult": 0.0001, "descent_time": 10000.0,
			"speed_mult": 0.0001}
	for k in extra_row:
		row[k] = extra_row[k]
	main.wave_rows = [row, row]
	main._start_wave(1)
	main.player.invuln = 0.0
	_advance(6.0)  # innflyging ferdig
	main.player.position.x = 320.0


func _advance(seconds: float) -> void:
	for _i in int(seconds / DT):
		main._process(DT)


func _fire() -> bool:
	return main.bullets.spawn_player_bullet(main.player.position + Vector2(0, -12))


# Flytter den første fienden i lista dit vi vil ha den (plassen følger med,
# så bevegelsen ikke drar den tilbake).
func _put_enemy(index: int, pos: Vector2) -> Dictionary:
	var e: Dictionary = main.swarm.enemies[index]
	e["slot"] = pos
	e["sprite"].position = pos
	main.swarm.move_state["offset"] = Vector2.ZERO
	return e


func _alive() -> int:
	return main.swarm.alive_count()


func _check_attack_speed():
	_setup([], [["grunt", 8]])
	_check(_fire() and not _fire(), "hurtigskudd: basis = én kule i lufta")
	_setup(["attack_speed", "attack_speed"], [["grunt", 8]])
	_check(_fire() and _fire() and _fire() and not _fire(), "hurtigskudd: to nivåer = tre skudd i lufta")
	return true


func _check_multishot():
	_setup(["multishot", "multishot"], [["grunt", 8]])
	_fire()
	_check(main.bullets.player_bullet_count() == 3, "spredningsskudd: nivå 2 gir tre kuler (%d)" % main.bullets.player_bullet_count())
	var xs := []
	for b in main.bullets.player_bullets:
		xs.append(b["vel"].x)
	xs.sort()
	_check(xs[0] < -1.0 and abs(xs[1]) < 0.01 and xs[2] > 1.0, "spredningsskudd: vifte (%s)" % str(xs))
	_check(not _fire(), "spredningsskudd: hele vifta teller som ett skudd")
	# En vifte treffer bredere enn ett skudd: tre fiender på en rad over spilleren.
	_setup(["multishot", "multishot"], [["grunt", 8]])
	for i in 3:
		_put_enemy(i, Vector2(320 + (i - 1) * 36, 150))
	for _k in 3:
		_fire()
		_advance(0.6)
	_check(_alive() <= 6, "spredningsskudd: treffer flere i bredden (%d av 8 igjen)" % _alive())
	return true


func _check_damage():
	_setup([], [["elite", 8]])
	_put_enemy(0, Vector2(320, 150))
	_fire()
	_advance(0.6)
	_check(_alive() == 8, "skarpt skyts: basis trenger flere treff på en elite (hp 3)")
	_setup(["damage", "damage"], [["elite", 8]])
	_put_enemy(0, Vector2(320, 150))
	_fire()
	_advance(0.6)
	_check(_alive() == 7, "skarpt skyts: nivå 2 dreper en elite i ett skudd (%d igjen)" % _alive())
	return true


func _check_piercing():
	# To grunts rett over hverandre: uten gjennomtrenging dør bare den nederste.
	_setup([], [["grunt", 8]])
	_put_enemy(0, Vector2(320, 200))
	_put_enemy(1, Vector2(320, 150))
	_fire()
	_advance(0.6)
	_check(_alive() == 7, "gjennomtrenging: basis stopper i første fiende (%d igjen)" % _alive())
	_setup(["piercing"], [["grunt", 8]])
	_put_enemy(0, Vector2(320, 200))
	_put_enemy(1, Vector2(320, 150))
	_put_enemy(2, Vector2(320, 100))
	_fire()
	_advance(0.6)
	_check(_alive() == 6, "gjennomtrenging: nivå 1 går gjennom én ekstra (%d igjen)" % _alive())
	return true


func _check_big_bullets():
	# En fiende 18 px til siden: utenfor en vanlig kule, innenfor en stor.
	_setup([], [["grunt", 8]])
	_put_enemy(0, Vector2(320 + 17, 150))
	_fire()
	_advance(0.6)
	_check(_alive() == 8, "store kuler: basis bommer 17 px til siden")
	_setup(["big_bullets", "big_bullets"], [["grunt", 8]])
	_put_enemy(0, Vector2(320 + 17, 150))
	_fire()
	_advance(0.6)
	_check(_alive() == 7, "store kuler: nivå 2 treffer 17 px til siden (%d igjen)" % _alive())
	return true


func _check_explosion():
	# Tre på rad med 36 px mellom: drapet i midten skal ta naboene med seg.
	_setup(["explosion"], [["grunt", 8]])
	for i in 3:
		_put_enemy(i, Vector2(320 + (i - 1) * 36, 150))
	_fire()
	_advance(0.6)
	_check(_alive() == 5, "eksplosjon: naboene dør med (%d av 8 igjen)" % _alive())
	# Smitter ikke: en fjerde 36 px bortenfor skal overleve.
	_setup(["explosion"], [["grunt", 8]])
	for i in 4:
		_put_enemy(i, Vector2(260 + i * 36, 150))
	main.player.position.x = 296.0
	_fire()
	_advance(0.6)
	_check(_alive() == 5, "eksplosjon: smitter ikke videre (%d av 8 igjen)" % _alive())
	return true


func _check_homing():
	# Én fiende 60 px til siden, høyt oppe: en rett kule bommer, en målsøkende treffer.
	_setup([], [["grunt", 1]])
	_put_enemy(0, Vector2(380, 120))
	_fire()
	_advance(1.0)
	_check(_alive() == 1, "målsøking: basis bommer 60 px til siden")
	_setup(["homing"], [["grunt", 1]])
	_put_enemy(0, Vector2(380, 120))
	_fire()
	_advance(1.0)
	_check(_alive() == 0, "målsøking: nivå 1 svinger inn og treffer")
	return true


func _check_lives():
	_setup([], [["grunt", 8]])
	_check(main.player.lives == 3 and main.player.max_lives() == 5, "liv: basis 3 av maks 5")
	for _i in 3:
		main.player.add_life()
	_check(main.player.lives == 5, "liv: stopper på maks")
	main.upgrades_enabled = true
	main._start_run(2)
	main._set_state(main.State.UPGRADE)
	main.pick_upgrade("hp_up")
	_check(main.player.lives == 4 and main.player.max_lives() == 6, "liv: MER LIV gir +1 nå og +1 maks (%d/%d)"
			% [main.player.lives, main.player.max_lives()])
	_check(main.wave == 2 and main.state == main.State.WAVE_INTRO, "liv: valget starter neste bølge")
	# Helbredelse: +1 ved valg og +1 etter hver bølge.
	main._start_run(3)
	main.player.take_hit()
	main.player.take_hit()
	main._set_state(main.State.UPGRADE)
	main.pick_upgrade("healing")
	_check(main.player.lives == 2, "liv: HELBREDELSE gir +1 nå (%d)" % main.player.lives)
	main.player.invuln = 999.0
	_advance(6.0)
	while _alive() > 0:
		main.swarm.try_hit(_first_alive_pos())
	_check(main.state == main.State.WAVE_CLEAR and main.player.lives == 3, "liv: +1 etter bølgen (%d)" % main.player.lives)
	main.upgrades_enabled = false
	return true


func _check_shield():
	_setup(["potion"], [["grunt", 8]])
	_check(main.player.shield == 1, "skjold: ladet ved bølgestart")
	var lives: int = main.player.lives
	main.player.take_hit()
	_check(main.player.lives == lives and main.player.shield == 0, "skjold: tar første treff uten å koste liv")
	main.player.invuln = 0.0
	main.player.take_hit()
	_check(main.player.lives == lives - 1, "skjold: andre treff koster liv")
	main._start_wave(2)
	_check(main.player.shield == 1, "skjold: lades igjen neste bølge")
	return true


func _check_thorns():
	# Treff på spilleren: alle fiender innen radius tar 2 skade, kulene forsvinner.
	_setup(["thorns"], [["skytter", 8]])
	_put_enemy(0, Vector2(320, 260))     # nær: dør (hp 2)
	_put_enemy(1, Vector2(320, 60))      # langt unna: overlever
	main.bullets.spawn_enemy_bullet(Vector2(100, 100))
	main.bullets.spawn_enemy_bullet(Vector2(500, 100))
	main.player.take_hit()
	_check(_alive() == 7, "pigger: fienden nær spilleren dør (%d igjen)" % _alive())
	_check(main.bullets.enemy_bullet_count() == 0, "pigger: fiendekulene forsvinner")
	_check(main.swarm.enemies[1]["alive"], "pigger: fienden langt unna lever")
	return true


func _check_size_and_speed():
	_setup([], [["grunt", 8]])
	main.player.invuln = 0.0
	_check(main.player.hit_test(main.player.position + Vector2(10, 0)), "størrelse: basis treffes 10 px fra midten")
	_setup(["size_down"], [["grunt", 8]])
	main.player.invuln = 0.0
	_check(not main.player.hit_test(main.player.position + Vector2(10, 0)), "størrelse: MINDRE SKIP treffes ikke 10 px fra midten")
	_check(main.player.scale.x < 1.0, "størrelse: skipet tegnes mindre")
	_setup([], [["grunt", 8]])
	main.player.autopilot = {"dir": 1.0, "fire": false}
	_advance(0.5)
	var base_dx: float = main.player.position.x - 320.0
	_setup(["move_speed"], [["grunt", 8]])
	main.player.autopilot = {"dir": 1.0, "fire": false}
	_advance(0.5)
	var fast_dx: float = main.player.position.x - 320.0
	main.player.autopilot = null
	_check(fast_dx > base_dx * 1.2, "fart: RAKETTSTØVLER er raskere (%.0f mot %.0f px)" % [fast_dx, base_dx])
	return true


func _check_screen():
	main.upgrades_enabled = true
	main._start_run(5)
	main._set_state(main.State.UPGRADE)
	var screen = main.upgrade_screen
	_check(screen.visible and screen.active and screen.offer.size() == 3, "skjerm: vises med tre kort")
	_check(screen.selected == 1, "skjerm: starter på midterste kort")
	screen._move(1)
	_check(screen.selected == 2, "skjerm: høyre flytter markøren")
	screen._move(1)
	_check(screen.selected == 2, "skjerm: stopper på kanten")
	# Autovalg etter tida.
	main._process(screen.AUTO_PICK_TIME + 0.1)
	_check(not screen.active and main.wave == 2, "skjerm: autovalg etter %d s" % int(screen.AUTO_PICK_TIME))
	_check(main.stats.taken.size() == 1, "skjerm: autovalget tok ett kort")
	main.upgrades_enabled = false
	return true


# ---------------------------------------------------------------------------
# Hjelpere
# ---------------------------------------------------------------------------

func _first_alive_pos() -> Vector2:
	for e in main.swarm.enemies:
		if e["alive"]:
			return e["sprite"].position
	return Vector2.ZERO


func _unique(ids: Array) -> bool:
	var seen := {}
	for id in ids:
		if seen.has(id):
			return false
		seen[id] = true
	return true


func _has_rare(ids: Array) -> bool:
	for id in ids:
		if Upgrades.CATALOG[id]["rarity"] != "common":
			return true
	return false


func _check(ok: bool, what: String) -> void:
	checks += 1
	if ok:
		print("  ok   ", what)
	else:
		failures += 1
		print("  FEIL ", what)
