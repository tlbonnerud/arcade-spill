# Ailien Invaders — Roguelike-design

Dette er spilldesignet: hva spillet skal være og hvordan det skal føles.
Hvordan det bygges står i [ARCHITECTURE.md](ARCHITECTURE.md), og rekkefølgen
i [ROADMAP.md](ROADMAP.md).

## Kjernen

Et **run** er 10 bølger. Etter hver bølge velger du **1 av 3 oppgraderinger**.
Bølge 10 er en **boss**. Dør du, starter du på nytt fra bølge 1 uten
oppgraderinger (permadeath). Målet er å fullføre runnet med høyest mulig poeng.

Status: de 10 bølgene og oppgraderingene finnes, bossen gjenstår.

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

Alle tall som oppgraderinger kan påvirke samles i én statblokk
(`player/player_stats.gd`). Basisverdiene er oppførselen uten oppgraderinger.

| Stat | Basis | Påvirkes av |
|---|---|---|
| `move_speed` | 220 px/s | Rakettstøvler |
| `max_bullets` | 1 skudd i lufta | Hurtigskudd |
| `bullet_speed` | 420 px/s | (ingen ennå) |
| `bullet_size` | 1,0 | Store kuler |
| `shots` | 1 kule per skudd | Spredningsskudd |
| `pierce` | 0 | Gjennomtrenging |
| `damage` | 1 | Skarpt skyts |
| `homing` | 0 rad/s | Målsøking |
| `explosion` | 0 px | Eksplosjon |
| `start_lives` / `max_lives` | 3 / 5 | Mer liv |
| `heal_per_wave` | 0 | Helbredelse |
| `shield` | 0 | Skjolddrikk |
| `thorns` | 0 | Pigger |
| `ship_scale` | 1,0 | Mindre skip |

## Oppgraderingskatalog (slik den ligger i `upgrades/upgrades.gd`)

Sjeldenhet: **V** = vanlig (vekt 10), **S** = sjelden (vekt 4), **E** = episk (vekt 1).
Ikonene er 24×20-sprites i `sprites/`.

| Id | Navn | Effekt | Sjeldenhet | Maks | Ikon |
|---|---|---|---|---|---|
| `multishot` | SPREDNINGSSKUDD | +1 kule per skudd, i vifte (9° mellom) | S | 3 | Multishot |
| `damage` | SKARPT SKYTS | +1 skade per kule | S | 3 | atck_up |
| `attack_speed` | HURTIGSKUDD | +1 skudd (vifte) i lufta samtidig | V | 3 | Attck_speed_up |
| `piercing` | GJENNOMTRENGING | kula går gjennom +1 fiende | S | 2 | Piercing |
| `homing` | MÅLSØKING | kulene svinger mot nærmeste fiende foran (2,2 så 4,0 rad/s) | S | 2 | Homing |
| `explosion` | EKSPLOSJON | drap skader fiender innen 46 px (nivå 2: 72 px) med 1. Smitter ikke. | S | 2 | Explotion |
| `big_bullets` | STORE KULER | kulene 50 % større (treffboks og tegning) | V | 2 | Big_bullet |
| `hp_up` | MER LIV | +1 liv nå og +1 maks liv | V | 3 | HP_up |
| `healing` | HELBREDELSE | +1 liv nå og etter hver bølge | S | 1 | Healing |
| `potion` | SKJOLDDRIKK | tåler ett treff per bølge, lades ved bølgestart | S | 2 | Potion |
| `thorns` | PIGGER | treff på deg: fiender innen 150 px tar 2 skade, fiendekulene forsvinner | E | 1 | Thorns |
| `size_down` | MINDRE SKIP | skip og treffboks 25 % mindre | V | 2 | Size_down |
| `move_speed` | RAKETTSTØVLER | +30 % fart | V | 2 | Move_speed_up |

Regler for trekking:

- Aldri to like i samme tilbud.
- Oppgraderinger som er maks-stablet trekkes ikke.
- Første tilbud (etter bølge 1) inneholder alltid minst én S eller bedre, så
  runnet "kjennes" fra start.
- Skjermen velger selv det markerte kortet etter 15 s.

## Fiender

Spritene som finnes i dag tildeles roller. Boss-sprite må tegnes.

| Type | Sprite | Kule | HP | Poeng | Oppførsel |
|---|---|---|---|---|---|
| Grunt | Enemy_4 (manet) | Projectile_5, lilla kule | 1 | 10 | Skyter sjelden, rett ned. |
| Soldat | Enemy_1 (kyklop) | Projectile_3, grønn | 1 | 20 | Skyter oftere. |
| Skytter | Enemy_2 (vinget) | Projectile_4, blå | 2 | 30 | Sikter mot spilleren. |
| Elite | Enemy_3 (hai) | Projectile_2, rød | 3 | 40 | Dykker ut av formasjonen mot spilleren, flyr tilbake. |
| Boss | Boss.png (160×90, 6 frames) | ikke bestemt | 60 | 1000 | Tre faser, se under. |

Spilleren skyter med Projectile_1 (gul/oransje bolt). Kuletypene er definert
i `core/bullets.gd` (`KINDS`), og hvilken fiende som bruker hvilken står i
`enemies/enemy_types.gd` (`TYPES`).

Skalering per bølge: hver bølge har `hp_mult` (hp × dette, avrundet til
nærmeste, minst 1), `fire_rate_mult`, `speed_mult` og `bullet_speed_mult`.
Tallene bor i `waves/waves.gd`, ikke spredt rundt i koden.

## Bølgetabell (v2, slik den ligger i `waves/waves.gd`)

Bossen finnes ikke ennå, så bølge 10 er en finale med vanlige fiender. Tabellen er laget av et designpanel (tempo, spektakkel,
rettferdighet) og stilt inn mot bot-simulatoren i `tests/sim_waves.tscn`.

| Bølge | Banner | Fiender | Formasjon | Innflyging (pool) | Bevegelse (pool) | Nytt denne bølgen |
|---|---|---|---|---|---|---|
| 1 | BØLGE 1 | 16 grunt | rader | ovenfra | klassisk | Opplæring: flytt, skyt, én kule om gangen. |
| 2 | SOLDATER | 12 soldat + 15 grunt | V-form (tre hele vinkler) | fra sidene | sinus | Soldater skyter ofte, og formasjonen svaier i stedet for å marsjere. |
| 3 | DE SIKTER! | 9 skytter + 15 grunt | diamant | løkke, spiral | puls | Første siktede skudd og første show-innflyging. |
| 4 | PORTEN | 8 skytter + 8 soldat + 16 grunt | to grupper | kryss, fra sidene | splitt | Første store bølge: to dører som åpner og lukker seg. |
| 5 | HAIENE | 16 grunt + 8 elite | pil mot spilleren | stup | vugge | Miniboss-følelse: haiene sitter i pilspissen og dykker. Rolige kuler, dykkene er hele historien. |
| 6 | KULEREGN | 13 soldat + 19 grunt | sjakkbrett | regn | puls | Pustepause med vri: flest kuler i hele spillet, men ingenting sikter eller dykker. |
| 7 | SLANGEN | 8 skytter + 16 soldat + 16 grunt | søyler | slange | åttetall | Maks antall (40, Pi-testen). Skyt skytterne bakerst gjennom banene mellom søylene. |
| 8 | DØDSHJULET | 7 elite + 17 skytter | ring | spiral, løkke | bane (karusell) | Få, men alle farlige: alle sikter, ingen kanonføde, målene går i ring. |
| 9 | ALT VI HAR | 4 elite + 4 skytter + 16 soldat + 16 grunt | X | kryss, stup | vugge, splitt | Alle fire typer samtidig, størst variasjon fra run til run. |
| 10 | SISTE BØLGE | 8 elite + 4 skytter + 12 soldat + 16 grunt | rader | slange, regn | klassisk | Finalen: tilbake til start, men 5 × 8, raskest marsj, raskest kuler, og nå dykker skytterne også. |

Hver formasjon (9), innflyging (8) og bevegelse (7) brukes minst én gang.

### Vanskelighetskurve

**Med oppgraderinger (oktober 2026):** bonuslivene er tatt ut, og `hp_mult`
er 1,5 i bølge 4–5, 2,0 i 6–7, 2,5 i 8–9 og 3,0 i bølge 10 som motvekt til
vifte, skade og hurtigskudd. Målt på hele spillet, 40 runs:

| Bot | Oppgraderinger | Seier | Snitt-tid for seier |
|---|---|---|---|
| good | smart valg | 39/40 | 3,5 min |
| average | smart valg | 23/40 | 3,9 min |
| average | tilfeldige valg | 19/40 | 5,4 min |
| good | ingen (før HP-skalering) | 13/40 | 6,5 min |

Før HP-skaleringen vant "average" 36 av 40 run med tilfeldige valg på
under 4 minutter, så oppgraderingene bærer spillet. Bevisst ikke
finjustert videre: spillet skal først prøves av folk på Pi-en. Tallene
under er fra før oppgraderingene og gjelder hver bølge for seg, uten dem.

Målt med boten "good" (øvet arkadespiller), hver bølge for seg med tre liv,
96 forsøk per bølge:

| Bølge | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 |
|---|---|---|---|---|---|---|---|---|---|---|
| Tapte liv | 0,08 | 0,12 | 0,15 | 0,24 | 0,57 | 0,39 | 0,64 | 0,70 | 0,81 | 1,18 |
| Sekunder | 17 | 29 | 20 | 35 | 25 | 48 | 60 | 30 | 41 | 73 |

Jevnt stigende med en bevisst dupp i bølge 6. Summen er ca. 4,9 liv, mot 3 liv
+ 3 bonusliv. På hele spillet vinner den gode boten 38 % av forsøkene på
6,5 minutter, og den uøvede ("average") når typisk bølge 6 og vinner nesten
aldri. Formasjonen når aldri bunnen for noen av dem: `descent_time` er
tidspress, ikke det som tar livet av deg.

Ta tallene som en rettesnor, ikke en fasit. Boten jukser ett sted (den leser
dykkets mål rett fra spillet, der et menneske må lese banen), så dykk er
trolig litt farligere for folk enn tallene sier. Ekte spillere på Pi-en er
den endelige testen.

Det designpanelet lærte om knappene (verdt å huske når oppgraderingene kommer):

- **`speed_mult` (tempo i mønsteret) er den sterkeste knappen for øvede
  spillere.** Med én kule i lufta betyr et mål i sidebevegelse bom, og hver
  bom koster ca. 0,8 s.
- **`fire_rate_mult`, `bullet_speed_mult` og `max_bullets` betyr lite for
  øvede, men mye for uøvede.** Derfor er de lave i bølge 1–3 og kan være
  høye sent.
- **Valg av mønster betyr like mye som tallene.** `pulse` er klart
  vanskeligst sammen med siktede skudd, `classic` og `split` lettest, og
  `orbit` på en ring er raskt fordi karusellen bringer fiendene ned til
  kanonen. Poolene er derfor holdt homogene i vanskelighet.
- **HP er dyrest** så lenge spilleren har én kule, og derfor er `hp_mult`
  den riktige motvekten når oppgraderingene gir flere kuler og mer skade.

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
