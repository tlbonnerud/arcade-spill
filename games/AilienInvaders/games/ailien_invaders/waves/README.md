# waves/

Bølgene som **data**, ikke kode. Én rad per bølge i `waves.gd`: fiendetyper
og antall, pool av formasjoner, innflygings- og bevegelsesmønstre, dykk og
skalering (hp, skytefrekvens, fart, kulefart). Motoren som kjører dem er
`core/wave_manager.gd`.

Slik legger du til en bølge: kopier en rad i `WAVES`, endre tallene. Felt du
utelater får verdiene fra `DEFAULTS`. Kjør `tests/play_waves.tscn` etterpå.

Slik legger du til et nytt mønster: ny `static func` i `enemies/formations.gd`,
`entry_patterns.gd` eller `movement_patterns.gd`, legg navnet i `match`-blokken
der, og bruk navnet i en pool her.

Format og begrunnelse: `docs/ARCHITECTURE.md`. Innholdet: `docs/DESIGN.md`.
