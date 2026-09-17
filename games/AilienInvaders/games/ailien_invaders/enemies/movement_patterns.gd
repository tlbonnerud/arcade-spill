extends Reference

# Bevegelse under WAVE: hvordan formasjonen flytter seg mens man slåss.
#
# API (brukes av core/wave_manager.gd og tests/check_patterns.gd):
#   start(kind, area, slots, descent_time) -> state   lager tilstanden
#   step(state, delta, ctx)                            flytter tiden fram
#   place(state, slot) -> Vector2                      hvor plassen `slot` er nå
#
# `place` regnes ut per fiende, så et mønster kan gjøre mer enn å skyve hele
# formasjonen: rotere den, dele den i to grupper, la den puste.
#
# ctx fra wave_manager per frame:
#   dead_frac   andel døde (0..1) → alt går fortere mot slutten
#   speed_mult  fra bølgedataene (sideveis fart / tempo, IKKE nedstigning)
#   min_x/max_x ytterste levende plasser (uten forskyvning), for kantsjekk
#
# KONTRAKT (sjekkes av tests/check_patterns.tscn for hvert navn i NAMES):
#   1. place(state, slot) == slot rett etter start(), så innflygingen går
#      sømløst over i bevegelsen.
#   2. Ingen plass havner utenfor x ∈ [X_MIN, X_MAX] eller over y = Y_MIN,
#      uansett formasjon. Passer ikke formasjonen, må mønsteret dempe seg
#      (mindre utslag/vinkel), ikke gå ut av skjermen.
#   3. Nedstigning styres av descent_time: med alle i live når den laveste
#      plassen BOTTOM_LIMIT etter ca. descent_time sekunder (0,75–1,35×),
#      uavhengig av formasjonens bredde og av speed_mult. Døde fiender gjør
#      at det går fortere (KILL_SPEEDUP), aldri saktere.
#   4. Ingen hopp: en plass flytter seg maks MAX_STEP px per frame (1/60 s).
#
# Dykk (én fiende forlater formasjonen) håndteres av wave_manager, ikke her.

const NAMES := ["classic", "sine"]

const SIDE_MARGIN := 24.0
const BOTTOM_LIMIT := 304.0   # når en fiende i formasjonen er her, har de vunnet
const X_MIN := 14.0
const X_MAX := 626.0
const Y_MIN := 24.0
const MAX_STEP := 26.0
const KILL_SPEEDUP := 1.5     # nedstigning og tempo × (1 + dette × dead_frac)
const CLASSIC_MAX_DROP := 24.0


static func start(kind: String, area: Vector2, slots: Array, descent_time: float) -> Dictionary:
	if not (kind in NAMES):
		push_warning("Ukjent bevegelse '%s', bruker 'classic'" % kind)
		kind = "classic"
	var b := bounds(slots, area)
	var state := {
		"kind": kind,
		"area": area,
		"bounds": b,
		"center": b["center"],
		"t": 0.0,            # mønsterets egen klokke (påvirkes av speed_mult og døde)
		"y": 0.0,            # oppsamlet nedstigning
		"dir": 1.0,
		"owed": 0.0,         # classic: nedstigning som venter på neste kantstøt
		"offset": Vector2.ZERO,
		# Hvor langt formasjonen kan skyves sideveis før den treffer kanten.
		"amp": max(0.0, area.x / 2 - SIDE_MARGIN - b["half_width"] - 8.0),
		# Piksler per sekund nedover med alle i live.
		"descent": max(0.0, BOTTOM_LIMIT - b["bottom"]) / max(1.0, descent_time),
	}
	return state


# Mål på formasjonen. half_width måles fra midten av SKJERMEN (formasjonene
# er sentrert der), half_height og radius fra formasjonens eget sentrum.
static func bounds(slots: Array, area: Vector2) -> Dictionary:
	var cx := area.x / 2
	var top := area.y
	var bottom := 0.0
	var half_width := 0.0
	for s in slots:
		top = min(top, s.y)
		bottom = max(bottom, s.y)
		half_width = max(half_width, abs(s.x - cx))
	if slots.empty():
		top = 0.0
	var center := Vector2(cx, (top + bottom) / 2)
	var radius := 0.0
	for s in slots:
		radius = max(radius, s.distance_to(center))
	return {
		"center": center,
		"top": top,
		"bottom": bottom,
		"half_width": half_width,
		"half_height": (bottom - top) / 2,
		"radius": radius,
	}


static func step(state: Dictionary, delta: float, ctx: Dictionary) -> void:
	var pace: float = 1.0 + KILL_SPEEDUP * ctx["dead_frac"]
	state["t"] += delta * ctx["speed_mult"] * pace
	match state["kind"]:
		"sine":
			_sine(state, delta, pace)
		_:
			_classic(state, delta, pace, ctx)


static func place(state: Dictionary, slot: Vector2) -> Vector2:
	match state["kind"]:
		_:
			return slot + state["offset"]


# Space Invaders: sideveis, ett hakk ned ved kanten. Hakket er så stort som
# nedstigningen som har "samlet seg opp" siden forrige kantstøt, så brede og
# smale formasjoner bruker like lang tid ned.
static func _classic(state: Dictionary, delta: float, pace: float, ctx: Dictionary) -> void:
	var area: Vector2 = state["area"]
	var speed: float = (30.0 + 100.0 * ctx["dead_frac"]) * ctx["speed_mult"]
	var offset: Vector2 = state["offset"]
	offset.x += state["dir"] * speed * delta
	state["owed"] += state["descent"] * pace * delta

	var right: float = ctx["max_x"] + offset.x
	var left: float = ctx["min_x"] + offset.x
	var bounced := false
	if right > area.x - SIDE_MARGIN and state["dir"] > 0:
		offset.x -= right - (area.x - SIDE_MARGIN)
		bounced = true
	elif left < SIDE_MARGIN and state["dir"] < 0:
		offset.x += SIDE_MARGIN - left
		bounced = true
	if bounced:
		state["dir"] = -state["dir"]
	# Smale formasjoner har lang vei mellom kantene og støter sjelden; da
	# slipper vi også ned når det har samlet seg et fullt hakk.
	if bounced or state["owed"] >= CLASSIC_MAX_DROP:
		var drop: float = min(state["owed"], CLASSIC_MAX_DROP)
		offset.y += drop
		state["owed"] -= drop
	state["offset"] = offset


# Svaier i sinus og siger sakte nedover mens den dupper.
static func _sine(state: Dictionary, delta: float, pace: float) -> void:
	state["y"] += state["descent"] * pace * delta
	var t: float = state["t"]
	state["offset"] = Vector2(
		state["amp"] * sin(t * 0.9),
		state["y"] + 8.0 * sin(t * 2.1)
	)
