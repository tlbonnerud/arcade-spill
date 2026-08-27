extends Control

# Fase 1-pilot: enkel liste over spill funnet i games-mappa.
# Design og animasjoner kommer i fase 2 — dette skal bare bevise flyten.

var games := []
var games_dir := ""
var selected := 0
var rows := []

onready var list: VBoxContainer = VBoxContainer.new()


func _ready() -> void:
	games_dir = _find_games_dir()
	games = _scan_games(games_dir)
	_build_ui()

	if Arcade.smoke_test:
		_run_smoke_test()


func _input(event: InputEvent) -> void:
	if games.empty():
		return
	if event.is_action_pressed("p1_down"):
		_select(selected + 1)
	elif event.is_action_pressed("p1_up"):
		_select(selected - 1)
	elif event.is_action_pressed("p1_a") or event.is_action_pressed("arcade_start"):
		_launch(selected)
	elif event.is_action_pressed("arcade_back") and OS.is_debug_build():
		# Kun for utvikling på Mac — på Pi-en starter systemd launcheren på nytt,
		# så der skal denne aldri trigges.
		get_tree().quit()


# ---------------------------------------------------------------------------

func _find_games_dir() -> String:
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

func _build_ui() -> void:
	var title := Label.new()
	title.text = "ARCADE"
	title.align = Label.ALIGN_CENTER
	title.rect_scale = Vector2(2, 2)

	list.alignment = BoxContainer.ALIGN_CENTER
	list.set("custom_constants/separation", 8)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_WIDE)
	root.alignment = BoxContainer.ALIGN_CENTER
	root.set("custom_constants/separation", 24)
	add_child(root)

	var title_center := CenterContainer.new()
	title_center.add_child(title)
	root.add_child(title_center)

	var list_center := CenterContainer.new()
	list_center.add_child(list)
	root.add_child(list_center)

	if games.empty():
		var empty := Label.new()
		empty.text = "Ingen spill funnet i:\n" + games_dir
		empty.align = Label.ALIGN_CENTER
		list.add_child(empty)
		return

	for game in games:
		var row := Label.new()
		var best: int = Arcade.get_best_score(game["id"])
		row.text = game["name"] + ("   (rekord: %d)" % best if best > 0 else "")
		row.align = Label.ALIGN_CENTER
		list.add_child(row)
		rows.append(row)

	_select(0)


func _select(index: int) -> void:
	selected = int(clamp(index, 0, games.size() - 1))
	for i in rows.size():
		if i == selected:
			rows[i].modulate = Color(1, 0.9, 0.3)
			rows[i].text = "> " + games[i]["name"] + " <"
		else:
			rows[i].modulate = Color(0.7, 0.7, 0.8)
			rows[i].text = games[i]["name"]


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
	list.add_child(err)


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
