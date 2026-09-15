# Ailien Invaders — Roguelike-design

Dette er spilldesignet: hva spillet skal være og hvordan det skal føles.
Hvordan det bygges står i [ARCHITECTURE.md](ARCHITECTURE.md), og rekkefølgen
i [ROADMAP.md](ROADMAP.md).

## Kjernen

Et **run** er 10 bølger. Etter hver bølge velger du **1 av 3 oppgraderinger**.
Bølge 10 er en **boss**. Dør du, starter du på nytt fra bølge 1 uten
oppgraderinger (permadeath). Målet er å fullføre runnet med høyest mulig poeng.

Arkade-rammer som styrer alt:

- Et run skal ta **5–8 minutter**. Folk står i kø bak maskinen.
- Kun joystick, A, B, START og tilbake. Ingen mus, ingen tekstinntasting.
- Ingen meta-progresjon mellom runs. Highscore-lista er den eneste "arven".
- All tekst på norsk, store bokstaver, kort.

## Run-løkka (tilstandsmaskin)

```
INTRO ─► WAVE_INTRO ─► WAVE ─► WAVE_CLEAR ─► UPGRADE ─┐
           ▲                                           │
           └───────────────────────────────────────────┘  (bølge 1–9)

           ... etter bølge 9 ──► BOSS_INTRO ─► BOSS ─► VICTORY
           når som helst: liv = 0 ──► GAME_OVER ─► (START) ─► INTRO
```

| Tilstand | Hva skjer | Varighet |
|---|---|---|
| INTRO | Tittel, "TRYKK START". Attract-modus senere. | til START |
| WAVE_INTRO | Banner "BØLGE 3", fiender flyr inn til formasjonsplassene sine. Spilleren kan bevege seg og skyte; fiendene skyter ikke før alle er på plass. | ~1,5 s |
| WAVE | Selve spillet. | til alle er døde |
| WAVE_CLEAR | Kort "ryddet"-øyeblikk: fiendekuler forsvinner, spilleren blinker grønt, bakgrunnen scroller raskere (vi "flyr videre"). | ~1 s |
| UPGRADE | Tre kort side om side. Venstre/høyre velger, A bekrefter. Auto-velger midterste etter 15 s. | til valg |
| BOSS_INTRO | "ADVARSEL" blinker rødt, bossen senker seg ned fra toppen. | ~2,5 s |
| BOSS | Bosskamp i tre faser. | til bossen dør |
| VICTORY | "DU VANT" + poeng + bonus for gjenværende liv. Lagrer highscore. | til START |
| GAME_OVER | Som nå: årsak, poeng, rekord. | til START |

## Hva gjør det roguelike

- **Tilfeldige oppgraderingstilbud.** Tre kort trekkes fra katalogen, vektet
  etter sjeldenhet. Samme oppgradering kan tas flere ganger der det gir mening.
- **Variasjon i bølgene.** Hver bølge har en *pool* av formasjoner og
  bevegelsesmønstre, og én trekkes. To runs er aldri like.
- **Synergier.** Spredningsskudd + gjennomtrenging + større kuler blir noe helt
  annet enn hver for seg. Det er dette som gjør at folk vil spille "én til".
- **Permadeath.** Ingen fortsettelse. Alt eller ingenting.
- Nice-to-have: vis run-seed på game over-skjermen, så to spillere kan
  spille samme run og sammenligne.

## Spillerstats

Alle tall som oppgraderinger kan påvirke samles i én stat-blokk.
Basisverdiene er dagens oppførsel.

| Stat | Basis | Påvirkes av |
|---|---|---|
| `move_speed` | 220 px/s | Rakettstøvler |
| `max_bullets` | 1 kule i lufta | Dobbeltløp |
| `bullet_speed` | 420 px/s | Turbokuler |
| `bullet_size` | 1,0 | Store kuler |
| `shots` | 1 | Spredningsskudd (2, så 3) |
| `pierce` | 0 | Gjennomtrenging |
| `damage` | 1 | Tungt skyts |
| `lives` | 3 | Ekstra liv |
| `shield` | 0 | Skjold (tåler ett treff per bølge) |
| `score_mult` | 1,0 | Grådighet |
| `enemy_bullet_speed_mult` | 1,0 | Tidsfelt |
| `bombs` | 0 | Bombe (B-knappen) |

## Oppgraderingskatalog (v1)

Sjeldenhet: **V** = vanlig (vekt 10), **S** = sjelden (vekt 4), **E** = episk (vekt 1).

| Id | Navn | Effekt | Sjeldenhet | Stables? |
|---|---|---|---|---|
| `rapid_fire` | HURTIGSKUDD | +1 `max_bullets` | V | ja (maks 4) |
| `big_bullets` | STORE KULER | `bullet_size` ×1,5 | V | ja (maks 2) |
| `turbo` | TURBOKULER | `bullet_speed` +30 % | V | ja (maks 2) |
| `boots` | RAKETTSTØVLER | `move_speed` +25 % | V | ja (maks 2) |
| `greed` | GRÅDIGHET | `score_mult` +0,25 | V | ja |
| `slow_field` | TIDSFELT | fiendekuler 20 % tregere | V | ja (maks 2) |
| `spread` | SPREDNINGSSKUDD | `shots` +1 (vifte) | S | ja (maks 3) |
| `pierce` | GJENNOMTRENGING | kula går gjennom +1 fiende | S | ja (maks 2) |
| `heavy` | TUNGT SKYTS | `damage` +1 | S | ja |
| `extra_life` | EKSTRA LIV | +1 liv | S | ja |
| `shield` | SKJOLD | tåler ett treff, lades opp hver bølge | S | nei |
| `repair` | REPARASJON | +1 liv hver 3. bølge | S | nei |
| `bomb` | BOMBE | B: dreper alle fiendekuler + 1 hp på alle. 1 lading per bølge | E | nei |
| `side_guns` | SIDEKANONER | to ekstra kuler skrått ut til sidene | E | nei |
| `laser` | LASER | hold A: kontinuerlig stråle, lav skade, uendelig gjennomtrenging | E | nei |

Regler for trekking:

- Aldri to like i samme tilbud.
- Oppgraderinger som er maks-stablet eller allerede tatt (ikke stables) trekkes ikke.
- Første tilbud (etter bølge 1) inneholder alltid minst én S eller bedre, så
  runnet "kjennes" fra start.

## Fiender

Spritene som finnes i dag tildeles roller. Boss-sprite må tegnes.

| Type | Sprite | Kule | HP | Poeng | Oppførsel |
|---|---|---|---|---|---|
| Grunt | Enemy_3 (manet) | Projectile_5, lilla kule | 1 | 10 | Skyter sjelden, rett ned. |
| Soldat | Enemy_1 (kyklop) | Projectile_3, grønn | 1 | 20 | Skyter oftere. |
| Skytter | Enemy_2 (vinget) | Projectile_4, blå | 2 | 30 | Sikter mot spilleren. |
| Elite | Enemy_4 (hai) | Projectile_2, rød | 3 | 40 | Dykker ut av formasjonen mot spilleren, flyr tilbake. |
| Boss | Boss.png (160×90, 6 frames) | ikke bestemt | 60 | 1000 | Tre faser, se under. |

Spilleren skyter med Projectile_1 (gul/oransje bolt). Kuletypene er definert
i `core/bullets.gd` (`KINDS`), og hvilken fiende som bruker hvilken står i
`enemies/swarm.gd` (`ROW_BULLETS`).

Skalering per bølge: `hp × (1 + 0,15 × (bølge − 1))` rundet opp, og
skytefrekvens `× (1 + 0,1 × (bølge − 1))`. Tallene bor i `waves/waves.gd`,
ikke spredt rundt i koden.

## Bølgetabell (v1)

| Bølge | Fiender | Formasjon (pool) | Bevegelse (pool) | Nytt denne bølgen |
|---|---|---|---|---|
| 1 | 16 grunt | 2 rader | klassisk | Opplæring: som i dag, men færre. |
| 2 | 24 grunt/soldat | 3 rader, V-form | klassisk | Soldater skyter mer. |
| 3 | 24 + 8 skytter | 4 rader | klassisk, sinus | Siktede skudd. |
| 4 | 32 blandet | grid, sjakkbrett | sinus | Første "store" bølge. |
| 5 | 8 elite + 16 grunt | ring, V-form | klassisk + dykk | Dykkere. Elite-bølge, føles som miniboss. |
| 6 | 32 blandet | grid, to grupper | sinus, dykk | To grupper med hver sin retning. |
| 7 | 40 blandet | sjakkbrett, to grupper | alle | Maks antall. Ytelsestest på Pi. |
| 8 | 24 skytter/elite | ring | dykk, sinus | Færre, men alle er farlige. |
| 9 | 40 blandet | alle | alle | "Alt vi har". |
| 10 | Boss (+ grunts i fase 2) | — | boss-mønster | Bossen. |

## Fiendeanimasjoner (inn og ut)

Alt gjøres med `create_tween()` (SceneTreeTween, finnes i Godot 3.5+), ingen
AnimationPlayer nødvendig.

- **Inn (WAVE_INTRO):** hver fiende starter utenfor skjermen og tweenes til
  formasjonsplassen sin langs en bue. Fiendene starter 40 ms etter hverandre,
  så det ser ut som en strøm. Innflygingsmønstre (pool): fra toppen, fra
  sidene vekselvis, spiral. Fiender kan treffes underveis (belønner aggressive
  spillere), men skyter ikke før alle er på plass.
- **Dykk (i WAVE):** en elite forlater plassen sin, tweenes i en S-kurve ned
  mot spilleren og tilbake til plassen. Maks én dykker om gangen på Pi-en.
- **Ut (WAVE_CLEAR):** ingen fiender igjen, så "ut" er spillerens øyeblikk:
  bakgrunnen scroller fortere, skipet gjør et lite hopp fremover.
- **Boss inn:** "ADVARSEL" blinker tre ganger, bossen senker seg ned over 2 s
  med lett svai.
- **Boss død:** serie av små eksplosjoner (hvite rektangler, som kulene) over
  1,5 s, så VICTORY.

## Boss

HP 60 (skaleres ikke). Faser etter gjenværende HP:

| Fase | HP | Oppførsel |
|---|---|---|
| 1 | 100–66 % | Glir sideveis, skyter vifte på 3 kuler hvert 1,2 s. |
| 2 | 66–33 % | Tilkaller 8 grunts som flyr inn. Skyter siktede skudd. |
| 3 | 33–0 % | Dobbel fart, laser-sveip fra side til side hvert 4. s (varsles med tynn linje 0,5 s før). |

Bossen er sårbar hele tiden. Enkelt å forstå, vanskelig å overleve.

## Ytelse på Pi 3B+

Dagens tilnærming beholdes: ingen fysikk, ingen Area2D, manuell AABB-sjekk.

- Maks 40 fiender + 1 boss samtidig.
- Kuler tegnes fortsatt i ett lag (sprite-ark via `draw_texture_rect_region`). Pool på 64 kuler.
- Én tween per fiende under innflyging er greit (40 tweens i 1,5 s).
- Bølge 7 er ytelsestesten. Holder den ikke 60 fps, kutter vi til 32.

## Åpne spørsmål

- [ ] Boss-sprite må tegnes. Størrelse og antall frames?
- [ ] Skal B være bombe (kun med oppgradering) eller alltid "special"?
- [ ] Endless-modus etter bossen (bølge 11+ med økende skalering)?
- [ ] Lyd: prosjektet har ingen lyd ennå. Trengs minst skudd, treff, død, oppgradering.
- [ ] Skal poeng for oppgraderinger vises på highscore-lista ("build")?
