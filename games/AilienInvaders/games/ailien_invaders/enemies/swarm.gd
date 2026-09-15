extends Node2D

# Fiendesvermen: bygger formasjonen, flytter og animerer den, velger hvem
# som skyter og håndterer treff. Sier fra via signaler når noe viktig skjer.
#
# Fremtid (se docs/ARCHITECTURE.md): dette blir wave_manager + enemy.gd,
# og formasjon/bevegelse/skyting hentes fra bølgedata i waves/.

signal enemy_killed(points)
signal cleared              # alle fiender i bølgen er døde
signal reached_bottom       # svermen nådde spillerens høyde
signal fire_requested(pos, kind)  # en fiende vil skyte fra pos; kind er kuletype (bullets.gd KINDS)

const SPRITES := "res://games/ailien_invaders/sprites/"

const COLS := 8
const ROWS := 4
const H_SPACING := 40.0
const V_SPACING := 34.0
const GRID_TOP := 64.0
const SIDE_MARGIN := 24.0
const DROP := 12.0
const BOTTOM_LIMIT := 304.0
const ANIM_INTERVAL := 0.35
const HIT_HALF_SIZE := Vector2(14, 12)
const MUZZLE_OFFSET := Vector2(0, 12)

# Én fiendetype per rad (øverst til nederst), poeng og kuletype for hver.
# Kulefargen følger fienden: rød hai, blå vinget, grønn kyklop, lilla manet.
const ROW_TEXTURES := ["Enemy_4.png", "Enemy_2.png", "Enemy_1.png", "Enemy_3.png"]
const ROW_POINTS := [40, 30, 20, 10]
const ROW_BULLETS := ["red", "blue", "green", "orb"]

var area_size := Vector2(640, 360)
var wave := 1
var enemies := []  # [{sprite, points, alive}]
var move_dir := 1.0
var anim_timer := 0.0
var fire_timer := 1.5


func setup(size: Vector2) -> void:
	area_size = size


func spawn(wave_number: int) -> void:
	wave = wave_number
	for child in get_children():
		remove_child(child)
		child.queue_free()
	enemies.clear()
	move_dir = 1.0

	# Litt lavere start for hver bølge, så det blir vanskeligere.
	position = Vector2(0, min((wave - 1) * DROP, 60.0))

	var grid_width := (COLS - 1) * H_SPACING
	var left := (area_size.x - grid_width) / 2
	for row in ROWS:
		var tex: Texture = load(SPRITES + ROW_TEXTURES[row])
		var hframes := int(tex.get_width() / 32)
		for col in COLS:
			var s := Sprite.new()
			s.texture = tex
			s.hframes = hframes
			s.position = Vector2(left + col * H_SPACING, GRID_TOP + row * V_SPACING)
			add_child(s)
			enemies.append({"sprite": s, "points": ROW_POINTS[row], "bullet": ROW_BULLETS[row], "alive": true})


func alive_count() -> int:
	var n := 0
	for e in enemies:
		if e["alive"]:
			n += 1
	return n


# Sprite-animasjon. Kjører også under game over, så svermen "lever" i bakgrunnen.
func animate(delta: float) -> void:
	anim_timer += delta
	if anim_timer >= ANIM_INTERVAL:
		anim_timer = 0.0
		for e in enemies:
			if e["alive"]:
				var s: Sprite = e["sprite"]
				s.frame = (s.frame + 1) % s.hframes


# Bevegelse og skyting. fire_allowed settes av main (tak på antall fiendekuler).
func step(delta: float, fire_allowed: bool) -> void:
	_move(delta)
	_fire(delta, fire_allowed)


func _move(delta: float) -> void:
	var speed := 30.0 + (ROWS * COLS - alive_count()) * 3.0 + (wave - 1) * 10.0
	position.x += move_dir * speed * delta

	var min_x := area_size.x
	var max_x := 0.0
	var max_y := 0.0
	for e in enemies:
		if not e["alive"]:
			continue
		var p: Vector2 = position + e["sprite"].position
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	if (max_x > area_size.x - SIDE_MARGIN and move_dir > 0) \
			or (min_x < SIDE_MARGIN and move_dir < 0):
		move_dir = -move_dir
		position.y += DROP

	if max_y >= BOTTOM_LIMIT:
		emit_signal("reached_bottom")


func _fire(delta: float, allowed: bool) -> void:
	fire_timer -= delta
	if fire_timer <= 0.0 and allowed:
		fire_timer = rand_range(0.6, 1.4)
		var alive := []
		for e in enemies:
			if e["alive"]:
				alive.append(e)
		if alive.size() > 0:
			var e: Dictionary = alive[randi() % alive.size()]
			emit_signal("fire_requested", position + e["sprite"].position + MUZZLE_OFFSET, e["bullet"])


# Prøver å treffe en fiende i punktet p. Returnerer true hvis noen ble truffet.
func try_hit(p: Vector2) -> bool:
	var killed := false
	for e in enemies:
		if not e["alive"]:
			continue
		var ep: Vector2 = position + e["sprite"].position
		if abs(p.x - ep.x) < HIT_HALF_SIZE.x and abs(p.y - ep.y) < HIT_HALF_SIZE.y:
			e["alive"] = false
			e["sprite"].visible = false
			emit_signal("enemy_killed", e["points"])
			killed = true
			break

	# Signalet sendes etter løkka: mottakeren kan kalle spawn() og bytte ut lista.
	if killed and alive_count() == 0:
		emit_signal("cleared")
	return killed
