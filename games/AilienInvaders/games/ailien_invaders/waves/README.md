# waves/

De 10 bølgene som **data**, ikke kode. Én rad per bølge i `waves.gd`:
fiendetyper og antall, pool av formasjoner, innflygings- og bevegelsesmønstre,
dykk, bonusliv og skalering (hp, skytefrekvens, tempo, kulefart,
nedstigningstid). Motoren som kjører dem er `core/wave_manager.gd`.

**Ny eller endret bølge:** endre raden i `WAVES`. Felt du utelater får
verdiene fra `DEFAULTS`. Kjør så testene fra `games/AilienInvaders/`:

```bash
AILIEN_CHECK=waves ../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/check_patterns.tscn
../../tools/Godot3.app/Contents/MacOS/Godot --no-window --path . res://tests/sim_waves.tscn
```

Den første sier fra hvis en kombinasjon i poolene går ut av skjermen eller
ikke kommer ned i tide. Den andre lar en bot spille bølgene og viser tapte
liv, tid og verste kombinasjon per bølge. Vil du prøve tall uten å endre
spillet, legg radene i en JSON-fil og sett `AILIEN_WAVES_JSON=/sti/fil.json`.

**Nytt mønster:** ny `static func` i `enemies/formations.gd`,
`entry_patterns.gd` eller `movement_patterns.gd`, legg navnet i `NAMES` og
`match`-blokken der, og bruk navnet i en pool her.

Format og begrunnelse: `docs/ARCHITECTURE.md`. Innholdet og det vi lærte om
hvilke knapper som virker: `docs/DESIGN.md`.
