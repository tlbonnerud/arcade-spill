extends Reference

# Formasjoner: tar antall fiender og skjermstørrelse, returnerer en liste
# med plasser (Vector2 i skjermkoordinater) sortert ovenfra og ned, venstre
# til høyre. Sorteringen betyr at de første fiendetypene i bølgedataene
# havner øverst, slik at de sterkeste alltid står bakerst.
#
# Alle formasjoner er sentrert horisontalt og holder seg innenfor
# SIDE_MARGIN, så samme formasjon virker med 16 eller 40 fiender.
#
# KONTRAKT (sjekkes av tests/check_patterns.tscn for hvert navn i NAMES,
# for 8 til 40 fiender):
#   1. Nøyaktig `count` plasser, sortert ovenfra og ned.
#   2. x ∈ [SIDE_MARGIN, area.x - SIDE_MARGIN], y ∈ [MIN_Y, MAX_Y]. Blir
#      formasjonen for høy med mange fiender, må den bli bredere/tettere,
#      ikke lavere: under MAX_Y trengs plassen til nedstigningen.
#   3. Minst MIN_SPACING px mellom to plasser (32 px sprites skal ikke
#      ligge oppå hverandre).
#   4. Sentrert: snittet av x ligger innen 20 px fra midten av skjermen.
#
# Formasjonene holder seg dessuten innenfor ca. ±230 px fra midten, så
# bevegelsesmønstrene har litt plass å svinge på også med 40 fiender.
# Alt regnes ut én gang per bølge, så litt løkker her koster ingenting.

const NAMES := ["rows", "v_shape", "ring", "checkerboard", "two_groups",
		"diamond", "arrow", "columns", "x_shape"]

const MIN_Y := 40.0
const MAX_Y := 230.0
const MIN_SPACING := 28.0

const TOP := 60.0
const SIDE_MARGIN := 40.0
const H_SPACING := 40.0
const V_SPACING := 34.0


static func build(kind: String, count: int, area: Vector2) -> Array:
	var slots := []
	if count <= 0:
		return slots
	match kind:
		"rows":
			slots = _rows(count, area)
		"v_shape":
			slots = _v_shape(count, area)
		"ring":
			slots = _ring(count, area)
		"checkerboard":
			slots = _checkerboard(count, area)
		"two_groups":
			slots = _two_groups(count, area)
		"diamond":
			slots = _diamond(count, area)
		"arrow":
			slots = _arrow(count, area)
		"columns":
			slots = _columns(count, area)
		"x_shape":
			slots = _x_shape(count, area)
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


# Én rad med n plasser, sentrert rundt cx.
static func _row(out: Array, cx: float, y: float, n: int, spacing: float) -> void:
	var left := cx - (n - 1) * spacing / 2.0
	for i in n:
		out.append(Vector2(left + i * spacing, y))


# Klassisk: rader med 8 i bredden. En halvfull siste rad står midtstilt.
static func _rows(count: int, area: Vector2) -> Array:
	var cols := int(max(8, ceil(count / 6.0)))
	var out := []
	var left := count
	var row := 0
	while left > 0:
		var n := int(min(cols, left))
		_row(out, area.x / 2, TOP + row * V_SPACING, n, H_SPACING)
		left -= n
		row += 1
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


# Ellipse-ringer rundt samme sentrum. Så mange ringer som trengs for at det
# blir minst RING_SPACING px mellom naboer langs ringen (én ring til og med 21,
# to opp til 40); med flere ringer vokser den ytterste litt, så de indre får
# plass. Fiendene fordeles etter omkretsen. Under 16 fiender krymper ringen,
# så den ikke blir glissen.
const RING_SPACING := 37.0
const MAX_RINGS := 3

static func _ring(count: int, area: Vector2) -> Array:
	var rings := 1
	while rings < MAX_RINGS and _ring_capacity(rings) < count:
		rings += 1
	var scale: float = min(1.0, count / 16.0)
	var radii := []
	var total := 0.0
	for i in rings:
		var r: Vector2 = _ring_radius(rings, i) * scale
		radii.append(r)
		total += _ellipse_perimeter(r)
	# Toppen av ytterste ring like under TOP, men aldri så bunnen går under MAX_Y.
	var outer: Vector2 = radii[0]
	var center := Vector2(area.x / 2, min(TOP + 8.0 + outer.y, MAX_Y - 2.0 - outer.y))
	var out := []
	var left := count
	for i in rings:
		var n := left
		if i < rings - 1:
			n = int(min(left, round(count * _ellipse_perimeter(radii[i]) / total)))
		# Annenhver ring forskyves et halvt steg, så de ikke står rett over hverandre.
		_ring_points(out, center, radii[i], n, 0.5 * (i % 2))
		left -= n
	return out


# Radius til ring nr. i (0 = ytterst) når formasjonen har `rings` ringer.
static func _ring_radius(rings: int, i: int) -> Vector2:
	return Vector2(170.0 + 25.0 * (rings - 1) - 58.0 * i, 72.0 + 8.0 * (rings - 1) - 32.0 * i)


static func _ring_capacity(rings: int) -> int:
	var total := 0
	for i in rings:
		total += int(_ellipse_perimeter(_ring_radius(rings, i)) / RING_SPACING)
	return total


# Ramanujans tilnærming av omkretsen til en ellipse.
static func _ellipse_perimeter(r: Vector2) -> float:
	return PI * (3.0 * (r.x + r.y) - sqrt((3.0 * r.x + r.y) * (r.x + 3.0 * r.y)))


# n plasser jevnt fordelt langs BUELENGDEN av ellipsen, med start øverst
# (jevnt fordelt i vinkel klumper de seg i endene av en flat ellipse).
# phase 0.5 = forskjøvet et halvt steg. Speilsymmetrisk om den loddrette aksen.
static func _ring_points(out: Array, center: Vector2, radius: Vector2, n: int, phase: float) -> void:
	if n <= 0:
		return
	var steps := 96
	var pts := []
	var cum := [0.0]
	for i in steps + 1:
		var a: float = -PI / 2 + TAU * i / steps
		pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
		if i > 0:
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
	var seg := 1
	for k in n:
		var target: float = cum[steps] * (k + phase) / n
		while seg < steps and cum[seg] < target:
			seg += 1
		var t: float = (target - cum[seg - 1]) / (cum[seg] - cum[seg - 1])
		out.append(pts[seg - 1].linear_interpolate(pts[seg], t))


# Sjakkbrett: annenhver rute, lange og korte rader om hverandre, så brettet er
# speilsymmetrisk. Få fiender gir et smalt brett, mange gir et bredere (maks 5 rader).
static func _checkerboard(count: int, area: Vector2) -> Array:
	var row_h := 30.0
	var sizes := _checker_rows(count, 4 if count <= 24 else 5)
	var widest := 1
	for k in sizes:
		widest = int(max(widest, k))
	# Rutebredde: naboer i samme rad står 2 * step fra hverandre.
	var step: float = min(36.0, 230.0 / max(1, widest - 1))
	var out := []
	for row in sizes.size():
		_row(out, area.x / 2, TOP + row * row_h, sizes[row], 2.0 * step)
	return out


# Radstørrelsene i sjakkbrettet: p og p - 1 annenhver gang. Velger den smaleste
# p (og lang eller kort første rad) der den halvfulle siste raden kan midtstilles
# uten å forlate rutenettet, dvs. at antall tomme ruter i den er et partall.
static func _checker_rows(count: int, max_rows: int) -> Array:
	for p in range(4, count + 3):
		for first in [p, p - 1]:
			var sizes := []
			var cap: int = first
			var last_cap := cap
			var left := count
			while left > 0:
				last_cap = cap
				sizes.append(int(min(cap, left)))
				left -= cap
				cap = 2 * p - 1 - cap
			var last: int = sizes.back()
			if sizes.size() <= max_rows and (last_cap - last) % 2 == 0:
				return sizes
	return [count]


# To blokker på hver sin side av en tom gate (ca. 96 px) midt på skjermen.
# Blokkene er 4 brede og vokser nedover; først når de er 5 høye blir de bredere.
# Ved oddetall får venstre blokk én ekstra.
static func _two_groups(count: int, area: Vector2) -> Array:
	var inner := 64.0       # fra skjermmidten til innerste kolonne
	var max_rows := 5
	var per_side := (count + 1) / 2
	var cols := int(max(4, ceil(per_side / float(max_rows))))
	var out := []
	for side in [-1.0, 1.0]:
		var left: int = per_side if side < 0.0 else count - per_side
		var block_cx: float = area.x / 2 + side * (inner + (cols - 1) * H_SPACING / 2.0)
		var row := 0
		while left > 0:
			var n := int(min(cols, left))
			_row(out, block_cx, TOP + row * V_SPACING, n, H_SPACING)
			left -= n
			row += 1
	return out


# Rombe: smal øverst og nederst, bredest på midten. Maks 7 rader; med flere
# fiender blir radene bredere (1-3-5-7-5-3-1, 2-4-6-8-6-4-2) i stedet for flere.
static func _diamond(count: int, area: Vector2) -> Array:
	var row_h := 30.0
	# m = rader over (og under) midtraden.
	var m := 3
	if count < 4:
		m = 0
	elif count < 9:
		m = 1
	elif count < 16:
		m = 2
	var widths := _diamond_widths(count, m)
	var widest: int = widths[m]
	var spacing: float = min(H_SPACING, (area.x - 2 * SIDE_MARGIN) / max(1, widest - 1))
	# 7 rader rekker ikke fra TOP til MAX_Y: da starter romben litt høyere.
	var top: float = min(TOP, MAX_Y - 2.0 - 2 * m * row_h)
	var out := []
	for i in widths.size():
		_row(out, area.x / 2, top + i * row_h, widths[i], spacing)
	return out


# Radbreddene i en rombe med 2 * m + 1 rader. Prøver spiss på 1 eller 2 og alle
# "steg" (hvor mye bredere hver rad er enn den utenfor) og velger den jevneste
# skråkanten, helst spiss og smal. Det siste steget, inn til midtraden, er det
# som får summen til å gå opp. Maks 98 forsøk, én gang per bølge.
static func _diamond_widths(count: int, m: int) -> Array:
	var best_tip := 0
	var best_steps := []
	var best_cost := 1e9
	for tip in [1, 2]:
		for code in int(pow(7, max(0, m - 1))):
			var steps := []
			var rest: int = count - (2 * m + 1) * tip
			var digits: int = code
			for j in range(1, m):
				var step: int = digits % 7 + 1
				digits /= 7
				steps.append(step)
				rest -= step * (2 * (m - j) + 1)   # steget gjelder alle radene innenfor
			if m == 0 or rest < 1:
				continue
			steps.append(rest)
			var total := 0
			for d in steps:
				total += d
			var mean := total / float(m)
			var cost: float = 0.5 * (tip - 1) + 0.3 * (tip + total)
			for d in steps:
				cost += (d - mean) * (d - mean)
			if cost < best_cost - 0.0001:
				best_cost = cost
				best_tip = tip
				best_steps = steps
	if best_steps.empty():
		return [count]
	var widths := [best_tip]
	for k in m:
		widths.append(widths[k] + best_steps[k])
	for k in m:
		widths.append(widths[m - 1 - k])
	return widths


# Pilspiss som peker NED mot spilleren: spissen er nederst i midten, armene
# går opp og ut. Med flere fiender kommer mindre V-er inni den ytterste, alle
# med armtuppene på samme linje øverst.
const ARROW_SHRINK := 3    # hver indre V har 3 færre per arm og spissen 3 trinn høyere

static func _arrow(count: int, area: Vector2) -> Array:
	var arm := 1
	while _arrow_capacity(arm) < count:
		arm += 1
	var dx: float = min(32.0, 232.0 / arm)
	var dy: float = min(20.0, 165.0 / arm)
	var cx := area.x / 2
	var apex_y := TOP + arm * dy
	var out := []
	var left := count
	while left > 0 and arm >= 0:
		var n := int(min(2 * arm + 1, left))
		var pairs := n / 2
		if n % 2 == 1:
			out.append(Vector2(cx, apex_y))
		elif arm >= 2:
			# Partall (bare den innerste, halvfulle V-en): behold spissen og sett
			# den siste midt på topplinja, så V-en fortsatt er symmetrisk.
			out.append(Vector2(cx, apex_y))
			out.append(Vector2(cx, TOP))
			pairs -= 1
		for step in range(1, pairs + 1):
			out.append(Vector2(cx - step * dx, apex_y - step * dy))
			out.append(Vector2(cx + step * dx, apex_y - step * dy))
		left -= n
		arm -= ARROW_SHRINK
		apex_y -= ARROW_SHRINK * dy
	return out


# Hvor mange som får plass i en pil der den ytterste V-en har `arm` per arm.
static func _arrow_capacity(arm: int) -> int:
	var total := 0
	while arm >= 0:
		total += 2 * arm + 1
		arm -= ARROW_SHRINK
	return total


# 4–8 loddrette søyler med brede gater mellom (64–80 px), maks 5 i høyden, så
# spilleren kan skyte gjennom gatene på de bakerste.
static func _columns(count: int, area: Vector2) -> Array:
	var max_tall := 5
	var pillars := int(clamp(ceil(count / float(max_tall)), 4, 8))
	# Én søyle til hvis det går opp da, eller hvis resten ellers ikke kan speiles
	# (partall søyler og oddetall til overs).
	if pillars < 8 and count % pillars != 0:
		if count % (pillars + 1) == 0 or (pillars % 2 == 0 and (count % pillars) % 2 == 1):
			pillars += 1
	var base := count / pillars
	var extra := count % pillars
	var heights := []
	for i in pillars:
		heights.append(base)
	# Resten deles ut parvis fra midten og utover (bunnlinja blir en slak V).
	# Oddetall søyler og partall til overs: fra kantene og innover i stedet
	# (en bue), ellers ville midtsøyla blitt stående igjen som et hakk.
	var outside_in := pillars % 2 == 1 and extra % 2 == 0
	for q in (pillars + 1) / 2:
		var lo: int = q if outside_in else (pillars - 1) / 2 - q
		var hi: int = pillars - 1 - lo
		if extra > 0:
			heights[lo] += 1
			extra -= 1
		if extra > 0 and hi != lo:
			heights[hi] += 1
			extra -= 1
	var gap: float = min(80.0, 448.0 / (pillars - 1))   # alltid ≥ 56 px mellom søylene
	var left := area.x / 2 - (pillars - 1) * gap / 2.0
	var out := []
	for i in pillars:
		for j in heights[i]:
			out.append(Vector2(left + i * gap, TOP + j * V_SPACING))
	return out


# Kryss: to diagonaler gjennom midten. Opptil 21 fiender gir et enkelt kryss
# som vokser utover fra midten. Flere enn det gir full høyde og doble linjer:
# en ekstra linje på innsiden av hver arm, fylt fra midten og utover.
static func _x_shape(count: int, area: Vector2) -> Array:
	var dx := 34.0
	var dy := 16.5
	var arm := 5                       # rader over og under midten
	var cx := area.x / 2
	var out := []
	if count <= 4 * arm + 1:
		# Enkelt kryss: plassene ligger i (±r, ±r). Partall har ikke midtplassen.
		var pairs := count / 2
		var mid_y := TOP + ((pairs + 1) / 2) * dy
		if count % 2 == 1:
			out.append(Vector2(cx, mid_y))
		for p in pairs:
			var r: int = p / 2 + 1
			var y: float = mid_y - r * dy if p % 2 == 0 else mid_y + r * dy
			out.append(Vector2(cx - r * dx, y))
			out.append(Vector2(cx + r * dx, y))
		return out
	# Dobbelt kryss på et sjakkbrettnett (kolonne + rad er alltid et oddetall):
	# ytterlinjene ligger i kolonne ±(|r| + 1), innerlinjene i ±(|r| - 1).
	# Nettet rommer 8 * arm = 40. Skulle noen be om flere, vokser krysset.
	arm = int(max(arm, ceil(count / 8.0)))
	var cy := TOP + arm * dy
	for r in range(-arm, arm + 1):
		var k: int = int(abs(r)) + 1
		out.append(Vector2(cx - k * dx, cy + r * dy))
		out.append(Vector2(cx + k * dx, cy + r * dy))
	# Innerlinjene møtes i to plasser rett over og under midten: begge ved
	# partall til overs, bare den øverste ved oddetall. Resten går parvis
	# utover, oppe og nede annenhver gang.
	var extra := count - out.size()
	if extra > 0:
		out.append(Vector2(cx, cy - dy))
		extra -= 1
	if extra % 2 == 1:
		out.append(Vector2(cx, cy + dy))
		extra -= 1
	for p in extra / 2:
		var r: int = p / 2 + 2
		var y: float = cy - r * dy if p % 2 == 0 else cy + r * dy
		out.append(Vector2(cx - (r - 1) * dx, y))
		out.append(Vector2(cx + (r - 1) * dx, y))
	return out
