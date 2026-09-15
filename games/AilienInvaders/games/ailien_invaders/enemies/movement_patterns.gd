extends Reference

# Bevegelse under WAVE: hvordan hele formasjonen flytter seg. Mønsteret eier
# en tilstands-dictionary og returnerer formasjonens forskyvning (offset)
# hver frame. wave_manager legger offset til hver fiendes plass.
#
# ctx fra wave_manager per frame:
#   dead_frac   andel døde (0..1) → alt går fortere mot slutten
#   speed_mult  fra bølgedataene
#   min_x/max_x ytterste levende fiender (uten offset), for kantsjekk
#
# Dykk (én fiende forlater formasjonen) håndteres av wave_manager, ikke her,
# fordi det gjelder én fiende og ikke formasjonen.

const SIDE_MARGIN := 24.0
const DROP := 12.0


static func start(kind: String, area: Vector2, half_width: float) -> Dictionary:
	if not (kind in ["classic", "sine"]):
		push_warning("Ukjent bevegelse '%s', bruker 'classic'" % kind)
		kind = "classic"
	return {
		"kind": kind,
		"area": area,
		"dir": 1.0,
		"t": 0.0,
		"y": 0.0,
		"offset": Vector2.ZERO,
		# Hvor langt sinus-svaiet kan gå før formasjonen treffer kanten.
		"amp": max(0.0, area.x / 2 - SIDE_MARGIN - half_width - 8.0),
	}


static func step(state: Dictionary, delta: float, ctx: Dictionary) -> Vector2:
	match state["kind"]:
		"sine":
			_sine(state, delta, ctx)
		_:
			_classic(state, delta, ctx)
	return state["offset"]


# Space Invaders: sideveis, ett hakk ned ved kanten.
static func _classic(state: Dictionary, delta: float, ctx: Dictionary) -> void:
	var area: Vector2 = state["area"]
	var speed: float = (30.0 + 100.0 * ctx["dead_frac"]) * ctx["speed_mult"]
	var offset: Vector2 = state["offset"]
	offset.x += state["dir"] * speed * delta

	var right: float = ctx["max_x"] + offset.x
	var left: float = ctx["min_x"] + offset.x
	if (right > area.x - SIDE_MARGIN and state["dir"] > 0) \
			or (left < SIDE_MARGIN and state["dir"] < 0):
		state["dir"] = -state["dir"]
		offset.y += DROP
	state["offset"] = offset


# Svaier i sinus og siger sakte nedover mens den dupper.
static func _sine(state: Dictionary, delta: float, ctx: Dictionary) -> void:
	var rate: float = ctx["speed_mult"] * (1.0 + 1.5 * ctx["dead_frac"])
	state["t"] += delta * rate
	state["y"] += 4.0 * rate * delta
	var t: float = state["t"]
	state["offset"] = Vector2(
		state["amp"] * sin(t * 0.9),
		state["y"] + 8.0 * sin(t * 2.1)
	)
