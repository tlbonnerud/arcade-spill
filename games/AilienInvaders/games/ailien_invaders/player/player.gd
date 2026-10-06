extends Sprite

# Spillerskipet: bevegelse, skyting, treff, skjold og usårbarhet.
# Vet ingenting om fiender eller kuler — sier bare fra via signaler,
# så main.gd kan koble det sammen med resten.
#
# Tallene kommer fra statblokken (player/player_stats.gd): main kaller
# apply_stats() hver gang en oppgradering er valgt.

signal fire_requested(pos)   # spilleren trykket skyt; kulelaget avgjør om det er lov
signal lives_changed(lives)
signal shield_changed(shield)
signal hit(pos)              # noe traff spilleren (også når skjoldet tok det)
signal died                  # ingen liv igjen

const PlayerStats := preload("res://games/ailien_invaders/player/player_stats.gd")

const TEXTURE := "res://games/ailien_invaders/sprites/Romskip.png"
const INVULN_TIME := 2.0
const SHIELD_INVULN_TIME := 0.8   # kort pust etter at skjoldet tok et treff
const EDGE_MARGIN := 20.0
const HIT_HALF_SIZE := Vector2(12, 10)  # halv bredde/høyde på treffboksen
const MUZZLE_OFFSET := Vector2(0, -12)
const SHIELD_COLOR := Color(0.6, 0.9, 1.0)

var area_width := 640.0
var start_position := Vector2.ZERO
var stats: Dictionary = PlayerStats.BASE.duplicate()
var lives := 3
var shield := 0
var invuln := 0.0
var controllable := true  # false under game over
# Settes av tester (og senere attract-modus) for å styre skipet uten input:
# {"dir": -1.0..1.0, "fire": bool}. null = vanlig input.
var autopilot = null


func _ready() -> void:
	texture = load(TEXTURE)
	hframes = 4


func setup(area_size: Vector2, y: float) -> void:
	area_width = area_size.x
	start_position = Vector2(area_size.x / 2, y)
	position = start_position


# Ny statblokk (fra player_stats.current). Varige effekter: fart, størrelse,
# maks liv. Skjoldet lades ved bølgestart (recharge_shield), ikke her.
func apply_stats(s: Dictionary) -> void:
	stats = s
	scale = Vector2.ONE * float(stats["ship_scale"])


func reset() -> void:
	lives = int(stats["start_lives"])
	shield = 0
	invuln = 0.0
	controllable = true
	visible = true
	modulate = Color.white
	position = start_position
	emit_signal("lives_changed", lives)
	emit_signal("shield_changed", shield)


func max_lives() -> int:
	return int(stats["max_lives"])


# Kalles hver frame av main.gd mens spillet pågår.
# (Heter ikke update(): det navnet er opptatt av CanvasItem.)
func step(delta: float) -> void:
	if not controllable:
		return

	var dir := Input.get_action_strength("p1_right") - Input.get_action_strength("p1_left")
	var fire := Input.is_action_just_pressed("p1_a")
	if autopilot != null:
		dir = clamp(autopilot["dir"], -1.0, 1.0)
		fire = autopilot["fire"]
	position.x = clamp(position.x + dir * float(stats["move_speed"]) * delta, EDGE_MARGIN, area_width - EDGE_MARGIN)

	if fire:
		emit_signal("fire_requested", position + MUZZLE_OFFSET * scale.y)

	frame = int(OS.get_ticks_msec() / 120) % 4
	if invuln > 0.0:
		invuln -= delta
		visible = int(OS.get_ticks_msec() / 100) % 2 == 0
	else:
		visible = true
	modulate = SHIELD_COLOR if shield > 0 else Color.white


# Bonusliv og helbredelse. Returnerer false hvis spilleren alt har maks.
func add_life() -> bool:
	if lives >= max_lives():
		return false
	lives += 1
	emit_signal("lives_changed", lives)
	return true


# Lader skjoldet til det statblokken sier. Kalles ved hver bølgestart.
func recharge_shield() -> void:
	shield = int(stats["shield"])
	emit_signal("shield_changed", shield)


func is_vulnerable() -> bool:
	return controllable and invuln <= 0.0


# extra utvider treffboksen, for ting som er større enn en kule (dykkende fiender).
func hit_test(p: Vector2, extra: Vector2 = Vector2.ZERO) -> bool:
	if not is_vulnerable():
		return false
	var half := HIT_HALF_SIZE * float(stats["ship_scale"]) + extra
	return abs(p.x - position.x) < half.x and abs(p.y - position.y) < half.y


func take_hit() -> void:
	emit_signal("hit", position)
	if shield > 0:
		shield -= 1
		invuln = SHIELD_INVULN_TIME
		emit_signal("shield_changed", shield)
		return
	lives -= 1
	emit_signal("lives_changed", lives)
	if lives <= 0:
		controllable = false
		visible = false
		emit_signal("died")
	else:
		invuln = INVULN_TIME
		position.x = start_position.x
