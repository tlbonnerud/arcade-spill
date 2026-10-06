extends Node

# Kontraktstest for mønstrene i enemies/ og bølgene i waves/.
#
#   cd games/AilienInvaders
#   AILIEN_CHECK=formations ../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/check_patterns.tscn
#
# AILIEN_CHECK: formations | entries | movements | waves | all (standard).
# AILIEN_WAVES_JSON: fil med bølgerader som "waves" sjekker i stedet for waves.gd.
# Hver modus laster bare sin egen fil (pluss syntetiske plasser), så en feil i
# én mønsterfil ikke velter testen for de andre. "waves" laster alt og sjekker
# hver kombinasjon bølgene faktisk kan trekke.
# Avslutter med kode 0 (OK) eller 1 (feil).
#
# NB om Godot 3: en skriptfeil avbryter bare funksjonen den skjer i, og den
# som kalte får null tilbake og fortsetter. Derfor returnerer hver sjekk true
# til slutt, og den som kaller regner "ikke true" som feil. Slik kan testen
# aldri melde OK fordi en sjekk krasjet halvveis. En vaktbikkje avslutter med
# kode 1 hvis selve _ready skulle bli avbrutt.

const AREA := Vector2(640, 360)
const DT := 1.0 / 60.0
const COUNTS := [8, 12, 16, 20, 24, 28, 32, 36, 40]
const BASE := "res://games/ailien_invaders/"

const WATCHDOG_FRAMES := 120  # _ready er synkron; kommer vi hit har den krasjet

var failures := 0
var checks := 0
var frames := 0


func _ready() -> void:
	var mode := OS.get_environment("AILIEN_CHECK")
	if mode == "":
		mode = "all"
	if not (mode in ["formations", "entries", "movements", "waves", "all"]):
		_fail("ukjent AILIEN_CHECK '%s'" % mode)
	if mode in ["formations", "all"] and not _check_formations():
		_fail("formations: sjekken ble avbrutt av en skriptfeil")
	if mode in ["entries", "all"] and not _check_entries():
		_fail("entries: sjekken ble avbrutt av en skriptfeil")
	if mode in ["movements", "all"] and not _check_movements():
		_fail("movements: sjekken ble avbrutt av en skriptfeil")
	if mode in ["waves", "all"] and not _check_waves():
		_fail("waves: sjekken ble avbrutt av en skriptfeil")
	if checks == 0:
		_fail("ingen sjekker ble kjørt")
	if failures == 0:
		print("OK: %d sjekker (%s)" % [checks, mode])
		get_tree().quit(0)
	else:
		print("FEIL: %d av %d sjekker feilet (%s)" % [failures, checks, mode])
		get_tree().quit(1)


func _process(_delta: float) -> void:
	frames += 1
	if frames > WATCHDOG_FRAMES:
		print("FEIL: testen ble avbrutt av en skriptfeil før den rakk å avslutte")
		get_tree().quit(1)


# Laster et skript og sjekker at det faktisk kompilerte. load() gir et
# objekt også for et skript med parsefeil, så null-sjekk er ikke nok.
func _load_script(path: String):
	var script = load(BASE + path)
	if script == null or not (script is Script) or not script.can_instance():
		_fail("%s lar seg ikke laste/kompilere" % path)
		return null
	return script


# ---------------------------------------------------------------------------
# Formasjoner
# ---------------------------------------------------------------------------

func _check_formations() -> bool:
	var F = _load_script("enemies/formations.gd")
	if F == null:
		return true
	for name in F.NAMES:
		for n in COUNTS:
			if not _check_formation(F, name, n):
				_fail("formasjon %s n=%d: sjekken ble avbrutt av en skriptfeil" % [name, n])
	return true


func _check_formation(F, name: String, n: int) -> bool:
	var tag := "formasjon %s n=%d" % [name, n]
	var slots: Array = F.build(name, n, AREA)
	if not _ok(slots.size() == n, "%s: %d plasser (fikk %d)" % [tag, n, slots.size()]):
		return true
	var sum_x := 0.0
	var sorted := true
	var in_bounds := true
	var worst := ""
	for i in n:
		var s: Vector2 = slots[i]
		sum_x += s.x
		if s.x < F.SIDE_MARGIN - 0.5 or s.x > AREA.x - F.SIDE_MARGIN + 0.5 \
				or s.y < F.MIN_Y - 0.5 or s.y > F.MAX_Y + 0.5:
			in_bounds = false
			worst = str(s)
		if i > 0 and slots[i - 1].y > s.y + 0.5:
			sorted = false
	_ok(in_bounds, "%s: alle innenfor x∈[%d,%d] y∈[%d,%d] (verst %s)" % [tag,
			F.SIDE_MARGIN, AREA.x - F.SIDE_MARGIN, F.MIN_Y, F.MAX_Y, worst])
	_ok(sorted, "%s: sortert ovenfra og ned" % tag)
	_ok(abs(sum_x / n - AREA.x / 2) <= 20.0, "%s: sentrert (snitt x = %.1f)" % [tag, sum_x / n])
	var min_d := 9999.0
	for i in n:
		for j in range(i + 1, n):
			min_d = min(min_d, slots[i].distance_to(slots[j]))
	_ok(min_d >= F.MIN_SPACING - 0.01, "%s: minst %d px mellom plasser (fikk %.1f)" % [tag, F.MIN_SPACING, min_d])
	return true


# ---------------------------------------------------------------------------
# Innflyging
# ---------------------------------------------------------------------------

func _check_entries() -> bool:
	var E = _load_script("enemies/entry_patterns.gd")
	if E == null:
		return true
	for name in E.NAMES:
		for shape in _synthetic_shapes():
			if not _check_entry(E, name, shape["name"], shape["slots"]):
				_fail("innflyging %s på %s: sjekken ble avbrutt av en skriptfeil" % [name, shape["name"]])
	return true


func _check_entry(E, name: String, shape: String, slots: Array) -> bool:
	var tag := "innflyging %s på %s" % [name, shape]
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var entries: Array = E.build(name, slots, AREA, rng)
	if not _ok(entries.size() == slots.size(), "%s: én bane per plass (%d/%d)" % [tag, entries.size(), slots.size()]):
		return true
	rng.seed = 77
	var again: Array = E.build(name, slots, AREA, rng)
	_ok(str(entries) == str(again), "%s: samme seed gir samme baner" % tag)

	var starts_off := true
	var ends_on := true
	var fields := true
	var path_ok := true
	var worst := ""
	for i in slots.size():
		var e: Dictionary = entries[i]
		if not (e.has("start") and e.has("ctrl") and e.has("delay") and e.has("duration")) \
				or e["duration"] <= 0.0 or e["delay"] < 0.0:
			fields = false
			continue
		var st: Vector2 = e["start"]
		if st.x >= -16 and st.x <= AREA.x + 16 and st.y >= -16 and st.y <= AREA.y + 16:
			starts_off = false
		if E.point(e, slots[i], 0.0).distance_to(st) > 0.5 or E.point(e, slots[i], 1.0).distance_to(slots[i]) > 0.5:
			ends_on = false
		for k in 41:
			var p: Vector2 = E.point(e, slots[i], k / 40.0)
			if p.x < -80 or p.x > AREA.x + 80 or p.y < -80 or p.y > E.PATH_MAX_Y:
				path_ok = false
				worst = "plass %d u=%.2f %s" % [i, k / 40.0, str(p)]
	_ok(fields, "%s: start/ctrl/delay/duration finnes, duration > 0" % tag)
	_ok(starts_off, "%s: starter utenfor skjermen" % tag)
	_ok(ends_on, "%s: point(0) = start og point(1) = plassen" % tag)
	_ok(path_ok, "%s: banen innenfor x∈[-80,720] y∈[-80,%d] (%s)" % [tag, E.PATH_MAX_Y, worst])
	var total: float = E.total_time(entries)
	_ok(total <= E.MAX_TOTAL_TIME, "%s: varer %.2f s (maks %.1f)" % [tag, total, E.MAX_TOTAL_TIME])
	return true


# ---------------------------------------------------------------------------
# Bevegelse
# ---------------------------------------------------------------------------

func _check_movements() -> bool:
	var M = _load_script("enemies/movement_patterns.gd")
	if M == null:
		return true
	for name in M.NAMES:
		for shape in _synthetic_shapes():
			for descent_time in [60.0, 100.0]:
				for speed_mult in [1.0, 1.6]:
					var tag := "bevegelse %s på %s (ned %ds, fart %.1f)" % [name, shape["name"], int(descent_time), speed_mult]
					if not _check_movement(M, name, shape["name"], shape["slots"], descent_time, speed_mult, tag):
						_fail("%s: sjekken ble avbrutt av en skriptfeil" % tag)
	return true


# Simulerer mønsteret med alle i live til noen når bunnen, og en gang til
# med 90 % døde. Returnerer false hvis noe feilet.
func _check_movement(M, name: String, shape: String, slots: Array, descent_time: float, speed_mult: float, tag: String) -> bool:
	var min_x := AREA.x
	var max_x := 0.0
	for s in slots:
		min_x = min(min_x, s.x)
		max_x = max(max_x, s.x)

	var state: Dictionary = M.start(name, AREA, slots, descent_time)
	var seamless := true
	for s in slots:
		if M.place(state, s).distance_to(s) > 0.5:
			seamless = false
	_ok(seamless, "%s: place() == plassen ved start" % tag)

	var ctx := {"dead_frac": 0.0, "speed_mult": speed_mult, "min_x": min_x, "max_x": max_x}
	var res := _simulate(M, state, slots, ctx, descent_time * 2.0)
	_ok(res["bounds_ok"], "%s: innenfor x∈[%d,%d], y ≥ %d (%s)" % [tag, M.X_MIN, M.X_MAX, M.Y_MIN, res["worst"]])
	_ok(res["max_step"] <= M.MAX_STEP, "%s: ingen hopp (største steg %.1f px, maks %d)" % [tag, res["max_step"], M.MAX_STEP])
	var t: float = res["time"]
	_ok(t >= 0.75 * descent_time and t <= 1.35 * descent_time,
			"%s: når bunnen etter %.1f s (vil ha %.0f–%.0f)" % [tag, t, 0.75 * descent_time, 1.35 * descent_time])

	var state2: Dictionary = M.start(name, AREA, slots, descent_time)
	var ctx2 := {"dead_frac": 0.9, "speed_mult": speed_mult, "min_x": min_x, "max_x": max_x}
	var res2 := _simulate(M, state2, slots, ctx2, descent_time * 2.0)
	_ok(res2["bounds_ok"], "%s: innenfor skjermen også med 90 %% døde (%s)" % [tag, res2["worst"]])
	_ok(res2["time"] <= t + 0.5 and res2["time"] >= 0.2 * descent_time,
			"%s: 90 %% døde går fortere, men ikke vilt (%.1f s mot %.1f s)" % [tag, res2["time"], t])

	# Kantene kan flytte seg mens bølgen pågår (kolonner dør, dykkere er ute).
	# Snevrer vi inn min_x/max_x underveis, skal ingenting hoppe eller forsvinne.
	var state3: Dictionary = M.start(name, AREA, slots, descent_time)
	var ctx3 := {"dead_frac": 0.5, "speed_mult": speed_mult, "min_x": min_x, "max_x": max_x}
	var mid := (min_x + max_x) / 2
	var prev := []
	for s in slots:
		prev.append(s)
	var worst_step := 0.0
	for frame in 1800:
		var squeeze: float = min(1.0, frame / 1500.0)
		ctx3["min_x"] = lerp(min_x, mid, squeeze)
		ctx3["max_x"] = lerp(max_x, mid, squeeze)
		M.step(state3, DT, ctx3)
		for i in slots.size():
			var p: Vector2 = M.place(state3, slots[i])
			worst_step = max(worst_step, p.distance_to(prev[i]))
			prev[i] = p
	_ok(worst_step <= M.MAX_STEP, "%s: ingen hopp når kantene flytter seg (største steg %.1f px)" % [tag, worst_step])
	return true


func _simulate(M, state: Dictionary, slots: Array, ctx: Dictionary, max_time: float) -> Dictionary:
	var prev := []
	for s in slots:
		prev.append(s)
	var t := 0.0
	var bounds_ok := true
	var worst := ""
	var max_step := 0.0
	var reached := false
	while t < max_time and not reached:
		M.step(state, DT, ctx)
		t += DT
		for i in slots.size():
			var p: Vector2 = M.place(state, slots[i])
			max_step = max(max_step, p.distance_to(prev[i]))
			prev[i] = p
			if p.x < M.X_MIN or p.x > M.X_MAX or p.y < M.Y_MIN:
				if bounds_ok:
					worst = "t=%.1f plass %d %s" % [t, i, str(p)]
				bounds_ok = false
			if p.y >= M.BOTTOM_LIMIT:
				reached = true
	return {"time": t if reached else 9999.0, "bounds_ok": bounds_ok, "worst": worst, "max_step": max_step}


# ---------------------------------------------------------------------------
# Bølgene: alt de refererer til finnes, og hver kombinasjon de kan trekke
# holder kontraktene med ekte formasjoner og bølgens egne tall.
# ---------------------------------------------------------------------------

func _check_waves() -> bool:
	var F = _load_script("enemies/formations.gd")
	var E = _load_script("enemies/entry_patterns.gd")
	var M = _load_script("enemies/movement_patterns.gd")
	var W = _load_script("waves/waves.gd")
	var T = _load_script("enemies/enemy_types.gd")
	if F == null or E == null or M == null or W == null or T == null:
		return true
	var rows := []
	if OS.get_environment("AILIEN_WAVES_JSON") != "":
		rows = W.rows_from_json(OS.get_environment("AILIEN_WAVES_JSON"))
		if not _ok(not rows.empty(), "AILIEN_WAVES_JSON lar seg lese"):
			return true
	var wave_total: int = W.count() if rows.empty() else rows.size()
	for n in range(1, wave_total + 1):
		var data: Dictionary = W.get_wave(n) if rows.empty() else W.with_defaults(rows[n - 1], n)
		var tag := "bølge %d" % n
		if not _ok(data.has("enemies") and typeof(data["enemies"]) == TYPE_ARRAY and not data["enemies"].empty(),
				"%s: har 'enemies'" % tag):
			continue
		var count: int = W.enemy_count(data)
		_ok(count >= 8 and count <= 40, "%s: %d fiender (8–40, Pi-grensa)" % [tag, count])
		for pair in data["enemies"]:
			_ok(T.TYPES.has(pair[0]), "%s: fiendetype '%s' finnes" % [tag, pair[0]])
		for t in data["dive_types"]:
			_ok(T.TYPES.has(t), "%s: dive_type '%s' finnes" % [tag, t])
		if data["dives"]:
			var someone := false
			for pair in data["enemies"]:
				if (data["dive_types"].empty() and T.TYPES[pair[0]]["can_dive"]) or pair[0] in data["dive_types"]:
					someone = true
			_ok(someone, "%s: dives=true og noen kan faktisk dykke" % tag)
		for f in data["formations"]:
			if not _ok(f in F.NAMES, "%s: formasjon '%s' finnes" % [tag, f]):
				continue
			if not _check_formation(F, f, count):
				_fail("%s: formasjon %s ble avbrutt av en skriptfeil" % [tag, f])
			var slots: Array = F.build(f, count, AREA)
			for en in data["entries"]:
				if _ok(en in E.NAMES, "%s: innflyging '%s' finnes" % [tag, en]):
					if not _check_entry(E, en, "%s/%s" % [tag, f], slots):
						_fail("%s: innflyging %s ble avbrutt av en skriptfeil" % [tag, en])
			for m in data["movements"]:
				if _ok(m in M.NAMES, "%s: bevegelse '%s' finnes" % [tag, m]):
					if not _check_movement(M, m, f, slots, data["descent_time"], data["speed_mult"],
							"%s: %s + %s" % [tag, f, m]):
						_fail("%s: bevegelse %s ble avbrutt av en skriptfeil" % [tag, m])
	return true


# ---------------------------------------------------------------------------
# Hjelpere
# ---------------------------------------------------------------------------

# Plasser som ligner ekte formasjoner, uten å være avhengig av formations.gd.
func _synthetic_shapes() -> Array:
	var shapes := []
	shapes.append({"name": "rader24", "slots": _grid(8, 3, 40.0, 34.0, 60.0)})
	shapes.append({"name": "rader40", "slots": _grid(8, 5, 40.0, 34.0, 60.0)})
	var ring := []
	for i in 16:
		var a: float = -PI / 2 + TAU * i / 16
		ring.append(Vector2(320, 140) + Vector2(cos(a) * 170.0, sin(a) * 72.0))
	shapes.append({"name": "ring16", "slots": ring})
	var wide := []
	for row in 3:
		for col in 4:
			wide.append(Vector2(70 + col * 40.0, 60 + row * 34.0))
			wide.append(Vector2(570 - col * 40.0, 60 + row * 34.0))
	shapes.append({"name": "bred24", "slots": wide})
	var small := []
	for i in 8:
		var b: float = TAU * i / 8
		small.append(Vector2(320, 110) + Vector2(cos(b), sin(b)) * 60.0)
	shapes.append({"name": "liten8", "slots": small})
	return shapes


func _grid(cols: int, rows: int, dx: float, dy: float, top: float) -> Array:
	var out := []
	var left := AREA.x / 2 - (cols - 1) * dx / 2
	for row in rows:
		for col in cols:
			out.append(Vector2(left + col * dx, top + row * dy))
	return out


func _ok(cond: bool, what: String) -> bool:
	checks += 1
	if not cond:
		failures += 1
		print("  FEIL ", what)
	return cond


func _fail(what: String) -> void:
	_ok(false, what)
