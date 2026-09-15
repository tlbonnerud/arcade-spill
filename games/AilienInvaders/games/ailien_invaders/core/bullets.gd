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
# Fremtid: kule-pool med flere typer (spread, pierce, laser) styrt av
# player_stats, se docs/DESIGN.md.

const PLAYER_BULLET_SPEED := 420.0
const ENEMY_BULLET_SPEED := 150.0
const OFFSCREEN_MARGIN := 8.0
const FRAME_SIZE := Vector2(10, 10)

# Kuletyper. Svermen velger type per fiende (se swarm.gd ROW_BULLETS).
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
var player_bullet := {}  # {pos, kind, age}
var player_bullet_active := false
var enemy_bullets := []  # [{pos, kind, age}]

var _player: Node = null
var _swarm: Node = null


func _ready() -> void:
	z_index = 10


func setup(size: Vector2, player: Node, swarm: Node) -> void:
	area_size = size
	_player = player
	_swarm = swarm


func clear() -> void:
	player_bullet_active = false
	enemy_bullets.clear()
	update()


# Bare én spillerkule i lufta om gangen. Returnerer true hvis den ble avfyrt.
func spawn_player_bullet(pos: Vector2) -> bool:
	if player_bullet_active:
		return false
	player_bullet = _make_bullet(pos, "player")
	player_bullet_active = true
	return true


func spawn_enemy_bullet(pos: Vector2, kind: String = "red") -> void:
	enemy_bullets.append(_make_bullet(pos, kind))


func enemy_bullet_count() -> int:
	return enemy_bullets.size()


func step(delta: float) -> void:
	if player_bullet_active:
		player_bullet["pos"].y -= PLAYER_BULLET_SPEED * delta
		player_bullet["age"] += delta
		if player_bullet["pos"].y < -OFFSCREEN_MARGIN:
			player_bullet_active = false
		elif _swarm.try_hit(player_bullet["pos"]):
			player_bullet_active = false

	var remaining := []
	for b in enemy_bullets:
		b["pos"].y += ENEMY_BULLET_SPEED * delta
		b["age"] += delta
		if b["pos"].y > area_size.y + OFFSCREEN_MARGIN:
			continue
		if _player.hit_test(b["pos"]):
			_player.take_hit()
			continue
		remaining.append(b)
	enemy_bullets = remaining
	update()


func _make_bullet(pos: Vector2, kind: String) -> Dictionary:
	if not KINDS.has(kind):
		push_warning("Ukjent kuletype '%s', bruker 'red'" % kind)
		kind = "red"
	return {"pos": pos, "kind": kind, "age": 0.0}


func _draw() -> void:
	if player_bullet_active:
		_draw_bullet(player_bullet)
	for b in enemy_bullets:
		_draw_bullet(b)


func _draw_bullet(b: Dictionary) -> void:
	var kind: Dictionary = KINDS[b["kind"]]
	var tex: Texture = kind["texture"]
	var frames := int(tex.get_width() / FRAME_SIZE.x)
	var frame := int(b["age"] / kind["frame_time"]) % frames
	var src := Rect2(Vector2(frame * FRAME_SIZE.x, 0), FRAME_SIZE)
	var dst := Rect2(b["pos"] - FRAME_SIZE / 2, FRAME_SIZE)
	draw_texture_rect_region(tex, dst, src)
