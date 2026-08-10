# SilphNet

An async multiplayer presence layer for [Pokémon Gen 1 Recomp](https://github.com/bryanthaboi/gen1recomp) —
built so it works **on Android**, not just desktop, and needs no server of
your own left running.

**Status: v1.1.0 — async presence + friends, added in-game.** Log in with a
name and password to get a unique 5-digit Trainer ID, then add friends
entirely in-game by entering their Trainer ID on a D-pad digit spinner — no
typing, no web page. The game periodically reports where you were last seen;
friends show up as static "last known position" markers on the map, plus a
friends list showing where they were, how long ago, and whether they're
likely still online. There's no live/real-time movement — see "Why this
isn't real-time" below for why that trade-off was made deliberately.

## Why this works on Android (when Gen1Online doesn't)

Gen1Recomp runs on LÖVE 11, whose Android build has **no TLS/SSL**. The
existing Gen1Online mod talks to its server over `https://`, so on Android the
request dies before it leaves the app — that's the "CANNOT CONNECT" you hit.

SilphNet instead uses **plain `http://`**. LuaSocket's `socket.http` module
opens a raw socket directly rather than going through Android's Java HTTP
stack (`HttpURLConnection`/`okhttp`) — which is specifically what Android's
cleartext-traffic block targets — so plain HTTP gets through even though
HTTPS can't. Confirmed on-device against a real endpoint before any of this
was built on top of it (see `experiments/http_test/`).

## Why this isn't real-time

An earlier version of this mod had a live, real-time overworld: a background
TCP relay so you'd see friends walking around in real time, the same way
Gen1Online works when it works. That needed a persistent server process
running *somewhere* at all times — either a home PC left on 24/7, or a paid
VPS — which didn't fit the goal of running entirely on ordinary PHP+MySQL
web hosting. It also fought a persistent movement judder that traced back to
the game engine's own `handle:scriptMove` having a real per-call cost, never
fully resolved cleanly across several rounds of fixes.

SilphNet now does the opposite trade-off on purpose: no live movement, no
server process, nothing running unless you're actively playing. Friends
appear as a **static snapshot** of where they were a little while ago, not a
live avatar — closer to "last seen" on a messaging app than to seeing them
walk in real time. The old real-time code is kept in `archive/tcp_relay_retired/`
in case it's ever worth revisiting.

## Layout

```
mod/silphnet/           the LÖVE mod (install this into the game's mods/ folder)
  main.lua               client: HTTP login, presence ping/poll, friend markers
  manifest.json          declares the "network" permission
  mod.card               manager detail card
dist/silphnet.zip        the mod, zipped and ready to install
server/
  web/                   the PHP + MySQL API (all you need to host - no VPS, no persistent process)
    schema.sql            run once in phpMyAdmin to create the tables
    db.php                DB connection - edit DB_PASS here, never commit it
    register.php          create an account (name + password -> account_id + token)
    login.php             log in with name + password -> account_id + token
    login_token.php        re-authenticate with a cached token (no retyping)
    ping.php               report your last-known position (requires a token)
    friends.php            fetch your friends' last-known positions (requires a token)
    add_friend.php          send a friend request by name
    accept_friend.php       accept an incoming friend request
archive/tcp_relay_retired/  the old real-time TCP relay - retired, kept for reference
experiments/http_test/      the throwaway diagnostic that confirmed plain HTTP works on Android
ACCOUNTS.md               the account model (now web/MySQL-backed)
SECURITY.md               what plain-HTTP + password hashing means for safety
```

## Quick start

### 1. Set up the database (once)

You need a MySQL database (via cPanel/phpMyAdmin or similar) and somewhere
to host five small PHP files — most ordinary shared web hosting works,
nothing beyond PHP + MySQL is required.

1. In phpMyAdmin, run `server/web/schema.sql` against your database to
   create the `accounts`, `sessions`, `presence`, and `friends` tables.
2. Upload everything in `server/web/` to your site (e.g. `yoursite.com/api/`).
3. Edit `db.php` **on the server** to set `DB_USER`/`DB_PASS` to your real
   database credentials — never commit real credentials to git.
4. In `mod/silphnet/main.lua`, set `API_BASE` at the top to your site's
   `/api` URL, then rebuild `dist/silphnet.zip`.

### 2. Install the mod

- **Desktop:** copy `mod/silphnet/` into the game's `mods/` folder, or install
  `dist/silphnet.zip` from the in-game Mod Manager.
- **Android:** get `dist/silphnet.zip` onto the phone (cloud drive, USB,
  whatever's easy) and install it from the in-game Mod Manager. Because this
  repo is private, the manager's "install from GitHub" won't reach it — use
  the zip.

Enable **SilphNet** in the Mod Manager. It will ask to allow the `network`
permission.

### 3. Log in

In the Mod Manager → **SilphNet** options, **MY NAME** and **PASSWORD** open
the classic Game Boy letter-grid when you press **A** on them. Gen 1's naming
screen has no digits by default, so this mod adds a **0–9 row** to that grid —
but only when one of these two fields is open; every other naming screen in
the game (Pokémon nicknames, your trainer name, etc.) stays exactly vanilla.

The first time you log in with a new name, an account is created
automatically — there's no separate signup step. After that, the same name +
password logs into the same account from any device. A session token is
cached locally so you don't have to retype your password every launch;
changing MY NAME or PASSWORD in the options forces a fresh login.

Your password is hashed (bcrypt) before it's ever stored — nobody, including
the account owner running the database, can look up the original password
from it. See `SECURITY.md`.

On first login, you're also assigned a unique **Trainer ID** — a random
5-digit number (00000–65535, the same range the mainline games use) shown on
the status screen. Share it with a friend (in person, over chat — however
you'd like) so they can add you.

### 4. Add friends and check the status screen

Open **START** — the menu shows `SILPHNET <name>` once logged in, or a
status message otherwise (`SILPHNET SET NAME/PASS`, `SILPHNET LOGIN FAIL`,
`SILPHNET ...` while logging in). Select that row for the status screen:

- **A** — retry login
- **START** — open the friends list (name, online/offline, last-known map +
  tile, how long ago, game version)
- **RIGHT** — open Add Friend (enter a Trainer ID with a digit spinner: **UP/DOWN**
  changes the selected digit, **LEFT/RIGHT** moves the cursor, **A** sends the request)
- **LEFT** — open pending friend requests (shown when REQUESTS > 0; page
  through with **LEFT/RIGHT**, **A** to accept)
- **SELECT** — reset (clears the cached login on this device only)
- **B** — back

No typing and no web page needed — adding a friend is entirely a Trainer ID
number entry, in-game. Once accepted, they'll show up in the friends list
and, if you're standing on their last-known map, as a static marker on the
ground.

### 5. Play

Every ~30 seconds while you're in the overworld, the mod reports your
current map/tile to the server and fetches your friends' last-known
positions back. If a friend's last-known map matches the one you're
standing on, a static, non-animated marker appears at their last-known
tile — it never moves on its own; if they move, the marker just relocates
once on the next poll, not tweened or animated.

## Troubleshooting

- **`SILPHNET OFF` / `SILPHNET LOGIN FAIL`** → check `API_BASE` in
  `main.lua` points at your real API URL, that the PHP files are uploaded
  and reachable over plain `http://` (not force-redirected to https), and
  that `db.php`'s credentials are correct on the server.
- **`SILPHNET SET NAME/PASS`** → set MY NAME and a PASSWORD in the mod
  options; that pair is your account.
- **Mod errors** → the Mod Manager lists them per-mod, prefixed `[silphnet]`.
- **Can't type numbers in a field / it caps at 7 characters** → the naming
  grid has no digits by default; reinstall the latest `dist/silphnet.zip`,
  which adds a digits row for MY NAME and PASSWORD specifically.
- **Force a clean re-login** → open the SilphNet status screen and press
  **SELECT**, then **A** to confirm. This clears the cached login token on
  this device only — your account and password are untouched, so logging in
  again with the same name+password picks up right where you left off.
- **Friend not showing on the map** → markers only appear when your current
  map matches their *last-known* map from their most recent ping — if
  they've since moved on (or haven't played recently), you'll only see them
  in the friends list, not on the ground.

## What's verified vs. what to check on-device

Verified via a lupa-based Lua test harness (stubbing `love`/`mod` and
exercising the real `main.lua`): login/register/cached-token flows, presence
firing on the correct schedule, friend marker spawn/despawn/relocate
lifecycle (including that a moved or departed friend causes exactly one
despawn and, if still on your map, one respawn — never a per-tick
animation), and friendly map-name rendering.

Marked `<< VERIFY >>` in `main.lua` (engine specifics not run against the
real game):

- the marker `sprite` id (`SPRITE_RED`) and exact `spawnNpc` object fields;
- `input.step` continuing to fire every fixed-step tick on your engine build
  — it's real and present in engine source but isn't in the curated wiki
  hook reference;
- how (or whether) the engine exposes which ROM version (Red/Blue/Yellow)
  is running — `gameVersion` defaults to `"UNKNOWN"` until this is wired up.

If something misbehaves, the `[silphnet]` manager errors will point right at it.

## Roadmap

1. ✅ Async presence — login, periodic position reporting, friends' last-known positions
2. ✅ Static friend markers on the map + friends list with online/offline + time-ago
3. ✅ Trainer ID + in-game "add friend" / "accept friend" screens (digit-entry, no typing)
4. ✅ GitHub auto-update — the launcher can pull new mod releases directly (see `.github/workflows/release-silphnet.yml`)
5. Multiple game-version tracking per account (Red/Blue/Yellow as separate "characters") wired up to the real ROM
6. Trainer card view (party, badges, League clears, game version)
7. Battle a friend's last-known party as an offline NPC
8. "Friend came online" notifications, custom greetings, unlockable battle music

See `ACCOUNTS.md` for the account design and `SECURITY.md` for the security model.

## Notes

Private repo, pushed manually via GitHub Desktop. The `SilphNet_Technical_
Specification` files are the original Gemini design study — see the project
notes for the review of what holds up and what doesn't. The original
real-time relay design lives in `archive/tcp_relay_retired/` if any of it is
ever useful again.
