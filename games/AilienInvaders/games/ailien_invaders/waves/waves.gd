extends Reference

# Bølgene som data. Én rad per bølge, ingen kode. Motoren som kjører dem er
# core/wave_manager.gd, og alt den trenger står her.
#
#   enemies        [[type, antall], ...] i rekkefølgen de fyller formasjonen
#                  (første type havner øverst). Typene: enemies/enemy_types.gd
#   formations     pool, én trekkes per run: rows, v_shape, ring, checkerboard,
#                  two_groups, diamond, arrow, columns, x_shape
#   entries        pool: from_top, from_sides, spiral, swoop, rain, crossover,
#                  loop, snake
#   movements      pool: classic, sine, figure8, split, rock, orbit, pulse
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
#   banner         tekst i WAVE_INTRO (standard "BØLGE N"). Bruk \n for to linjer;
#                  standardfonten har ikke tankestrek.
#   bonus_life     true: +1 liv når bølgen er klarert (maks player.MAX_LIVES)
#
# Ny bølge = ny rad. Nytt mønster = ny funksjon i enemies/, så navnet her.
#
# Tallene er stilt inn mot boten i tests/sim_waves.tscn (se waves/README.md og
# docs/DESIGN.md). Hold poolene homogene: ett vanskelig mønster i en pool gir
# run som føles urettferdige. Sterkeste knapp for øvede spillere er speed_mult;
# skuddtakt, kulefart og max_bullets rammer mest de uøvede.

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
	"bonus_life": false,
}

const WAVES := [
	{ # Bølge 1 — Opplæring. To rader maneter som marsjerer som i Space Invaders.
		"enemies": [["grunt", 16]],
		"formations": ["rows"],
		"entries": ["from_top"],
		"movements": ["classic"],
		"max_bullets": 3,
	},
	{ # Bølge 2 — Soldater skyter ofte, og formasjonen svaier i stedet for å marsjere.
	  # 27 = tre hele vinkler i V-formen.
		"banner": "BØLGE 2\nSOLDATER",
		"enemies": [["soldat", 12], ["grunt", 15]],
		"formations": ["v_shape"],
		"entries": ["from_sides"],
		"movements": ["sine"],
		"max_bullets": 3,
	},
	{ # Bølge 3 — De sikter! Første siktede skudd, første show-innflyging. Gir bonusliv.
		"banner": "BØLGE 3\nDE SIKTER!",
		"enemies": [["skytter", 9], ["grunt", 15]],
		"formations": ["diamond"],
		"entries": ["loop", "spiral"],
		"movements": ["pulse"],
		"max_bullets": 3,
		"bonus_life": true,
	},
	{ # Bølge 4 — Porten. Første store bølge: to dører som åpner og lukker seg.
		"banner": "BØLGE 4\nPORTEN",
		"enemies": [["skytter", 8], ["soldat", 8], ["grunt", 16]],
		"formations": ["two_groups"],
		"entries": ["crossover", "from_sides"],
		"movements": ["split"],
		"fire_rate_mult": 1.4,
		"speed_mult": 1.0,
		"bullet_speed_mult": 1.15,
		"max_bullets": 4,
	},
	{ # Bølge 5 — Haiene (miniboss-følelse). Manetene listes først, så haiene havner
	  # i pilspissen som peker på spilleren. Rolige kuler: dykkene er historien.
		"banner": "BØLGE 5\nHAIENE",
		"enemies": [["grunt", 16], ["elite", 8]],
		"formations": ["arrow"],
		"entries": ["swoop"],
		"movements": ["rock"],
		"dives": true,
		"dive_interval": 4.5,
		"max_divers": 1,
		"max_bullets": 3,
	},
	{ # Bølge 6 — Kuleregn. Pustepause med vri: flest kuler i spillet, men ingenting
	  # sikter eller dykker. Gir bonusliv.
		"banner": "BØLGE 6\nKULEREGN",
		"enemies": [["soldat", 13], ["grunt", 19]],
		"formations": ["checkerboard"],
		"entries": ["rain"],
		"movements": ["pulse"],
		"fire_rate_mult": 2.0,
		"bullet_speed_mult": 1.3,
		"max_bullets": 6,
		"bonus_life": true,
	},
	{ # Bølge 7 — Slangen. Maks antall (Pi-testen). Skytterne bakerst nås gjennom
	  # banene mellom søylene.
		"banner": "BØLGE 7\nSLANGEN",
		"enemies": [["skytter", 8], ["soldat", 16], ["grunt", 16]],
		"formations": ["columns"],
		"entries": ["snake"],
		"movements": ["figure8"],
		"fire_rate_mult": 1.5,
		"speed_mult": 1.1,
		"bullet_speed_mult": 1.15,
		"max_bullets": 5,
	},
	{ # Bølge 8 — Dødshjulet. Få, men alle farlige: alle sikter, og ringen går i karusell.
		"banner": "BØLGE 8\nDØDSHJULET",
		"enemies": [["elite", 7], ["skytter", 17]],
		"formations": ["ring"],
		"entries": ["spiral", "loop"],
		"movements": ["orbit"],
		"dives": true,
		"dive_interval": 3.2,
		"max_divers": 1,
		"fire_rate_mult": 1.2,
		"bullet_speed_mult": 1.15,
		"max_bullets": 4,
	},
	{ # Bølge 9 — Alt vi har. Alle fire typer, størst variasjon fra run til run. Gir bonusliv.
		"banner": "BØLGE 9\nALT VI HAR",
		"enemies": [["elite", 4], ["skytter", 4], ["soldat", 16], ["grunt", 16]],
		"formations": ["x_shape"],
		"entries": ["crossover", "swoop"],
		"movements": ["rock", "split"],
		"dives": true,
		"dive_interval": 6.0,
		"max_divers": 1,
		"fire_rate_mult": 1.1,
		"speed_mult": 1.1,
		"bullet_speed_mult": 1.1,
		"max_bullets": 4,
		"bonus_life": true,
	},
	{ # Bølge 10 — Siste bølge. Tilbake til start, men 5 × 8: raskest marsj, raskest kuler,
	  # og skytterne dykker også. (Byttes ut med bossen når den finnes.)
		"banner": "SISTE BØLGE",
		"enemies": [["elite", 8], ["skytter", 4], ["soldat", 12], ["grunt", 16]],
		"formations": ["rows"],
		"entries": ["snake", "rain"],
		"movements": ["classic"],
		"descent_time": 110.0,
		"dives": true,
		"dive_types": ["elite", "skytter"],
		"dive_interval": 4.0,
		"max_divers": 1,
		"fire_rate_mult": 2.0,
		"speed_mult": 1.6,
		"bullet_speed_mult": 1.35,
		"max_bullets": 6,
	},
]


static func count() -> int:
	return WAVES.size()


# Bølge n (1-basert) med standardverdier fylt inn.
static func get_wave(n: int) -> Dictionary:
	return with_defaults(WAVES[clamp(n - 1, 0, WAVES.size() - 1)], n)


# Fyller inn DEFAULTS i en rad. Brukes også av tester som lager egne rader.
static func with_defaults(row: Dictionary, n: int) -> Dictionary:
	var data := DEFAULTS.duplicate()
	for key in row:
		data[key] = row[key]
	if not data.has("banner"):
		data["banner"] = "BØLGE %d" % n
	return data


# Leser bølgerader fra en JSON-fil med samme felt som WAVES. Testene bruker
# dette (AILIEN_WAVES_JSON) til å prøve ut bølger uten å endre denne fila.
static func rows_from_json(path: String) -> Array:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		push_error("Kan ikke åpne " + path)
		return []
	var parsed := JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_ARRAY:
		push_error("Ugyldig JSON i %s (linje %d): %s" % [path, parsed.error_line, parsed.error_string])
		return []
	return parsed.result


static func enemy_count(data: Dictionary) -> int:
	var n := 0
	for pair in data["enemies"]:
		n += int(pair[1])
	return n
