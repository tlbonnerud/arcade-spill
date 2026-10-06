extends Node

const GAME_ID := "dodge_the_creeps"

export (PackedScene) var Mob

var score
var difficulty_time = 0
var game_running = false

func _ready():
	randomize()
	$MobTimer.stop()
	$CanvasLayer/GameOverLabel.visible = false
	$CanvasLayer/RestartButton.visible = false
	$CanvasLayer/HighScoreLabel.text = "Highscore: " + str(Arcade.get_best_score(GAME_ID))
	$CanvasLayer/TimeLabel.visible = false
	$CanvasLayer/TitleLabel.visible = true
	$CanvasLayer/StartButton.visible = true
	$Player.hide()

	if Arcade.smoke_test:
		yield(get_tree().create_timer(0.5), "timeout")
		print("Røyktest: Dodge the Creeps kjører, går tilbake til launcheren ...")
		Arcade.quit_to_launcher()

func _process(delta):
	if game_running:
		difficulty_time += delta
		$CanvasLayer/TimeLabel.text = "Tid: " + str(int(difficulty_time))

func _unhandled_input(event):
	if event.is_action_pressed("arcade_start"):
		if $CanvasLayer/StartButton.visible or $CanvasLayer/RestartButton.visible:
			new_game()

func game_over():
	game_running = false
	$MobTimer.stop()

	var final_time = int(difficulty_time)
	Arcade.save_highscore(GAME_ID, "P1", final_time)
	$CanvasLayer/HighScoreLabel.text = "Highscore: " + str(Arcade.get_best_score(GAME_ID))

	$CanvasLayer/GameOverLabel.visible = true
	$CanvasLayer/RestartButton.visible = true

	get_tree().call_group("mobs", "queue_free")

func new_game():
	score = 0
	difficulty_time = 0
	game_running = true

	$CanvasLayer/TitleLabel.visible = false
	$CanvasLayer/StartButton.visible = false
	$CanvasLayer/GameOverLabel.visible = false
	$CanvasLayer/RestartButton.visible = false
	$CanvasLayer/TimeLabel.visible = true

	$Player.start($StartPosition.position)
	$MobTimer.start()

func _on_MobTimer_timeout():
	var mob = Mob.instance()
	mob.add_to_group("mobs")

	var mob_spawn_location = $MobPath/MobSpawnLocation
	var path_length = $MobPath.curve.get_baked_length()
	var fixed_points = [0, path_length * 0.25, path_length * 0.5, path_length * 0.75]
	mob_spawn_location.set_offset(fixed_points[randi() % fixed_points.size()])

	var mob_position = mob_spawn_location.position
	mob.position = mob_position
	var direction = mob_spawn_location.rotation + PI / 2
	direction += rand_range(-PI / 4, PI / 4)
	mob.rotation = direction
	add_child(mob)

	var speed_bonus = min(difficulty_time * 3, 200)
	var velocity = Vector2(rand_range(200.0, 280.0) + speed_bonus, 0)
	mob.linear_velocity = velocity.rotated(direction)

	var new_wait_time = max(1.5 - difficulty_time * 0.02, 1.0)
	$MobTimer.wait_time = new_wait_time

func _on_Player_hit():
	game_over()



func _on_RestartButton_pressed():
	new_game()

func _on_StartButton_pressed():
	new_game()
