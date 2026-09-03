extends Control

# Dummy-spill for fase 1-piloten: viser bare en tekst. Beviser at
# .pck-lasting, felles input og quit_to_launcher() fungerer ende-til-ende.
# Tilbake til menyen: SELECT/ESC (globalt i arcade_api.gd).

var elapsed := 0.0
onready var hint: Label = Label.new()


func _ready() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_WIDE)
	root.alignment = BoxContainer.ALIGN_CENTER
	root.set("custom_constants/separation", 16)
	add_child(root)

	var title := Label.new()
	title.text = "DUMMY-SPILL"
	title.align = Label.ALIGN_CENTER
	title.rect_scale = Vector2(2, 2)
	var title_center := CenterContainer.new()
	title_center.add_child(title)
	root.add_child(title_center)

	hint.text = "Trykk SELECT (ESC på tastatur) for å gå tilbake"
	hint.align = Label.ALIGN_CENTER
	var hint_center := CenterContainer.new()
	hint_center.add_child(hint)
	root.add_child(hint_center)

	if Arcade.smoke_test:
		yield(get_tree().create_timer(0.5), "timeout")
		print("Røyktest: dummy-spillet kjører, går tilbake til launcheren ...")
		Arcade.quit_to_launcher()


func _process(delta: float) -> void:
	elapsed += delta
	hint.modulate.a = 0.5 + 0.5 * abs(sin(elapsed * 3.0))
