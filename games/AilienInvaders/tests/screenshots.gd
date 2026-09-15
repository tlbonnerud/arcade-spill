extends Node

# Tar skjermbilder av hver formasjon og innflyging, midt i og etter
# innflygingen, for visuell kontroll. Krever et vindu (ikke --no-window).
#
#   ../../tools/Godot3.app/Contents/MacOS/Godot --path . res://tests/screenshots.tscn
#
# Bildene havner i mappa gitt av AILIEN_SHOTS (standard user://shots/).

const MainScene := preload("res://games/ailien_invaders/main.tscn")
const Formations := preload("res://games/ailien_invaders/enemies/formations.gd")
const Entries := preload("res://games/ailien_invaders/enemies/entry_patterns.gd")

const FORMATIONS := ["rows", "v_shape", "ring", "checkerboard"]
const ENTRIES := ["from_top", "from_sides", "spiral", "swoop"]

var main: Node2D
var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_environment("AILIEN_SHOTS")
	if out_dir == "":
		out_dir = "user://shots"
	Directory.new().make_dir_recursive(out_dir)
	main = MainScene.instance()
	add_child(main)
	call_deferred("_run")


func _run() -> void:
	yield(get_tree(), "idle_frame")
	main.set_process(false)  # vi stepper selv
	var swarm = main.swarm
	for i in 4:
		var f: String = FORMATIONS[i]
		var en: String = ENTRIES[i]
		main.rng.seed = 1
		swarm.spawn(3, main.rng)
		_force_choice(swarm, f, en)
		# Midt i innflygingen: 0,8 s inn.
		for _k in 48:
			swarm.step(1.0 / 60.0, false, Vector2(320, 330))
		swarm.animate(0.4)
		yield(_shoot("%s_%s_1_inn" % [f, en]), "completed")
		for _k in 240:
			swarm.step(1.0 / 60.0, false, Vector2(320, 330))
		yield(_shoot("%s_%s_2_plass" % [f, en]), "completed")
	print("OK: skjermbilder i ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit(0)


# Bygger bølgen på nytt med gitt formasjon og innflyging.
func _force_choice(swarm, formation: String, entry: String) -> void:
	swarm.wave_data["formations"] = [formation]
	swarm.wave_data["entries"] = [entry]
	var data: Dictionary = swarm.wave_data
	swarm.spawn(3, main.rng)
	swarm.wave_data["chosen"]["formation"] = formation
	swarm.wave_data["chosen"]["entry"] = entry
	var slots: Array = Formations.build(formation, swarm.total, swarm.area_size)
	var entries: Array = Entries.build(entry, slots, swarm.area_size, main.rng)
	for i in swarm.enemies.size():
		swarm.enemies[i]["slot"] = slots[i]
		swarm.enemies[i]["entry"] = entries[i]
		swarm.enemies[i]["sprite"].position = entries[i]["start"]


func _shoot(name: String) -> void:
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var img: Image = get_viewport().get_texture().get_data()
	img.flip_y()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	print("  ", name, " -> ", err)
