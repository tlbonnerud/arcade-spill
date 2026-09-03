extends Control

# Launcher-meny i to steg:
#  1) Startskjerm: ARCADE-logo + blinkende "Press any button to start".
#  2) Spillvalg: én knapp-sprite per spill, valgt knapp skaleres opp.
# Grafikken ligger i res://sprites/ (tegnet for 160x90, skaleres 4x opp
# til 640x360). Spill uten egen knapp-sprite får en tekst-knapp.

const SPRITES := "res://sprites/"
const SIZE := Vector2(640, 360)

# manifest-id -> knapp-sprite
const BUTTON_TEXTURES := {
	"ailien_invaders": "aliens-button.png",
	"ball": "creep-button.png",
}

const SCALE_SELECTED := 3.6
const SCALE_NORMAL := 2.6
const COLOR_SELECTED := Color(1, 1, 1)
const COLOR_NORMAL := Color(0.55, 0.55, 0.65)
const ANIM_SPEED := 10.0

enum State { START, SELECT }

var state: int = State.START
var games := []
var games_dir := ""
var selected := 0
var buttons := []  # Node2D per spill, skaleres rundt eget origo
var elapsed := 0.0

var start_screen: Node2D
var select_screen: Node2D
var press_text: Sprite
var record_label: Label

# Input-testmodus (ARCADE_INPUT_DEBUG=1): viser rå knapp-/akse-hendelser
# på skjermen og i terminalen, så vi kan finne ut hvilke indekser
# USB-encoderen faktisk sender.
var input_debug := false
var debug_log: Label
var debug_joy: Label
var debug_lines := []


func _ready() -> void:
	input_debug = OS.get_environment("ARCADE_INPUT_DEBUG") != ""
	if input_debug:
		_build_debug_ui()
		return

	games_dir = _find_games_dir()
	games = _scan_games(games_dir)
	_build_ui()

	# Rett tilbake til spillvalget når man kommer fra et spill,
	# og i røyktesten (som starter spillene selv).
	if Arcade.returned_from_game or Arcade.smoke_test:
		_show_select()
	else:
		_show_start()

	if Arcade.smoke_test:
		_run_smoke_test()

	# Dev-verktøy: ARCADE_SCREENSHOT=/sti/prefiks lagrer begge skjermene
	# som PNG og avslutter. Brukes ikke på arkaden.
	if OS.get_environment("ARCADE_SCREENSHOT") != "":
		yield(get_tree().create_timer(1.2), "timeout")
		_save_screenshot(OS.get_environment("ARCADE_SCREENSHOT") + "-start.png")
		_show_select()
		yield(get_tree().create_timer(1.2), "timeout")
		_save_screenshot(OS.get_environment("ARCADE_SCREENSHOT") + "-select.png")
		get_tree().quit()


func _input(event: InputEvent) -> void:
	if input_debug:
		_debug_input(event)
		return

	if state == State.START:
		var pressed_button: bool = (event is InputEventKey or event is InputEventJoypadButton) \
				and event.pressed and not event.is_echo()
		if pressed_button:
			if event.is_action("arcade_back") and OS.is_debug_build():
				# Kun for utvikling på Mac — på Pi-en starter systemd
				# launcheren på nytt, så der skal denne aldri trigges.
				get_tree().quit()
			else:
				_show_select()
		return

	if games.empty():
		return
	if event.is_action_pressed("p1_right") or event.is_action_pressed("p1_down"):
		_select(selected + 1)
	elif event.is_action_pressed("p1_left") or event.is_action_pressed("p1_up"):
		_select(selected - 1)
	elif event.is_action_pressed("p1_a") or event.is_action_pressed("arcade_start"):
		_launch(selected)
	elif event.is_action_pressed("arcade_back"):
		_show_start()


# ---------------------------------------------------------------------------

func _find_games_dir() -> String:
	# Eksplisitt overstyring (brukes av pi/run.sh på Raspberry Pi).
	var env_dir := OS.get_environment("ARCADE_GAMES_DIR")
	if env_dir != "":
		return env_dir
	if OS.has_feature("editor"):
		# Kjørt fra editor/CLI mot prosjektmappa: bruk dist/games i repoet.
		return ProjectSettings.globalize_path("res://").plus_file("../dist/games")
	# Eksportert binær: games/ ligger ved siden av programmet.
	return OS.get_executable_path().get_base_dir().plus_file("games")


func _scan_games(dir_path: String) -> Array:
	var found := []
	var dir := Directory.new()
	if dir.open(dir_path) != OK:
		printerr("Fant ikke games-mappa: " + dir_path)
		return found
	dir.list_dir_begin(true, true)
	var fname := dir.get_next()
	while fname != "":
		if fname.ends_with(".json"):
			var manifest := _read_manifest(dir_path.plus_file(fname))
			if not manifest.empty():
				found.append(manifest)
		fname = dir.get_next()
	dir.list_dir_end()
	found.sort_custom(self, "_by_name")
	return found


func _read_manifest(path: String) -> Dictionary:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return {}
	var parsed := JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		printerr("Ugyldig manifest: " + path)
		return {}
	var m: Dictionary = parsed.result
	for required in ["id", "name", "pck", "main_scene"]:
		if not m.has(required):
			printerr("Manifest mangler '%s': %s" % [required, path])
			return {}
	return m


static func _by_name(a, b) -> bool:
	return a["name"] < b["name"]


# ---------------------------------------------------------------------------
# UI
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	start_screen = Node2D.new()
	add_child(start_screen)

	var logo_big := Sprite.new()
	logo_big.texture = load(SPRITES + "ARCADE-text.png")
	logo_big.scale = Vector2(4, 4)
	logo_big.position = Vector2(SIZE.x / 2, 140)
	start_screen.add_child(logo_big)

	press_text = Sprite.new()
	press_text.texture = load(SPRITES + "Press_any_button_to_start.png")
	press_text.hframes = 2
	press_text.scale = Vector2(2, 2)
	press_text.position = Vector2(SIZE.x / 2, 240)
	start_screen.add_child(press_text)

	select_screen = Node2D.new()
	add_child(select_screen)

	var logo_small := Sprite.new()
	logo_small.texture = load(SPRITES + "ARCADE-text.png")
	logo_small.scale = Vector2(2, 2)
	logo_small.position = Vector2(SIZE.x / 2, 64)
	select_screen.add_child(logo_small)

	_build_game_buttons()

	record_label = Label.new()
	record_label.rect_position = Vector2(0, 268)
	record_label.rect_size = Vector2(SIZE.x, 20)
	record_label.align = Label.ALIGN_CENTER
	record_label.modulate = Color(1.0, 0.85, 0.25)
	select_screen.add_child(record_label)

	# Rammen ligger øverst og er felles for begge skjermene.
	var border := Sprite.new()
	border.texture = load(SPRITES + "Border.png")
	border.centered = false
	border.scale = SIZE / Vector2(160, 90)
	add_child(border)


func _build_game_buttons() -> void:
	if games.empty():
		var empty := Label.new()
		empty.text = "Ingen spill funnet i:\n" + games_dir
		empty.align = Label.ALIGN_CENTER
		empty.rect_position = Vector2(0, 160)
		empty.rect_size = Vector2(SIZE.x, 60)
		select_screen.add_child(empty)
		return

	var n := games.size()
	var spacing := 190.0
	var start_x := SIZE.x / 2 - (n - 1) * spacing / 2
	for i in n:
		var holder := Node2D.new()
		holder.position = Vector2(start_x + i * spacing, 180)
		select_screen.add_child(holder)
		buttons.append(holder)

		var game: Dictionary = games[i]
		if BUTTON_TEXTURES.has(game["id"]):
			var s := Sprite.new()
			s.texture = load(SPRITES + BUTTON_TEXTURES[game["id"]])
			holder.add_child(s)
		else:
			# Ingen egen sprite — enkel tekst-knapp i samme stil.
			var l := Label.new()
			l.text = game["name"].to_upper()
			l.align = Label.ALIGN_CENTER
			l.valign = Label.VALIGN_CENTER
			l.rect_position = Vector2(-28, -16)
			l.rect_size = Vector2(56, 32)
			l.rect_scale = Vector2(0.5, 0.5)
			l.rect_pivot_offset = Vector2(28, 16)
			holder.add_child(l)


func _show_start() -> void:
	state = State.START
	start_screen.visible = true
	select_screen.visible = false


func _show_select() -> void:
	state = State.SELECT
	start_screen.visible = false
	select_screen.visible = true
	_select(selected)


func _select(index: int) -> void:
	selected = int(clamp(index, 0, games.size() - 1))
	if games.empty():
		return
	var best: int = Arcade.get_best_score(games[selected]["id"])
	record_label.text = "rekord: %d" % best if best > 0 else ""


func _process(delta: float) -> void:
	if input_debug:
		debug_joy.text = _debug_joy_info()
		return

	elapsed += delta

	if state == State.START:
		press_text.frame = int(elapsed * 2.0) % 2
		return

	for i in buttons.size():
		var target_scale := SCALE_NORMAL
		var target_color := COLOR_NORMAL
		if i == selected:
			target_scale = SCALE_SELECTED + 0.08 * sin(elapsed * 5.0)
			target_color = COLOR_SELECTED
		var t: float = clamp(delta * ANIM_SPEED, 0.0, 1.0)
		var holder: Node2D = buttons[i]
		var s: float = lerp(holder.scale.x, target_scale, t)
		holder.scale = Vector2(s, s)
		holder.modulate = holder.modulate.linear_interpolate(target_color, t)


func _launch(index: int) -> void:
	var m: Dictionary = games[index]
	var pck_path: String = games_dir.plus_file(m["pck"])
	if not ProjectSettings.load_resource_pack(pck_path):
		_show_error("Kunne ikke laste " + m["pck"])
		return
	if not ResourceLoader.exists(m["main_scene"]):
		_show_error("Fant ikke scenen " + m["main_scene"])
		return
	print("Starter spill: " + m["name"])
	Arcade.start_game(m["main_scene"])


func _show_error(msg: String) -> void:
	printerr(msg)
	var err := Label.new()
	err.text = msg
	err.modulate = Color(1, 0.4, 0.4)
	err.align = Label.ALIGN_CENTER
	err.rect_position = Vector2(0, 310)
	err.rect_size = Vector2(SIZE.x, 20)
	add_child(err)


func _save_screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_data()
	img.flip_y()
	img.save_png(path)


# ---------------------------------------------------------------------------
# Input-testmodus
# ---------------------------------------------------------------------------

func _build_debug_ui() -> void:
	var title := Label.new()
	title.text = "INPUT-TEST — trykk på hver knapp/spak. Ctrl+C i terminalen avslutter."
	title.rect_position = Vector2(8, 6)
	title.modulate = Color(1.0, 0.85, 0.25)
	add_child(title)

	debug_joy = Label.new()
	debug_joy.rect_position = Vector2(8, 26)
	debug_joy.modulate = Color(0.45, 0.85, 1.0)
	add_child(debug_joy)

	debug_log = Label.new()
	debug_log.rect_position = Vector2(8, 64)
	debug_log.rect_size = Vector2(SIZE.x - 16, SIZE.y - 72)
	add_child(debug_log)

	print("INPUT-TEST aktiv. " + _debug_joy_info())


func _debug_joy_info() -> String:
	var pads := Input.get_connected_joypads()
	if pads.empty():
		return "Ingen joypad funnet — sjekk at USB-encoderen er koblet til."
	var lines := []
	for d in pads:
		lines.append("Joypad %d: %s  [guid %s]" % [d, Input.get_joy_name(d), Input.get_joy_guid(d)])
	return PoolStringArray(lines).join("\n")


func _debug_input(event: InputEvent) -> void:
	var line := ""
	if event is InputEventJoypadButton and event.pressed:
		line = "KNAPP %d  (enhet %d)%s" % [event.button_index, event.device, _debug_actions(event)]
	elif event is InputEventJoypadMotion and abs(event.axis_value) > 0.5:
		line = "AKSE %d = %+.1f  (enhet %d)%s" % [event.axis, event.axis_value, event.device, _debug_actions(event)]
	elif event is InputEventKey and event.pressed and not event.is_echo():
		line = "TAST %s  (scancode %d)%s" % [OS.get_scancode_string(event.scancode), event.scancode, _debug_actions(event)]
	if line == "":
		return
	print(line)
	debug_lines.append(line)
	if debug_lines.size() > 18:
		debug_lines.pop_front()
	debug_log.text = PoolStringArray(debug_lines).join("\n")


func _debug_actions(event: InputEvent) -> String:
	var hits := []
	for a in ["p1_up", "p1_down", "p1_left", "p1_right", "p1_a", "p1_b", "arcade_start", "arcade_back"]:
		if event.is_action(a):
			hits.append(a)
	if hits.empty():
		return "   ->  (ikke bundet)"
	return "   ->  " + PoolStringArray(hits).join(", ")


# ---------------------------------------------------------------------------
# Røyktest: ARCADE_SMOKE_TEST=1 → start første spill automatisk;
# når vi er tilbake i menyen er hele løkka bevist, og vi avslutter.
# ---------------------------------------------------------------------------

func _run_smoke_test() -> void:
	if games.empty():
		printerr("SMOKE TEST FEILET: ingen spill i " + games_dir)
		get_tree().quit(1)
		return
	if Arcade.smoke_index >= games.size():
		print("SMOKE TEST OK (%d spill testet)" % games.size())
		get_tree().quit(0)
		return
	var index: int = Arcade.smoke_index
	Arcade.smoke_index += 1
	print("Røyktest %d/%d: starter '%s' ..." % [index + 1, games.size(), games[index]["name"]])
	call_deferred("_launch", index)
