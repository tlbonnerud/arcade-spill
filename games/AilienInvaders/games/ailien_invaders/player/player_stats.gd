extends Reference

# Spillerens statblokk: alle tall oppgraderingene kan påvirke, samlet ett sted.
# `base` er dagens oppførsel uten oppgraderinger. `taken` er oppgraderingene
# i den rekkefølgen de ble valgt, og `current` regnes alltid ut fra bunnen av
# (base + alle apply på nytt), så stats aldri kan komme ut av synk.
#
# Hvem leser hva:
#   player.gd   move_speed, max_lives, ship_scale, shield
#   bullets.gd  max_bullets, bullet_speed, bullet_size, shots, pierce, damage,
#               homing, explosion
#   main.gd     heal_per_wave, thorns, start_lives

const Upgrades := preload("res://games/ailien_invaders/upgrades/upgrades.gd")

const BASE := {
	"move_speed": 220.0,     # px/s
	"start_lives": 3,
	"max_lives": 5,
	"max_bullets": 1,        # spillerkuler i lufta samtidig (per skudd-vifte)
	"bullet_speed": 420.0,   # px/s
	"bullet_size": 1.0,      # tegnet størrelse og treffboks × dette
	"shots": 1,              # kuler per trykk (vifte)
	"pierce": 0,             # fiender en kule kan gå gjennom
	"damage": 1,             # hp per treff
	"homing": 0.0,           # svingfart mot fiender, rad/s (0 = av)
	"explosion": 0.0,        # radius px rundt drap der naboer tar 1 skade (0 = av)
	"ship_scale": 1.0,       # sprite og treffboks × dette
	"shield": 0,             # treff som tåles per bølge
	"heal_per_wave": 0,      # liv tilbake etter hver bølge
	"thorns": 0,             # 1: treff på spilleren skader fiender i nærheten
}

var base := BASE.duplicate()
var taken := []            # id-er i valgt rekkefølge
var current := BASE.duplicate()


func reset() -> void:
	taken.clear()
	recompute()


func take(id: String) -> void:
	taken.append(id)
	recompute()


func stacks(id: String) -> int:
	return taken.count(id)


# {id: antall} for alle tatte, i katalogrekkefølge.
func stack_counts() -> Dictionary:
	var out := {}
	for id in Upgrades.IDS:
		var n := stacks(id)
		if n > 0:
			out[id] = n
	return out


func recompute() -> void:
	current = base.duplicate()
	var seen := {}
	for id in taken:
		seen[id] = int(seen.get(id, 0)) + 1
		Upgrades.apply(id, current, seen[id])
