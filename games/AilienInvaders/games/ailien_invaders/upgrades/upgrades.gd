extends Reference

# Oppgraderingskatalogen. Én oppføring per oppgradering, med ikon, sjeldenhet,
# hvor mange ganger den kan tas, og en apply-funksjon som endrer statblokken
# (player/player_stats.gd). Alt som kan stilles på ligger her, ikke i koden
# som bruker stats.
#
#   name        tittel på kortet (store bokstaver, kort)
#   desc        én linje som sier hva den gjør
#   rarity      common / rare / epic (vekt ved trekking, se WEIGHTS)
#   max_stacks  hvor mange ganger den kan tas i ett run
#   icon        24×20-ikon fra sprites/. Flere ruter = animert på kortet.
#   apply       metode som får (stats, stacks) og endrer stats
#   on_pick     valgfritt: umiddelbar effekt main gjør idet kortet velges
#               ("add_life"). Varige effekter går alltid via stats.
#
# Trekking (offer): tre ulike, aldri en som er maks-stablet, vektet etter
# sjeldenhet. Første tilbud i et run har alltid minst én sjelden, så runnet
# "kjennes" fra start.

const WEIGHTS := {"common": 10, "rare": 4, "epic": 1}
const RARITY_NAMES := {"common": "VANLIG", "rare": "SJELDEN", "epic": "EPISK"}
const RARITY_COLORS := {
	"common": Color(0.75, 0.85, 1.0),
	"rare": Color(0.45, 0.95, 0.55),
	"epic": Color(1.0, 0.65, 0.25),
}
const ICON_SIZE := Vector2(24, 20)

# (preload krever bokstavelige stier i Godot 3.)
const CATALOG := {
	"multishot": {
		"name": "SPREDNINGSSKUDD", "desc": "+1 KULE PER SKUDD, I VIFTE",
		"rarity": "rare", "max_stacks": 3, "apply": "_apply_multishot",
		"icon": preload("res://games/ailien_invaders/sprites/Multishot.png"),
	},
	"damage": {
		"name": "SKARPT SKYTS", "desc": "+1 SKADE PER KULE",
		"rarity": "rare", "max_stacks": 3, "apply": "_apply_damage",
		"icon": preload("res://games/ailien_invaders/sprites/atck_up.png"),
	},
	"attack_speed": {
		"name": "HURTIGSKUDD", "desc": "+1 KULE I LUFTA SAMTIDIG",
		"rarity": "common", "max_stacks": 3, "apply": "_apply_attack_speed",
		"icon": preload("res://games/ailien_invaders/sprites/Attck_speed_up.png"),
	},
	"piercing": {
		"name": "GJENNOMTRENGING", "desc": "KULA GÅR GJENNOM +1 FIENDE",
		"rarity": "rare", "max_stacks": 2, "apply": "_apply_piercing",
		"icon": preload("res://games/ailien_invaders/sprites/Piercing.png"),
	},
	"homing": {
		"name": "MÅLSØKING", "desc": "KULENE SVINGER MOT FIENDENE",
		"rarity": "rare", "max_stacks": 2, "apply": "_apply_homing",
		"icon": preload("res://games/ailien_invaders/sprites/Homing.png"),
	},
	"explosion": {
		"name": "EKSPLOSJON", "desc": "DRAP SKADER FIENDENE RUNDT",
		"rarity": "rare", "max_stacks": 2, "apply": "_apply_explosion",
		"icon": preload("res://games/ailien_invaders/sprites/Explotion.png"),
	},
	"big_bullets": {
		"name": "STORE KULER", "desc": "KULENE ER 50% STØRRE",
		"rarity": "common", "max_stacks": 2, "apply": "_apply_big_bullets",
		"icon": preload("res://games/ailien_invaders/sprites/Big_bullet.png"),
	},
	"hp_up": {
		"name": "MER LIV", "desc": "+1 LIV NÅ OG +1 MAKS LIV",
		"rarity": "common", "max_stacks": 3, "apply": "_apply_hp_up", "on_pick": "add_life",
		"icon": preload("res://games/ailien_invaders/sprites/HP_up.png"),
	},
	"healing": {
		"name": "HELBREDELSE", "desc": "+1 LIV ETTER HVER BØLGE",
		"rarity": "rare", "max_stacks": 1, "apply": "_apply_healing", "on_pick": "add_life",
		"icon": preload("res://games/ailien_invaders/sprites/Healing.png"),
	},
	"potion": {
		"name": "SKJOLDDRIKK", "desc": "TÅLER ETT TREFF PER BØLGE",
		"rarity": "rare", "max_stacks": 2, "apply": "_apply_potion",
		"icon": preload("res://games/ailien_invaders/sprites/Potion.png"),
	},
	"thorns": {
		"name": "PIGGER", "desc": "TREFF PÅ DEG SKADER ALLE NÆR",
		"rarity": "epic", "max_stacks": 1, "apply": "_apply_thorns",
		"icon": preload("res://games/ailien_invaders/sprites/Thorns.png"),
	},
	"size_down": {
		"name": "MINDRE SKIP", "desc": "SKIPET ER 25% MINDRE",
		"rarity": "common", "max_stacks": 2, "apply": "_apply_size_down",
		"icon": preload("res://games/ailien_invaders/sprites/Size_down.png"),
	},
	"move_speed": {
		"name": "RAKETTSTØVLER", "desc": "+30% FART",
		"rarity": "common", "max_stacks": 2, "apply": "_apply_move_speed",
		"icon": preload("res://games/ailien_invaders/sprites/Move_speed_up.png"),
	},
}

# Rekkefølgen kortene vises i HUD-en og tester itererer i.
const IDS := ["multishot", "damage", "attack_speed", "piercing", "homing", "explosion",
		"big_bullets", "hp_up", "healing", "potion", "thorns", "size_down", "move_speed"]


static func get_upgrade(id: String) -> Dictionary:
	if not CATALOG.has(id):
		push_warning("Ukjent oppgradering '%s'" % id)
		return {}
	return CATALOG[id]


static func max_stacks(id: String) -> int:
	return int(get_upgrade(id).get("max_stacks", 1))


# Kjører apply for id på stats. stacks er hvor mange ganger den er tatt, så
# ikke-lineære effekter (eksplosjonsradius) kan regnes ut fra antallet.
static func apply(id: String, stats: Dictionary, stacks: int) -> void:
	var u := get_upgrade(id)
	if u.empty():
		return
	var self_ref := load("res://games/ailien_invaders/upgrades/upgrades.gd")
	self_ref.call(u["apply"], stats, stacks)


# Trekker opptil n ulike oppgraderinger som fortsatt kan tas, vektet etter
# sjeldenhet. first=true garanterer minst én sjelden/episk (første tilbud).
static func offer(rng: RandomNumberGenerator, stacks: Dictionary, n: int = 3, first: bool = false) -> Array:
	var pool := []
	for id in IDS:
		if int(stacks.get(id, 0)) < max_stacks(id):
			pool.append(id)
	var out := []
	while out.size() < n and not pool.empty():
		var id: String = _draw(rng, pool)
		pool.erase(id)
		out.append(id)
	if first and not out.empty() and not _has_rare(out):
		# Bytt det siste kortet mot en sjelden/episk som ikke alt er med.
		var rares := []
		for id in pool:
			if CATALOG[id]["rarity"] != "common":
				rares.append(id)
		if not rares.empty():
			out[out.size() - 1] = _draw(rng, rares)
	return out


static func _has_rare(ids: Array) -> bool:
	for id in ids:
		if CATALOG[id]["rarity"] != "common":
			return true
	return false


static func _draw(rng: RandomNumberGenerator, pool: Array) -> String:
	var sum := 0
	for id in pool:
		sum += int(WEIGHTS[CATALOG[id]["rarity"]])
	var r := rng.randi() % sum
	for id in pool:
		r -= int(WEIGHTS[CATALOG[id]["rarity"]])
		if r < 0:
			return id
	return pool[pool.size() - 1]


# ---------------------------------------------------------------------------
# Effektene. Alle tallene som kan stilles på står her.
# ---------------------------------------------------------------------------

static func _apply_multishot(stats: Dictionary, _stacks: int) -> void:
	stats["shots"] += 1


static func _apply_damage(stats: Dictionary, _stacks: int) -> void:
	stats["damage"] += 1


static func _apply_attack_speed(stats: Dictionary, _stacks: int) -> void:
	stats["max_bullets"] += 1


static func _apply_piercing(stats: Dictionary, _stacks: int) -> void:
	stats["pierce"] += 1


# Svingfart i radianer per sekund. To nivåer: mykt, så skarpt.
static func _apply_homing(stats: Dictionary, stacks: int) -> void:
	stats["homing"] = 2.2 if stacks <= 1 else 4.0


# Radius i px rundt et drap der andre fiender tar 1 skade. Plassene i
# formasjonene er minst 28 px fra hverandre, så 46 tar nærmeste naboer og
# 72 tar naboenes naboer. Eksplosjoner smitter ikke videre.
static func _apply_explosion(stats: Dictionary, stacks: int) -> void:
	stats["explosion"] = 46.0 if stacks <= 1 else 72.0


static func _apply_big_bullets(stats: Dictionary, _stacks: int) -> void:
	stats["bullet_size"] *= 1.5


static func _apply_hp_up(stats: Dictionary, _stacks: int) -> void:
	stats["max_lives"] += 1


static func _apply_healing(stats: Dictionary, _stacks: int) -> void:
	stats["heal_per_wave"] += 1


static func _apply_potion(stats: Dictionary, _stacks: int) -> void:
	stats["shield"] += 1


static func _apply_thorns(stats: Dictionary, _stacks: int) -> void:
	stats["thorns"] = 1


static func _apply_size_down(stats: Dictionary, _stacks: int) -> void:
	stats["ship_scale"] *= 0.75


static func _apply_move_speed(stats: Dictionary, _stacks: int) -> void:
	stats["move_speed"] *= 1.3
