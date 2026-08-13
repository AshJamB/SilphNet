# Gen 1 save file structure - confirmed against a real export

Verified against `gen1recomp-blue-slot1.sav` (32,768 bytes = 32KB, standard
Gen 1 SRAM size), attached by Ash on 2026-08-12. This is a **real, standard,
byte-accurate Gen 1 Game Boy save file** - not an engine-specific or
custom format. Every field decoded below cross-checks against
well-documented, 25+ year old Pokémon Red/Blue disassembly sources
(`pret/pokered` on GitHub) and produced sane, internally-consistent, real
values - not garbage - which is the strongest possible confirmation this
mapping is right.

This directly unblocks roadmap items #9 (Community Champion) and #15
(per-friend detail screen): **party, badges, money, Pokédex, and Hall of
Fame status are all genuinely readable from a save file.** The remaining
question is only *how the mod gets at its own save data at runtime*, not
whether the data exists or is decodable - see "What this means for
SilphNet" below.

## File layout (SRAM banks)

The file is 4 banks of `0x2000` (8192) bytes each, back to back:

| File offset range | Real address range | Bank | Contents |
|---|---|---|---|
| `0x0000-0x1FFF` | `A000-BFFF` | Bank 0 | Sprite decompression buffers, Hall of Fame data |
| `0x2000-0x3FFF` | `A000-BFFF` | Bank 1 | Player name, main save data, party data, current box |
| `0x4000-0x5FFF` | `A000-BFFF` | Bank 2 | PC Boxes 1-6 |
| `0x6000-0x7FFF` | `A000-BFFF` | Bank 3 | PC Boxes 7-12 |

Translate a real address `A` in bank `N` to a file offset:
`fileOffset = N * 0x2000 + (A - 0xA000)`

## Confirmed field offsets (Bank 1)

All confirmed by decoding this exact file and getting sane, real values.

| Field | Real address (Bank 1) | File offset | This save's value |
|---|---|---|---|
| Player name | `A598` (11 bytes) | `0x2598` | `ASH` |
| Main data start | `A5A3` | `0x25A3` | - |
| Party count | `AF2C` | `0x2F2C` | `6` |
| Party species list | `AF2D` (7 bytes, `0xFF`-terminated) | `0x2F2D` | Blastoise/Dratini/Pidgeot/Golem/Kadabra/Gyarados |
| Party Pokémon structs | `AF34` (44 bytes each × 6) | `0x2F34` | see below |
| Player money (3-byte BCD) | `A5A3 + 80 = A5F3` | `0x25F3` | `027833` (₽27,833) |
| Rival's name | `A5A3 + 83 = A5F6` | `0x25F6` | `GARY` |
| Badges (bitfield, 1 byte) | `A5A3 + 95 = A602` | `0x2602` | `01011111` = 6 badges |
| Trainer ID (2 bytes, big-endian) | `A5A3 + 98 = A605` | `0x2605` | `45799` |
| Hall of Fame data | `A598-B857` (Bank 0) | `0x0598-0x1857` | all zero - Champion not yet beaten on this save |

The money/rival/badges/trainer-ID offsets were derived from the real
`pret/pokered` WRAM layout (`wPlayerMoney`, `wRivalName`,
`wObtainedBadges`, `wPlayerID` in `ram/wram.asm`'s "Main Data" section),
NOT guessed - `sMainData` in `ram/sram.asm` is declared as an exact,
same-size mirror of the WRAM main-data block
(`sMainData:: ds wMainDataEnd - wMainDataStart`), so the byte offset of
any field *within* that block is identical between WRAM and the save
file; only the base address differs. Decoding "GARY" for the rival name
and a sane 3-digit-BCD money value from that derivation is strong
confirmation it's correct - those aren't values that come out looking
right by chance.

## Party Pokémon struct (44 bytes, repeats ×6 from `AF34`)

Confirmed against this file - species/level/HP were all sane, and this
matches the well-documented struct exactly:

```
+0x00  species (internal Gen 1 index, NOT dex number - see below)
+0x01  current HP (2 bytes, big-endian)
+0x03  level (duplicate/box-transfer field, not authoritative - see +0x21)
+0x04  status (poison/paralysis/etc.)
+0x05  type 1
+0x06  type 2
+0x07  catch rate / held item
+0x08  move 1
+0x09  move 2
+0x0A  move 3
+0x0B  move 4
+0x0C  trainer ID (2 bytes)
+0x0E  experience (3 bytes)
+0x11  HP EV (2 bytes)
+0x13  Attack EV (2 bytes)
+0x15  Defense EV (2 bytes)
+0x17  Speed EV (2 bytes)
+0x19  Special EV (2 bytes)
+0x1B  Attack/Defense IV
+0x1C  Speed/Special IV
+0x1D  PP move 1
+0x1E  PP move 2
+0x1F  PP move 3
+0x20  PP move 4
+0x21  level (ACTUAL, authoritative)
+0x22  max HP (2 bytes)
+0x24  Attack (2 bytes)
+0x26  Defense (2 bytes)
+0x28  Speed (2 bytes)
+0x2A  Special (2 bytes)  [struct ends at +0x2C = 44 bytes]
```

Species byte is Gen 1's own **internal index number**, not the National
Dex number everyone knows today - Gen 1 famously reordered species
internally. A lookup table (`pokemon_constants.asm` from `pret/pokered`)
is required to turn the raw byte into a real species name; this was
already built and verified against this file (all 6 party members
decoded to real, sensible species names - Blastoise, Dratini, Pidgeot,
Golem, Kadabra, Gyarados - not garbage).

OT names and nicknames for the party follow immediately after the 6
structs (11 bytes each, ×6, then ×6 again) - not yet individually
decoded here but same text encoding as the player/rival name fields.

## Text encoding

Gen 1's own charset, not ASCII:
- `0x80-0x99` = `A-Z`
- `0xA0-0xB9` = `a-z`
- `0xF6-0xFF` = `0-9`
- `0x50` = string terminator ("END"), also used as trailing padding

Confirmed by decoding "ASH" (player name) and "GARY" (rival name)
correctly from this exact file.

## What this means for SilphNet

The byte-level analysis above proves the underlying DATA is real and
well-understood; it turns out to be the wrong layer to build against,
though. The engine doesn't store saves as raw SRAM at all - per
`Guide-Save-Editor`, a Gen1Recomp save is a plain Lua data file
(`save.lua`), read by a data-only parser that never executes code. That
means the actual save-table field names are the right thing to target,
not raw byte offsets - and those field names are now confirmed directly
from the engine's real source (`src/core/SaveData.lua` on GitHub, fetched
and grepped - not guessed):

| What | Real field | Notes |
|---|---|---|
| Player name | `save.player.name` | Already known from the Oak-speech hook table; now doubly confirmed |
| Player money | `save.money` | NOT nested under `save.player` (a real guess-by-analogy mistake caught before shipping v1.5.0's friend detail screen) - confirmed directly from `SaveData.newGame()`'s own table construction: `money` is a plain top-level key, sibling to `player`/`party`/`flags`/`pokedex`, seeded from `boot.startMoney` (vanilla default 3000) |
| Party | `save.party` | A plain Lua array/list, `ipairs`-able - `SaveData.validate` calls `scrubMonList(save.party, ...)` directly on it |
| A party mon | `mon.species`, `mon.level`, `mon.moves` (array of `{id, pp}` or bare move ids), `mon.dvs`, `mon.statExp`, `mon.stats` | From `scrubKnownMon` - `species` is already a resolved string id, not a raw index byte; no lookup table needed unlike the raw .sav bytes |
| Pokédex owned | `save.pokedex.owned` | A set/map keyed by species id - `SaveData.slotSummary` counts entries via `pairs()` for the dex count shown on the title screen |
| Pokédex seen | `save.pokedex.seen` | Same shape as `owned` |
| Play time | `save.playTime` | **Two possible shapes**: a plain seconds count (this engine, Gen 1), OR a `{ hours, minutes, seconds, frames }` table (their Gen 2/Gold saves) - the engine's own code checks `type(pt) == "table"` before deciding how to read it, and SilphNet should do the same rather than assume one shape |
| Hall of Fame / Champion-beaten | `save.hallOfFame` | A list of entries, each entry itself a list of mon objects (`entry[i].species`, etc.) - a NON-EMPTY `save.hallOfFame` is the real "has beaten the Champion at least once" signal, matching what was seen in the raw .sav (empty table = never beaten, exactly as this save showed) |
| Badges | NOT a plain field - derived via `Badges.count(nil, save)` in `src/inventory/Badges.lua` | This internal module is not on the mod-safe `require` allowlist (`Reference-Mod-Object` only permits `src.mods.Semver`, `src.audio.ChipAsm`, `src.pokemon.Stats`), so a mod can't call it directly. Likely workaround: badges resolve to real `items` records via the `constants.badges` registry (`Concepts-Data-Model` - each badge entry's `id` must resolve to an `items` record), so a mod can probably derive its own badge count by checking `save.inventory` for each badge item id - not yet tested against a real save, since this save's raw badge byte was read directly rather than via inventory |
| Story/quest flags | `save.flags` | Confirmed working, real code in Tutorial 08: `game.save.flags.TUT8_HINTED = true`, read the same way |

Confirmed access pattern for a mod (from Tutorial 08's real, working
`onStep` example): `game.save` is a live, directly-readable-and-writable
Lua table available at runtime, not just at `save.loading`/`save.loaded`
event time - `game.save.flags.X` works directly inside any hook/event
handler once `game.ready` has fired. The same should hold for
`game.save.player`, `game.save.party`, `game.save.pokedex`, and
`game.save.hallOfFame` - reading them should need nothing more than
`game.save.party` at any point after `game.ready`, no raw-byte parsing,
no `save.loading` event needed at all for a simple read.

## Remaining open question

Badge count specifically still needs one more confirmation (checking
`save.inventory` against `constants.badges` on a real save/device) before
it can be trusted the same way party/Pokédex/Hall-of-Fame are now. Play
time's two-shape handling should be copied defensively regardless of
which engine build is running, per the source comment above ("the
launcher calls slotSummary on EVERY version's slot, so this has to read
both shapes or the whole launcher crashes").

This is now enough to start building the stats-snapshot mechanism for
roadmap items #9 and #15 - reading `game.save.party`, `game.save.pokedex`,
`game.save.playTime`, and `game.save.hallOfFame` directly, with badges
derived from `save.inventory` + `constants.badges` rather than assumed.

## Addendum - game version detection (`save.version`)

A separate, previously-unresolved `<< VERIFY >>` in `main.lua` - not
about save CONTENTS, but about which cartridge (Red/Blue/Yellow/Gold)
produced the save at all. Confirmed the same way as everything else in
this document: by reading `SaveData.lua`'s own `SaveData.newGame(boot)`
table construction directly, rather than guessing.

`save.version` is a plain top-level string key, sibling to `player`/
`party`/`flags`/etc: `version = boot.version or "red"`. Confirmed values
(from `GameVersion.lua`'s `GameVersion.VERSIONS` table keys) are exactly
`"red"`, `"blue"`, `"yellow"`, `"gold"` - lowercase, four values not
three (Gold is Gen 2, currently beta in the launcher). Guaranteed non-nil
on every real save by an explicit core migration
(`SaveData.addCoreMigration(2, ...)`) that backfills `"red"` onto any
save written before Blue support existed - so `game.save.version` is
always safely readable once a save exists, no defensive nil-check dance
needed beyond a basic type check.

SilphNet reads this at `game.ready` (`resolveGameVersion()` in
`main.lua`), uppercases it to match the project's existing
RED/BLUE/YELLOW/UNKNOWN convention, and maps `"gold"` to `UNKNOWN` -
this mod is Gen 1 only (friend markers, presence, and every stats field
read so far all assume Gen 1's save shape), so a Gen 2 save correctly
reporting in as GOLD would be true but not actually useful anywhere else
in this mod yet. Server endpoints accept GOLD as a stored value anyway
(forward-compatible), even though the client doesn't send it today.
