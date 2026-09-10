extends Node2D

# Ailien Invaders — hovedscene.
# Orkestrerer spillet: bygger bakgrunn og HUD, kobler sammen spiller, sverm
# og kuler, og eier rundetilstanden (poeng, bølge, game over).
# Selve logikken bor i player/, enemies/ og core/.
#
# Piltaster flytter romskipet, A (Z) skyter. Tilbake-knappen går til menyen.

const SIZE := Vector2(640, 360)
const GAME_ID := "ailien_invaders"
const SPRITES := "res://games/ailien_invaders/sprites/"
const PLAYER_Y := 330.0
const BG_FRAME_TIME := 0.5

# Skript lastes med preload, ikke class_name: globale klasser fra en .pck
# blir ikke registrert i launcheren (se docs/ARCHITECTURE.md).
const PlayerScript := preload("res://games/ailien_invaders/player/player.gd")
const SwarmScript := preload("res://games/ailien_invaders/enemies/swarm.gd")
const BulletsScript := preload("res://games/ailien_invaders/core/bullets.gd")

var bg: Sprite
var player: Sprite
var swarm: Node2D
var bullets: Node2D

var score := 0
var wave := 1
var game_over := false
var bg_timer := 0.0

var score_label: Label
var lives_label: Label
var msg_label: Label


func _ready() -> void:
	randomize()
	_build_background()
	_build_actors()
	_build_hud()
	_connect_signals()
	_start_run()

	if Arcade.smoke_test:
		yield(get_tree().create_timer(0.5), "timeout")
		print("Røyktest: Ailien Invaders kjører, går tilbake til launcheren ...")
		Arcade.quit_to_launcher()


# ---------------------------------------------------------------------------
# Oppsett
# ---------------------------------------------------------------------------

func _build_background() -> void:
	bg = Sprite.new()
	bg.texture = load(SPRITES + "Background.png")
	bg.hframes = 2
	bg.centered = false
	bg.scale = SIZE / Vector2(160, 90)
	add_child(bg)


func _build_actors() -> void:
	player = PlayerScript.new()
	player.setup(SIZE, PLAYER_Y)
	add_child(player)

	swarm = SwarmScript.new()
	swarm.setup(SIZE)
	add_child(swarm)

	bullets = BulletsScript.new()
	bullets.setup(SIZE, player, swarm)
	add_child(bullets)


func _build_hud() -> void:
	score_label = _label(Vector2(8, 4), "POENG: 0")
	lives_label = _label(Vector2(SIZE.x - 108, 4), "LIV: 0")
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


func _connect_signals() -> void:
	player.connect("fire_requested", bullets, "spawn_player_bullet")
	player.connect("lives_changed", self, "_on_lives_changed")
	player.connect("died", self, "_set_game_over", ["GAME OVER"])

	swarm.connect("fire_requested", bullets, "spawn_enemy_bullet")
	swarm.connect("enemy_killed", self, "_on_enemy_killed")
	swarm.connect("cleared", self, "_on_wave_cleared")
	swarm.connect("reached_bottom", self, "_set_game_over", ["ROMVESENENE TOK DEG!"])


# ---------------------------------------------------------------------------
# Rundetilstand
# ---------------------------------------------------------------------------

func _start_run() -> void:
	score = 0
	wave = 1
	game_over = false
	score_label.text = "POENG: 0"
	msg_label.visible = false
	player.reset()
	bullets.clear()
	swarm.spawn(wave)


func _process(delta: float) -> void:
	_animate_background(delta)
	swarm.animate(delta)

	if game_over:
		if Input.is_action_just_pressed("arcade_start"):
			_start_run()
		return

	player.step(delta)
	swarm.step(delta, bullets.enemy_bullet_count() < 2 + wave)
	bullets.step(delta)


func _animate_background(delta: float) -> void:
	bg_timer += delta
	if bg_timer >= BG_FRAME_TIME:
		bg_timer = 0.0
		bg.frame = (bg.frame + 1) % 2


func _on_enemy_killed(points: int) -> void:
	score += points
	score_label.text = "POENG: %d" % score


func _on_wave_cleared() -> void:
	wave += 1
	bullets.clear()
	swarm.spawn(wave)


func _on_lives_changed(lives: int) -> void:
	lives_label.text = "LIV: %d" % lives


func _set_game_over(reason: String) -> void:
	if game_over:
		return
	game_over = true
	player.controllable = false
	player.visible = false
	Arcade.save_highscore(GAME_ID, "P1", score)
	var best: int = Arcade.get_best_score(GAME_ID)
	msg_label.text = "%s\nPoeng: %d   Rekord: %d\nSTART = nytt spill" % [reason, score, best]
	msg_label.visible = true
	bullets.update()
