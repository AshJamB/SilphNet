# SilphNet

![SilphNet](assets/silphnet-banner.png)

A multiplayer presence mod for [Pokémon Gen 1 Recomp](https://github.com/bryanthaboi/gen1recomp).
Install it, log in with a name and password, and see where your friends
were last - on any platform the game runs on, with nothing extra to run or
configure on your end.

**Status: v1.2.7 - async presence and friends, added in-game.** Log in with
a name and password to get a unique 5-digit Trainer ID, then add friends
entirely in-game by entering their Trainer ID on a D-pad digit spinner - no
typing, no web page. The game periodically reports where you were last
seen; friends show up as static "last known position" markers on the map,
plus a friends list showing where they were, how long ago, and whether
they're likely still online. There's no live, real-time movement - see
"Why this isn't real-time" below for why that's a deliberate choice.

SilphNet is free to use and the server's running costs come out of my own
pocket - if you'd like to help keep it going, you can do so here:
[buymeacoffee.com/ashjam](https://buymeacoffee.com/ashjam). Entirely
optional, and much appreciated.

## How it works

SilphNet talks to a small web API over plain `http://` rather than a live
game server. That keeps it simple to run (just PHP and MySQL, the kind of
hosting most people already have) and means it works the same way on
desktop and mobile alike, without needing anything platform-specific.

## Why this isn't real-time

An earlier version of this mod had a live, real-time overworld: a
background relay so you'd see friends walking around as it happened. That
needed a persistent process running *somewhere* at all times, which didn't
fit the goal of running entirely on ordinary PHP and MySQL web hosting. It
also fought a persistent movement judder that traced back to the game
engine's own `handle:scriptMove` having a real per-call cost, never fully
resolved cleanly across several rounds of fixes.

SilphNet now does the opposite trade-off on purpose: no live movement, no
server process, nothing running unless you're actively playing. Friends
appear as a **static snapshot** of where they were a little while ago, not
a live avatar - closer to "last seen" on a messaging app than to watching
them walk around in real time. The old real-time code is kept in
`archive/tcp_relay_retired/` in case it's ever worth revisiting.

## Layout

```
mod/silphnet/           the LÖVE mod (install this into the game's mods/ folder)
  main.lua               client: HTTP login, presence ping/poll, friend markers
  manifest.json          declares the "network" permission, github field for auto-update
  mod.card               manager detail card
dist/silphnet.zip        the mod, zipped and ready to install
server/
  web/                   the PHP and MySQL API (all that's needed to host - no VPS, no persistent process)
    schema.sql            run once in phpMyAdmin to create the tables
    migrations.sql         column changes for an existing database (run only when a new version needs one)
    db.php.example         DB connection template - copy to db.php and fill in real credentials there
    register.php           create an account (name + password -> account_id + token)
    login.php              log in with name + password -> account_id + token
    login_token.php         re-authenticate with a cached token (no retyping)
    ping.php                report a last-known position (requires a token)
    friends.php             fetch friends' last-known positions (requires a token)
    add_friend.php           send a friend request by Trainer ID
    accept_friend.php        accept an incoming friend request
    remove_friend.php        remove an accepted friend (or decline/cancel a pending request)
    pending_requests.php     list incoming friend requests awaiting your accept
archive/tcp_relay_retired/  the old real-time relay - retired, kept for reference
experiments/http_test/      the throwaway diagnostic that confirmed plain HTTP works from the game
assets/                  images used in this README (banner, etc.)
.github/workflows/       the release pipeline - publishes a GitHub Release + zip on every push to mod/silphnet/
ACCOUNTS.md               the account model (web and MySQL-backed)
SECURITY.md               what plain HTTP and password hashing mean for safety
```

## Quick start

### 1. Install the mod

Copy `mod/silphnet/` into the game's `mods/` folder, or install
`dist/silphnet.zip` from the in-game Mod Manager - either works on any
platform Gen1Recomp runs on. On mobile, get `dist/silphnet.zip` onto the
device first (cloud drive, USB, whatever's easiest) and install it from
the in-game Mod Manager there.

Enable **SilphNet** in the Mod Manager. It will ask to allow the `network`
permission.

### 2. Log in

In the Mod Manager -> **SilphNet** options, **MY NAME** and **PASSWORD**
open the classic Game Boy letter-grid when pressing **A** on them. Gen 1's
naming screen has no digits by default, so this mod adds a **0-9 row** to
that grid - but only when one of these two fields is open; every other
naming screen in the game (Pokémon nicknames, trainer name, etc.) stays
exactly vanilla.

The first time logging in with a new name, an account is created
automatically - there's no separate sign-up step. After that, the same
name and password logs into the same account from any device. A session
token is cached locally to avoid retyping the password every launch;
changing MY NAME or PASSWORD in the options forces a fresh login.

The password is hashed (bcrypt) before it's ever stored - nobody, including
whoever runs the database, can look up the original password from it. See
`SECURITY.md`.

On first login, a unique **Trainer ID** is also assigned - a random 5-digit
number (00000-65535, the same range the mainline games use) shown on the
status screen. Share it with a friend (in person, over chat, however's
easiest) so they can add you.

### 3. Add friends and check the status screen

Open **START** - the menu shows `SILPHNET <name>` once logged in, or a
status message otherwise (`SILPHNET SET NAME/PASS` if MY NAME/PASSWORD
aren't set yet, `SILPHNET NEW ACCT?` if that name doesn't have an account
yet, `SILPHNET LOGIN FAIL`, or `SILPHNET ...` while logging in). Select
that row for the status screen:

- **A** - retry login, or (if no account exists yet for MY NAME) open a
  confirmation screen before one gets created - nothing is ever registered
  without this explicit confirmation
- **START** - open the friends list (name, online/offline, last-known map
  and tile, how long ago)
- **RIGHT** - open Add Friend (enter a Trainer ID with a digit spinner:
  **UP/DOWN** changes the selected digit, **LEFT/RIGHT** moves the cursor,
  **A** sends the request)
- **LEFT** - open pending friend requests (always opens, showing "NONE
  PENDING" if there aren't any; page through with **LEFT/RIGHT**, **A** to
  accept)
- **SELECT** - reset (clears the cached login on this device only)
- **B** - back

An **ABOUT SILPHNET** row also lives in the mod manager's own OPTIONS
screen for SilphNet (not the in-game GB status screen, which is already at
its practical space limit) - it shows who made this and a link to
[ash.jamtv.co.uk](https://ash.jamtv.co.uk).

No typing and no web page needed - adding a friend is entirely a Trainer ID
number entry, in-game. Once accepted, they'll show up in the friends list
and, when standing on their last-known map, as a static marker on the
ground.

The friends list shows one friend per screen, not a scrolling list - the
"N/M" counter at the top (e.g. "1/3") means "friend 1 of 3 total," and
**LEFT/RIGHT** or **A** switches which one is shown. Page
through (**START** from the status screen), **SELECT** opens a confirm
screen to remove the friend currently on screen (**A** confirms, **B**
cancels) - it removes the friendship for both sides, not just locally, and
the screen waits for the server to fully confirm the removal AND for the
friends list to actually refresh (showing "REMOVING..." throughout) before
returning to the list, rather than popping back while still showing the
just-removed friend.

### 4. Play

Roughly every 30 seconds of actual play, the mod reports the current map
and tile to the server and fetches friends' last-known positions back. The
timer only advances while you're taking steps in the overworld rather than
running on a strict background clock - standing still in a menu doesn't
tick it forward, and it catches up on your next step once 30 seconds of
real time have actually passed. If a friend's last-known map matches the
one being explored, a static, non-animated marker appears at their
last-known tile - it never moves on its own; if they move, the marker just
relocates once on the next poll, not tweened or animated.

### Data usage

Negligible - each 30-second cycle (position report, friends list, pending
requests) is under 2KB, so roughly 200-250KB an hour of continuous play
with a handful of friends added, similar to occasionally refreshing a
plain text page. There's no image, audio, or streaming data involved, so
this is safe to leave running on mobile data without worrying about a
data cap.

## Troubleshooting

- **`SILPHNET OFF` / `SILPHNET LOGIN FAIL`** -> usually a connectivity blip
  with the SilphNet service; try again in a minute. If it persists, flag it
  (see Notes below).
- **`SILPHNET SET NAME/PASS`** -> set MY NAME and a PASSWORD in the mod
  options; that pair is the account.
- **Mod errors** -> the Mod Manager lists them per-mod, prefixed
  `[silphnet]`.
- **Can't type numbers in a field / it caps at 7 characters** -> the naming
  grid has no digits by default; reinstall the latest `dist/silphnet.zip`,
  which adds a digits row for MY NAME and PASSWORD specifically.
- **Force a clean re-login** -> open the SilphNet status screen and press
  **SELECT**, then **A** to confirm. This clears the cached login token on
  this device only - the account and password are untouched, so logging in
  again with the same name and password picks up right where things left
  off.
- **Friend not showing on the map** -> markers only appear when the current
  map matches their *last-known* map from their most recent ping - if
  they've since moved on (or haven't played recently), they'll only show
  in the friends list, not on the ground.

## What's verified vs. what to check on-device

Verified via a lupa-based Lua test harness (stubbing `love`/`mod` and
exercising the real `main.lua`): login/register/cached-token flows,
presence firing on the correct schedule, friend marker spawn, despawn and
relocate lifecycle (including that a moved or departed friend causes
exactly one despawn and, if still on the current map, one respawn - never
a per-tick animation), and friendly map-name rendering.

Marked `<< VERIFY >>` in `main.lua` (engine specifics not run against the
real game):

- the marker `sprite` id (`SPRITE_RED`) and exact `spawnNpc` object fields;
- exact GB-screen text glyph width - `main.lua` assumes 8px/character and
  budgets every screen conservatively under that, but this hasn't been
  independently confirmed against the engine's font asset.

An earlier version drove its background presence/friends timer off
`input.step`, a hook that's real in engine source but was never in the
curated wiki hook reference and was marked `<< VERIFY >>` here for exactly
that reason. Real two-player on-device testing eventually confirmed it:
presence pings simply weren't firing, even after 60+ continuous seconds in
the overworld. Checking the engine's actual generated-from-source hook
catalog confirmed `input.step` isn't a documented hook at all, so the timer
now runs off `world.stepped` instead - real, documented, and already relied
on elsewhere in this mod - with the trade-off that the timer only advances
on an actual step rather than a strict clock (see "Play" above).

Switching to `world.stepped` fixed the timer but introduced a second real
bug, also caught via on-device testing: results that finish while the
player is standing still (not stepping) - a login started right at boot, an
Add Friend request, a friend removal - could sit fully complete but unread
in the background HTTP channel, showing "LOGGING IN.." or "SENDING..."
indefinitely, since nothing was draining that channel except world.stepped
itself. Checking the engine's mod object reference confirmed there's no
generic per-frame hook independent of movement in this API at all - every
documented hook/event ties to a specific gameplay moment. The fix: the
channel-draining logic was split out from the presence timer into its own
function, called both from `world.stepped` (general case) and directly from
every screen's own `update(dt)` that's actually waiting on a result (the
status screen while logging in, Add Friend while sending, the remove-friend
confirm while removing) - `update(dt)` runs every frame regardless of
movement, so those specific waits now resolve immediately.

There's deliberately no game-version (Red/Blue/Yellow) tracking: the
engine doesn't expose which ROM a player imported anywhere in the mod API,
so this can't be auto-detected, and there's no in-game picker for it
either - see the Roadmap below.

If something misbehaves, the `[silphnet]` manager errors will point right
at it.

## Roadmap

1. Done - async presence: login, periodic position reporting, friends' last-known positions
2. Done - static friend markers on the map, plus a friends list with online/offline and time-ago
3. Done - Trainer ID and in-game "add friend"/"accept friend" screens (digit entry, no typing)
4. Done - GitHub auto-update, so the launcher can pull new mod releases directly (see `.github/workflows/release-silphnet.yml`)
5. Done - account creation requires explicit confirmation; no silent registration and no fallback to your in-game trainer name
6. Done - remove an accepted friend (or decline/cancel a pending request), removing the friendship for both sides
7. Not currently possible - trainer card view (party, badges, League clears) and trading/battling a friend's real party: the
   mod API has no documented way to read or write a player's party/box data outside the engine's own live, synchronous
   link-play session (UDP, both players online at once), which doesn't fit SilphNet's async model. Revisit if a future
   engine version exposes this.
8. "Friend came online" notifications, custom greetings, unlockable battle music
9. A custom-drawn UI (like other mods' non-Game-Boy-style menus) instead of the current `Font.drawBox` dialogue screens -
   a real, separate visual overhaul, not a quick reskin

See `ACCOUNTS.md` for the account design and `SECURITY.md` for the security
model.

## Running your own SilphNet server

The mod is hard-wired to a single, already-running SilphNet service, so
none of this is needed for normal play - it's here for anyone who wants to
fork the project and run their own instance instead.

The backend is a handful of small PHP files plus a MySQL database - no VPS
and no persistent process required, ordinary shared web hosting is enough:

1. In phpMyAdmin, run `server/web/schema.sql` against the database to
   create the `accounts`, `sessions`, `presence`, and `friends` tables.
2. Upload everything in `server/web/` to the site (e.g. `yoursite.com/api/`),
   except `db.php.example` - copy that one to `db.php` first and fill in
   the real database credentials there before uploading it.
3. In `mod/silphnet/main.lua`, change `API_BASE` at the top to point at
   the new site's `/api` URL, then rebuild `dist/silphnet.zip`.

If a database column needs adding later (e.g. after pulling in a newer
version of this mod), see `server/web/migrations.sql`.

## Notes

The `SilphNet_Technical_Specification` files are the original design
study - see the project notes for a review of what holds up and what
doesn't. The original real-time relay design lives in
`archive/tcp_relay_retired/` if any of it is ever useful again.
