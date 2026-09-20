extends Node2D

# Bølgemotoren. Leser én rad fra waves/waves.gd, bygger fiendene, kjører
# innflygingen, flytter formasjonen etter valgt mønster, lar eliter dykke,
# velger hvem som skyter og håndterer treff. Sier fra via signaler.
#
# Erstatter den gamle swarm.gd. Samme grensesnitt mot main og bullets:
# spawn / animate / step / try_hit / alive_count, pluss entry_finished og
# diver_positions() for kontakt mellom dykkere og spiller.
#
# Fiendene lever i lista `enemies` som dictionaries; sprite-posisjoner er
# absolutte skjermkoordinater (noden selv står i origo).

signal enemy_killed(points)
signal cleared                    # alle fiender i bølgen er døde
signal reached_bottom             # formasjonen nådde spillerens høyde
signal entry_finished             # alle gjenlevende er på plass, bølgen kan begynne
signal fire_requested(pos, kind, dir)  # en fiende vil skyte; dir er enhetsvektor

const EnemyTypes := preload("res://games/ailien_invaders/enemies/enemy_types.gd")
const Formations := preload("res://games/ailien_invaders/enemies/formations.gd")
const Entries := preload("res://games/ailien_invaders/enemies/entry_patterns.gd")
const Movements := preload("res://games/ailien_invaders/enemies/movement_patterns.gd")
const Waves := preload("res://games/ailien_invaders/waves/waves.gd")

const BOTTOM_LIMIT := Movements.BOTTOM_LIMIT
const ANIM_INTERVAL := 0.35
const HIT_HALF_SIZE := Vector2(14, 12)
const MUZZLE_OFFSET := Vector2(0, 12)
const FLASH_TIME := 0.08
const FLASH_COLOR := Color(1.0, 0.35, 0.35)
const DIVE_DOWN_TIME := 1.0
const DIVE_UP_TIME := 1.3
const DIVE_TARGET_Y := 320.0   # like over spillerens høyde
const MIN_DOWNWARD := 0.35     # siktede kuler går aldri rett sidelengs
const MIN_FIRE_WINDOW := 0.4   # s fra munning til spillerens treffboks; fiender som er lavere enn det skyter ikke
const ENEMY_BULLET_SPEED := 150.0  # samme som core/bullets.gd

var area_size := Vector2(640, 360)
var wave := 1
var wave_data := {}
var enemies := []            # se _make_enemy
var total := 0
var move_state := {}          # tilstanden til bevegelsesmønsteret (enemies/movement_patterns.gd)
var entering := false
var anim_timer := 0.0
var fire_timer := 1.5
var dive_timer := 0.0
var divers := []             # fiender (dictionaries fra enemies) som dykker nå
var player_pos := Vector2(320, 330)
var rng := RandomNumberGenerator.new()


func setup(size: Vector2) -> void:
	area_size = size
	rng.randomize()


# Bygger bølge wave_number. rng gir reproduserbare valg fra poolene.
func spawn(wave_number: int, run_rng: RandomNumberGenerator = null) -> void:
	spawn_data(wave_number, Waves.get_wave(wave_number), run_rng)


# Bygger en bølge fra en ferdig utfylt rad (se Waves.with_defaults). Tester
# bruker denne til å tvinge fram bestemte mønstre.
func spawn_data(wave_number: int, data: Dictionary, run_rng: RandomNumberGenerator = null) -> void:
	wave = wave_number
	if run_rng != null:
		rng = run_rng
	wave_data = data

	for child in get_children():
		remove_child(child)
		child.queue_free()
	enemies.clear()
	divers.clear()
	entering = true
	fire_timer = 1.5
	dive_timer = wave_data["dive_interval"]

	var type_ids := []
	for pair in wave_data["enemies"]:
		for _i in int(pair[1]):
			type_ids.append(pair[0])
	total = type_ids.size()

	# Trekk fra poolene. Valgene lagres så tester og feilsøking kan se dem.
	wave_data["chosen"] = {
		"formation": _pick(wave_data["formations"]),
		"entry": _pick(wave_data["entries"]),
		"movement": _pick(wave_data["movements"]),
	}
	var slots: Array = Formations.build(wave_data["chosen"]["formation"], total, area_size)
	var entries: Array = Entries.build(wave_data["chosen"]["entry"], slots, area_size, rng)
	move_state = Movements.start(wave_data["chosen"]["movement"], area_size,
			slots, wave_data["descent_time"])

	# Typene fyller formasjonen ovenfra, og innenfor en rad fra midten og ut.
	# Da blir fargene speilsymmetriske også når en type tar slutt midt i en rad.
	var order := _fill_order(slots)
	var type_of := []
	type_of.resize(total)
	for k in total:
		type_of[order[k]] = type_ids[k]
	for i in total:
		enemies.append(_make_enemy(type_of[i], slots[i], entries[i]))


# Plassindekser i rekkefølgen typene skal fylle dem: rad for rad ovenfra
# (plassene er alt sortert slik), og innenfor raden nærmest midten først.
func _fill_order(slots: Array) -> Array:
	var cx := area_size.x / 2
	var order := []
	var i := 0
	while i < slots.size():
		var row := [i]
		var j := i + 1
		while j < slots.size() and abs(slots[j].y - slots[i].y) < 1.0:
			# Sett inn sortert på avstand fra midten (radene er korte).
			var k := row.size()
			while k > 0 and abs(slots[row[k - 1]].x - cx) > abs(slots[j].x - cx):
				k -= 1
			row.insert(k, j)
			j += 1
		order += row
		i = j
	return order


func _pick(pool: Array):
	return pool[rng.randi() % pool.size()]


func _make_enemy(type_id: String, slot: Vector2, entry: Dictionary) -> Dictionary:
	var type: Dictionary = EnemyTypes.get_type(type_id)
	var s := Sprite.new()
	s.texture = type["texture"]
	s.hframes = EnemyTypes.frame_count(type)
	s.frame = rng.randi() % s.hframes
	s.position = entry["start"]
	add_child(s)
	return {
		"sprite": s,
		"type": type_id,
		"hp": int(max(1, round(type["hp"] * wave_data["hp_mult"]))),
		"points": type["points"],
		"bullet": type["bullet"],
		"aimed": type["aimed"],
		"can_dive": _can_dive(type_id, type),
		"fire_weight": type["fire_weight"],
		"alive": true,
		"slot": slot,
		"entry": entry,
		"entry_t": 0.0,
		"entered": false,
		"diving": false,
		"dive": {},
		"flash": 0.0,
	}


# Bølgen kan overstyre hvem som dykker med "dive_types"; ellers gjelder typen.
func _can_dive(type_id: String, type: Dictionary) -> bool:
	var allowed: Array = wave_data["dive_types"]
	if allowed.empty():
		return type["can_dive"]
	return type_id in allowed


# ---------------------------------------------------------------------------
# Spørringer
# ---------------------------------------------------------------------------

func alive_count() -> int:
	var n := 0
	for e in enemies:
		if e["alive"]:
			n += 1
	return n


func is_entering() -> bool:
	return entering


# Posisjonene til fiender som dykker, for kontaktsjekk mot spilleren.
func diver_positions() -> Array:
	var out := []
	for d in divers:
		if d["alive"]:
			out.append(d["sprite"].position)
	return out


# Hvor fiendens plass i formasjonen er akkurat nå (der den står, eller skal
# tilbake til etter et dykk).
func slot_position(e: Dictionary) -> Vector2:
	return Movements.place(move_state, e["slot"])


func enemy_positions() -> Array:
	var out := []
	for e in enemies:
		if e["alive"]:
			out.append(e["sprite"].position)
	return out


# ---------------------------------------------------------------------------
# Per frame
# ---------------------------------------------------------------------------

# Sprite-animasjon og treff-blink. Kjører også under game over.
func animate(delta: float) -> void:
	anim_timer += delta
	var advance := anim_timer >= ANIM_INTERVAL
	if advance:
		anim_timer = 0.0
	for e in enemies:
		if not e["alive"]:
			continue
		var s: Sprite = e["sprite"]
		if advance:
			s.frame = (s.frame + 1) % s.hframes
		if e["flash"] > 0.0:
			e["flash"] -= delta
			if e["flash"] <= 0.0:
				s.modulate = Color.white


# Bevegelse, dykk og skyting. fire_allowed settes av main (tak på kuler).
func step(delta: float, fire_allowed: bool, player_position: Vector2) -> void:
	player_pos = player_position
	if entering:
		_step_entry(delta)
		return
	_step_movement(delta)
	_step_dive(delta)
	_fire(delta, fire_allowed)


func _step_entry(delta: float) -> void:
	var all_in := true
	for e in enemies:
		if not e["alive"] or e["entered"]:
			continue
		var entry: Dictionary = e["entry"]
		e["entry_t"] += delta
		var u: float = (e["entry_t"] - entry["delay"]) / entry["duration"]
		if u <= 0.0:
			e["sprite"].position = entry["start"]
			all_in = false
		elif u >= 1.0:
			e["sprite"].position = e["slot"]
			e["entered"] = true
		else:
			e["sprite"].position = Entries.point(entry, e["slot"], u)
			all_in = false
	if all_in:
		entering = false
		emit_signal("entry_finished")


func _step_movement(delta: float) -> void:
	# Ytterste levende plasser, også dykkernes: plassen deres hører fortsatt
	# til formasjonen. Uten dem kunne formasjonen vandre ut mens en kantfiende
	# dykket, og så rykke tilbake i ett hopp når den landet.
	var min_x := area_size.x
	var max_x := 0.0
	var alive := 0
	for e in enemies:
		if e["alive"]:
			alive += 1
			min_x = min(min_x, e["slot"].x)
			max_x = max(max_x, e["slot"].x)
	var ctx := {
		"dead_frac": 1.0 - float(alive) / max(1, total),
		"speed_mult": wave_data["speed_mult"],
		"min_x": min_x,
		"max_x": max_x,
	}
	Movements.step(move_state, delta, ctx)
	var lowest := 0.0
	for e in enemies:
		if e["alive"] and not e["diving"]:
			var p: Vector2 = Movements.place(move_state, e["slot"])
			e["sprite"].position = p
			lowest = max(lowest, p.y)
	# Formasjonen (ikke dykkere) har nådd spillerens høyde.
	if lowest >= BOTTOM_LIMIT:
		emit_signal("reached_bottom")


# ---------------------------------------------------------------------------
# Dykk: en fiende forlater plassen, stuper mot spilleren i en bue og flyr
# tilbake til plassen sin (som kan ha flyttet seg). Faren er kroppen. Bølgen
# bestemmer hvor ofte (dive_interval) og hvor mange samtidig (max_divers).
# ---------------------------------------------------------------------------

func _step_dive(delta: float) -> void:
	if wave_data["dives"] and divers.size() < int(wave_data["max_divers"]):
		dive_timer -= delta
		if dive_timer <= 0.0:
			dive_timer = wave_data["dive_interval"]
			_start_dive()

	for e in divers.duplicate():
		if not e["alive"]:
			divers.erase(e)
			continue
		_step_diver(e, delta)


func _step_diver(e: Dictionary, delta: float) -> void:
	var d: Dictionary = e["dive"]
	var s: Sprite = e["sprite"]
	if d["phase"] == 0:
		d["t"] += delta / DIVE_DOWN_TIME
		s.position = _bezier(d["p0"], d["ctrl"], d["target"], min(d["t"], 1.0))
		if d["t"] >= 1.0:
			# Dykkeren skyter ikke i bunnen: munningen ville ligget i spillerens
			# rad, og en kule derfra er enten ufarlig eller umulig å unngå.
			d["phase"] = 1
			d["t"] = 0.0
			d["p0"] = d["target"]
			d["ctrl"] = Vector2(d["target"].x - d["side"] * 160.0, (d["target"].y + e["slot"].y) / 2)
	else:
		d["t"] += delta / DIVE_UP_TIME
		s.position = _bezier(d["p0"], d["ctrl"], slot_position(e), min(d["t"], 1.0))
		if d["t"] >= 1.0:
			e["diving"] = false
			divers.erase(e)


func _start_dive() -> void:
	var candidates := []
	for e in enemies:
		if e["alive"] and e["can_dive"] and not e["diving"]:
			candidates.append(e)
	if candidates.empty():
		return
	var e: Dictionary = candidates[rng.randi() % candidates.size()]
	var p0: Vector2 = e["sprite"].position
	var side := 1.0 if p0.x < area_size.x / 2 else -1.0
	var target := Vector2(clamp(player_pos.x + rng.randf_range(-30.0, 30.0), 30.0, area_size.x - 30.0), DIVE_TARGET_Y)
	e["diving"] = true
	e["dive"] = {
		"phase": 0,
		"t": 0.0,
		"side": side,
		"p0": p0,
		"ctrl": Vector2(p0.x + side * 160.0, (p0.y + target.y) / 2),
		"target": target,
	}
	divers.append(e)


static func _bezier(p0: Vector2, ctrl: Vector2, p2: Vector2, u: float) -> Vector2:
	var t := u * u * (3.0 - 2.0 * u)
	var it := 1.0 - t
	return it * it * p0 + 2.0 * it * t * ctrl + t * t * p2


# ---------------------------------------------------------------------------
# Skyting
# ---------------------------------------------------------------------------

func _fire(delta: float, allowed: bool) -> void:
	fire_timer -= delta
	if fire_timer <= 0.0 and allowed:
		fire_timer = rng.randf_range(0.6, 1.4) / wave_data["fire_rate_mult"]
		var e := _pick_shooter()
		if not e.empty():
			_fire_from(e)


# Vektet trekning blant fiender i formasjonen.
func _pick_shooter() -> Dictionary:
	var sum := 0.0
	for e in enemies:
		if e["alive"] and e["entered"] and not e["diving"] and _can_fire(e):
			sum += e["fire_weight"]
	if sum <= 0.0:
		return {}
	var r := rng.randf() * sum
	for e in enemies:
		if e["alive"] and e["entered"] and not e["diving"] and _can_fire(e):
			r -= e["fire_weight"]
			if r <= 0.0:
				return e
	return {}


# En kule må være i lufta lenge nok til at spilleren kan reagere. Fiender
# som står så lavt at kula når treffboksen på under MIN_FIRE_WINDOW sekunder
# holder ilden (som de nederste radene i Space Invaders).
func _can_fire(e: Dictionary) -> bool:
	var speed: float = ENEMY_BULLET_SPEED * wave_data["bullet_speed_mult"]
	var muzzle_y: float = e["sprite"].position.y + MUZZLE_OFFSET.y
	return (DIVE_TARGET_Y - muzzle_y) / speed >= MIN_FIRE_WINDOW


func _fire_from(e: Dictionary) -> void:
	var pos: Vector2 = e["sprite"].position + MUZZLE_OFFSET
	var dir := Vector2.DOWN
	if e["aimed"]:
		dir = (player_pos - pos).normalized()
		dir.y = max(dir.y, MIN_DOWNWARD)
		dir = dir.normalized()
	emit_signal("fire_requested", pos, e["bullet"], dir)


# ---------------------------------------------------------------------------
# Treff
# ---------------------------------------------------------------------------

# Prøver å treffe en fiende i punktet p. Returnerer true hvis noen ble truffet.
func try_hit(p: Vector2) -> bool:
	var hit := false
	var killed := false
	for e in enemies:
		if not e["alive"]:
			continue
		var ep: Vector2 = e["sprite"].position
		if abs(p.x - ep.x) < HIT_HALF_SIZE.x and abs(p.y - ep.y) < HIT_HALF_SIZE.y:
			hit = true
			e["hp"] -= 1
			if e["hp"] <= 0:
				e["alive"] = false
				e["sprite"].visible = false
				emit_signal("enemy_killed", e["points"])
				killed = true
			else:
				e["flash"] = FLASH_TIME
				e["sprite"].modulate = FLASH_COLOR
			break

	# Signalet sendes etter løkka: mottakeren kan kalle spawn() og bytte ut lista.
	if killed and alive_count() == 0:
		emit_signal("cleared")
	return hit
