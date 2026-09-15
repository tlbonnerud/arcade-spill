extends Reference

# Fiendetypene som tabell. Bølgene i waves/waves.gd refererer til dem med id.
# Teksturene preloades her (preload krever bokstavelige stier i Godot 3).
# NB: filnavnene lyver litt: Enemy_3.png er haien og Enemy_4.png er maneten.
#
#   hp          grunn-hp før bølgeskalering (waves.gd hp_mult)
#   points      poeng ved død
#   bullet      kuletype i core/bullets.gd KINDS
#   aimed       true: skyter mot spilleren, false: rett ned
#   fire_weight sannsynlighetsvekt for å bli valgt som skytter
#   can_dive    kan forlate formasjonen og dykke mot spilleren

const TYPES := {
	"grunt": {  # rosa manet
		"texture": preload("res://games/ailien_invaders/sprites/Enemy_4.png"),
		"hp": 1, "points": 10, "bullet": "orb", "aimed": false,
		"fire_weight": 1.0, "can_dive": false,
	},
	"soldat": {  # grønn kyklop
		"texture": preload("res://games/ailien_invaders/sprites/Enemy_1.png"),
		"hp": 1, "points": 20, "bullet": "green", "aimed": false,
		"fire_weight": 2.5, "can_dive": false,
	},
	"skytter": {  # blå vinget
		"texture": preload("res://games/ailien_invaders/sprites/Enemy_2.png"),
		"hp": 2, "points": 30, "bullet": "blue", "aimed": true,
		"fire_weight": 2.0, "can_dive": false,
	},
	"elite": {  # mørk hai
		"texture": preload("res://games/ailien_invaders/sprites/Enemy_3.png"),
		"hp": 3, "points": 40, "bullet": "red", "aimed": true,
		"fire_weight": 2.0, "can_dive": true,
	},
}

const FRAME_WIDTH := 32


static func get_type(id: String) -> Dictionary:
	if not TYPES.has(id):
		push_warning("Ukjent fiendetype '%s', bruker 'grunt'" % id)
		return TYPES["grunt"]
	return TYPES[id]


# Antall animasjonsruter i sprite-arket (32 px brede ruter på rad).
static func frame_count(type: Dictionary) -> int:
	var tex: Texture = type["texture"]
	return int(max(1, tex.get_width() / FRAME_WIDTH))
