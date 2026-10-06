extends Node2D

# "Velg 1 av 3"-skjermen mellom bølgene. Bygges i kode (som resten av
# spillet), tre kort side om side: ikon, navn, hva den gjør, sjeldenhet og
# nivå. Venstre/høyre velger, A bekrefter. Velger selv det markerte kortet
# når tida går ut, så maskinen aldri står og venter på noen som har gått.
#
# main.gd kaller show_offer(ids, stacks) og step(delta), og lytter på
# `chosen`. Tester og boten kaller choose(index) direkte.

signal chosen(id)

const Upgrades := preload("res://games/ailien_invaders/upgrades/upgrades.gd")

const AUTO_PICK_TIME := 15.0
const CARD_SIZE := Vector2(176, 180)
const CARD_GAP := 20.0
const CARD_Y := 90.0
const ICON_SCALE := 4.0
const ICON_FRAME_TIME := 0.5
const COLOR_BG := Color(0.0, 0.0, 0.05, 0.82)
const COLOR_CARD := Color(0.07, 0.08, 0.18)
const COLOR_CARD_SELECTED := Color(0.14, 0.16, 0.32)
const COLOR_BORDER := Color(0.3, 0.35, 0.55)
const COLOR_BORDER_SELECTED := Color(1.0, 0.95, 0.5)
const COLOR_TEXT := Color(0.85, 0.88, 1.0)
const COLOR_DIM := Color(0.55, 0.6, 0.75)

var area_size := Vector2(640, 360)
var offer := []            # id-er som vises
var stacks := {}           # {id: antall} spilleren alt har
var selected := 1
var timer := 0.0
var icon_timer := 0.0
var active := false
# Tester/bot: null = vanlig input, ellers kalles choose() av den som styrer.
var autopilot = null

var _cards := []   # [{panel, border, icon, name, desc, rarity, level}]
var _title: Label
var _hint: Label


func setup(size: Vector2) -> void:
	area_size = size
	z_index = 20
	visible = false
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.rect_position = Vector2.ZERO
	bg.rect_size = area_size
	bg.color = COLOR_BG
	add_child(bg)

	_title = _label(Vector2(0, 40), area_size.x, "VELG OPPGRADERING", COLOR_TEXT)
	_hint = _label(Vector2(0, area_size.y - 50), area_size.x, "", COLOR_DIM)

	var total_w := CARD_SIZE.x * 3 + CARD_GAP * 2
	var x0 := (area_size.x - total_w) / 2
	for i in 3:
		var pos := Vector2(x0 + i * (CARD_SIZE.x + CARD_GAP), CARD_Y)
		var border := ColorRect.new()
		border.rect_position = pos - Vector2(2, 2)
		border.rect_size = CARD_SIZE + Vector2(4, 4)
		border.color = COLOR_BORDER
		add_child(border)
		var panel := ColorRect.new()
		panel.rect_position = pos
		panel.rect_size = CARD_SIZE
		panel.color = COLOR_CARD
		add_child(panel)

		var icon := Sprite.new()
		icon.position = pos + Vector2(CARD_SIZE.x / 2, 52)
		icon.scale = Vector2.ONE * ICON_SCALE
		add_child(icon)

		var card := {
			"panel": panel, "border": border, "icon": icon,
			"rarity": _label(pos + Vector2(0, 6), CARD_SIZE.x, "", COLOR_DIM),
			"name": _label(pos + Vector2(0, 96), CARD_SIZE.x, "", COLOR_TEXT),
			"desc": _label(pos + Vector2(0, 118), CARD_SIZE.x, "", COLOR_DIM),
			"level": _label(pos + Vector2(0, 154), CARD_SIZE.x, "", COLOR_DIM),
		}
		card["desc"].autowrap = true
		card["desc"].rect_size = Vector2(CARD_SIZE.x - 12, 36)
		card["desc"].rect_position.x += 6
		_cards.append(card)


func _label(pos: Vector2, width: float, text: String, color: Color) -> Label:
	var l := Label.new()
	l.rect_position = pos
	l.rect_size = Vector2(width, 20)
	l.align = Label.ALIGN_CENTER
	l.text = text
	l.add_color_override("font_color", color)
	add_child(l)
	return l


# Viser tilbudet. ids er 1–3 oppgraderinger, stacks hva spilleren alt har.
func show_offer(ids: Array, have: Dictionary) -> void:
	offer = ids.duplicate()
	stacks = have
	selected = int(min(1, offer.size() - 1))
	timer = 0.0
	icon_timer = 0.0
	active = true
	visible = true
	for i in 3:
		var card: Dictionary = _cards[i]
		var shown: bool = i < offer.size()
		for key in ["panel", "border", "icon", "rarity", "name", "desc", "level"]:
			card[key].visible = shown
		if not shown:
			continue
		var u: Dictionary = Upgrades.get_upgrade(offer[i])
		var icon: Sprite = card["icon"]
		icon.texture = u["icon"]
		icon.hframes = int(max(1, u["icon"].get_width() / Upgrades.ICON_SIZE.x))
		icon.frame = 0
		card["rarity"].text = Upgrades.RARITY_NAMES[u["rarity"]]
		card["rarity"].add_color_override("font_color", Upgrades.RARITY_COLORS[u["rarity"]])
		card["name"].text = u["name"]
		card["desc"].text = u["desc"]
		var have_n := int(stacks.get(offer[i], 0))
		var max_n := int(u["max_stacks"])
		card["level"].text = ("NIVÅ %d AV %d" % [have_n + 1, max_n]) if max_n > 1 else "ÉN GANG"
	_refresh_selection()


func hide_screen() -> void:
	active = false
	visible = false


func step(delta: float) -> void:
	if not active:
		return
	timer += delta
	icon_timer += delta
	_hint.text = "VENSTRE/HØYRE VELGER   A BEKREFTER   AUTOVALG OM %d" % int(ceil(AUTO_PICK_TIME - timer))
	if icon_timer >= ICON_FRAME_TIME:
		icon_timer = 0.0
		for card in _cards:
			var icon: Sprite = card["icon"]
			if icon.visible and icon.hframes > 1:
				icon.frame = (icon.frame + 1) % icon.hframes

	if autopilot == null:
		if Input.is_action_just_pressed("p1_left"):
			_move(-1)
		elif Input.is_action_just_pressed("p1_right"):
			_move(1)
		if Input.is_action_just_pressed("p1_a") or Input.is_action_just_pressed("arcade_start"):
			choose(selected)
			return
	if timer >= AUTO_PICK_TIME:
		choose(selected)


func _move(dir: int) -> void:
	if offer.empty():
		return
	selected = int(clamp(selected + dir, 0, offer.size() - 1))
	_refresh_selection()


func _refresh_selection() -> void:
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var sel: bool = (i == selected)
		card["panel"].color = COLOR_CARD_SELECTED if sel else COLOR_CARD
		card["border"].color = COLOR_BORDER_SELECTED if sel else COLOR_BORDER
		card["name"].add_color_override("font_color", COLOR_BORDER_SELECTED if sel else COLOR_TEXT)


# Velger kort nummer index. Sender `chosen` én gang og skjuler skjermen.
func choose(index: int) -> void:
	if not active or offer.empty():
		return
	index = int(clamp(index, 0, offer.size() - 1))
	var id: String = offer[index]
	hide_screen()
	emit_signal("chosen", id)
