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
# YTELSE: place() kalles for hver levende fiende hver frame (opptil 40 på en
# Pi 3). Den skal bare være et par regneoperasjoner og aldri lage nye Array/
# Dictionary. Alt som koster (sin/cos, skala, trygge utslag) regnes ut én gang
# i start() eller step() og legges i state. state["mode"] (PLACE_*) sier
# hvilken av de tre regnemåtene place() skal bruke, så den slipper å
# sammenligne strenger per fiende.
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

const NAMES := ["classic", "sine", "figure8", "split", "rock", "orbit", "pulse"]

const SIDE_MARGIN := 24.0
const BOTTOM_LIMIT := 304.0   # når en fiende i formasjonen er her, har de vunnet
const X_MIN := 14.0
const X_MAX := 626.0
const Y_MIN := 24.0
const MAX_STEP := 26.0
const KILL_SPEEDUP := 1.5     # nedstigning og tempo × (1 + dette × dead_frac)
const CLASSIC_MAX_DROP := 24.0

# Regnemåtene til place(), se state["mode"].
const PLACE_OFFSET := 0       # plassen + state["offset"] (hele formasjonen skyves)
const PLACE_SPLIT := 1        # venstre halvdel bruker "offset_l", høyre "offset"
const PLACE_XFORM := 2        # state["xf"] (Transform2D): dreid/skalert rundt sentrum

const TOP_PAD := 2.0          # luft mot Y_MIN for mønstre som løfter plasser
# Mønstre som selv stikker nedover (dupp, vipp, pust) får bruke høyst så stor
# del av veien ned til BOTTOM_LIMIT, og nedstigningen bremses med
# SAG_COMPENSATION av det. Da holder punkt 3 (0,90–1,29×) uansett tempo.
const SAG_FRAC := 0.3
const SAG_COMPENSATION := 0.75

const FIGURE8_BOB := 18.0     # høyden på åttetallet (± px)
const FIGURE8_RATE := 0.8     # rad/s gjennom åttetallet ved tempo 1
const SINE_MAX_SPEED := 150.0    # px/s sideveis for sine
const FIGURE8_MAX_SPEED := 220.0 # px/s sideveis på det raskeste (spilleren klarer 220)
const ROCK_MAX_ANGLE := 0.314 # ca. 18°
const ROCK_SWAY := 16.0
const ORBIT_SPEED := 0.45     # rad/s: én runde på ca. 14 s
const ORBIT_MAX_ASPECT := 2.5 # flatere ellipser enn dette klemmer plassene sammen
const ORBIT_MIN_SPACING := 24.0 # så tett får to plasser komme (sprite 32 px, treffboks 28 × 24)
const ORBIT_MAX_SWING_RATE := 1.0 # rad/s: små utslag pendler ikke fortere enn dette
const PULSE_AMOUNT := 0.15    # puster mellom 0,85× og 1,15×
const PULSE_SWAY := 14.0


static func start(kind: String, area: Vector2, slots: Array, descent_time: float) -> Dictionary:
	if not (kind in NAMES):
		push_warning("Ukjent bevegelse '%s', bruker 'classic'" % kind)
		kind = "classic"
	var b := bounds(slots, area)
	var state := {
		"kind": kind,
		"mode": PLACE_OFFSET,
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
	match kind:
		"figure8":
			_figure8_start(state)
		"split":
			_split_start(state)
		"rock":
			_rock_start(state, slots)
		"orbit":
			_orbit_start(state, slots)
		"pulse":
			_pulse_start(state)
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
			_sine(state, delta, pace, ctx)
		"figure8":
			_figure8(state, delta, pace, ctx)
		"split":
			_split(state, delta, pace)
		"rock":
			_rock(state, delta, pace)
		"orbit":
			_orbit(state, delta, pace)
		"pulse":
			_pulse(state, delta, pace)
		_:
			_classic(state, delta, pace, ctx)


# Per fiende per frame: hold den billig (se YTELSE øverst).
static func place(state: Dictionary, slot: Vector2) -> Vector2:
	var mode: int = state["mode"]
	if mode == PLACE_OFFSET:
		return slot + state["offset"]
	if mode == PLACE_XFORM:
		return state["xf"].xform(slot)
	# PLACE_SPLIT
	if slot.x < state["cx"]:
		return slot + state["offset_l"]
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
static func _sine(state: Dictionary, delta: float, pace: float, ctx: Dictionary) -> void:
	state["y"] += state["descent"] * pace * delta
	# Egen fase med fartstak. Hele formasjonen feier sidelengs, så taket ligger
	# godt under spillerens 220 px/s: ved 220 måtte man løpe for fullt bare
	# for å holde følge, og de siste fiendene ble nesten umulige å treffe.
	var rate: float = min(0.9 * ctx["speed_mult"] * pace, SINE_MAX_SPEED / max(1.0, state["amp"]))
	state["phase"] = state.get("phase", 0.0) + rate * delta
	var phase: float = state["phase"]
	state["offset"] = Vector2(
		state["amp"] * sin(phase),
		state["y"] + 8.0 * sin(phase * 2.33)
	)


# ---------------------------------------------------------------------------
# Felles hjelpere for mønstrene under
# ---------------------------------------------------------------------------

# Hvor mange px den øverste plassen kan løftes før den når Y_MIN.
static func _headroom(state: Dictionary) -> float:
	return max(0.0, state["bounds"]["top"] - Y_MIN - TOP_PAD)


# Hvor mange px mønsteret selv får stikke nedenfor formasjonens egen bunn.
static func _max_sag(state: Dictionary) -> float:
	return SAG_FRAC * max(0.0, BOTTOM_LIMIT - state["bounds"]["bottom"])


# Mønsteret stikker selv `sag` px nedenfor formasjonens bunn på det meste.
# Da må den sige tilsvarende saktere, ellers når den bunnen for tidlig.
static func _slow_for_sag(state: Dictionary, sag: float) -> void:
	var room: float = max(1.0, BOTTOM_LIMIT - state["bounds"]["bottom"])
	state["descent"] *= max(0.0, 1.0 - SAG_COMPENSATION * max(0.0, sag) / room)


# Setter state["xf"] slik at place() gir
#   sentrum + [[xx, xy], [yx, yy]] × (plass − sentrum) + offset
static func _set_xform(state: Dictionary, xx: float, xy: float, yx: float, yy: float, offset: Vector2) -> void:
	var c: Vector2 = state["center"]
	state["xf"] = Transform2D(
		Vector2(xx, yx),
		Vector2(xy, yy),
		Vector2(c.x - xx * c.x - xy * c.y + offset.x, c.y - yx * c.x - yy * c.y + offset.y)
	)


# ---------------------------------------------------------------------------
# figure8
# ---------------------------------------------------------------------------

# Hele formasjonen tegner et liggende åttetall (Lissajous 1:2) mens den
# siger nedover. Bredden er sideplassen, høyden det som er av luft over.
# Åttetallet har sin egen fase med tak på farten: smale formasjoner har langt
# utslag, og uten taket løper de fra spilleren når tempoet øker.
static func _figure8_start(state: Dictionary) -> void:
	var bob: float = min(FIGURE8_BOB, min(_headroom(state), _max_sag(state)))
	state["bob"] = bob
	state["phase"] = 0.0
	# Sideveis toppfart er utslag × fasefart, så dette er fasefarten som gir
	# akkurat FIGURE8_MAX_SPEED.
	state["max_rate"] = FIGURE8_MAX_SPEED / max(1.0, state["amp"])
	_slow_for_sag(state, bob)


static func _figure8(state: Dictionary, delta: float, pace: float, ctx: Dictionary) -> void:
	state["y"] += state["descent"] * pace * delta
	var rate: float = min(FIGURE8_RATE * ctx["speed_mult"] * pace, state["max_rate"])
	state["phase"] += rate * delta
	var phase: float = state["phase"]
	state["offset"] = Vector2(
		state["amp"] * sin(phase),
		state["y"] + state["bob"] * sin(phase * 2.0)
	)


# ---------------------------------------------------------------------------
# split
# ---------------------------------------------------------------------------

# Formasjonen deler seg på midten: venstre og høyre halvdel glir speilvendt
# ut til sidemargen og sammen igjen, som en port som åpner og lukker seg.
# Åpningen er aldri negativ, så halvdelene kan ikke krysse hverandre.
static func _split_start(state: Dictionary) -> void:
	var area: Vector2 = state["area"]
	state["mode"] = PLACE_SPLIT
	state["cx"] = state["center"].x
	state["offset_l"] = Vector2.ZERO
	state["reach"] = max(0.0, area.x / 2 - SIDE_MARGIN - state["bounds"]["half_width"])


static func _split(state: Dictionary, delta: float, pace: float) -> void:
	state["y"] += state["descent"] * pace * delta
	var open: float = state["reach"] * 0.5 * (1.0 - cos(state["t"] * 0.7))
	state["offset"] = Vector2(open, state["y"])
	state["offset_l"] = Vector2(-open, state["y"])


# ---------------------------------------------------------------------------
# rock
# ---------------------------------------------------------------------------

# Formasjonen vipper stivt som en pendel rundt sitt eget sentrum (inntil ca.
# 18°) og svaier litt sideveis. Brede og høye formasjoner vipper mindre, så
# hjørnene verken går over Y_MIN, ut i sidene eller for langt ned.
static func _rock_start(state: Dictionary, slots: Array) -> void:
	var area: Vector2 = state["area"]
	var c: Vector2 = state["center"]
	var half_height: float = state["bounds"]["half_height"]
	var sway: float = min(ROCK_SWAY, state["amp"])
	var side: float = area.x / 2 - SIDE_MARGIN - sway
	var up_room: float = half_height + _headroom(state)
	var down_room: float = half_height + _max_sag(state)

	# Ved vinkel v flytter en plass (dx, dy) seg høyst |dy|·sin v sideveis og
	# |dx|·sin v opp/ned. Det gir en øvre grense for sin v per plass.
	var max_sin: float = sin(ROCK_MAX_ANGLE)
	for s in slots:
		var dx: float = abs(s.x - c.x)
		var dy: float = s.y - c.y
		if dx > 0.5:
			max_sin = min(max_sin, (up_room - max(0.0, -dy)) / dx)
			max_sin = min(max_sin, (down_room - max(0.0, dy)) / dx)
		if abs(dy) > 0.5:
			max_sin = min(max_sin, (side - dx) / abs(dy))
	var max_angle: float = asin(clamp(max_sin, 0.0, 1.0))

	# Hvor mye lavere enn bunnen det laveste hjørnet kommer på fullt utslag.
	var sn: float = sin(max_angle)
	var cs: float = cos(max_angle)
	var low: float = half_height
	for s in slots:
		var reach_down: float = abs(s.x - c.x) * sn + (s.y - c.y) * cs
		low = max(low, reach_down)

	state["mode"] = PLACE_XFORM
	state["xf"] = Transform2D.IDENTITY
	state["max_angle"] = max_angle
	state["sway"] = sway
	_slow_for_sag(state, low - half_height)


static func _rock(state: Dictionary, delta: float, pace: float) -> void:
	state["y"] += state["descent"] * pace * delta
	var t: float = state["t"]
	var angle: float = state["max_angle"] * sin(t * 1.3)
	var cs: float = cos(angle)
	var sn: float = sin(angle)
	_set_xform(state, cs, -sn, sn, cs, Vector2(state["sway"] * sin(t * 0.7), state["y"]))


# ---------------------------------------------------------------------------
# orbit
# ---------------------------------------------------------------------------

# Plassene sirkulerer sakte rundt sentrum, hver i sin egen ellipse med samme
# fasong som formasjonen (en ring blir et karusell-hjul). Skalaen er alltid 1.
# Tåler ikke formasjonen en hel runde (hjørner som svinger ut av banen, eller
# rader som ville blitt stående oppå hverandre på høykant), snur den mykt ved
# den største trygge vinkelen og pendler fram og tilbake som en vaskemaskin.
static func _orbit_start(state: Dictionary, slots: Array) -> void:
	var area: Vector2 = state["area"]
	var c: Vector2 = state["center"]
	var half_width: float = state["bounds"]["half_width"]
	var half_height: float = state["bounds"]["half_height"]
	# Ellipsenes bredde/høyde. Holdes innenfor ORBIT_MAX_ASPECT så en enkelt
	# rad (høyde 0) eller en veldig flat formasjon ikke klapper helt sammen
	# når den står på høykant, og så vi aldri deler på null.
	var aspect: float = clamp(max(half_width, 1.0) / max(half_height, 1.0),
			1.0 / ORBIT_MAX_ASPECT, ORBIT_MAX_ASPECT)
	# Rommet er aldri mindre enn det formasjonen alt bruker.
	var side: float = max(area.x / 2 - SIDE_MARGIN, half_width)
	var up_room: float = half_height + _headroom(state)
	var down_room: float = half_height + _max_sag(state)

	# Ved vinkel v står plassen (dx, dy) i
	#   x = dx·cos v − aspect·dy·sin v      y = dy·cos v + dx/aspect·sin v
	# Hver grense er altså a·cos v + b·sin v ≤ rom, og _max_swing løser den
	# eksakt. Ingen prøving vinkel for vinkel, så start() er billig.
	var swing: float = PI
	for s in slots:
		var dx: float = s.x - c.x
		var dy: float = s.y - c.y
		swing = min(swing, _max_swing(dx, -aspect * dy, side))
		swing = min(swing, _max_swing(-dx, aspect * dy, side))
		swing = min(swing, _max_swing(-dy, -dx / aspect, up_room))
		swing = min(swing, _max_swing(dy, dx / aspect, down_room))

	# Avstanden mellom to plasser med innbyrdes vektor d er ved vinkel v
	#   |d'|² = (p + q)/2 + (p − q)/2·cos 2v + r·sin 2v
	# der p er |d|² nå, q er |d|² på høykant (v = 90°) og r er kryssleddet.
	# Den skal aldri under ORBIT_MIN_SPACING (eller 0,9 × utgangsavstanden for
	# par som alt står tettere). Dreiingen klemmer høyst med 1/aspect, så par
	# lenger fra hverandre enn det (reach2) trenger vi ikke regne på.
	var squeeze: float = max(aspect, 1.0 / aspect)
	var limit2: float = ORBIT_MIN_SPACING * ORBIT_MIN_SPACING
	var reach2: float = limit2 * squeeze * squeeze
	var a2: float = aspect * aspect
	for i in slots.size():
		var here: Vector2 = slots[i]
		for j in range(i + 1, slots.size()):
			var d: Vector2 = slots[j] - here
			var p: float = d.length_squared()
			if p >= reach2:
				continue
			var q: float = a2 * d.y * d.y + d.x * d.x / a2
			var r: float = d.x * d.y * (1.0 / aspect - aspect)
			var room: float = (p + q) / 2 - min(limit2, 0.81 * p)
			swing = min(swing, _max_swing((q - p) / 2, -r, room) / 2)
	swing = max(0.0, swing)

	# Hvor lavt den laveste plassen kommer innenfor utslaget: y over er
	# lengde·cos(v − fase), størst når v er så nær fasen som utslaget tillater.
	var low: float = half_height
	for s in slots:
		var nx: float = (s.x - c.x) / aspect
		var dy: float = s.y - c.y
		var off: float = max(0.0, abs(atan2(nx, dy)) - swing)
		low = max(low, sqrt(nx * nx + dy * dy) * cos(off))

	state["mode"] = PLACE_XFORM
	state["xf"] = Transform2D.IDENTITY
	state["aspect"] = aspect
	# swing == PI betyr hele runder. Ellers pendler vinkelen ±swing med samme
	# toppfart som en hel runde, men små utslag får ikke pendle hektisk.
	state["swing"] = swing
	state["swing_rate"] = min(ORBIT_MAX_SWING_RATE, ORBIT_SPEED / max(swing, 0.01))
	_slow_for_sag(state, low - half_height)


# Største utslag u slik at a·cos v + b·sin v ≤ limit for alle |v| ≤ u.
# TAU betyr at grensa aldri brytes, 0 at den brytes med en gang.
static func _max_swing(a: float, b: float, limit: float) -> float:
	var length: float = sqrt(a * a + b * b)
	if length <= limit:
		return TAU
	# a·cos v + b·sin v = length·cos(v − phase): brudd når v er nærmere
	# phase enn `half`.
	var phase: float = atan2(b, a)
	var half: float = acos(clamp(limit / length, -1.0, 1.0))
	var first: float = fposmod(phase - half, TAU)
	var last: float = fposmod(phase + half, TAU)
	if first > last:
		return 0.0    # v = 0 ligger selv i bruddet
	return min(first, TAU - last)


static func _orbit(state: Dictionary, delta: float, pace: float) -> void:
	state["y"] += state["descent"] * pace * delta
	var swing: float = state["swing"]
	var angle: float = state["t"] * ORBIT_SPEED
	if swing < PI:
		angle = swing * sin(state["t"] * state["swing_rate"])
	var cs: float = cos(angle)
	var sn: float = sin(angle)
	var aspect: float = state["aspect"]
	_set_xform(state, cs, -sn * aspect, sn / aspect, cs, Vector2(0.0, state["y"]))


# ---------------------------------------------------------------------------
# pulse
# ---------------------------------------------------------------------------

# Formasjonen puster: den trekker seg sammen til 0,85× og utvider seg til
# 1,15× rundt sentrum, med et rolig sideveis svai. Er det trangt, utvider den
# seg mindre (og puster i stedet mest innover), men starter alltid på 1,0.
static func _pulse_start(state: Dictionary) -> void:
	var area: Vector2 = state["area"]
	var half_width: float = state["bounds"]["half_width"]
	var half_height: float = state["bounds"]["half_height"]
	var sway: float = min(PULSE_SWAY, state["amp"] * 0.5)
	var grow: float = PULSE_AMOUNT
	if half_width > 1.0:
		grow = min(grow, (area.x / 2 - SIDE_MARGIN - sway) / half_width - 1.0)
	if half_height > 1.0:
		grow = min(grow, min(_headroom(state), _max_sag(state)) / half_height)
	grow = max(0.0, grow)

	# Én ren sinus mellom (1 − PULSE_AMOUNT) og (1 + grow). Fasen velges slik
	# at skalaen er nøyaktig 1 ved t = 0.
	var mid: float = 1.0 + (grow - PULSE_AMOUNT) / 2
	var swing: float = (grow + PULSE_AMOUNT) / 2
	state["mode"] = PLACE_XFORM
	state["xf"] = Transform2D.IDENTITY
	state["sway"] = sway
	state["pulse_mid"] = mid
	state["pulse_swing"] = swing
	state["pulse_phase"] = asin(clamp((1.0 - mid) / swing, -1.0, 1.0))
	_slow_for_sag(state, half_height * grow)


static func _pulse(state: Dictionary, delta: float, pace: float) -> void:
	state["y"] += state["descent"] * pace * delta
	var t: float = state["t"]
	var k: float = state["pulse_mid"] + state["pulse_swing"] * sin(t * 1.5 + state["pulse_phase"])
	_set_xform(state, k, 0.0, 0.0, k, Vector2(state["sway"] * sin(t * 0.6), state["y"]))
