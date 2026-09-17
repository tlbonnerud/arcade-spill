extends Reference

# Innflyging (WAVE_INTRO). For hver plass i formasjonen lages en bane:
# startpunkt utenfor skjermen, ett kontrollpunkt (kvadratisk bezier) og en
# forsinkelse, så fiendene kommer som en strøm i stedet for på likt.
#
# Banen regnes ut per frame i wave_manager (ingen tweens: én kurve per
# fiende i step() er billigere på Pi-en enn 40 SceneTreeTweens, og det er
# lett å teste uten skjerm).
#
# Hvert element: {"start": Vector2, "ctrl": Vector2, "delay": float, "duration": float}
# Valgfritt "ctrl2": Vector2 gir kubisk bezier (start, ctrl, ctrl2, plass), som
# trengs for S-kurver og løkker.
#
# KONTRAKT (sjekkes av tests/check_patterns.tscn for hvert navn i NAMES):
#   1. Én bane per plass, i samme rekkefølge som slots.
#   2. start ligger utenfor skjermen, og banen ender nøyaktig på plassen.
#   3. Banen holder seg innenfor x ∈ [-80, 720] og y ∈ [-80, PATH_MAX_Y]:
#      fiender skal aldri fly gjennom spillerens rad (det er ingen kollisjon
#      under innflyging, så det ville sett ut som juks).
#   4. Hele innflygingen (største delay + duration) tar maks MAX_TOTAL_TIME
#      sekunder, også med 40 fiender. Skaler forsinkelsen med antallet.
#   5. Samme rng-seed gir samme baner.

const NAMES := ["from_top", "from_sides", "spiral", "swoop", "rain", "crossover", "loop", "snake"]

const OFF := 48.0            # hvor langt utenfor skjermen de starter
const PATH_MAX_Y := 300.0
const MAX_TOTAL_TIME := 4.5


static func build(kind: String, slots: Array, area: Vector2, rng: RandomNumberGenerator) -> Array:
	match kind:
		"from_top":
			return _from_top(slots, area, rng)
		"from_sides":
			return _from_sides(slots, area)
		"spiral":
			return _spiral(slots, area)
		"swoop":
			return _swoop(slots, area)
		"rain":
			return _rain(slots, rng)
		"crossover":
			return _crossover(slots, area)
		"loop":
			return _loop(slots, area)
		"snake":
			return _snake(slots, area, rng)
		_:
			push_warning("Ukjent innflyging '%s', bruker 'from_top'" % kind)
			return _from_top(slots, area, rng)


# Rett ned ovenfra med en liten sving, kolonne for kolonne.
static func _from_top(slots: Array, area: Vector2, rng: RandomNumberGenerator) -> Array:
	var out := []
	for i in slots.size():
		var s: Vector2 = slots[i]
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		out.append({
			"start": Vector2(s.x + side * 30.0, -OFF),
			"ctrl": Vector2(s.x - side * 40.0, s.y * 0.4),
			"delay": i * 0.04,
			"duration": 0.9,
		})
	return out


# Vekselvis fra venstre og høyre, sveiper under formasjonen og opp på plass.
static func _from_sides(slots: Array, area: Vector2) -> Array:
	var out := []
	for i in slots.size():
		var s: Vector2 = slots[i]
		var from_left: bool = i % 2 == 0
		var start_x := -OFF if from_left else area.x + OFF
		var ctrl_x := area.x * 0.3 if from_left else area.x * 0.7
		out.append({
			"start": Vector2(start_x, 30.0 + (i % 6) * 12.0),
			"ctrl": Vector2(ctrl_x, s.y + 130.0),
			"delay": (i / 2) * 0.07,
			"duration": 1.1,
		})
	return out


# Alle starter i samme punkt over midten og vifter ut i en virvel.
static func _spiral(slots: Array, area: Vector2) -> Array:
	var out := []
	var center := Vector2(area.x / 2, 150.0)
	for i in slots.size():
		var a: float = i * 0.55
		out.append({
			"start": Vector2(area.x / 2, -OFF),
			"ctrl": center + Vector2(cos(a), sin(a)) * 230.0,
			"delay": i * 0.05,
			"duration": 1.2,
		})
	return out


# Stuper ned mot spillerens høyde og trekker seg opp på plass. Ser farlig ut.
static func _swoop(slots: Array, area: Vector2) -> Array:
	var out := []
	for i in slots.size():
		var s: Vector2 = slots[i]
		var side := 1.0 if i % 2 == 0 else -1.0
		# Klemt: plasser nær kanten ville ellers startet utenfor kontraktens x-grense (±80).
		var start_x: float = clamp(s.x + side * 220.0, -70.0, area.x + 70.0)
		out.append({
			"start": Vector2(start_x, -OFF),
			"ctrl": Vector2(s.x - side * 60.0, area.y * 0.95),
			"delay": i * 0.04,
			"duration": 1.3,
		})
	return out


# Hagl: hver fiende faller nesten rett ned over sin egen plass, i tilfeldig
# rekkefølge, og spretter så vidt forbi plassen før den faller til ro.
static func _rain(slots: Array, rng: RandomNumberGenerator) -> Array:
	var n := slots.size()
	var order := []
	for i in n:
		order.append(i)
	for i in range(n - 1, 0, -1):  # Fisher-Yates med bølgens egen rng
		var j: int = rng.randi_range(0, i)
		var tmp: int = order[i]
		order[i] = order[j]
		order[j] = tmp
	var step: float = min(0.07, 2.4 / max(1, n))
	var out := []
	for i in n:
		var s: Vector2 = slots[i]
		var turn: int = order[i]
		out.append({
			"start": Vector2(s.x + rng.randf_range(-10.0, 10.0), -OFF),
			"ctrl": Vector2(s.x, min(s.y + 60.0, PATH_MAX_Y)),
			"delay": turn * step,
			"duration": rng.randf_range(0.55, 0.7),
		})
	return out


# Saks: plasser til venstre fylles fra høyre kant og omvendt. Hver strøm dukker
# ned på sin egen side, stiger mot midten der de to krysser hverandre, og buer
# over toppen og ned i plassen (S-kurve).
#
# ctrl2 ligger på INNSIDEN av plassen (mot midten) og over den. Da peker siste
# bein samme vei som fienden allerede flyr. Ligger ctrl2 på yttersiden, bretter
# kurven seg: fienden skyter forbi plassen, bråstopper og rygger tilbake.
static func _crossover(slots: Array, area: Vector2) -> Array:
	var out := []
	var mid := area.x * 0.5
	var duration := 1.5
	var step := _group_step(slots, mid, duration, 0.08)
	var ranks := [0, 0]  # neste tur i venstre og høyre strøm
	for i in slots.size():
		var s: Vector2 = slots[i]
		var group := 0 if s.x < mid else 1
		var side := 1.0 if group == 0 else -1.0  # +1: plass til venstre, kommer fra høyre
		out.append({
			"start": Vector2(mid + side * (mid + OFF), 30.0),
			"ctrl": Vector2(mid + side * 60.0, 430.0),
			"ctrl2": Vector2(s.x + side * 180.0, s.y - 120.0),
			"delay": ranks[group] * step,
			"duration": duration,
		})
		ranks[group] += 1
	return out


# Galaga-løkke: to strømmer stuper inn fra hvert sitt øvre hjørne, slår en hel
# løkke nede på midten og flyr så over til plassen på motsatt side.
#
# Kontrollpunktene er et symmetrisk løkke-bezier: ctrl ligger forbi plassen og
# ctrl2 bak starten (de krysser hverandre), og begge er trukket mot løkkas
# bunnpunkt. En slik kurve krysser alltid seg selv så lenge reach er lengre enn
# halve korden. Starten ligger i hjørnet på MOTSATT side av plassen: da ligger
# plassen aldri på linja mellom hjørnet og løkka, så løkka blir aldri klemt flat.
static func _loop(slots: Array, area: Vector2) -> Array:
	var out := []
	var mid := area.x * 0.5
	var duration := 1.9
	var step := _group_step(slots, mid, duration, 0.09)
	var ranks := [0, 0]  # neste tur i venstre og høyre strøm
	for i in slots.size():
		var s: Vector2 = slots[i]
		var group := 0 if s.x < mid else 1
		var side := 1.0 if group == 0 else -1.0  # +1: plass til venstre, kommer fra høyre
		var start := Vector2(mid + side * (mid + OFF), -OFF)
		var bottom := Vector2(mid + side * 110.0, PATH_MAX_Y - 38.0)  # her er fienden ved u = 0.5
		var half: Vector2 = (s - start) * 0.5
		var reach: Vector2 = half.normalized() * (half.length() * 1.66 + 170.0)
		# Midt på kurven er punktet start + half + 0.75 * pull, derav delingen.
		var pull: Vector2 = (bottom - start - half) / 0.75
		out.append({
			"start": start,
			"ctrl": start + half + reach + pull,
			"ctrl2": start + half - reach + pull,
			"delay": ranks[group] * step,
			"duration": duration,
		})
		ranks[group] += 1
	return out


# Slange: alle på én rekke fra toppen, ut mot den ene kanten, i en lang krok
# under formasjonen og opp i plassene. Start og begge kontrollpunktene er felles,
# så de følger samme spor som et tog og skiller først lag på slutten. rng velger
# hvilken kant kroken går mot.
#
# Det felles sporet ender lavt og peker oppover, så alle plasser ligger FORAN
# toget. Med et felles spor som sveiper en gang til (en S) havner noen plasser bak
# sveipet, og de fiendene må bråstoppe og snu 180 grader for å komme hjem.
static func _snake(slots: Array, area: Vector2, rng: RandomNumberGenerator) -> Array:
	var out := []
	var mid := area.x * 0.5
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var duration := 1.9
	var step: float = min(0.1, (MAX_TOTAL_TIME - duration - 0.2) / max(1, slots.size()))
	for i in slots.size():
		out.append({
			"start": Vector2(mid, -OFF),
			"ctrl": Vector2(mid - side * area.x, 200.0),
			"ctrl2": Vector2(mid - side * 200.0, 400.0),
			"delay": i * step,
			"duration": duration,
		})
	return out


# Forsinkelse mellom to fiender i samme strøm når plassene deles i venstre og
# høyre gruppe: den største gruppa skal rekke inn før MAX_TOTAL_TIME.
static func _group_step(slots: Array, mid: float, duration: float, max_step: float) -> float:
	var left := 0
	for s in slots:
		if s.x < mid:
			left += 1
	var biggest: float = max(left, slots.size() - left)
	return min(max_step, (MAX_TOTAL_TIME - duration - 0.2) / max(1.0, biggest))


# Posisjon langs banen. u i [0, 1], med myk start og slutt.
static func point(entry: Dictionary, end: Vector2, u: float) -> Vector2:
	var t := u * u * (3.0 - 2.0 * u)  # smoothstep
	var start: Vector2 = entry["start"]
	var ctrl: Vector2 = entry["ctrl"]
	var it := 1.0 - t
	if entry.has("ctrl2"):
		var ctrl2: Vector2 = entry["ctrl2"]
		return it * it * it * start + 3.0 * it * it * t * ctrl \
				+ 3.0 * it * t * t * ctrl2 + t * t * t * end
	return it * it * start + 2.0 * it * t * ctrl + t * t * end


# Hvor lenge hele innflygingen varer.
static func total_time(entries: Array) -> float:
	var longest := 0.0
	for e in entries:
		longest = max(longest, e["delay"] + e["duration"])
	return longest
