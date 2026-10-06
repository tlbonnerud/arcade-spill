extends Node2D

# Ailien Invaders — hovedscene.
# Orkestrerer spillet: bygger bakgrunn og HUD, kobler sammen spiller,
# bølgemotor, kuler og oppgraderingsskjerm, og eier tilstandsmaskinen
# (bølge, poeng, oppgradering, game over).
# Selve logikken bor i player/, enemies/, core/, waves/ og upgrades/.
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
const THORNS_RADIUS := 150.0   # pigger: fiender så nær spilleren tar skade ved treff
const THORNS_DAMAGE := 2
const HUD_ICON_X := 8.0
const HUD_ICON_Y := 34.0
const HUD_ICON_STEP := 34.0

# Skript lastes med preload, ikke class_name: globale klasser fra en .pck
# blir ikke registrert i launcheren (se docs/ARCHITECTURE.md).
const PlayerScript := preload("res://games/ailien_invaders/player/player.gd")
const PlayerStatsScript := preload("res://games/ailien_invaders/player/player_stats.gd")
const WaveManagerScript := preload("res://games/ailien_invaders/core/wave_manager.gd")
const BulletsScript := preload("res://games/ailien_invaders/core/bullets.gd")
const UpgradeScreenScript := preload("res://games/ailien_invaders/upgrades/upgrade_screen.gd")
const Upgrades := preload("res://games/ailien_invaders/upgrades/upgrades.gd")
const Waves := preload("res://games/ailien_invaders/waves/waves.gd")

enum State { WAVE_INTRO, WAVE, WAVE_CLEAR, UPGRADE, VICTORY, GAME_OVER }

var bg: Sprite
var player: Sprite
var swarm: Node2D
var bullets: Node2D
var upgrade_screen: Node2D
var stats: Reference   # player/player_stats.gd

var state: int = State.WAVE_INTRO
var score := 0
var wave := 1
var run_seed := 0
var rng := RandomNumberGenerator.new()
var state_timer := 0.0
var bg_timer := 0.0
var save_scores := true   # tester setter false så de ikke fyller highscore-lista
var wave_rows := []       # tester kan legge inn egne bølgerader; tom = waves/waves.gd
var upgrades_enabled := true  # false: rett til neste bølge (tester, sammenligning)
var shield := 0

var score_label: Label
var lives_label: Label
var wave_label: Label
var msg_label: Label
var hud_icons: Node2D


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
	stats = PlayerStatsScript.new()

	player = PlayerScript.new()
	player.setup(SIZE, PLAYER_Y)
	add_child(player)

	swarm = WaveManagerScript.new()
	swarm.setup(SIZE)
	add_child(swarm)

	bullets = BulletsScript.new()
	bullets.setup(SIZE, player, swarm)
	add_child(bullets)

	upgrade_screen = UpgradeScreenScript.new()
	upgrade_screen.setup(SIZE)
	add_child(upgrade_screen)


func _build_hud() -> void:
	score_label = _label(Vector2(8, 4), "POENG: 0")
	lives_label = _label(Vector2(SIZE.x - 150, 4), "LIV: 0")
	lives_label.rect_size = Vector2(142, 20)
	lives_label.align = Label.ALIGN_RIGHT
	wave_label = _label(Vector2(0, 4), "")
	wave_label.rect_size = Vector2(SIZE.x, 20)
	wave_label.align = Label.ALIGN_CENTER
	msg_label = _label(Vector2(0, SIZE.y / 2 - 30), "")
	msg_label.rect_size = Vector2(SIZE.x, 60)
	msg_label.align = Label.ALIGN_CENTER
	msg_label.visible = false
	hud_icons = Node2D.new()
	hud_icons.position = Vector2(HUD_ICON_X, HUD_ICON_Y)
	add_child(hud_icons)


func _label(pos: Vector2, text: String) -> Label:
	var l := Label.new()
	l.rect_position = pos
	l.text = text
	add_child(l)
	return l


func _connect_signals() -> void:
	player.connect("fire_requested", bullets, "spawn_player_bullet")
	player.connect("lives_changed", self, "_on_lives_changed")
	player.connect("shield_changed", self, "_on_shield_changed")
	player.connect("hit", self, "_on_player_hit")
	player.connect("died", self, "_set_game_over", ["GAME OVER"])

	swarm.connect("fire_requested", bullets, "spawn_enemy_bullet")
	swarm.connect("enemy_killed", self, "_on_enemy_killed")
	swarm.connect("cleared", self, "_on_wave_cleared")
	swarm.connect("entry_finished", self, "_on_entry_finished")
	swarm.connect("reached_bottom", self, "_set_game_over", ["ROMVESENENE TOK DEG!"])

	upgrade_screen.connect("chosen", self, "_on_upgrade_chosen")


# ---------------------------------------------------------------------------
# Tilstandsmaskin
# ---------------------------------------------------------------------------

func _start_run(seed_value: int = -1) -> void:
	run_seed = seed_value if seed_value >= 0 else randi() % 1000000
	rng.seed = run_seed
	score = 0
	score_label.text = "POENG: 0"
	stats.reset()
	_apply_stats()
	player.reset()
	bullets.clear()
	upgrade_screen.hide_screen()
	_start_wave(1)


func _start_wave(n: int) -> void:
	wave = n
	bullets.clear()
	swarm.spawn_data(wave, wave_data_for(wave), rng)
	bullets.enemy_speed_mult = swarm.wave_data["bullet_speed_mult"]
	player.recharge_shield()
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
		State.UPGRADE:
			var have: Dictionary = stats.stack_counts()
			upgrade_screen.show_offer(Upgrades.offer(rng, have, 3, wave == 1), have)
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
				elif upgrades_enabled:
					_set_state(State.UPGRADE)
				else:
					_start_wave(wave + 1)
		State.UPGRADE:
			upgrade_screen.step(delta)
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
# Oppgraderinger
# ---------------------------------------------------------------------------

# Deler ut statblokken til dem som leser den.
func _apply_stats() -> void:
	player.apply_stats(stats.current)
	bullets.apply_stats(stats.current)


# Velger oppgradering id (fra skjermen, tester eller boten) og går videre.
func _on_upgrade_chosen(id: String) -> void:
	if state != State.UPGRADE:
		return
	upgrade_screen.hide_screen()  # (choose() gjør det alt; pick_upgrade går utenom)
	stats.take(id)
	_apply_stats()
	if Upgrades.get_upgrade(id).get("on_pick", "") == "add_life":
		player.add_life()
	_rebuild_hud_icons()
	_start_wave(wave + 1)


# Tar oppgradering id direkte (tester). Virker bare i UPGRADE-tilstanden.
func pick_upgrade(id: String) -> void:
	_on_upgrade_chosen(id)


func _rebuild_hud_icons() -> void:
	for child in hud_icons.get_children():
		hud_icons.remove_child(child)
		child.queue_free()
	var i := 0
	for id in stats.stack_counts():
		var u: Dictionary = Upgrades.get_upgrade(id)
		var s := Sprite.new()
		s.texture = u["icon"]
		s.hframes = int(max(1, u["icon"].get_width() / Upgrades.ICON_SIZE.x))
		s.frame = s.hframes - 1
		s.centered = false
		s.position = Vector2(i * HUD_ICON_STEP, 0)
		hud_icons.add_child(s)
		var n: int = stats.stacks(id)
		if n > 1:
			var l := Label.new()
			l.text = "%d" % n
			l.rect_position = Vector2(i * HUD_ICON_STEP + 20, 4)
			hud_icons.add_child(l)
		i += 1


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
		var gained := 0
		if swarm.wave_data["bonus_life"] and player.add_life():
			gained += 1
		for _i in int(stats.current["heal_per_wave"]):
			if player.add_life():
				gained += 1
		if gained > 0:
			_show_message("+%d LIV" % gained)


func _on_lives_changed(lives: int) -> void:
	_update_lives_label(lives)


func _on_shield_changed(n: int) -> void:
	shield = n
	_update_lives_label(player.lives)


func _update_lives_label(lives: int) -> void:
	lives_label.text = "LIV: %d" % lives
	if shield > 0:
		lives_label.text = "SKJOLD: %d   LIV: %d" % [shield, lives]


# Pigger: alt som treffer spilleren koster fiendene i nærheten dyrt, og
# fiendekulene i lufta forsvinner (ellers dør man gjerne to ganger på rad).
func _on_player_hit(pos: Vector2) -> void:
	if int(stats.current["thorns"]) <= 0:
		return
	bullets.clear_enemy_bullets()
	bullets.show_ring(pos, THORNS_RADIUS)
	swarm.damage_area(pos, THORNS_RADIUS, THORNS_DAMAGE)


func _set_game_over(reason: String) -> void:
	if state == State.GAME_OVER or state == State.VICTORY:
		return
	_set_state(State.GAME_OVER)
	_show_message("%s\nPoeng: %d   Rekord: %d   Seed: %d\nSTART = nytt spill"
			% [reason, score, Arcade.get_best_score(GAME_ID), run_seed])
