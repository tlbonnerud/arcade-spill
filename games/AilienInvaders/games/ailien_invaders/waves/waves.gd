extends Reference

# Bølgene som data. Én rad per bølge, ingen kode. Motoren som kjører dem er
# core/wave_manager.gd, og alt den trenger står her.
#
#   enemies        [[type, antall], ...] i rekkefølgen de fyller formasjonen
#                  (første type havner øverst). Typene: enemies/enemy_types.gd
#   formations     pool, én trekkes per run: rows, v_shape, ring, checkerboard
#   entries        pool: from_top, from_sides, spiral, swoop
#   movements      pool: classic, sine
#   descent_time   sekunder til formasjonen når bunnen hvis ingen dør. Dette
#                  er bølgens "klokke"; det går fortere jo flere som er døde.
#   dives          true: fiender dykker mot spilleren
#   dive_types     hvem som dykker; tom liste = typene med can_dive
#   dive_interval  sekunder mellom hvert nytt dykk
#   max_divers     hvor mange som kan dykke samtidig
#   hp_mult        fiendenes hp × dette, avrundet (minst 1)
#   fire_rate_mult skytefrekvens × dette
#   speed_mult     formasjonens sideveis fart/tempo × dette
#   bullet_speed_mult fiendekulenes fart × dette
#   max_bullets    tak på fiendekuler i lufta samtidig
#   banner         tekst i WAVE_INTRO (standard "BØLGE N")
#
# Ny bølge = ny rad. Nytt mønster = ny funksjon i enemies/, så navnet her.

const DEFAULTS := {
	"formations": ["rows"],
	"entries": ["from_top"],
	"movements": ["classic"],
	"descent_time": 100.0,
	"dives": false,
	"dive_types": [],
	"dive_interval": 3.0,
	"max_divers": 1,
	"hp_mult": 1.0,
	"fire_rate_mult": 1.0,
	"speed_mult": 1.0,
	"bullet_speed_mult": 1.0,
	"max_bullets": 3,
}

const WAVES := [
	{ # Bølge 1 — opplæring. Som gamle Ailien Invaders, bare færre.
		"enemies": [["grunt", 16]],
		"formations": ["rows"],
		"entries": ["from_top"],
		"movements": ["classic"],
		"max_bullets": 3,
	},
	{ # Bølge 2 — soldater skyter oftere, formasjonen svaier.
		"enemies": [["soldat", 12], ["grunt", 12]],
		"formations": ["v_shape", "rows"],
		"entries": ["from_sides", "spiral"],
		"movements": ["sine", "classic"],
		"hp_mult": 1.0,
		"fire_rate_mult": 1.25,
		"speed_mult": 1.15,
		"bullet_speed_mult": 1.1,
		"max_bullets": 4,
	},
	{ # Bølge 3 — skyttere sikter, eliter dykker, alt tåler mer.
		"enemies": [["elite", 4], ["skytter", 8], ["soldat", 16]],
		"formations": ["ring", "checkerboard"],
		"entries": ["spiral", "swoop"],
		"movements": ["sine", "classic"],
		"dives": true,
		"dive_interval": 3.0,
		"hp_mult": 1.3,
		"fire_rate_mult": 1.5,
		"speed_mult": 1.3,
		"bullet_speed_mult": 1.2,
		"max_bullets": 5,
		"banner": "BØLGE 3 — ELITE",
	},
]


static func count() -> int:
	return WAVES.size()


# Bølge n (1-basert) med standardverdier fylt inn.
static func get_wave(n: int) -> Dictionary:
	var data := DEFAULTS.duplicate()
	var src: Dictionary = WAVES[clamp(n - 1, 0, WAVES.size() - 1)]
	for key in src:
		data[key] = src[key]
	if not data.has("banner"):
		data["banner"] = "BØLGE %d" % n
	return data


static func enemy_count(data: Dictionary) -> int:
	var n := 0
	for pair in data["enemies"]:
		n += int(pair[1])
	return n
