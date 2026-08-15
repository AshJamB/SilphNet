# SilphNet

![SilphNet](assets/silphnet-banner.png)

A multiplayer presence mod for [Pokémon Gen 1 Recomp](https://github.com/bryanthaboi/gen1recomp).
Install it, log in with a name and password, and see where your friends
were last - on any platform the game runs on, with nothing extra to run or
configure on your end.

**Status: v1.9.0 - HTTP requests are now synchronous (a Gen1Recomp engine update permanently blocked love.thread for mods).**
Log in with
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
  web/                   the site root - upload this whole folder as-is
    index.php              public landing page (features, install steps, GitHub link, socials)
    account.php            log in on the web to manage your account (rename, Trainer ID, password, recovery email)
    assets/                images used by index.php (logo, banner)
    api/                  the PHP + MySQL gameplay API, kept separate from the public site above -
                           everything the mod itself talks to lives here, at /api on your host
      schema.sql             run once in phpMyAdmin to create the tables
      migrations.sql         column changes for an existing database (run only when a new version needs one)
      db.php.example         DB + SMTP + email-encryption connection template - copy to db.php and fill in real values there
      register.php           create an account (name + password -> account_id + token)
      login.php              log in with name + password -> account_id + token
      login_token.php        re-authenticate with a cached token (no retyping)
      check_name.php         live availability check for a candidate username (account.php)
      check_trainer_id.php   live availability check for a candidate Trainer ID (account.php)
      update_account.php     rename your username and/or reassign your Trainer ID (password-gated, logs old values to account_history)
      change_password.php    change your password (requires your current password)
      set_email.php          add/change your recovery email (password-gated; stored encrypted, see SECURITY.md)
      request_password_reset.php   request a password-reset email (public - only works if a recovery email is on file)
      reset_password.php     consume a password-reset link/token and set a new password
      email_crypto.php        AES-256-GCM encrypt/decrypt helpers for the stored recovery email
      mailer.php               thin wrapper around the vendored PHPMailer, sends the reset email
      vendor/phpmailer/        vendored PHPMailer library (3 files, copied from the official release - no composer needed)
      ping.php                report a last-known position (requires a token)
      friends.php             fetch friends' last-known positions (requires a token)
      add_friend.php           send a friend request by Trainer ID
      accept_friend.php        accept an incoming friend request
      remove_friend.php        remove an accepted friend (or decline/cancel a pending request)
      pending_requests.php     list incoming friend requests awaiting your accept
      online_count.php         count of everyone currently online, globally (not just friends)
      online_by_version.php    everyone online, grouped by game version (RED/BLUE/YELLOW), with player lists
      nearby.php               everyone else (friend or not) currently on a given map
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

Open **START** - the menu shows `SN <name>` once logged in, or a
status message otherwise (`SN SET NAME/PASS` if MY NAME/PASSWORD
aren't set yet, `SN NEW ACCT?` if that name doesn't have an account
yet, `SN LOGIN FAIL`, or `SN ...` while logging in). Kept short
("SN", not "SILPHNET") since some third-party UI mods truncate Start
Menu rows by simply chopping off anything past a length limit rather
than adding an ellipsis - a longer label could disappear entirely
depending on name length. Select that row for the status screen:

- **Before logging in**: **A** retries login, or (if no account exists
  yet for MY NAME) opens a confirmation screen before one gets created -
  nothing is ever registered without this explicit confirmation. START
  does nothing yet at this point - there's no friends list to show
  before you're logged in.
- **Once logged in**: **A** opens the friends list (name, online/offline,
  last-known map and tile, how long ago). The **A:FRIENDS** hint itself
  also shows how many of YOUR FRIENDS are currently online, when there
  IS at least one (`A:FRIENDS(2 ON)`) - dropped entirely when none of
  your friends are online, rather than showing a placeholder like
  `(0 ON)` or `(- ON)`. **START** is now re-auth (forces a fresh login
  check) - swapped from the original layout since A feels more natural
  as the "open/select" button, matching how A is used everywhere else in
  this mod (accepting a request, confirming a removal).
A second Start Menu row, **SN NEARBY**, sits right below the main
**SN \<name\>** row (rather than being folded into the friends
list) and opens its own screen: everyone else currently on your own
map, by name and Trainer ID, Pokémon-Go-style - titled with how many
people are there (`- NEARBY (n) -`) and the map name underneath.
Someone already on your friends list shows **ALREADY A FRIEND** instead
of an add prompt; anyone else shows **NOT YET A FRIEND** with a
reminder to add them the normal way (**RIGHT** from the status screen,
entering their shown Trainer ID) - there's no separate "add" button on
the NEARBY screen itself, to avoid building the same flow twice.
A fourth Start Menu row, **SN ONLINE**, shows everyone currently online
across the whole service, not just your friends (self included). This
used to be folded into the **A:FRIENDS** hint above as a single flat
number, but that read as confusing: a player with no friends online, who
was themselves within the 5-minute ONLINE window, would see
`A:FRIENDS(1 ON)` right next to a friends list showing everyone OFFLINE -
technically correct (that count always included the player), but easy to
misread as "one of my friends is online." Splitting these into two
clearly separate numbers, on two separate screens, means neither can be
mistaken for the other again.

**SN ONLINE** itself has two pages: a summary (`RED n ON` / `BLUE n ON` /
`YELLOW n ON`, one line per game version), and - **LEFT/RIGHT** from
there - each version's own page listing exactly who's online in it, one
person per screen (**UP/DOWN** pages between them), with the same
**ALREADY A FRIEND** / **NOT YET A FRIEND** + add-by-Trainer-ID flow
**SN NEARBY** already uses. UNKNOWN-version presence rows (an account
whose client hasn't reported a real game.save.version yet) never appear
here - see "There's deliberately no..." further down for why this
mod can tell RED/BLUE/YELLOW apart at all.

A fifth Start Menu row, **SN ABOUT** (credits and links), always sits
last, directly above **QUIT** - a deliberate, permanent position as the
mod grows new rows over time, not just wherever it happened to land.
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
title line reads "FRIENDS N/M" (e.g. "FRIENDS 1/3", meaning "friend 1 of
3 total"), and **LEFT/RIGHT** switches which one is shown. While a friend entry is
ONLINE, the ONLINE/OFFLINE line itself also shows which version they're
playing right now ("ONLINE (BLUE)") - offline, no version is shown at
all, regardless of how many versions that friend has. **A** opens that friend's detail screen
(see below); **SELECT** opens a confirm screen to remove the friend
currently on screen (**A** confirms, **B** cancels) - it removes the
friendship for both sides, not just locally, and the screen waits for the
server to fully confirm the removal AND for the friends list to actually
refresh (showing "REMOVING..." throughout) before returning to the list,
rather than popping back while still showing the just-removed friend.
The bottom hint line reads **A:DETAIL LR:PAGE** (both controls combined
onto one line) - this screen is already at its 144px display limit, so
that combination is what frees enough room for a real gap above it,
fixing an earlier report that the last data row and the hint row beneath
it looked squashed together.

**Friend detail screen** (**A** on a friend in the list): **A** cycles
through every page in one flat loop - that friend's STATS, then their
ACTIVITY, then (only if they've genuinely played more than one game
version with real data) the next version's STATS, then ACTIVITY, and so
on, wrapping back to the start. **B** backs out at any point. A version
only gets a slot in this cycle if that friend has actually uploaded
stats or activity for it - a version they're merely pinging presence
under (e.g. just started a fresh file) doesn't show up until they've
actually reported something. The game version is shown on its own line
right under the page title (e.g. "ARCHADA STATS" / "BLUE"), for every
friend, not just ones with multiple versions - it's just part of reading
the page now, not a conditional hint.

- **STATS pages**: badges (out of 8), Pokédex seen/caught, League wins,
  and money - all self-reported by that friend's own client, since a mod
  can only ever read its own save data, never someone else's. Shows "NO
  STATS YET" if they haven't uploaded a snapshot for that version yet.
- **ACTIVITY pages**: that version's latest status message on two lines -
  e.g. "CAUGHT LVL 25" / "BLASTOISE" - with its own time-ago, plus that
  friend's overall last-known map and time-ago (their single most recent
  ping across ALL their versions, not scoped to just this one) repeated
  from the main friends list. Two lines, not one, since a long species
  name plus the level prefix risked overflowing a single 16-char line.
  These are deliberately two separate timestamps, not one shared "X AGO" -
  catching something and being last seen online are different moments (a
  friend could catch something and then go offline, or still be walking
  around minutes later).

Activity is driven by the real, documented `pokemon.caught` event (not a
poll) - fires the moment a catch happens and uploads immediately,
independent of the slower stats cycle. Level comes from that event's own
`mon` field. Stats themselves (badges/Pokédex counts/money/League wins)
upload roughly every 3 minutes of play instead - slower than the ~30s
presence cycle, since none of those need to be that fresh.

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

Press **A** while facing a friend's marker to see who it is - a small,
full-screen box (not a vanilla-style speech bubble) pops up with their
name, then closes on A or B. This is a live lookup done the instant you
press A, not something baked in when the marker appeared, so it's always
correct even if the marker's owner changed in the meantime. Up to 8
friend markers can be identified this way at once (more than enough for
any normal friends list); if that's ever not
enough, `MARKER_SLOTS` in `main.lua` can be raised.

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
- **Friend not showing on the map** -> markers only appear when the
  current map matches their *last-known* map from their most recent ping
  AND they're currently ONLINE (pinged within the last 5 minutes) - if
  they've since moved on, gone offline, or haven't played recently,
  they'll only show in the friends list, not on the ground.

## What's verified vs. what to check on-device

Verified via a lupa-based Lua test harness (stubbing `love`/`mod` and
exercising the real `main.lua`): login/register/cached-token flows,
presence firing on the correct schedule, friend marker spawn, despawn and
relocate lifecycle (including that a moved or departed friend causes
exactly one despawn and, if still on the current map, one respawn - never
a per-tick animation), friendly map-name rendering, and that an OFFLINE
friend's marker is excluded from the spawn set even when their last-known
map still matches yours.

Caught on-device: a friend's marker used to keep standing on their
last-known tile forever after they went offline - `refreshMarkers` only
checked "is this friend's last-known map the one I'm on", with no check
against the same 5-minute ONLINE/OFFLINE threshold the friends list
already uses, so nothing ever told the marker to disappear once someone
logged off (their `map_id` doesn't change again once they're offline).
Fixed by gating marker eligibility on that same threshold. Fixing this
also surfaced (and fixed) the exact forward-declaration ordering bug this
file has hit a few times before: the fix needed `parseMysqlDatetimeUtc`
inside `refreshMarkers`, but that function was defined further down the
file, after `refreshMarkers` - a local function's name only exists from
its own declaration onward, so this would have resolved to a nil global
at runtime. Moved the date-parsing helpers above `refreshMarkers` instead
of adding another forward-declare pair.

Marked `<< VERIFY >>` in `main.lua` (engine specifics not run against the
real game):

- the marker `sprite` id (`SPRITE_RED`) and exact `spawnNpc` object fields;
- exact GB-screen text glyph width - `main.lua` assumes 8px/character and
  budgets every screen conservatively under that, but this hasn't been
  independently confirmed against the engine's font asset.
- the friend-marker "press A to see who it is" feature: built on the
  documented `map_scripts`/`talk`/`push_screen` API surface, using a
  fixed pool of 8 talk-script "slots" registered on every map (see the
  `MARKER_SLOTS` comment in `main.lua`) rather than one script per
  friend, since the wiki doesn't document a way for a talk script to
  identify which specific NPC object triggered it. The first shipped
  version of this registered those talk scripts lazily, from
  `map.entered` - which real two-player testing caught immediately:
  pressing A did nothing at all, on both devices. Root cause, confirmed
  against the wiki's own lifecycle docs: content registries (including
  `map_scripts`) freeze after the merge phase, and
  register/override/patch/remove all raise from then on - "register
  content at entry-chunk time." `map.entered` fires during Play, long
  after that freeze, so every registration attempt was raising and
  being silently swallowed by a `pcall`. Fixed by registering all 8
  slots on every real map up front, once, at true entry-chunk time
  (enumerated via `mod.content.maps:each()`, which already sees the
  whole imported game before any mod's entry chunk runs) - not yet
  re-confirmed on a real device. Once it did fire on-device, two-player
  testing confirmed the popup itself works (right friend, right name),
  but caught a real layout bug: the box was only drawn 4 rows tall, so
  the "A/B:CLOSE" hint line landed with no clearance above the box's own
  bottom border and rendered jammed against/behind that frame line.
  Fixed by making the box 6 rows tall, matching the one-clear-row-above-
  the-border rule every other screen in this file already follows - not
  yet re-confirmed on-device.
- the global online counter and the NEARBY screen (both added this
  session): the server endpoints and NEARBY's paging logic were tested
  in isolation (a standalone Lua test confirming paging wraps correctly
  in both directions, including the empty-list case), the Start Menu's
  two-row anchored insertion was also tested standalone (confirms both
  SilphNet rows land together, in order, directly above QUIT), and the
  full file compiles cleanly under real LuaJIT - but none of this has
  been pressed on a real device yet. NEARBY briefly shipped as a mode
  toggled by START inside the friends list before being pulled back out
  into its own Start Menu row/screen, once it was clear the mod could
  simply add more Start Menu entries as it grows rather than needing to
  cram new features into existing screens.

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

### Shipped

1. Done - presence: login, periodic position reporting, friends' last-known positions (originally async via a background love.thread per request; now synchronous as of v1.9.0 - see that version's changelog entry for why)
2. Done - static friend markers on the map, plus a friends list with online/offline and time-ago
3. Done - Trainer ID and in-game "add friend"/"accept friend" screens (digit entry, no typing)
4. Done - GitHub auto-update, so the launcher can pull new mod releases directly (see `.github/workflows/release-silphnet.yml`)
5. Done - account creation requires explicit confirmation; no silent registration and no fallback to your in-game trainer name
6. Done - remove an accepted friend (or decline/cancel a pending request), removing the friendship for both sides
7. Done - press A on a friend's map marker to see their name, live-looked-up, closing on A or B
8. Done - global online counter (folded onto the status screen's FRIENDS line, "FRIENDSn ONn")
9. Done - "who's nearby" (non-friends) - its own Start Menu row ("SN NEARBY") and screen, showing everyone else's name/Trainer ID on your current map, friend or not
10. Done - status screen controls swapped once logged in: A opens the friends list, START is re-auth (was the other way round)
11. Done - friend detail screen (press A on a friend in the friends list): self-reported stats (badges, Pokédex seen/caught, League wins, money) plus latest activity - currently catches only, shown on two lines ("CAUGHT LVL 25" / "BLASTOISE") - with its own time-ago, and last-seen repeated from the main friends list
12. Done (partial) - auto status updates: driven by the real `pokemon.caught` event (not a poll), including level from the event's own payload, uploaded immediately independent of the slower ~3 min stats cycle. Trainer-battle events ("DFTD BUG CATCHER" etc.) are NOT wired up - see the corrected note on item 12 below, this was originally overstated as straightforwardly buildable and isn't. Level-up/badge-earned/League-win also aren't wired up yet.
13. Done - real game version detection: `game.save.version` (confirmed directly from the engine's own `SaveData.lua`) replaces the permanent "UNKNOWN" placeholder that had sat unverified for most of this project. A friend who's genuinely played more than one version (e.g. cleared a BLUE run, then started a fresh YELLOW one) shows a version tag on the friends list ("1/3 (BLUE)") and can be viewed per-version on the friend detail screen (**SELECT** cycles versions there) - both only appear once a friend actually has more than one to disambiguate.

### Next up

These are aimed at the core problem raised in planning: with few friends
added yet, the mod has little to offer a new player. Grounded against
the actual documented mod API (`Reference-Events`, `Reference-Hooks`,
`Reference-Registries` on the [gen1recomp wiki](https://github.com/bryanthaboi/gen1recomp/wiki)) rather than assumed:

11. **Friends-who-cleared-this-gym sign.** A new, clearly-distinct sign/NPC
   placed in each gym (not a rewrite of the vanilla statue's own text,
   which is frozen per-map content the mod can't rewrite per-viewer) -
   shows which of your friends have beaten that gym leader. Needs a
   deliberately different look (different sprite, or a `[!]`/`[?]`-style
   marker rather than a plain statue) and careful placement so it never
   sits in a trainer's path or blocks a walkway - existing gym layouts
   need checking map-by-map before placement. Data source: see the
   corrected note under item 12 below on trainer-battle detection - the
   gym-leader-specific case has the exact same "no single event gives
   both identity and outcome" problem as a general "DFTD BUG CATCHER"
   message would.
12. **Auto status updates - catches: Done (see Shipped, item 12 above).**
    Driven by the real `pokemon.caught` event
    (`{ battle, mon, species, isNew, ball, destination, game }`), with
    level read off the event's own `mon` field.

    **Trainer-beaten messages ("DFTD BUG CATCHER", "DFTD CHAMPION", "DFTD
    RIVAL") - corrected, NOT straightforwardly buildable.** An earlier
    version of this note claimed `battle.ended` carried enough for this;
    checked against the real Reference-Events wiki page and that's
    wrong. `battle.ended`'s real payload is just `{ battle, result }`
    (`result` is `"caught"`/`"run"`/`"skipped"`/etc, not a trainer
    win/loss flag) - no trainer identity at all. `world.trainer_engaged`
    (`{ npc, trainerClass, partyIndex }`) has the trainer's class, but
    fires at the START of the fight, before any outcome is known. So
    this would need the mod to remember `trainerClass` from
    `world.trainer_engaged` and match it up with whatever `battle.ended`
    fires shortly after - not a single clean event, and not yet tested
    for whether `battle.ended`'s `result` values even distinguish
    "beat a trainer" from "lost" or "ran".

    `pokemon.level_up` (`{ mon, level, prevLevel, learnable }`) and
    `pokemon.evolved` are real, documented, and not yet wired up either
    - both would slot into the same activity-upload path stats.php
    already supports, whenever this is picked up.
13. **Done - account webpage** (`account.php`) - log in with your name and
    password (same credentials the mod uses) to change your username
    and/or Trainer ID, with live availability checking as you type
    (`check_name.php`/`check_trainer_id.php`) and a real password
    re-check at save time (`update_account.php`) - not just a valid
    session token, the actual password, since this changes
    identity-bearing account fields. Both uniqueness re-checks and the
    write happen inside one transaction, so two people can't both be
    told a name/ID is free and only one actually end up with it.
    Password itself isn't changeable from this page yet (only name and
    Trainer ID) - a natural follow-up, not built this round.
    As anticipated: a changed Trainer ID only takes effect the next time
    that device logs in (the mod still only reads its Trainer ID once,
    right after login/register, cached in `myTrainerId` and never
    re-fetched mid-session) - the save confirmation on `account.php`
    says this explicitly rather than implying an instant update.
14. **Leaderboards.** Cheapest/safest options rank on data the server
    already has or can easily start recording: most accepted friends,
    longest current login streak (consecutive days pinged), most maps
    visited, first-to-clear-the-league (self-reported, honor system -
    see item 15). A "most Pokémon caught" or "highest Pokédex count"
    board needs the stats-snapshot mechanism from item 16 first, since
    that data lives in each player's own save file, not the database.

### Unblocked - confirmed against the engine's real source

A real exported save (`gen1recomp-blue-slot1.sav`) was analyzed byte by
byte against the public Gen 1 save-file format, THEN the engine's actual
GitHub source (`src/core/SaveData.lua`) was fetched and grepped directly
to find the real Lua-level field names a mod would use - not raw byte
offsets. Full breakdown in `research/gen1-save-format-findings.md`.
Confirmed, from the engine's own working code:

- `save.party` - a plain Lua array of mon objects (`mon.species`,
  `mon.level`, `mon.moves`, `mon.dvs`, `mon.stats`), already resolved to
  real ids, no lookup table needed.
- `save.pokedex.owned` / `save.pokedex.seen` - sets keyed by species id;
  count via `pairs()` for a Pokédex count (this is literally what the
  engine's own title-screen slot summary does).
- `save.playTime` - a plain seconds count OR a `{hours, minutes, seconds,
  frames}` table depending on engine build; the engine's own code checks
  the type before reading it, and SilphNet should too.
- `save.hallOfFame` - a list of Champion-clear entries; empty means never
  beaten. This matches what the raw .sav showed (empty = not yet beaten).
- `save.player.name` - already known, now doubly confirmed.
- `save.flags` - confirmed directly readable/writable at runtime from a
  real, working example (Tutorial 08's `onStep` handler sets
  `game.save.flags.TUT8_HINTED` directly) - the same access pattern
  should work for `game.save.party` etc., no special event needed.
- Badges are the one exception: not a plain field, derived internally via
  `Badges.count()` in a module mods can't `require` (not on the
  documented safe-require allowlist). Confirmed workaround, by reading
  `Badges.lua`'s own source directly: it just checks `save.inventory`
  against the `constants.badges` registry (each entry resolving to a real
  item id) - a faithful reimplementation of the same logic, not an
  approximation, now shipped in `main.lua`'s `countBadges()`.
- `save.money` - a plain top-level key, NOT nested under `save.player`
  (confirmed directly from `SaveData.newGame()`'s table construction -
  `player` only holds map/x/y/facing/name/rival/id).

15. **Community Champion.** The remaining blocker is specifically about
    battling, not data access: another player's live party can only be
    READ from their own local save (confirmed possible, per above) -
    there's still no documented way to read or write a DIFFERENT
    player's party, or referee a real synchronous battle against them
    outside the engine's own same-room link-play session. So the
    buildable version is: once a player legitimately clears the League
    (a non-empty `save.hallOfFame`), their mod reads its own
    `save.party` and uploads it as a JSON snapshot naming them the
    reigning Champion. Anyone can view that snapshot read-only ("here's
    what you'd be up against"), but any actual "fight" against it would
    be honor-system only (both sides self-report the result), not
    something the mod verifies or enforces.
### Smaller UI polish, not yet scheduled

17. "Friend came online" notifications, custom greetings, unlockable
    battle music.
18. A custom-drawn UI (like other mods' non-Game-Boy-style menus)
    instead of the current `Font.drawBox` dialogue screens - a real,
    separate visual overhaul, not a quick reskin.

See `ACCOUNTS.md` for the account design and `SECURITY.md` for the security
model.

## Running your own SilphNet server

The mod is hard-wired to a single, already-running SilphNet service, so
none of this is needed for normal play - it's here for anyone who wants to
fork the project and run their own instance instead.

The backend is a handful of small PHP files plus a MySQL database - no VPS
and no persistent process required, ordinary shared web hosting is enough:

1. In phpMyAdmin, run `server/web/api/schema.sql` against the database to
   create all the tables (`accounts`, `sessions`, `presence`, `friends`,
   `friend_stats`, `friend_activity`, `account_history`,
   `password_resets`).
2. Upload `server/web/index.php`, `account.php`, and the `assets/` folder
   to the site root - `index.php` becomes the site's homepage
   automatically on most hosts; `account.php` is reachable at
   `yoursite.com/account.php`.
3. Upload everything in `server/web/api/` to an `api/` subfolder at the
   site root, except `db.php.example` - copy that one to `db.php` first
   and fill in the real database credentials (and, optionally,
   `EMAIL_ENCRYPTION_KEY`/`SMTP_*` for the recovery-email feature - see
   the comments in `db.php.example`) before uploading it. `account.php`'s
   own `API_BASE` already points at `/api` to match.
4. In `mod/silphnet/main.lua`, change `API_BASE` at the top to point at
   the new site's `/api` URL, then rebuild `dist/silphnet.zip`.

If a database column needs adding later (e.g. after pulling in a newer
version of this mod), see `server/web/api/migrations.sql`.

Recovery email (forgot-password) is entirely optional - the site works
fine without ever configuring `EMAIL_ENCRYPTION_KEY`/`SMTP_*`; players
just won't have a self-serve way to reset a forgotten password until you
do. See `SECURITY.md` for how the stored email is encrypted.

## Notes

The `SilphNet_Technical_Specification` files are the original design
study - see the project notes for a review of what holds up and what
doesn't. The original real-time relay design lives in
`archive/tcp_relay_retired/` if any of it is ever useful again.
