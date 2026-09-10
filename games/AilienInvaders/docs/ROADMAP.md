# Ailien Invaders — Roadmap

Rekkefølgen er valgt slik at spillet **kan spilles etter hvert steg**. Ingen
steg krever at neste er ferdig. Hvert steg har et "ferdig når"-kriterium,
og skal testes på Pi-en før neste starter (bygg med `./build.sh`).

## Steg 0 — Splitte main.gd ✅

- [x] `player/player.gd`, `enemies/swarm.gd`, `core/bullets.gd`
- [x] `main.gd` er bare orkestrering og HUD
- [x] Oppførsel identisk med før (automatisk spilltest passerer)

## Steg 1 — Tilstandsmaskin og bølgebanner

Ingen nye spillregler, bare struktur som resten bygger på.

- [ ] `State`-enum i main med `_set_state()`
- [ ] INTRO-skjerm ("TRYKK START")
- [ ] WAVE_INTRO: banner "BØLGE N" i 1,5 s, fiendene skyter ikke
- [ ] WAVE_CLEAR: 1 s pause, fiendekuler fjernes
- [ ] `core/run_state.gd` tar over poeng/bølge/liv fra main
- [ ] Bølge 10 → VICTORY-skjerm (foreløpig uten boss)

**Ferdig når:** du kan spille gjennom 10 bølger med dagens sverm, se banner
mellom hver, og få VICTORY etter den tiende.

## Steg 2 — Bølgedata og innflyging

- [ ] `waves/waves.gd` med de 10 bølgene fra DESIGN.md
- [ ] `enemies/formations.gd`: rows, grid, v_shape, ring, checkerboard
- [ ] `enemies/entry_patterns.gd`: from_top, from_sides, spiral (tween)
- [ ] `core/wave_manager.gd` erstatter `swarm.spawn()`: leser data, velger
      formasjon/innflyging, spawner
- [ ] Run-seed: `rand_seed`-basert RNG i run_state, vises på game over

**Ferdig når:** hver bølge ser forskjellig ut, fiendene flyr inn, og to runs
med samme seed er identiske.

## Steg 3 — Stats og oppgraderinger

Dette er steget som gjør det til et roguelike.

- [ ] `player/player_stats.gd` med base + `recompute()`
- [ ] Player og bullets leser fra stats i stedet for konstanter
- [ ] `upgrades/upgrades.gd`: katalog, vektet trekking, stabling
- [ ] `upgrades/upgrade_screen.gd`: tre kort, venstre/høyre + A, auto-valg 15 s
- [ ] UPGRADE-tilstand mellom bølgene
- [ ] Første pulje oppgraderinger: hurtigskudd, store kuler, turbokuler,
      rakettstøvler, grådighet, ekstra liv, spredningsskudd
- [ ] HUD viser ikoner/forkortelser for aktive oppgraderinger

**Ferdig når:** et run kjennes ulikt fra gang til gang, og spredningsskudd +
hurtigskudd føles kraftig.

## Steg 4 — Fiendetyper

- [ ] `enemies/enemy.gd`: én fiende med type, hp, poeng
- [ ] `enemies/enemy_types.gd`: grunt, soldat, skytter, elite
- [ ] Skytemønstre: rett ned, siktet
- [ ] `enemies/movement_patterns.gd`: classic, sine, dive (elite)
- [ ] HP-skalering per bølge, treff-blink på fiender med hp > 1
- [ ] Resten av oppgraderingene: gjennomtrenging, tungt skyts, skjold,
      reparasjon, tidsfelt

**Ferdig når:** bølge 5 (elite-bølgen) er merkbart annerledes og
gjennomtrenging har en grunn til å finnes.

## Steg 5 — Boss

- [ ] Boss-sprite (tegnes)
- [ ] `enemies/boss/boss.gd` + `boss.tscn` med tre faser
- [ ] BOSS_INTRO med "ADVARSEL"
- [ ] Fase 2 tilkaller grunts via wave_manager
- [ ] Fase 3 laser-sveip med forvarsel
- [ ] Boss-død-sekvens → VICTORY med livsbonus

**Ferdig når:** en god spiller vinner på første forsøk kanskje én av tre
ganger.

## Steg 6 — Polish

- [ ] Episke oppgraderinger: bombe (B), sidekanoner, laser
- [ ] WAVE_CLEAR-effekt (bakgrunn scroller fortere, skipet hopper)
- [ ] Lyd: skudd, treff, død, oppgradering, boss
- [ ] Attract-modus på INTRO (spiller seg selv etter 30 s)
- [ ] Highscore med initialer (venter på launcher-støtte)

## Steg 7 — Balansering på Pi

- [ ] Ytelse: bølge 7 og boss fase 2 holder 60 fps på Pi 3B+
- [ ] Spilletid 5–8 min for et fullt run
- [ ] Minst tre "builds" som kan vinne (skudd, forsvar, poeng)
- [ ] Juster tallene i `waves.gd` og `upgrades.gd`, ikke i koden

## Ikke bestemt ennå

Se "Åpne spørsmål" nederst i [DESIGN.md](DESIGN.md).
