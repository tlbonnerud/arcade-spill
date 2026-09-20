extends Node2D

# Ailien Invaders — hovedscene.
# Orkestrerer spillet: bygger bakgrunn og HUD, kobler sammen spiller,
# bølgemotor og kuler, og eier tilstandsmaskinen (bølge, poeng, game over).
# Selve logikken bor i player/, enemies/, core/ og waves/.
#
# Piltaster flytter romskipet, A (Z) skyter. Tilbake-knappen går til menyen.

const SIZE := Vector2(640, 360)
const GAME_ID := "ailien_invaders"
const SPRITES := "res://games/ailien_invaders/sprites/"
const PLAYER_Y := 330.0
const BG_FRAME_TIME := 0.5
const BG_FRAME_TIME_FAST := 0.12   # WAVE_CLEAR: vi "flyr videre"
const WAVE_CLEAR_TIME := 1.2
const DIVER_HIT_EXTRA := Vector2(10, 8)  # dykkere er større enn kuler

# Skript lastes med preload, ikke class_name: globale klasser fra en .pck
# blir ikke registrert i launcheren (se docs/ARCHITECTURE.md).
const PlayerScript := preload("res://games/ailien_invaders/player/player.gd")
const WaveManagerScript := preload("res://games/ailien_invaders/core/wave_manager.gd")
const BulletsScript := preload("res://games/ailien_invaders/core/bullets.gd")
const Waves := preload("res://games/ailien_invaders/waves/waves.gd")

enum State { WAVE_INTRO, WAVE, WAVE_CLEAR, VICTORY, GAME_OVER }

var bg: Sprite
var player: Sprite
var swarm: Node2D
var bullets: Node2D

var state: int = State.WAVE_INTRO
var score := 0
var wave := 1
var run_seed := 0
var rng := RandomNumberGenerator.new()
var state_timer := 0.0
var bg_timer := 0.0
var save_scores := true   # tester setter false så de ikke fyller highscore-lista
var wave_rows := []       # tester kan legge inn egne bølgerader; tom = waves/waves.gd

var score_label: Label
var lives_label: Label
var wave_label: Label
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
	bg.texture = load(SPRITES + "new_background.png")
	bg.hframes = 2
	bg.centered = false
	bg.scale = SIZE / (bg.texture.get_size() / Vector2(bg.hframes, 1))
	add_child(bg)


func _build_actors() -> void:
	player = PlayerScript.new()
	player.setup(SIZE, PLAYER_Y)
	add_child(player)

	swarm = WaveManagerScript.new()
	swarm.setup(SIZE)
	add_child(swarm)

	bullets = BulletsScript.new()
	bullets.setup(SIZE, player, swarm)
	add_child(bullets)


func _build_hud() -> void:
	score_label = _label(Vector2(8, 4), "POENG: 0")
	lives_label = _label(Vector2(SIZE.x - 108, 4), "LIV: 0")
	wave_label = _label(Vector2(0, 4), "")
	wave_label.rect_size = Vector2(SIZE.x, 20)
	wave_label.align = Label.ALIGN_CENTER
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
	swarm.connect("entry_finished", self, "_on_entry_finished")
	swarm.connect("reached_bottom", self, "_set_game_over", ["ROMVESENENE TOK DEG!"])


# ---------------------------------------------------------------------------
# Tilstandsmaskin
# ---------------------------------------------------------------------------

func _start_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else randi() % 1000000
	rng.seed = run_seed
	score = 0
	score_label.text = "POENG: 0"
	player.reset()
	bullets.clear()
	_start_wave(1)


func _start_wave(n: int) -> void:
	wave = n
	bullets.clear()
	swarm.spawn_data(wave, wave_data_for(wave), rng)
	bullets.enemy_speed_mult = swarm.wave_data["bullet_speed_mult"]
	wave_label.text = "BØLGE %d/%d" % [wave, wave_count()]
	_set_state(State.WAVE_INTRO)


func wave_count() -> int:
	return Waves.count() if wave_rows.empty() else wave_rows.size()


func wave_data_for(n: int) -> Dictionary:
	if wave_rows.empty():
		return Waves.get_wave(n)
	return Waves.with_defaults(wave_rows[clamp(n - 1, 0, wave_rows.size() - 1)], n)


func _set_state(next: int) -> void:
	state = next
	state_timer = 0.0
	msg_label.visible = false
	match state:
		State.WAVE_INTRO:
			_show_message(swarm.wave_data["banner"])
		State.WAVE_CLEAR:
			bullets.clear()
		State.VICTORY:
			player.controllable = false
			player.visible = true  # kan ha frosset midt i et usårbarhets-blink
			_save_score()
			_show_message("DU VANT!\nPoeng: %d   Rekord: %d\nSTART = nytt spill"
					% [score, Arcade.get_best_score(GAME_ID)])
		State.GAME_OVER:
			player.controllable = false
			player.visible = false
			_save_score()
			bullets.update()


func _save_score() -> void:
	if save_scores:
		Arcade.save_highscore(GAME_ID, "P1", score)


func _show_message(text: String) -> void:
	msg_label.text = text
	msg_label.visible = true


func _process(delta: float) -> void:
	state_timer += delta
	_animate_background(delta)
	swarm.animate(delta)

	match state:
		State.WAVE_INTRO:
			# Fiendene flyr inn og skyter ikke. Spilleren kan skyte dem underveis.
			player.step(delta)
			swarm.step(delta, false, player.position)
			bullets.step(delta)
		State.WAVE:
			player.step(delta)
			swarm.step(delta, bullets.enemy_bullet_count() < swarm.wave_data["max_bullets"], player.position)
			bullets.step(delta)
			_check_diver_contact()
		State.WAVE_CLEAR:
			player.step(delta)
			bullets.step(delta)
			if state_timer >= WAVE_CLEAR_TIME:
				if wave >= wave_count():
					_set_state(State.VICTORY)
				else:
					_start_wave(wave + 1)
		State.VICTORY, State.GAME_OVER:
			if Input.is_action_just_pressed("arcade_start"):
				_start_run()


func _check_diver_contact() -> void:
	for p in swarm.diver_positions():
		if player.hit_test(p, DIVER_HIT_EXTRA):
			player.take_hit()


func _animate_background(delta: float) -> void:
	bg_timer += delta
	var frame_time := BG_FRAME_TIME_FAST if state == State.WAVE_CLEAR else BG_FRAME_TIME
	if bg_timer >= frame_time:
		bg_timer = 0.0
		bg.frame = (bg.frame + 1) % 2


# ---------------------------------------------------------------------------
# Signaler
# ---------------------------------------------------------------------------

func _on_entry_finished() -> void:
	if state == State.WAVE_INTRO:
		_set_state(State.WAVE)


func _on_enemy_killed(points: int) -> void:
	if state == State.GAME_OVER or state == State.VICTORY:
		return  # poengsummen er alt lagret
	score += points
	score_label.text = "POENG: %d" % score


func _on_wave_cleared() -> void:
	if state == State.WAVE_INTRO or state == State.WAVE:
		_set_state(State.WAVE_CLEAR)
		if swarm.wave_data["bonus_life"] and player.add_life():
			_show_message("+1 LIV")


func _on_lives_changed(lives: int) -> void:
	lives_label.text = "LIV: %d" % lives


func _set_game_over(reason: String) -> void:
	if state == State.GAME_OVER or state == State.VICTORY:
		return
	_set_state(State.GAME_OVER)
	_show_message("%s\nPoeng: %d   Rekord: %d   Seed: %d\nSTART = nytt spill"
			% [reason, score, Arcade.get_best_score(GAME_ID), run_seed])
