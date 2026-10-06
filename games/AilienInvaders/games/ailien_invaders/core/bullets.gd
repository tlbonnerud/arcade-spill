extends Node2D

# Kulelaget: eier alle kuler, flytter dem, tegner dem og sjekker treff mot
# spiller og sverm. Ligger øverst i tegnerekkefølgen (z_index) — en nodes
# egen _draw() havner under barna dens, så kuler tegnet rett på rota ville
# blitt skjult av bakgrunnen.
#
# Alle kuler tegnes i ett lag med draw_texture_rect_region (én node totalt,
# aldri én node per kule — se docs/ARCHITECTURE.md). Hver kuletype er et
# sprite-ark med 10×10-ruter på rad; ruta velges ut fra kulas alder.
#
# Spillerens kuler styres av statblokken (player/player_stats.gd), som main
# setter med apply_stats(): hvor mange i lufta, vifte, størrelse, skade,
# gjennomtrenging, målsøking og eksplosjon ved drap.

const PlayerStats := preload("res://games/ailien_invaders/player/player_stats.gd")

const ENEMY_BULLET_SPEED := 150.0
const OFFSCREEN_MARGIN := 8.0
const FRAME_SIZE := Vector2(10, 10)
const SPREAD_STEP := 0.157           # radianer (9 grader) mellom kulene i en vifte
const HOMING_RANGE := 240.0         # px: lenger unna enn dette svinger ikke kula
const HOMING_AHEAD := 6.0           # målet må ligge minst så mange px foran kula
const EXPLOSION_TIME := 0.25        # s: hvor lenge eksplosjonsringen vises
const EXPLOSION_COLOR := Color(1.0, 0.7, 0.2)

# Kuletyper. Svermen velger type per fiende (enemies/enemy_types.gd).
# frame_time er sekunder per rute; antall ruter regnes ut fra teksturbredden.
# (preload krever bokstavelige stier i Godot 3, derfor ingen SPRITES-konstant.)
const KINDS := {
	"player": {"texture": preload("res://games/ailien_invaders/sprites/Projectile_1.png"), "frame_time": 0.05},
	"red":    {"texture": preload("res://games/ailien_invaders/sprites/Projectile_2.png"), "frame_time": 0.08},
	"green":  {"texture": preload("res://games/ailien_invaders/sprites/Projectile_3.png"), "frame_time": 0.08},
	"blue":   {"texture": preload("res://games/ailien_invaders/sprites/Projectile_4.png"), "frame_time": 0.05},
	"orb":    {"texture": preload("res://games/ailien_invaders/sprites/Projectile_5.png"), "frame_time": 0.08},
}

var area_size := Vector2(640, 360)
var stats: Dictionary = PlayerStats.BASE.duplicate()
var player_bullets := []  # [{pos, vel, age, kind, volley, hits}]
var enemy_bullets := []   # [{pos, kind, age, vel}]
var explosions := []      # [{pos, radius, age}] bare for tegning
var enemy_speed_mult := 1.0  # settes av main fra bølgedataene
var next_volley := 0

var _player: Node = null
var _swarm: Node = null


func _ready() -> void:
	z_index = 10


func setup(size: Vector2, player: Node, swarm: Node) -> void:
	area_size = size
	_player = player
	_swarm = swarm


func apply_stats(s: Dictionary) -> void:
	stats = s


func clear() -> void:
	player_bullets.clear()
	enemy_bullets.clear()
	explosions.clear()
	update()


func clear_enemy_bullets() -> void:
	enemy_bullets.clear()


# Antall skudd (vifter) i lufta. Taket er stats["max_bullets"]; én vifte
# teller som ett skudd uansett hvor mange kuler den har.
func volleys_in_air() -> int:
	var seen := {}
	for b in player_bullets:
		seen[b["volley"]] = true
	return seen.size()


func player_bullet_count() -> int:
	return player_bullets.size()


func can_fire() -> bool:
	return volleys_in_air() < int(stats["max_bullets"])


# Avfyrer ett skudd: stats["shots"] kuler i vifte. Returnerer true hvis det gikk.
func spawn_player_bullet(pos: Vector2) -> bool:
	if not can_fire():
		return false
	var shots := int(stats["shots"])
	var speed := float(stats["bullet_speed"])
	for k in shots:
		var angle: float = (k - (shots - 1) / 2.0) * SPREAD_STEP
		var b := _make_bullet(pos, "player")
		b["vel"] = Vector2(sin(angle), -cos(angle)) * speed
		b["volley"] = next_volley
		b["hits"] = []
		player_bullets.append(b)
	next_volley += 1
	return true


# dir er en enhetsvektor; rett ned som standard, mot spilleren for siktede skudd.
func spawn_enemy_bullet(pos: Vector2, kind: String = "red", dir: Vector2 = Vector2.DOWN) -> void:
	var b := _make_bullet(pos, kind)
	b["vel"] = dir * ENEMY_BULLET_SPEED * enemy_speed_mult
	enemy_bullets.append(b)


func enemy_bullet_count() -> int:
	return enemy_bullets.size()


func step(delta: float) -> void:
	_step_player_bullets(delta)

	var remaining := []
	for b in enemy_bullets:
		b["pos"] += b["vel"] * delta
		b["age"] += delta
		if _offscreen(b["pos"]):
			continue
		if _player.hit_test(b["pos"]):
			_player.take_hit()
			continue
		remaining.append(b)
	enemy_bullets = remaining

	for ex in explosions.duplicate():
		ex["age"] += delta
		if ex["age"] >= EXPLOSION_TIME:
			explosions.erase(ex)
	update()


func _step_player_bullets(delta: float) -> void:
	var homing := float(stats["homing"])
	var damage := int(stats["damage"])
	var pierce := int(stats["pierce"])
	var explosion := float(stats["explosion"])
	var extra := FRAME_SIZE / 2 * (float(stats["bullet_size"]) - 1.0)
	var remaining := []
	for b in player_bullets:
		if homing > 0.0:
			_steer(b, homing, delta)
		b["pos"] += b["vel"] * delta
		b["age"] += delta
		if _offscreen(b["pos"]):
			continue
		var e: Dictionary = _swarm.hit_at(b["pos"], damage, extra, b["hits"])
		if not e.empty():
			if not e["alive"] and explosion > 0.0:
				_explode(e["sprite"].position, explosion)
			b["hits"].append(e)
			if b["hits"].size() > pierce:
				continue
		remaining.append(b)
	player_bullets = remaining


# Målsøking: svinger kula mot nærmeste fiende som ligger foran den, med
# begrenset svingfart. Farten holdes, bare retningen endres.
func _steer(b: Dictionary, turn_rate: float, delta: float) -> void:
	var e: Dictionary = _swarm.nearest_enemy(b["pos"], HOMING_RANGE, b["pos"].y - HOMING_AHEAD)
	if e.empty():
		return
	var vel: Vector2 = b["vel"]
	var want: float = (e["sprite"].position - b["pos"]).angle()
	var diff := wrapf(want - vel.angle(), -PI, PI)
	var max_turn := turn_rate * delta
	b["vel"] = vel.rotated(clamp(diff, -max_turn, max_turn))


# Drap med eksplosjon: naboene tar 1 skade. Smitter ikke videre (et drap fra
# en eksplosjon gir ingen ny eksplosjon), ellers ville hele rader forsvinne.
func _explode(center: Vector2, radius: float) -> void:
	_swarm.damage_area(center, radius, 1)
	show_ring(center, radius)


# Tegner en ring som vokser og blekner (eksplosjon, pigger).
func show_ring(center: Vector2, radius: float) -> void:
	explosions.append({"pos": center, "radius": radius, "age": 0.0})


func _offscreen(p: Vector2) -> bool:
	return p.y > area_size.y + OFFSCREEN_MARGIN or p.y < -OFFSCREEN_MARGIN \
			or p.x < -OFFSCREEN_MARGIN or p.x > area_size.x + OFFSCREEN_MARGIN


func _make_bullet(pos: Vector2, kind: String) -> Dictionary:
	if not KINDS.has(kind):
		push_warning("Ukjent kuletype '%s', bruker 'red'" % kind)
		kind = "red"
	return {"pos": pos, "kind": kind, "age": 0.0}


func _draw() -> void:
	var size := float(stats["bullet_size"])
	for b in player_bullets:
		var vel: Vector2 = b["vel"]
		draw_set_transform(b["pos"], vel.angle() + PI / 2, Vector2.ONE * size)
		_draw_bullet_at(b, -FRAME_SIZE / 2)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	for b in enemy_bullets:
		_draw_bullet_at(b, b["pos"] - FRAME_SIZE / 2)
	for ex in explosions:
		var u: float = ex["age"] / EXPLOSION_TIME
		var color := EXPLOSION_COLOR
		color.a = 1.0 - u
		draw_arc(ex["pos"], ex["radius"] * (0.4 + 0.6 * u), 0.0, TAU, 20, color, 2.0)


func _draw_bullet_at(b: Dictionary, top_left: Vector2) -> void:
	var kind: Dictionary = KINDS[b["kind"]]
	var tex: Texture = kind["texture"]
	var frames := int(tex.get_width() / FRAME_SIZE.x)
	var frame := int(b["age"] / kind["frame_time"]) % frames
	var src := Rect2(Vector2(frame * FRAME_SIZE.x, 0), FRAME_SIZE)
	draw_texture_rect_region(tex, Rect2(top_left, FRAME_SIZE), src)
