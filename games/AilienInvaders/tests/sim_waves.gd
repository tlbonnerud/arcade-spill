extends Node

# Balansesimulator: en bot spiller bølgene mange ganger i hurtigtid og måler
# hvor vanskelige de er. Brukes til å stille tallene i waves/waves.gd.
#
#   cd games/AilienInvaders
#   ../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/sim_waves.tscn
#
# Miljøvariabler:
#   AILIEN_SIM_RUNS   forsøk per bølge / antall hele runs (standard 10)
#   AILIEN_SIM_WAVES  "1-10", "4,7" ... (standard alle)
#   AILIEN_SIM_SKILL  average | good | perfect (standard good)
#   AILIEN_SIM_MODE   waves | run | both (standard both)
#   AILIEN_SIM_JSON   fil som får resultatene som JSON
#
# "waves": hver bølge for seg, med 3 friske liv. Viser bølgens egen vanskelighet.
# "run":   hele spillet fra bølge 1 med 3 liv, slik spilleren opplever det.
#
# Boten er en modell av en menneskelig spiller, ikke en perfekt maskin:
# den reagerer med forsinkelse, ser bare kuler et stykke fram, overser noen,
# og sikter litt feil. "good" skal ligne en øvet arkadespiller.

const MainScene := preload("res://games/ailien_invaders/main.tscn")
const Waves := preload("res://games/ailien_invaders/waves/waves.gd")

const DT := 1.0 / 60.0
const WAVE_TIMEOUT := 300.0
const RUN_TIMEOUT := 1800.0
const PLAYER_SPEED := 220.0
const PLAYER_BULLET_SPEED := 420.0

const SKILLS := {
	"average": {"react": 0.18, "look": 0.55, "blind": 0.14, "aim_noise": 8.0, "fire_delay": 0.18},
	"good":    {"react": 0.10, "look": 0.70, "blind": 0.05, "aim_noise": 4.0, "fire_delay": 0.10},
	"perfect": {"react": 0.0,  "look": 1.00, "blind": 0.0,  "aim_noise": 0.0, "fire_delay": 0.02},
}

var main: Node2D
var skill := {}
var skill_name := "good"
var bot_rng := RandomNumberGenerator.new()
var hit_bottom := false
var hits_by_bullet := 0
var hits_by_diver := 0

# Bot-tilstand
var decide_t := 0.0
var fire_cd := 0.0
var target_x := 320.0
var aim_x := 320.0
var prev_pos := {}
var vel := {}


func _ready() -> void:
	skill_name = _env("AILIEN_SIM_SKILL", "good")
	skill = SKILLS.get(skill_name, SKILLS["good"])
	main = MainScene.instance()
	add_child(main)
	call_deferred("_run")


func _run() -> void:
	yield(get_tree(), "idle_frame")
	main.set_process(false)
	main.save_scores = false
	main.swarm.connect("reached_bottom", self, "_on_reached_bottom")

	var runs := int(_env("AILIEN_SIM_RUNS", "10"))
	var mode := _env("AILIEN_SIM_MODE", "both")
	var waves := _parse_waves(_env("AILIEN_SIM_WAVES", ""))
	var result := {"skill": skill_name, "runs": runs, "waves": [], "full_runs": {}}

	if mode in ["waves", "both"]:
		print("== Hver bølge for seg, 3 liv, bot '%s', %d forsøk ==" % [skill_name, runs])
		print("bølge  fiender  klart%  snitt-tid  liv-tapt  (kule/dykker)  bunn%  død%  igjen  verste kombinasjon")
		for n in waves:
			var stats := []
			for r in runs:
				stats.append(_play_wave(n, 1000 * n + r))
				yield(get_tree(), "idle_frame")
			result["waves"].append(_report_wave(n, stats))

	if mode in ["run", "both"]:
		print("== Hele spillet fra bølge 1, 3 liv, bot '%s', %d runs ==" % [skill_name, runs])
		var reached := []
		var wins := 0
		var times := []
		for r in runs:
			var res := _play_run(50000 + r)
			reached.append(res["wave"])
			if res["won"]:
				wins += 1
				times.append(res["time"])
			yield(get_tree(), "idle_frame")
		reached.sort()
		var histogram := {}
		for w in reached:
			histogram[w] = histogram.get(w, 0) + 1
		print("vant: %d/%d   median bølge nådd: %d   fordeling (bølge: antall): %s"
				% [wins, runs, reached[reached.size() / 2], str(histogram)])
		if times.size() > 0:
			print("snitt-tid for seier: %.0f s" % _mean(times))
		result["full_runs"] = {"wins": wins, "runs": runs, "reached": reached,
				"mean_win_time": _mean(times) if times.size() > 0 else 0.0}

	var json_path := _env("AILIEN_SIM_JSON", "")
	if json_path != "":
		var f := File.new()
		if f.open(json_path, File.WRITE) == OK:
			f.store_string(JSON.print(result, "  "))
			f.close()
	get_tree().quit(0)


# ---------------------------------------------------------------------------
# Spilling
# ---------------------------------------------------------------------------

func _play_wave(n: int, seed_value: int) -> Dictionary:
	main._start_run(seed_value)
	main.rng.seed = seed_value
	main._start_wave(n)
	_reset_bot(seed_value)
	var lives_start: int = main.player.lives
	var t := 0.0
	while t < WAVE_TIMEOUT and (main.state == main.State.WAVE_INTRO or main.state == main.State.WAVE):
		_tick()
		t += DT
	var cleared: bool = main.state == main.State.WAVE_CLEAR or main.state == main.State.VICTORY
	var c: Dictionary = main.swarm.wave_data["chosen"]
	return {
		"cleared": cleared,
		"time": t,
		"lives_lost": lives_start - main.player.lives,
		"bottom": hit_bottom,
		"died": main.state == main.State.GAME_OVER and not hit_bottom,
		"timeout": t >= WAVE_TIMEOUT,
		"by_bullet": hits_by_bullet,
		"by_diver": hits_by_diver,
		"alive_left": main.swarm.alive_count(),
		"combo": "%s/%s/%s" % [c["formation"], c["entry"], c["movement"]],
	}


func _play_run(seed_value: int) -> Dictionary:
	main._start_run(seed_value)
	_reset_bot(seed_value)
	var t := 0.0
	while t < RUN_TIMEOUT and main.state != main.State.GAME_OVER and main.state != main.State.VICTORY:
		_tick()
		t += DT
	return {"won": main.state == main.State.VICTORY, "wave": main.wave, "time": t}


# Ett spillsteg: boten bestemmer seg, spillet går 1/60 s fram. Teller også
# hva som traff spilleren (kule eller dykker).
func _tick() -> void:
	_bot_step()
	var lives_before: int = main.player.lives
	var divers_near := false
	for p in main.swarm.diver_positions():
		if abs(p.x - main.player.position.x) < 40.0 and abs(p.y - main.player.position.y) < 40.0:
			divers_near = true
	main._process(DT)
	if main.player.lives < lives_before:
		if divers_near:
			hits_by_diver += 1
		else:
			hits_by_bullet += 1


func _on_reached_bottom() -> void:
	hit_bottom = true


# ---------------------------------------------------------------------------
# Boten
# ---------------------------------------------------------------------------

func _reset_bot(seed_value: int) -> void:
	bot_rng.seed = seed_value * 7 + 13
	hit_bottom = false
	hits_by_bullet = 0
	hits_by_diver = 0
	decide_t = 0.0
	fire_cd = 0.0
	target_x = 320.0
	aim_x = 320.0
	prev_pos.clear()
	vel.clear()


func _bot_step() -> void:
	var player = main.player
	var swarm = main.swarm
	var bullets = main.bullets
	var px: float = player.position.x
	var py: float = player.position.y

	# Fartsanslag per fiende (glattet), for å sikte foran dem.
	for e in swarm.enemies:
		if not e["alive"]:
			continue
		var id: int = e["sprite"].get_instance_id()
		var p: Vector2 = e["sprite"].position
		if prev_pos.has(id):
			var v: Vector2 = (p - prev_pos[id]) / DT
			vel[id] = vel.get(id, v).linear_interpolate(v, 0.3)
		prev_pos[id] = p

	decide_t -= DT
	if decide_t <= 0.0:
		decide_t = skill["react"]
		aim_x = _pick_aim(px, py) + bot_rng.randf_range(-skill["aim_noise"], skill["aim_noise"])
		target_x = _pick_position(px, py, aim_x)

	var dir := 0.0
	if abs(target_x - px) > 2.5:
		dir = sign(target_x - px)

	var fire := false
	if bullets.player_bullet_active:
		fire_cd = skill["fire_delay"]
	else:
		fire_cd -= DT
		if fire_cd <= 0.0 and _lined_up(px, py):
			fire = true
	player.autopilot = {"dir": dir, "fire": fire}


# Hvor vil vi stå for å treffe? Foretrekker lave fiender (de er farligst).
func _pick_aim(px: float, py: float) -> float:
	var best_x := px
	var best_score := -1e9
	for e in main.swarm.enemies:
		if not e["alive"] or e["diving"]:
			continue  # dykkere jager vi ikke, dem holder vi oss unna
		var p: Vector2 = e["sprite"].position
		if p.y < 0 or p.y > py - 20:
			continue
		var x := _lead_x(e, py)
		var s: float = p.y - abs(x - px) * 0.35
		if s > best_score:
			best_score = s
			best_x = x
	return clamp(best_x, 20.0, 620.0)


func _lead_x(e: Dictionary, py: float) -> float:
	var p: Vector2 = e["sprite"].position
	var v: Vector2 = vel.get(e["sprite"].get_instance_id(), Vector2.ZERO)
	var flight: float = max(0.0, (py - 12.0 - p.y) / PLAYER_BULLET_SPEED)
	return p.x + v.x * flight


func _lined_up(px: float, py: float) -> bool:
	for e in main.swarm.enemies:
		if not e["alive"]:
			continue
		var p: Vector2 = e["sprite"].position
		if p.y < -10 or p.y > py - 20:
			continue
		if abs(_lead_x(e, py) - px) < 7.0:
			return true
	return false


# Velger et x som unngår kuler og dykkere, og ellers ligger nær aim_x.
func _pick_position(px: float, py: float, want_x: float) -> float:
	var threats := []  # {t0, t1, lo, hi}
	for b in main.bullets.enemy_bullets:
		var vy: float = b["vel"].y
		if vy <= 1.0:
			continue
		if not b.has("_seen"):
			b["_seen"] = bot_rng.randf() >= skill["blind"]
		if not b["_seen"]:
			continue
		var t0: float = (py - 12.0 - b["pos"].y) / vy
		var t1: float = (py + 12.0 - b["pos"].y) / vy
		if t1 < 0.0 or t0 > skill["look"]:
			continue
		t0 = max(t0, 0.0)
		var x0: float = b["pos"].x + b["vel"].x * t0
		var x1: float = b["pos"].x + b["vel"].x * t1
		threats.append({"t0": t0, "t1": t1, "lo": min(x0, x1) - 17.0, "hi": max(x0, x1) + 17.0})
	# Dykkere: et menneske ser banen og skjønner hvor dykket ender, så boten
	# får lese målet. Farlig rundt målet fra like før ankomst til dykkeren
	# har trukket seg opp igjen (den sveiper litt sideveis i bunnen).
	for d in main.swarm.divers:
		if not d["alive"]:
			continue
		var dive: Dictionary = d["dive"]
		var tx: float = dive["target"].x
		if dive["phase"] == 0:
			var arrival: float = (1.0 - dive["t"]) * main.swarm.DIVE_DOWN_TIME
			threats.append({"t0": max(0.0, arrival - 0.2), "t1": arrival + 0.4,
					"lo": tx - 42.0, "hi": tx + 42.0})
		elif dive["t"] < 0.3:
			var sweep: float = tx - dive["side"] * 45.0
			threats.append({"t0": 0.0, "t1": 0.4, "lo": min(tx, sweep) - 40.0, "hi": max(tx, sweep) + 40.0})

	if threats.empty():
		return want_x

	var best_x := px
	var best_cost := 1e12
	var x := 20.0
	while x <= 620.0:
		var cost: float = abs(x - want_x) * 1.0 + abs(x - px) * 0.2
		var move_dir: float = sign(x - px)
		var reach: float = abs(x - px) / PLAYER_SPEED
		for th in threats:
			for k in 3:
				var tau: float = lerp(th["t0"], th["t1"], k / 2.0)
				var pos_at: float = px + move_dir * PLAYER_SPEED * min(tau, reach)
				if pos_at > th["lo"] and pos_at < th["hi"]:
					cost += 2000.0 / (0.15 + th["t0"])
					break
		if cost < best_cost:
			best_cost = cost
			best_x = x
		x += 6.0
	return best_x


# ---------------------------------------------------------------------------
# Rapport
# ---------------------------------------------------------------------------

func _report_wave(n: int, stats: Array) -> Dictionary:
	var cleared := 0
	var bottom := 0
	var died := 0
	var times := []
	var lost := []
	var by_bullet := []
	var by_diver := []
	var left := []
	var combos := {}
	for s in stats:
		by_bullet.append(s["by_bullet"])
		by_diver.append(s["by_diver"])
		if not s["cleared"]:
			left.append(s["alive_left"])
		if s["cleared"]:
			cleared += 1
			times.append(s["time"])
		if s["bottom"]:
			bottom += 1
		if s["died"]:
			died += 1
		lost.append(s["lives_lost"])
		var c: Dictionary = combos.get(s["combo"], {"n": 0, "cleared": 0, "lost": 0})
		c["n"] += 1
		c["lost"] += s["lives_lost"]
		if s["cleared"]:
			c["cleared"] += 1
		combos[s["combo"]] = c
	var worst := ""
	var worst_lost := -1.0
	for key in combos:
		var avg: float = float(combos[key]["lost"]) / combos[key]["n"]
		if avg > worst_lost:
			worst_lost = avg
			worst = "%s (%.1f liv, %d/%d klart)" % [key, avg, combos[key]["cleared"], combos[key]["n"]]
	var count: int = Waves.enemy_count(Waves.get_wave(n))
	var total := float(stats.size())
	print("%5d  %7d  %5.0f%%  %8.1fs  %8.2f  (%4.2f/%4.2f)    %4.0f%%  %3.0f%%  %5.1f  %s" % [n, count,
			100.0 * cleared / total, _mean(times), _mean(lost), _mean(by_bullet), _mean(by_diver),
			100.0 * bottom / total, 100.0 * died / total, _mean(left), worst])
	return {"wave": n, "enemies": count, "clear_rate": cleared / total, "mean_time": _mean(times),
			"mean_lives_lost": _mean(lost), "by_bullet": _mean(by_bullet),
			"by_diver": _mean(by_diver), "mean_alive_left_when_lost": _mean(left), "bottom_rate": bottom / total, "death_rate": died / total,
			"combos": combos}


func _mean(values: Array) -> float:
	if values.empty():
		return 0.0
	var sum := 0.0
	for v in values:
		sum += v
	return sum / values.size()


func _parse_waves(spec: String) -> Array:
	var out := []
	if spec == "":
		for n in range(1, Waves.count() + 1):
			out.append(n)
		return out
	for part in spec.split(","):
		if "-" in part:
			var ends: Array = part.split("-")
			for n in range(int(ends[0]), int(ends[1]) + 1):
				out.append(n)
		else:
			out.append(int(part))
	return out


func _env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if v != "" else fallback
