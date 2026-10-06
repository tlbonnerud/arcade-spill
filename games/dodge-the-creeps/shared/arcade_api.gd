extends Node

# Arcade-API — felles kontrakt for launcheren og alle spill.
# VIKTIG: Denne fila skal være identisk i launcher/shared/ og i shared/-mappa
# i hvert spillprosjekt. Endrer du den ett sted, kopier til de andre.

const LAUNCHER_SCENE := "res://scenes/launcher.tscn"
const HIGHSCORE_FILE := "user://highscores.json"
const MAX_SCORES := 10

var in_game := false
var returned_from_game := false
var smoke_test := false
var smoke_index := 0  # røyktesten: neste spill som skal testes


func _ready() -> void:
	pause_mode = Node.PAUSE_MODE_PROCESS
	smoke_test = OS.get_environment("ARCADE_SMOKE_TEST") != ""
	_register_inputs()


func _input(event: InputEvent) -> void:
	# Globalt: tilbake-knappen avslutter spillet og går til menyen,
	# uansett hva spillet selv gjør. (Byttes til holde-kombinasjon i fase 2.)
	if in_game and event.is_action_pressed("arcade_back"):
		quit_to_launcher()


# ---------------------------------------------------------------------------
# Scenebytte
# ---------------------------------------------------------------------------

func start_game(main_scene: String) -> void:
	in_game = true
	get_tree().paused = false
	get_tree().change_scene(main_scene)


func quit_to_launcher() -> void:
	get_tree().paused = false
	in_game = false
	returned_from_game = true
	if ResourceLoader.exists(LAUNCHER_SCENE):
		get_tree().change_scene(LAUNCHER_SCENE)
	else:
		# Spillet kjører standalone (under utvikling) — bare avslutt.
		get_tree().quit()


# ---------------------------------------------------------------------------
# Highscores (lagres i user://, overlever oppgraderinger av spillene)
# ---------------------------------------------------------------------------

func get_highscores(game_id: String) -> Array:
	return _load_all_scores().get(game_id, [])


func get_best_score(game_id: String) -> int:
	var scores := get_highscores(game_id)
	return int(scores[0]["score"]) if scores.size() > 0 else 0


func save_highscore(game_id: String, player: String, score: int) -> void:
	var all := _load_all_scores()
	var list: Array = all.get(game_id, [])
	list.append({"name": player, "score": score})
	list.sort_custom(self, "_score_desc")
	if list.size() > MAX_SCORES:
		list.resize(MAX_SCORES)
	all[game_id] = list
	_save_all_scores(all)


static func _score_desc(a, b) -> bool:
	return a["score"] > b["score"]


func _load_all_scores() -> Dictionary:
	var f := File.new()
	if not f.file_exists(HIGHSCORE_FILE):
		return {}
	if f.open(HIGHSCORE_FILE, File.READ) != OK:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed := JSON.parse(text)
	if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
		return parsed.result
	return {}


func _save_all_scores(all: Dictionary) -> void:
	var f := File.new()
	if f.open(HIGHSCORE_FILE, File.WRITE) == OK:
		f.store_string(JSON.print(all, "  "))
		f.close()


# ---------------------------------------------------------------------------
# Input — registreres i kode så launcher og alle spill garantert har
# samme mapping. Tastatur for utvikling, joypad = USB-encoder på arkaden.
# ---------------------------------------------------------------------------

func _register_inputs() -> void:
	_action("p1_up",    [_key(KEY_UP),     _btn(JOY_DPAD_UP),    _axis(JOY_AXIS_1, -1.0)])
	_action("p1_down",  [_key(KEY_DOWN),   _btn(JOY_DPAD_DOWN),  _axis(JOY_AXIS_1,  1.0)])
	_action("p1_left",  [_key(KEY_LEFT),   _btn(JOY_DPAD_LEFT),  _axis(JOY_AXIS_0, -1.0)])
	_action("p1_right", [_key(KEY_RIGHT),  _btn(JOY_DPAD_RIGHT), _axis(JOY_AXIS_0,  1.0)])
	_action("p1_a",     [_key(KEY_Z),      _btn(JOY_BUTTON_0)])
	_action("p1_b",     [_key(KEY_X),      _btn(JOY_BUTTON_1)])
	# DragonRise-encoderen på arkaden har ingen standard-mapping:
	# START-knappen er indeks 3 og RESET (= tilbake/exit) er indeks 2.
	# JOY_START/JOY_SELECT beholdes for vanlige gamepads under utvikling.
	_action("arcade_start", [_key(KEY_ENTER),  _btn(JOY_START),  _btn(JOY_BUTTON_3)])
	_action("arcade_back",  [_key(KEY_ESCAPE), _btn(JOY_SELECT), _btn(JOY_BUTTON_2)])


func _action(action_name: String, events: Array) -> void:
	if InputMap.has_action(action_name):
		return
	InputMap.add_action(action_name)
	InputMap.action_set_deadzone(action_name, 0.5)
	for e in events:
		InputMap.action_add_event(action_name, e)


func _key(scancode: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.scancode = scancode
	return e


func _btn(index: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = index
	return e


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	return e
