extends Node

# Tar skjermbilder av hvert mønster for visuell kontroll:
#   formasjoner  med 24 og 40 fiender, på plass
#   innflyginger to tidspunkt underveis
#   bevegelser   fire tidspunkt, på en formasjon som passer
#
#   cd games/AilienInvaders
#   AILIEN_SHOTS=/tmp/shots ../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/screenshots.tscn
#   python3 tests/contact_sheets.py /tmp/shots      (setter bildene sammen til oversiktsark)
#
# Bildene havner i mappa gitt av AILIEN_SHOTS (standard user://shots/).

const MainScene := preload("res://games/ailien_invaders/main.tscn")
const Formations := preload("res://games/ailien_invaders/enemies/formations.gd")
const Entries := preload("res://games/ailien_invaders/enemies/entry_patterns.gd")
const Movements := preload("res://games/ailien_invaders/enemies/movement_patterns.gd")
const Waves := preload("res://games/ailien_invaders/waves/waves.gd")

const DT := 1.0 / 60.0
const MIX := [["elite", 4], ["skytter", 8], ["soldat", 12]]
const MIX_40 := [["elite", 6], ["skytter", 10], ["soldat", 12], ["grunt", 12]]
# Formasjonen hver bevegelse vises på (det den er tenkt brukt med).
const MOVEMENT_FORMATION := {
	"orbit": "ring", "split": "two_groups", "rock": "arrow", "pulse": "diamond",
	"figure8": "v_shape", "sine": "checkerboard", "classic": "rows",
}

var main: Node2D
var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_environment("AILIEN_SHOTS")
	if out_dir == "":
		out_dir = "user://shots"
	Directory.new().make_dir_recursive(out_dir)
	main = MainScene.instance()
	add_child(main)
	main.save_scores = false
	call_deferred("_run")


func _run() -> void:
	yield(get_tree(), "idle_frame")
	main.set_process(false)  # vi stepper selv
	main.msg_label.visible = false

	for f in Formations.NAMES:
		for mix in [MIX, MIX_40]:
			_spawn(mix, f, "from_top", "classic")
			_advance(6.0, true)
			yield(_shoot("formasjon_%s_%02d" % [f, main.swarm.total]), "completed")

	for en in Entries.NAMES:
		_spawn(MIX, "rows", en, "classic")
		var total: float = Entries.total_time(_entries_of(main.swarm))
		_advance(total * 0.35, true)
		yield(_shoot("innflyging_%s_1" % en), "completed")
		_advance(total * 0.30, true)
		yield(_shoot("innflyging_%s_2" % en), "completed")

	for m in Movements.NAMES:
		var f: String = MOVEMENT_FORMATION.get(m, "rows")
		if not (f in Formations.NAMES):
			f = "rows"
		_spawn(MIX, f, "from_top", m)
		_advance(6.0, true)   # ferdig innfløyet
		for k in 4:
			_advance(3.0, false)
			yield(_shoot("bevegelse_%s_%d" % [m, k + 1]), "completed")

	print("OK: skjermbilder i ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit(0)


func _spawn(mix: Array, formation: String, entry: String, movement: String) -> void:
	var row := {"enemies": mix, "formations": [formation], "entries": [entry], "movements": [movement]}
	main.rng.seed = 1
	main.swarm.spawn_data(1, Waves.with_defaults(row, 1), main.rng)
	main.wave_label.text = "%s / %s / %s" % [formation, entry, movement]


# Går tiden fram. entry_only=true stopper når innflygingen er ferdig.
func _advance(seconds: float, entry_only: bool) -> void:
	var t := 0.0
	while t < seconds:
		if entry_only and not main.swarm.is_entering():
			break
		main.swarm.step(DT, false, Vector2(320, 330))
		t += DT
	main.swarm.animate(0.4)


func _entries_of(swarm) -> Array:
	var out := []
	for e in swarm.enemies:
		out.append(e["entry"])
	return out


func _shoot(name: String) -> void:
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var img: Image = get_viewport().get_texture().get_data()
	img.flip_y()
	var err := img.save_png("%s/%s.png" % [out_dir, name])
	if err != OK:
		print("  FEIL ", name, " -> ", err)
