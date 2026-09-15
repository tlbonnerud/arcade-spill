extends Reference

# Formasjoner: tar antall fiender og skjermstørrelse, returnerer en liste
# med plasser (Vector2 i skjermkoordinater) sortert ovenfra og ned, venstre
# til høyre. Sorteringen betyr at de første fiendetypene i bølgedataene
# havner øverst, slik at de sterkeste alltid står bakerst.
#
# Alle formasjoner er sentrert horisontalt og holder seg innenfor
# SIDE_MARGIN, så samme formasjon virker med 16 eller 40 fiender.

const TOP := 60.0
const SIDE_MARGIN := 40.0
const H_SPACING := 40.0
const V_SPACING := 34.0


static func build(kind: String, count: int, area: Vector2) -> Array:
	var slots := []
	match kind:
		"rows":
			slots = _rows(count, area)
		"v_shape":
			slots = _v_shape(count, area)
		"ring":
			slots = _ring(count, area)
		"checkerboard":
			slots = _checkerboard(count, area)
		_:
			push_warning("Ukjent formasjon '%s', bruker 'rows'" % kind)
			slots = _rows(count, area)
	slots.sort_custom(FormationSort.new(), "top_to_bottom")
	return slots


class FormationSort:
	func top_to_bottom(a: Vector2, b: Vector2) -> bool:
		if abs(a.y - b.y) > 0.5:
			return a.y < b.y
		return a.x < b.x


# Klassisk: rader med 8 i bredden.
static func _rows(count: int, area: Vector2) -> Array:
	var cols := 8
	var out := []
	var left := area.x / 2 - (cols - 1) * H_SPACING / 2
	for i in count:
		var row: int = i / cols
		var col: int = i % cols
		out.append(Vector2(left + col * H_SPACING, TOP + row * V_SPACING))
	return out


# Stablede chevroner (V-er) med spiss øverst: apex + 4 per arm = 9 per chevron.
static func _v_shape(count: int, area: Vector2) -> Array:
	var arm := 4
	var per_chevron := 2 * arm + 1
	var dx := 36.0
	var dy := 14.0
	var chevron_gap := 34.0
	var cx := area.x / 2
	var out := []
	for i in count:
		var chevron: int = i / per_chevron
		var k: int = i % per_chevron
		var y := TOP + chevron * chevron_gap
		if k == 0:
			out.append(Vector2(cx, y))
		else:
			var step := (k + 1) / 2          # 1..arm
			var side := 1.0 if k % 2 == 1 else -1.0
			out.append(Vector2(cx + side * step * dx, y + step * dy))
	return out


# Ellipse-ring; over 16 fiender legges resten i en indre ring.
static func _ring(count: int, area: Vector2) -> Array:
	var center := Vector2(area.x / 2, TOP + 80)
	var out := []
	var outer := int(min(count, 16))
	_ring_points(out, center, Vector2(170, 72), outer)
	var inner := count - outer
	if inner > 0:
		_ring_points(out, center, Vector2(95, 36), inner)
	return out


static func _ring_points(out: Array, center: Vector2, radius: Vector2, n: int) -> void:
	for i in n:
		var a: float = -PI / 2 + TAU * i / n
		out.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))


# Sjakkbrett: 10 kolonner, annenhver rute, så 5 per rad.
static func _checkerboard(count: int, area: Vector2) -> Array:
	var cols := 10
	var spacing := 36.0
	var row_h := 30.0
	var left := area.x / 2 - (cols - 1) * spacing / 2
	var out := []
	var placed := 0
	var row := 0
	while placed < count:
		for col in cols:
			if (row + col) % 2 == 0 and placed < count:
				out.append(Vector2(left + col * spacing, TOP + row * row_h))
				placed += 1
		row += 1
	return out


# Halv bredde av formasjonen målt fra midten av skjermen. Brukes av
# sinus-bevegelsen for å vite hvor langt den kan svaie.
static func half_width(slots: Array, area: Vector2) -> float:
	var cx := area.x / 2
	var w := 0.0
	for s in slots:
		w = max(w, abs(s.x - cx))
	return w
