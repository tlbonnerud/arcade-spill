extends Node2D

# Ball: testspill nr. 2. En sprettball du kan dytte med joysticken.
# Ser helt annerledes ut enn dummy-spillet, så det er lett å se at
# launcheren faktisk har byttet spill.

const SIZE := Vector2(640, 360)
const RADIUS := 12.0
const PUSH := 400.0

var pos := SIZE / 2
var vel := Vector2(140, 100)


func _ready() -> void:
	var hint := Label.new()
	hint.text = "BALL — piltaster dytter ballen, A (Z) avslutter"
	hint.align = Label.ALIGN_CENTER
	hint.rect_position = Vector2(0, 8)
	hint.rect_size = Vector2(SIZE.x, 20)
	add_child(hint)

	if Arcade.smoke_test:
		yield(get_tree().create_timer(0.5), "timeout")
		print("Røyktest: ball-spillet kjører, går tilbake til launcheren ...")
		Arcade.quit_to_launcher()


func _process(delta: float) -> void:
	var push := Vector2(
		Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left"),
		Input.get_action_strength("p1_down") - Input.get_action_strength("p1_up")
	)
	vel += push * PUSH * delta
	pos += vel * delta

	if pos.x < RADIUS or pos.x > SIZE.x - RADIUS:
		vel.x = -vel.x
		pos.x = clamp(pos.x, RADIUS, SIZE.x - RADIUS)
	if pos.y < RADIUS or pos.y > SIZE.y - RADIUS:
		vel.y = -vel.y
		pos.y = clamp(pos.y, RADIUS, SIZE.y - RADIUS)

	update()


func _draw() -> void:
	draw_circle(pos, RADIUS, Color(0.4, 0.85, 1.0))
	draw_circle(pos, RADIUS * 0.5, Color(0.9, 0.97, 1.0))


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("p1_a"):
		Arcade.quit_to_launcher()
