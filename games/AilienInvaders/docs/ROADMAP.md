# Ailien Invaders — Roadmap

Rekkefølgen er valgt slik at spillet **kan spilles etter hvert steg**. Ingen
steg krever at neste er ferdig. Hvert steg har et "ferdig når"-kriterium,
og skal testes på Pi-en før neste starter (bygg med `./build.sh`).

## Steg 0 — Splitte main.gd ✅

- [x] `player/player.gd`, `enemies/swarm.gd`, `core/bullets.gd`
- [x] `main.gd` er bare orkestrering og HUD
- [x] Oppførsel identisk med før (automatisk spilltest passerer)

## Steg 1 — Tilstandsmaskin og bølgebanner (delvis ✅)

Ingen nye spillregler, bare struktur som resten bygger på.

- [x] `State`-enum i main med `_set_state()`
- [ ] INTRO-skjerm ("TRYKK START")
- [x] WAVE_INTRO: banner mens fiendene flyr inn, fiendene skyter ikke
- [x] WAVE_CLEAR: 1,2 s pause, kuler fjernes, bakgrunnen scroller fortere
- [ ] `core/run_state.gd` tar over poeng/bølge/liv fra main
- [x] Siste bølge → VICTORY-skjerm (foreløpig uten boss)
- [x] WAVE_CLEAR viser "+1 LIV" når bølgen gir bonusliv

**Ferdig når:** du kan spille gjennom alle bølgene, se banner mellom hver,
og få VICTORY etter den siste.

## Steg 2 — Bølgedata og innflyging ✅

- [x] `waves/waves.gd` med alle 10 bølgene (bølge 10 er en finale til bossen finnes)
- [x] `enemies/formations.gd`: rows, v_shape, ring, checkerboard, two_groups,
      diamond, arrow, columns, x_shape
- [x] `enemies/entry_patterns.gd`: from_top, from_sides, spiral, swoop, rain,
      crossover, loop, snake
- [x] `enemies/movement_patterns.gd`: classic, sine, figure8, split, rock,
      orbit, pulse (posisjon per fiende, nedstigning styrt av `descent_time`)
- [x] `core/wave_manager.gd` erstatter `swarm.gd`: leser data, velger
      formasjon/innflyging/bevegelse, spawner, flere samtidige dykkere
- [x] `enemies/enemy_types.gd` med grunt/soldat/skytter/elite, hp-skalering,
      siktede skudd, treff-blink (tatt fra steg 4)
- [x] Run-seed: RNG i main, vises på game over
- [x] Bonusliv per bølge (`bonus_life`), inntil oppgraderingene finnes
- [x] Tester: `play_waves` (gjennomspilling), `check_patterns` (kontrakter),
      `sim_waves` (bot som måler vanskelighet), `screenshots` (oversiktsark)
- [ ] Prøve alle ti bølgene på Pi-en (bølge 7, 9 og 10 har 40 fiender)

**Ferdig når:** hver bølge ser forskjellig ut, fiendene flyr inn, og to runs
med samme seed er identiske.

## Steg 3 — Stats og oppgraderinger ✅

Dette er steget som gjør det til et roguelike.

- [x] `player/player_stats.gd` med base + `recompute()`
- [x] Player og bullets leser fra stats i stedet for konstanter
- [x] `upgrades/upgrades.gd`: katalog, vektet trekking, stabling
- [x] `upgrades/upgrade_screen.gd`: tre kort, venstre/høyre + A, auto-valg 15 s
- [x] UPGRADE-tilstand mellom bølgene
- [x] Alle 13 oppgraderinger med ikon: spredningsskudd, skarpt skyts,
      hurtigskudd, gjennomtrenging, målsøking, eksplosjon, store kuler,
      mer liv, helbredelse, skjolddrikk, pigger, mindre skip, rakettstøvler
- [x] HUD viser ikoner (med antall) for aktive oppgraderinger
- [x] `tests/check_upgrades.tscn`, og boten i `sim_waves` velger oppgraderinger
- [x] Bonuslivene er ute, `hp_mult` skalerer bølge 4–10 som motvekt
- [ ] Prøve på Pi-en: føles valgene sterke, er kortene lesbare på skjermen?

**Ferdig når:** et run kjennes ulikt fra gang til gang, og spredningsskudd +
hurtigskudd føles kraftig. (Boten sier ja; folk får avgjøre.)

## Steg 4 — Fiendetyper (delvis ✅, det meste kom i steg 2)

- [x] `enemies/enemy_types.gd`: grunt, soldat, skytter, elite
- [x] Skytemønstre: rett ned, siktet
- [x] Dykk (elite) i wave_manager
- [x] HP-skalering per bølge, treff-blink på fiender med hp > 1
- [x] Resten av oppgraderingene (kom i steg 3)

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

- [ ] Flere episke oppgraderinger: bombe (B), sidekanoner, laser (trenger ikoner)
- [ ] WAVE_CLEAR-effekt (bakgrunn scroller fortere, skipet hopper)
- [ ] Lyd: skudd, treff, død, oppgradering, boss
- [ ] Attract-modus på INTRO (spiller seg selv etter 30 s)
- [ ] Highscore med initialer (venter på launcher-støtte)

## Steg 7 — Balansering på Pi

- [ ] Ytelse: bølge 7 og boss fase 2 holder 60 fps på Pi 3B+
- [ ] Spilletid 5–8 min for et fullt run
- [ ] Minst tre "builds" som kan vinne (skudd, forsvar, poeng)
- [ ] Juster tallene i `waves.gd` og `upgrades.gd`, ikke i koden. Bruk
      `tests/sim_waves.tscn` til å måle før og etter (`AILIEN_SIM_PICK`
      sammenligner med og uten oppgraderinger). Første grovjustering er gjort
      (hp_mult), finjustering venter på ekte spillere.

## Ikke bestemt ennå

Se "Åpne spørsmål" nederst i [DESIGN.md](DESIGN.md).
