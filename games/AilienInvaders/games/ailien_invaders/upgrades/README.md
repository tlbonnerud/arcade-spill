# upgrades/

Oppgraderingssystemet (roadmap steg 3, ferdig):

- `upgrades.gd` — katalogen: id, navn, beskrivelse, sjeldenhet, maks
  stabling, ikon og `apply`-funksjon som endrer statblokken. `offer()`
  trekker "3 ulike" vektet etter sjeldenhet; første tilbud i et run har
  alltid en sjelden.
- `upgrade_screen.gd` — "velg 1 av 3"-skjermen mellom bølgene. Bygges i
  kode. Venstre/høyre + A, autovalg av det markerte kortet etter 15 s.
  Tester og boten kaller `choose(index)` direkte.

Statblokken ligger i `player/player_stats.gd` (`base` → `taken` →
`current`, regnes alltid ut fra bunnen). Spilleren og kulelaget leser fra
den via `apply_stats()`, main deler den ut.

**Ny oppgradering:** ny oppføring i `CATALOG` + id i `IDS`, en
`_apply_*`-funksjon, og (om nødvendig) et felt i `PlayerStats.BASE` som
`player.gd`/`bullets.gd`/`main.gd` leser. Kjør så
`tests/check_upgrades.tscn`, og mål balansen med `tests/sim_waves.tscn`
(`AILIEN_SIM_PICK=smart|random|none`).

Katalogen og tallene står i `docs/DESIGN.md`.
