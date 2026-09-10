extends Sprite

# Spillerskipet: bevegelse, skyting, treff og usårbarhet.
# Vet ingenting om fiender eller kuler — sier bare fra via signaler,
# så main.gd kan koble det sammen med resten.
#
# Fremtid (se docs/ARCHITECTURE.md): tallene under flyttes til
# player/player_stats.gd når oppgraderinger kommer inn.

signal fire_requested(pos)   # spilleren trykket skyt; kulelaget avgjør om det er lov
signal lives_changed(lives)
signal died                  # ingen liv igjen

const TEXTURE := "res://games/ailien_invaders/sprites/Romskip.png"
const SPEED := 220.0
const START_LIVES := 3
const INVULN_TIME := 2.0
const EDGE_MARGIN := 20.0
const HIT_HALF_SIZE := Vector2(12, 10)  # halv bredde/høyde på treffboksen
const MUZZLE_OFFSET := Vector2(0, -12)

var area_width := 640.0
var start_position := Vector2.ZERO
var lives := START_LIVES
var invuln := 0.0
var controllable := true  # false under game over


func _ready() -> void:
	texture = load(TEXTURE)
	hframes = 4


func setup(area_size: Vector2, y: float) -> void:
	area_width = area_size.x
	start_position = Vector2(area_size.x / 2, y)
	position = start_position


func reset() -> void:
	lives = START_LIVES
	invuln = 0.0
	controllable = true
	visible = true
	position = start_position
	emit_signal("lives_changed", lives)


# Kalles hver frame av main.gd mens spillet pågår.
# (Heter ikke update(): det navnet er opptatt av CanvasItem.)
func step(delta: float) -> void:
	if not controllable:
		return

	var dir := Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
	position.x = clamp(position.x + dir * SPEED * delta, EDGE_MARGIN, area_width - EDGE_MARGIN)

	if Input.is_action_just_pressed("p1_a"):
		emit_signal("fire_requested", position + MUZZLE_OFFSET)

	frame = int(OS.get_ticks_msec() / 120) % 4
	if invuln > 0.0:
		invuln -= delta
		visible = int(OS.get_ticks_msec() / 100) % 2 == 0
	else:
		visible = true


func is_vulnerable() -> bool:
	return controllable and invuln <= 0.0


func hit_test(p: Vector2) -> bool:
	if not is_vulnerable():
		return false
	return abs(p.x - position.x) < HIT_HALF_SIZE.x and abs(p.y - position.y) < HIT_HALF_SIZE.y


func take_hit() -> void:
	lives -= 1
	emit_signal("lives_changed", lives)
	if lives <= 0:
		controllable = false
		visible = false
		emit_signal("died")
	else:
		invuln = INVULN_TIME
		position.x = start_position.x
