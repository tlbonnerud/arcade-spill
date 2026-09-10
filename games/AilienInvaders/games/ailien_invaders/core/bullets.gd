extends Node2D

# Kulelaget: eier alle kuler, flytter dem, tegner dem og sjekker treff mot
# spiller og sverm. Ligger øverst i tegnerekkefølgen (z_index) — en nodes
# egen _draw() havner under barna dens, så kuler tegnet rett på rota ville
# blitt skjult av bakgrunnen.
#
# Fremtid: kule-pool med flere typer (spread, pierce, laser) styrt av
# player_stats, se docs/DESIGN.md.

const PLAYER_BULLET_SPEED := 420.0
const ENEMY_BULLET_SPEED := 150.0
const OFFSCREEN_MARGIN := 8.0

var area_size := Vector2(640, 360)
var player_bullet := Vector2.ZERO
var player_bullet_active := false
var enemy_bullets := []  # [Vector2]

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
	player_bullet = pos
	player_bullet_active = true
	return true


func spawn_enemy_bullet(pos: Vector2) -> void:
	enemy_bullets.append(pos)


func enemy_bullet_count() -> int:
	return enemy_bullets.size()


func step(delta: float) -> void:
	if player_bullet_active:
		player_bullet.y -= PLAYER_BULLET_SPEED * delta
		if player_bullet.y < -OFFSCREEN_MARGIN:
			player_bullet_active = false
		elif _swarm.try_hit(player_bullet):
			player_bullet_active = false

	var remaining := []
	for b in enemy_bullets:
		b.y += ENEMY_BULLET_SPEED * delta
		if b.y > area_size.y + OFFSCREEN_MARGIN:
			continue
		if _player.hit_test(b):
			_player.take_hit()
			continue
		remaining.append(b)
	enemy_bullets = remaining
	update()


func _draw() -> void:
	if player_bullet_active:
		draw_rect(Rect2(player_bullet - Vector2(2, 6), Vector2(4, 12)), Color(1, 1, 0.5))
		draw_rect(Rect2(player_bullet - Vector2(1, 5), Vector2(2, 10)), Color(1, 1, 1))
	for b in enemy_bullets:
		draw_rect(Rect2(b - Vector2(2, 6), Vector2(4, 12)), Color(1, 0.35, 0.25))
		draw_rect(Rect2(b - Vector2(1, 5), Vector2(2, 10)), Color(1, 0.75, 0.5))
