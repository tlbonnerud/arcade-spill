extends Node2D

# Ailien Invaders — grunnversjonen.
# Piltaster flytter romskipet, A (Z) skyter. SELECT/ESC går til menyen.

const SIZE := Vector2(640, 360)
const GAME_ID := "ailien_invaders"
const SPRITES := "res://games/ailien_invaders/sprites/"

const COLS := 8
const ROWS := 4
const H_SPACING := 40.0
const V_SPACING := 34.0
const GRID_TOP := 64.0
const SIDE_MARGIN := 24.0
const DROP := 12.0

const PLAYER_Y := 330.0
const PLAYER_SPEED := 220.0
const PLAYER_BULLET_SPEED := 420.0
const ENEMY_BULLET_SPEED := 150.0
const BOTTOM_LIMIT := 304.0

# Én fiendetype per rad (øverst til nederst) og poeng for hver.
const ROW_TEXTURES := ["Enemy_4.png", "Enemy_2.png", "Enemy_1.png", "Enemy_3.png"]
const ROW_POINTS := [40, 30, 20, 10]

var bg: Sprite
var player: Sprite
var swarm: Node2D
var bullet_layer: Node2D
var enemies := []  # [{sprite, points, alive}]

var move_dir := 1.0
var player_bullet := Vector2.ZERO
var player_bullet_active := false
var enemy_bullets := []
var fire_timer := 1.5
var anim_timer := 0.0
var bg_timer := 0.0

var score := 0
var lives := 3
var wave := 1
var invuln := 0.0
var game_over := false

var score_label: Label
var lives_label: Label
var msg_label: Label


func _ready() -> void:
	randomize()
	_build_background()
	_build_player()
	_build_bullet_layer()
	_build_hud()
	_spawn_wave()

	if Arcade.smoke_test:
		yield(get_tree().create_timer(0.5), "timeout")
		print("Røyktest: Ailien Invaders kjører, går tilbake til launcheren ...")
		Arcade.quit_to_launcher()


func _build_background() -> void:
	bg = Sprite.new()
	bg.texture = load(SPRITES + "Background.png")
	bg.hframes = 2
	bg.centered = false
	bg.scale = SIZE / Vector2(160, 90)
	add_child(bg)


func _build_player() -> void:
	player = Sprite.new()
	player.texture = load(SPRITES + "Romskip.png")
	player.hframes = 4
	player.position = Vector2(SIZE.x / 2, PLAYER_Y)
	add_child(player)


func _build_bullet_layer() -> void:
	# Egen node øverst i tegnerekkefølgen — en nodes egen _draw() havner
	# under barna dens, så kuler tegnet rett på rota blir skjult av bakgrunnen.
	bullet_layer = Node2D.new()
	bullet_layer.z_index = 10
	bullet_layer.connect("draw", self, "_draw_bullets")
	add_child(bullet_layer)


func _build_hud() -> void:
	score_label = _label(Vector2(8, 4), "POENG: 0")
	lives_label = _label(Vector2(SIZE.x - 108, 4), "LIV: %d" % lives)
	msg_label = _label(Vector2(0, SIZE.y / 2 - 30), "")
	msg_label.rect_size = Vector2(SIZE.x, 60)
	msg_label.align = Label.ALIGN_CENTER
	msg_label.visible = false


func _label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.rect_position = pos
	l.text = text
	add_child(l)
	return l


func _spawn_wave() -> void:
	if swarm != null:
		swarm.queue_free()
	swarm = Node2D.new()
	# Litt lavere start for hver bølge, så det blir vanskeligere.
	swarm.position = Vector2(0, min((wave - 1) * DROP, 60.0))
	add_child(swarm)
	move_dir = 1.0
	enemies.clear()
	enemy_bullets.clear()
	player_bullet_active = false

	var grid_width := (COLS - 1) * H_SPACING
	var left := (SIZE.x - grid_width) / 2
	for row in ROWS:
		var tex: Texture = load(SPRITES + ROW_TEXTURES[row])
		var hframes := int(tex.get_width() / 32)
		for col in COLS:
			var s := Sprite.new()
			s.texture = tex
			s.hframes = hframes
			s.position = Vector2(left + col * H_SPACING, GRID_TOP + row * V_SPACING)
			swarm.add_child(s)
			enemies.append({"sprite": s, "points": ROW_POINTS[row], "alive": true})


func _alive_count() -> int:
	var n := 0
	for e in enemies:
		if e["alive"]:
			n += 1
	return n


func _process(delta: float) -> void:
	_animate(delta)
	if game_over:
		if Input.is_action_just_pressed("arcade_start"):
			_restart()
		return

	_move_player(delta)
	_move_swarm(delta)
	_shoot(delta)
	_move_bullets(delta)
	bullet_layer.update()


func _animate(delta: float) -> void:
	bg_timer += delta
	if bg_timer >= 0.5:
		bg_timer = 0.0
		bg.frame = (bg.frame + 1) % 2

	anim_timer += delta
	if anim_timer >= 0.35:
		anim_timer = 0.0
		for e in enemies:
			if e["alive"]:
				var s: Sprite = e["sprite"]
				s.frame = (s.frame + 1) % s.hframes

	if not game_over:
		player.frame = int(OS.get_ticks_msec() / 120) % 4
		if invuln > 0.0:
			invuln -= delta
			player.visible = int(OS.get_ticks_msec() / 100) % 2 == 0
		else:
			player.visible = true


func _move_player(delta: float) -> void:
	var dir := Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
	player.position.x = clamp(player.position.x + dir * PLAYER_SPEED * delta, 20, SIZE.x - 20)


func _move_swarm(delta: float) -> void:
	var speed := 30.0 + (ROWS * COLS - _alive_count()) * 3.0 + (wave - 1) * 10.0
	swarm.position.x += move_dir * speed * delta

	var min_x := SIZE.x
	var max_x := 0.0
	var max_y := 0.0
	for e in enemies:
		if not e["alive"]:
			continue
		var p: Vector2 = swarm.position + e["sprite"].position
		min_x = min(min_x, p.x)
		max_x = max(max_x, p.x)
		max_y = max(max_y, p.y)

	if (max_x > SIZE.x - SIDE_MARGIN and move_dir > 0) or (min_x < SIDE_MARGIN and move_dir < 0):
		move_dir = -move_dir
		swarm.position.y += DROP

	if max_y >= BOTTOM_LIMIT:
		_set_game_over("ROMVESENENE TOK DEG!")


func _shoot(delta: float) -> void:
	if Input.is_action_just_pressed("p1_a") and not player_bullet_active:
		player_bullet = player.position + Vector2(0, -12)
		player_bullet_active = true

	fire_timer -= delta
	if fire_timer <= 0.0 and enemy_bullets.size() < 2 + wave:
		fire_timer = rand_range(0.6, 1.4)
		var alive := []
		for e in enemies:
			if e["alive"]:
				alive.append(e)
		if alive.size() > 0:
			var e: Dictionary = alive[randi() % alive.size()]
			enemy_bullets.append(swarm.position + e["sprite"].position + Vector2(0, 12))


func _move_bullets(delta: float) -> void:
	if player_bullet_active:
		player_bullet.y -= PLAYER_BULLET_SPEED * delta
		if player_bullet.y < -8:
			player_bullet_active = false
		else:
			for e in enemies:
				if not e["alive"]:
					continue
				var p: Vector2 = swarm.position + e["sprite"].position
				if abs(player_bullet.x - p.x) < 14 and abs(player_bullet.y - p.y) < 12:
					e["alive"] = false
					e["sprite"].visible = false
					player_bullet_active = false
					score += e["points"]
					score_label.text = "POENG: %d" % score
					if _alive_count() == 0:
						wave += 1
						_spawn_wave()
					break

	var remaining := []
	for b in enemy_bullets:
		b.y += ENEMY_BULLET_SPEED * delta
		if b.y > SIZE.y + 8:
			continue
		if invuln <= 0.0 and not game_over \
				and abs(b.x - player.position.x) < 12 and abs(b.y - player.position.y) < 10:
			_player_hit()
			continue
		remaining.append(b)
	enemy_bullets = remaining


func _player_hit() -> void:
	lives -= 1
	lives_label.text = "LIV: %d" % lives
	if lives <= 0:
		_set_game_over("GAME OVER")
	else:
		invuln = 2.0
		player.position.x = SIZE.x / 2


func _set_game_over(reason: String) -> void:
	if game_over:
		return
	game_over = true
	player.visible = false
	Arcade.save_highscore(GAME_ID, "P1", score)
	var best: int = Arcade.get_best_score(GAME_ID)
	msg_label.text = "%s\nPoeng: %d   Rekord: %d\nSTART = nytt spill" % [reason, score, best]
	msg_label.visible = true
	bullet_layer.update()


func _restart() -> void:
	score = 0
	lives = 3
	wave = 1
	invuln = 0.0
	game_over = false
	score_label.text = "POENG: 0"
	lives_label.text = "LIV: %d" % lives
	msg_label.visible = false
	player.visible = true
	player.position = Vector2(SIZE.x / 2, PLAYER_Y)
	_spawn_wave()


func _draw_bullets() -> void:
	if player_bullet_active:
		bullet_layer.draw_rect(Rect2(player_bullet - Vector2(2, 6), Vector2(4, 12)), Color(1, 1, 0.5))
		bullet_layer.draw_rect(Rect2(player_bullet - Vector2(1, 5), Vector2(2, 10)), Color(1, 1, 1))
	for b in enemy_bullets:
		bullet_layer.draw_rect(Rect2(b - Vector2(2, 6), Vector2(4, 12)), Color(1, 0.35, 0.25))
		bullet_layer.draw_rect(Rect2(b - Vector2(1, 5), Vector2(2, 10)), Color(1, 0.75, 0.5))
