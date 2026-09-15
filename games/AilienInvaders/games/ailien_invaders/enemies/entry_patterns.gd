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

const OFF := 48.0  # hvor langt utenfor skjermen de starter


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
		out.append({
			"start": Vector2(s.x + side * 220.0, -OFF),
			"ctrl": Vector2(s.x - side * 60.0, area.y * 0.95),
			"delay": i * 0.04,
			"duration": 1.3,
		})
	return out


# Posisjon langs banen. u i [0, 1], med myk start og slutt.
static func point(entry: Dictionary, end: Vector2, u: float) -> Vector2:
	var t := u * u * (3.0 - 2.0 * u)  # smoothstep
	var start: Vector2 = entry["start"]
	var ctrl: Vector2 = entry["ctrl"]
	var it := 1.0 - t
	return it * it * start + 2.0 * it * t * ctrl + t * t * end
