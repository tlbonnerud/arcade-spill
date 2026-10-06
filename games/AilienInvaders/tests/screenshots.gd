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
# AILIEN_SHOTS_MODE=waves tar i stedet to bilder per bølge i waves.gd:
# banneret under innflygingen, og formasjonen i bevegelse.
# AILIEN_SHOTS_MODE=upgrades tar oppgraderingsskjermen og HUD-en med ikoner.

# load() i _ready, ikke preload (se tests/play_waves.gd).
const BASE := "res://games/ailien_invaders/"
const STALL_FRAMES := 600

const DT := 1.0 / 60.0
const MIX := [["elite", 4], ["skytter", 8], ["soldat", 12]]
const MIX_40 := [["elite", 6], ["skytter", 10], ["soldat", 12], ["grunt", 12]]
# Formasjonen hver bevegelse vises på (det den er tenkt brukt med).
const MOVEMENT_FORMATION := {
	"orbit": "ring", "split": "two_groups", "rock": "arrow", "pulse": "diamond",
	"figure8": "v_shape", "sine": "checkerboard", "classic": "rows",
}

var Formations
var Entries
var Movements
var Waves
var main: Node2D
var out_dir := ""
var save_errors := 0
var stalled_frames := 0


func _ready() -> void:
	out_dir = OS.get_environment("AILIEN_SHOTS")
	if out_dir == "":
		out_dir = "user://shots"
	Directory.new().make_dir_recursive(out_dir)
	Formations = load(BASE + "enemies/formations.gd")
	Entries = load(BASE + "enemies/entry_patterns.gd")
	Movements = load(BASE + "enemies/movement_patterns.gd")
	Waves = load(BASE + "waves/waves.gd")
	var scene = load(BASE + "main.tscn")
	for script in [Formations, Entries, Movements, Waves]:
		if script == null or not script.can_instance():
			_abort("et av spillets skript lar seg ikke laste")
			return
	main = scene.instance()
	add_child(main)
	if main.get_script() == null or not main.has_method("wave_count"):
		_abort("main.gd kompilerte ikke")
		return
	main.save_scores = false
	call_deferred("_run")


func _process(_delta: float) -> void:
	stalled_frames += 1
	if stalled_frames > STALL_FRAMES:
		_abort("stoppet opp (skriptfeil?)")


func _abort(why: String) -> void:
	print("FEIL: ", why)
	get_tree().quit(1)


func _finish() -> void:
	if save_errors > 0:
		_abort("%d bilder lot seg ikke lagre i %s" % [save_errors, out_dir])
		return
	print("OK: skjermbilder i ", ProjectSettings.globalize_path(out_dir))
	get_tree().quit(0)


func _run() -> void:
	yield(get_tree(), "idle_frame")
	main.set_process(false)  # vi stepper selv
	if OS.get_environment("AILIEN_SHOTS_MODE") == "waves":
		yield(_shoot_waves(), "completed")
		_finish()
		return
	if OS.get_environment("AILIEN_SHOTS_MODE") == "upgrades":
		yield(_shoot_upgrades(), "completed")
		_finish()
		return
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

	_finish()


# To bilder per bølge, slik spilleren ser dem (banner og HUD som i spillet).
func _shoot_waves() -> void:
	for n in range(1, main.wave_count() + 1):
		main.rng.seed = 7
		main._start_wave(n)
		main.player.invuln = 999.0
		for _k in 54:
			main._process(DT)
		yield(_shoot("bolge_%02d_a_innflyging" % n), "completed")
		var t := 0.0
		while main.swarm.is_entering() and t < 8.0:
			main._process(DT)
			t += DT
		for _k in 300:
			main._process(DT)
		yield(_shoot("bolge_%02d_b_kamp" % n), "completed")


# Oppgraderingsskjermen etter bølge 1 (med sjelden garantert), og HUD-en
# etter at noen kort er tatt, midt i en bølge med vifte og eksplosjon.
func _shoot_upgrades() -> void:
	main.upgrade_screen.autopilot = true
	main._start_run(11)
	main._set_state(main.State.UPGRADE)
	main._process(DT)
	yield(_shoot("oppgradering_a_skjerm"), "completed")
	main.upgrade_screen.choose(0)
	for id in ["multishot", "multishot", "attack_speed", "explosion", "potion", "size_down"]:
		main._set_state(main.State.UPGRADE)
		main.pick_upgrade(id)
	main._start_wave(4)
	main.player.invuln = 999.0
	var t := 0.0
	while main.swarm.is_entering() and t < 8.0:
		main._process(DT)
		t += DT
	for _k in 60:
		main._process(DT)
	main.player.autopilot = {"dir": 0.0, "fire": true}
	for _k in 12:
		main._process(DT)
	main.player.autopilot = null
	yield(_shoot("oppgradering_b_hud"), "completed")


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
	stalled_frames = 0
	if err != OK:
		save_errors += 1
		print("  FEIL ", name, " -> ", err)
