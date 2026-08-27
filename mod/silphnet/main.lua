-- SilphNet - async presence + friends (v1.13.2)
-- =============================================================================
-- See where your friends were last, without a live server. No real-time
-- movement, no persistent process anywhere - this only ever talks to a
-- small PHP+MySQL API over plain HTTP, on a timer.
--
-- HOW IT WORKS
--   * Log in (or register, on first use) with MY NAME + PASSWORD - the same
--     two fields, typed in-game exactly like before. This calls the web API
--     directly (login.php/register.php), not a game server - there is no
--     "SilphNet server" to run anymore.
--   * Once logged in, the mod POSTs your current map/x/y/facing to the API
--     every PRESENCE_INTERVAL seconds (see ping.php) and pulls your friends'
--     last-known positions back (see friends.php). That's it - no live
--     socket, no per-tick movement sync. The timer itself only advances
--     while you're actually taking steps in the overworld (driven off the
--     real, documented world.stepped event - see the comment above pump()
--     for why an earlier version's undocumented input.step hook was
--     replaced), so standing still in a menu doesn't tick it forward, and
--     a ping fires on your next step once PRESENCE_INTERVAL real seconds
--     have passed since the last one - not on a strict background clock.
--   * A friend who's on the SAME map as your last-known position gets a
--     static, non-animated NPC sprite placed at that tile (STAY movement,
--     refreshed only when a new presence poll moves them) - a "someone was
--     here" marker, not a live avatar. It never moves itself; if their
--     tile changes, the old marker is despawned and a new one spawned at
--     the new tile, once, on the next poll - never tweened or scripted.
--   * The status screen lists every accepted friend with their last-known
--     map/tile and how long ago that was, and derives ONLINE/OFFLINE from
--     whether that ping is more recent than OFFLINE_AFTER.
--
-- WHY PLAIN HTTP (NO HTTPS)
--   LOVE 11 (what Gen1Recomp Android builds run on) has no TLS. LuaSocket's
--   socket.http module opens a raw socket directly rather than going
--   through Android's Java HTTP stack (HttpURLConnection/okhttp) - which is
--   specifically what Android's cleartext-traffic block targets - so plain
--   http:// works even though https:// can't. Confirmed on-device against
--   silphnet.jamshark.co.uk (see experiments/http_test).
--
-- WHY NO LIVE RELAY ANYMORE
--   An earlier version of this mod also had a real-time overworld (a
--   background TCP thread relaying live positions, with remote trainers
--   rendered as NPCs that animated as they moved). That needed a
--   continuously-running relay process, which meant either leaving a home
--   PC on 24/7 or paying for a VPS - neither of which fit "just PHP+MySQL
--   on my existing cPanel hosting." It also fought a persistent movement
--   judder that traced back to the engine's own handle:scriptMove having a
--   real per-call cost, never fully resolved cleanly. Dropped entirely in
--   favour of this simpler async model - see git history if any of that
--   code is ever worth resurrecting.
--
-- Engine specifics I couldn't run here are marked << VERIFY >>.
-- =============================================================================

return function(mod)
  local MY_SPRITE = "SPRITE_RED"   -- << VERIFY >> a valid overworld sprite id

  -- The web API - plain HTTP, confirmed reachable from LOVE 11 on Android
  -- (see experiments/http_test). See server/web/ for the PHP + schema.
  local API_BASE = "http://silphnet.jamshark.co.uk/api"

  local PRESENCE_INTERVAL = 30.0   -- how often to POST your position
  local OFFLINE_AFTER     = 300.0  -- 5 minutes - no ping this recent => shown OFFLINE
  local STUCK_TICKS       = 20

  -- Friendly display names for map ids shown to the player (friends list,
  -- silhouette label) - PALLET_TOWN -> "PALLET TOWN" instead of the raw
  -- engine id. Falls back to underscore-to-space for anything not listed
  -- here, so an unmapped id still reads reasonably rather than looking
  -- broken - extend this table as more maps come up in testing.
  local FRIENDLY_MAP_NAMES = {
    PALLET_TOWN     = "PALLET TOWN",
    VIRIDIAN_CITY   = "VIRIDIAN CITY",
    PEWTER_CITY     = "PEWTER CITY",
    CERULEAN_CITY   = "CERULEAN CITY",
    VERMILION_CITY  = "VERMILION CITY",
    LAVENDER_TOWN   = "LAVENDER TOWN",
    CELADON_CITY    = "CELADON CITY",
    FUCHSIA_CITY    = "FUCHSIA CITY",
    SAFFRON_CITY    = "SAFFRON CITY",
    CINNABAR_ISLAND = "CINNABAR ISLAND",
    VIRIDIAN_FOREST = "VIRIDIAN FOREST",
    ROUTE_1 = "ROUTE 1", ROUTE_2 = "ROUTE 2", ROUTE_3 = "ROUTE 3",
    ROUTE_4 = "ROUTE 4", ROUTE_5 = "ROUTE 5", ROUTE_6 = "ROUTE 6",
    ROUTE_7 = "ROUTE 7", ROUTE_8 = "ROUTE 8", ROUTE_9 = "ROUTE 9",
    ROUTE_10 = "ROUTE 10", ROUTE_11 = "ROUTE 11", ROUTE_12 = "ROUTE 12",
    ROUTE_13 = "ROUTE 13", ROUTE_14 = "ROUTE 14", ROUTE_15 = "ROUTE 15",
    ROUTE_16 = "ROUTE 16", ROUTE_17 = "ROUTE 17", ROUTE_18 = "ROUTE 18",
    ROUTE_19 = "ROUTE 19", ROUTE_20 = "ROUTE 20", ROUTE_21 = "ROUTE 21",
    ROUTE_22 = "ROUTE 22", ROUTE_23 = "ROUTE 23", ROUTE_24 = "ROUTE 24",
    ROUTE_25 = "ROUTE 25",
  }
  local function friendlyMapName(mapId)
    if not mapId or mapId == "" then return "UNKNOWN" end
    return FRIENDLY_MAP_NAMES[mapId] or (mapId:gsub("_", " "))
  end

  -- Text fields default to Gen 1's classic 7-char name cap and the naming
  -- grid has no digits at all - so a password with numbers couldn't be
  -- typed however long the field was. maxLen asks for a longer field (the
  -- engine reads it straight off this row: see ManagerState.buildOptionRows,
  -- `maxLen = row.maxLen or 7`); the ui.naming.grid hook below adds a 0-9
  -- row when one of THESE fields is the one open. ADD FRIEND (in-game, not
  -- a mod option) reuses the same naming-grid screen via mod.ui's naming
  -- entry point - see openAddFriendPrompt below.
  local FIELD_MAXLEN = { ["MY NAME"] = 10, ["PASSWORD"] = 16, ["ADD FRIEND"] = 16 }

  pcall(function()
    mod.options:define({
      { key = "name",     type = "text", label = "MY NAME",  default = "", maxLen = FIELD_MAXLEN["MY NAME"] },
      { key = "password", type = "text", label = "PASSWORD", default = "", maxLen = FIELD_MAXLEN["PASSWORD"] },
    })
  end)
  -- Deliberately no "reset" option row here - the Manager auto-appends its
  -- own RESET DEFAULTS row to every mod's options screen, and it loops
  -- through this exact schema firing mod.options_changed once per row
  -- using each row's own `default`, including a "reset" row if one existed.
  -- That collided badly with a mod-defined reset action in an earlier
  -- version of this mod (RESET DEFAULTS silently triggering our own reset
  -- as a side effect). Reset lives on the SilphNetStatus screen instead
  -- (SELECT), which RESET DEFAULTS can't reach.

  -- Add a digits row to the naming-grid screen, but ONLY when it's one of
  -- our own fields open - every other naming screen (trainer name,
  -- nicknames, ...) must stay exactly vanilla.
  pcall(function()
    mod.hooks:wrap("ui.naming.grid", function(nextFn, grid, ctx)
      grid = nextFn(grid, ctx)
      local title = ctx and ctx.title
      local isOurs = title and FIELD_MAXLEN[title:gsub("%?$", "")] ~= nil
      if not isOurs or type(grid) ~= "table" then return grid end
      local out = {}
      for i, row in ipairs(grid) do out[i] = row end
      table.insert(out, math.max(1, #out), { "0","1","2","3","4","5","6","7","8","9" })
      return out
    end)
  end)

  local function opt(key, default)
    local ok, v = pcall(function() return mod.options:get(key) end)
    if ok and v ~= nil then return v end
    return default
  end

  -- ---- state ------------------------------------------------------------
  local game
  local accountId, myName, myPass, myTrainerId
  local myMap, myX, myY, myFacing
  local inOverworld = false
  -- Populated for real at game.ready (see resolveGameVersion below) - was
  -- a permanent "UNKNOWN" placeholder until now, since there was no
  -- confirmed way for a mod to read this. Confirmed via reading
  -- SaveData.lua directly: save.version is a real, always-populated
  -- top-level field ("red"/"blue"/"yellow"/"gold" - lowercase - guaranteed
  -- non-nil by a core migration that backfills "red" onto any save
  -- written before Blue support existed), read the same
  -- game.save.<key> way as save.flags/save.party elsewhere in this file.
  local gameVersion = "UNKNOWN"

  -- authState: idle|logging_in|need_creds|failed|authed
  local authState = "idle"
  local authBusy  = false

  -- Keyed by "account_id|game_version" (see parseFriendsJson), NOT bare
  -- account_id - one friend can have multiple entries here if they have
  -- more than one active save.
  local friends = {}   -- "account_id|game_version" -> { account_id, name, game_version, map_id, x, y, facing, last_seen (unix) }
  local markers = {}   -- same key -> { npcId, mapId, x, y, slot }  (spawned silhouettes on the CURRENT map only)
  local idToIndex, nextIndex = {}, 9000   -- object `index` (save-key namespace), separate from talk slots below

  -- ---- friend-marker talk slots --------------------------------------------
  -- map_scripts is per-real-mapId, compose semantics, keyed per TEXT constant
  -- (Reference-Registries, Tutorial-06-NPC-And-Dialogue) - there's no way to
  -- register "any map" once, so we register a FIXED set of SILPHNET_MARKER_SLOT_N
  -- talk entries on every map as the player enters it (guarded so a revisit
  -- doesn't try to :register a duplicate id, which errors). Each marker NPC
  -- claims one slot out of MARKER_SLOTS while it's alive; the slot's talk
  -- script always pushes the SAME generic SilphNetMarkerTalk screen with that
  -- slot number, and the screen looks up whichever friend currently OWNS that
  -- slot at the moment you press A - so the name shown is always live, never
  -- frozen at registration time. This is the documented-API-safe fallback:
  -- no per-friend TEXT ids, no reliance on ctx exposing which NPC was pressed
  -- (never confirmed in the wiki - see README << VERIFY >> note).
  local MARKER_SLOTS = 8   -- plenty for a friends list this size; raise if needed
  local slotToKey = {}     -- slot (1..MARKER_SLOTS) -> friends/markers key, or nil if free
  local keyToSlot = {}     -- friends/markers key -> slot

  local function allocSlot(key)
    if keyToSlot[key] then return keyToSlot[key] end
    for slot = 1, MARKER_SLOTS do
      if not slotToKey[slot] then
        slotToKey[slot] = key
        keyToSlot[key] = slot
        return slot
      end
    end
    return nil   -- all slots taken - more than MARKER_SLOTS friends on-screen at once
  end

  local function freeSlot(key)
    local slot = keyToSlot[key]
    if slot then slotToKey[slot] = nil; keyToSlot[key] = nil end
  end

  -- Registers the fixed slot talk scripts on EVERY known map, ONCE, right
  -- here at entry-chunk time. This used to happen lazily from map.entered,
  -- which was a real bug: Concepts-Lifecycle is explicit that content
  -- registries (map_scripts included) FREEZE after the merge phase -
  -- "register/override/patch/remove raise from then on... Register content
  -- at entry-chunk time." Calling mod.content.map_scripts:register from a
  -- map.entered handler (Play phase, long after the freeze) raised every
  -- single time - silently, because it was wrapped in pcall - which is
  -- exactly why pressing A on a marker did nothing at all on either device.
  -- The fix: enumerate every real map via mod.content.maps:each() (vanilla
  -- map data is already imported before any mod's entry chunk runs, so
  -- this sees the whole game) and register all MARKER_SLOTS talk entries
  -- on all of them up front, while registration is still legal.
  local function registerAllMarkerTalkScripts()
    local talk = {}
    for slot = 1, MARKER_SLOTS do
      talk["TEXT_SILPHNET_MARKER_SLOT_" .. slot] = {
        { "push_screen", "SilphNetMarkerTalk", { slot = slot } },
      }
    end
    -- Two more fixed slots, same "register on every map up front, look up
    -- the live state at push time" mechanism as the friend-marker slots
    -- above - NOT a new registration mechanism, since content registries
    -- (map_scripts included) freeze after the merge phase (see the long
    -- comment above this function). Both screens read their content from
    -- module-level state (currentGymBadge/currentGymFriends,
    -- leagueLeaderboard) at push time, same as SilphNetMarkerTalk already
    -- does for slotToKey/friends - so this fixed registration never needs
    -- to change no matter which gym or how many leaderboard rows exist.
    talk["TEXT_SILPHNET_GYM_SIGN"] = { { "push_screen", "SilphNetGymSign", {} } }
    talk["TEXT_SILPHNET_LEAGUE_SIGN"] = { { "push_screen", "SilphNetLeagueSign", {} } }
    local count = 0
    local ok, err = pcall(function()
      for mapId in mod.content.maps:each() do
        local rok, rerr = pcall(function() mod.content.map_scripts:register(mapId, { talk = talk }) end)
        if rok then count = count + 1
        else mod.log:warn("SilphNet: map_scripts register failed for %s: %s", tostring(mapId), tostring(rerr)) end
      end
    end)
    if not ok then mod.log:warn("SilphNet: maps:each() failed: %s", tostring(err)) end
    mod.log:info("SilphNet: marker talk scripts registered on %d map(s)", count)
  end

  -- Must run HERE, synchronously, during entry-chunk execution - not from
  -- any event handler - per Concepts-Lifecycle's content-registry freeze.
  registerAllMarkerTalkScripts()

  -- ---- gym sign + league leaderboard sign (badge-mask constants) ----------
  -- Fixed bit position for every individual badge id, shared by BOTH gyms
  -- (bits 0-7, Kanto - same 8 ids on a Gen1 save and a Gen2 Kanto run) and
  -- Johto (bits 8-15, Gen2 only) - one flat 16-bit mask per account per
  -- game_version (see encodeBadgeMask below, badges_mask in schema.sql),
  -- NOT re-derived from the plain badge COUNT this file already tracks
  -- (countBadges) - a count alone can't answer "does this friend have
  -- THIS SPECIFIC badge", which is exactly what the gym sign needs to
  -- answer. Order here is arbitrary but must never change once shipped -
  -- every already-uploaded friend_stats.badges_mask row on the server
  -- was encoded against THIS exact bit order, so reordering these later
  -- would silently reinterpret every existing row as the wrong badges.
  local BADGE_BIT_INDEX = {
    BOULDERBADGE = 0, CASCADEBADGE = 1, THUNDERBADGE = 2, RAINBOWBADGE = 3,
    SOULBADGE = 4,    MARSHBADGE = 5,   VOLCANOBADGE = 6, EARTHBADGE = 7,
    ZEPHYRBADGE = 8,  HIVEBADGE = 9,    PLAINBADGE = 10,  FOGBADGE = 11,
    STORMBADGE = 12,  MINERALBADGE = 13, GLACIERBADGE = 14, RISINGBADGE = 15,
  }

  -- Reads one bit out of a mask int without the LuaJIT `bit` library -
  -- that library isn't confirmed on this project's mod-safe require
  -- allowlist (nothing elsewhere in this file uses it), so plain
  -- arithmetic is used instead: dividing out every lower bit and taking
  -- the result mod 2 isolates exactly the target bit, the same technique
  -- daysFromCivil below already relies on for its own integer math (this
  -- file avoids Lua 5.3+ operators like // throughout, per that
  -- function's own comment, for the same real on-device syntax-error
  -- reason).
  local function maskHasBit(mask, bit)
    mask = tonumber(mask) or 0
    if mask <= 0 then return false end
    return math.floor(mask / (2 ^ bit)) % 2 >= 1
  end

  -- Flat mapId -> badgeId table covering every gym across all three runs
  -- this mod supports (Gen1 Kanto, Gen2 Johto, Gen2 Kanto) - map ids never
  -- collide across generations/regions, so one flat table is enough; no
  -- coordinates of any kind live here (this project ships no ROM data -
  -- see findSafeSignTile below for how the actual sign placement is
  -- discovered at runtime instead of hardcoded). Gen2 Kanto reuses most
  -- Gen1 Kanto map ids verbatim (same physical gym, same badge) EXCEPT
  -- Blaine, who relocated to Seafoam Islands in Gen2 - CINNABAR_GYM and
  -- SEAFOAM_GYM therefore both map to VOLCANOBADGE and coexist here (one
  -- real gym per generation, same badge string, looked up by mapId so
  -- there's no ambiguity about which one a given player is standing in).
  local GYM_MAP_TO_BADGE = {
    -- Gen1 Kanto
    PEWTER_GYM = "BOULDERBADGE", CERULEAN_GYM = "CASCADEBADGE",
    VERMILION_GYM = "THUNDERBADGE", CELADON_GYM = "RAINBOWBADGE",
    FUCHSIA_GYM = "SOULBADGE", SAFFRON_GYM = "MARSHBADGE",
    CINNABAR_GYM = "VOLCANOBADGE", VIRIDIAN_GYM = "EARTHBADGE",
    -- Gen2 Johto
    VIOLET_GYM = "ZEPHYRBADGE", AZALEA_GYM = "HIVEBADGE",
    GOLDENROD_GYM = "PLAINBADGE", ECRUTEAK_GYM = "FOGBADGE",
    CIANWOOD_GYM = "STORMBADGE", OLIVINE_GYM = "MINERALBADGE",
    MAHOGANY_GYM = "GLACIERBADGE",
    BLACKTHORN_GYM_1F = "RISINGBADGE", BLACKTHORN_GYM_2F = "RISINGBADGE",
    -- Gen2 Kanto (second run - Blaine only, relocated to Seafoam)
    SEAFOAM_GYM = "VOLCANOBADGE",
  }

  -- Elite Four entrance - confirmed real via data/scripts/story6.lua in
  -- Gen1. Deliberately NOT guessing a Gen2-specific id for this same
  -- lobby (unconfirmed whether Gen2's build even reuses this exact
  -- constant) - the map.entered hook below registers unconditionally for
  -- every generation and the whole spawn attempt is wrapped in pcall, so
  -- on a build where this id doesn't exist at all the hook just never
  -- matches and silently does nothing, rather than this file guessing
  -- wrong and either erroring or (worse) silently mislabeling some other
  -- real Gen2 map as the league entrance.
  local LEAGUE_SIGN_MAP_ID = "INDIGO_PLATEAU_LOBBY"

  local pendingRequests = {}   -- array of { name, trainer_id } - incoming requests awaiting YOUR accept
  local addFriendStatus = ""   -- last add-friend result, shown briefly on the Add Friend screen
  local pendingRemoveFriend = nil   -- { account_id, name } set by SilphNetFriends just before pushing the confirm screen
  -- removeFriendState: idle|removing|done|failed - lets the confirm screen
  -- wait for the REAL server result before popping back to SilphNetFriends,
  -- rather than popping immediately on A and leaving the just-removed
  -- friend still visible for the brief window before the async HTTP result
  -- (and the fireFriendsFetch/firePendingFetch it triggers) actually comes
  -- back - which could read as "that didn't work."
  local removeFriendState = "idle"

  -- Friend detail screen state - set by SilphNetFriends right before
  -- pushing SilphNetFriendDetail, same "set state, then push" pattern as
  -- pendingRemoveFriend above. friendDetail holds the LAST successfully
  -- fetched detail payload for whichever friend is currently being viewed
  -- (stats/activity/presence, or nil fields if that friend has never
  -- uploaded any) - friendDetailState tracks the fetch itself so the
  -- screen can show LOADING... rather than a blank/stale page while the
  -- request is in flight.
  local pendingFriendDetail = nil    -- { account_id, name, game_version } set just before pushing
  local friendDetail = nil           -- { stats, activity, presence } from the last successful fetch
  local friendDetailState = "idle"   -- idle|loading|failed
  local friendDetailBusy = false

  local function sanitizeName(s)
    if not s or s == "" then return nil end
    s = tostring(s):gsub("[|;,\r\n]", ""):sub(1, 10)
    if s == "" then return nil end
    return s
  end

  -- No fallback to game.save.player.name (the trainer name given to Oak)
  -- here on purpose - an earlier version silently used it whenever MY
  -- NAME was left blank, which meant an account could get created under
  -- a name the player never actually chose or saw, with zero indication
  -- that had happened. A SilphNet name is always something the player
  -- deliberately typed into MY NAME, same as the password.
  local function resolveMyName()
    return sanitizeName(opt("name", ""))
  end

  -- game.save.version is confirmed real (see the comment above gameVersion's
  -- declaration) - "red"/"blue"/"yellow"/"gold"/"silver"/"crystal", always
  -- non-nil once a save exists (GameVersion.VERSIONS, confirmed directly
  -- against the engine's real src/core/GameVersion.lua as of the update
  -- that added Crystal - Gold and Silver are no longer Beta in the
  -- launcher, launcherName is just "Gold"/"Silver" there now; Crystal is
  -- the new one, launcherName = "Crystal (Beta)"). Uppercased to match
  -- this project's existing RED/BLUE/YELLOW/GOLD/SILVER/CRYSTAL/UNKNOWN
  -- convention (schema.sql, every server endpoint's validation list).
  -- CRYSTAL is sent as-is, not collapsed to UNKNOWN, the same way
  -- GOLD/SILVER were added previously - see isGen2(), countBadges(), and
  -- readStatsSnapshot() below for the real save-shape a Gen 2 save needs
  -- handled (money/badges/pokedex.caught/hallOfFame all live somewhere
  -- different there). Falls back to UNKNOWN (not an error) if game.save
  -- isn't ready yet or version is missing entirely - shouldn't happen per
  -- the guaranteed-migration confirmation, but this function runs at
  -- game.ready, right as save loading finishes, so a defensive fallback
  -- costs nothing.
  local function resolveGameVersion()
    local v = game and game.save and game.save.version
    if type(v) ~= "string" then return "UNKNOWN" end
    v = v:upper()
    if v == "RED" or v == "BLUE" or v == "YELLOW" or v == "GOLD" or v == "SILVER" or v == "CRYSTAL" then return v end
    return "UNKNOWN"
  end

  -- Gen 2 (Gold/Silver/Crystal) save shape differs from Gen 1 in exactly the
  -- ways documented below - confirmed directly against the engine's real
  -- src/core/gen2/Save.lua, not guessed by analogy (this project has been
  -- burned by that before - see readStatsSnapshot's money comment). Crystal
  -- shares this SAME Save.lua module with Gold/Silver - money, badges,
  -- pokedex, and hallOfFame are read identically for all three; Crystal's
  -- own extras (save.crystal, save.battleTower) are separate fields this
  -- mod has no reason to touch, confirmed by reading that module directly
  -- rather than assuming Crystal needed its own branch here. This is a
  -- legitimate per-cart-CONTENT check (the save's actual field layout
  -- genuinely differs from Gen 1), not the "version allow-list as a
  -- feature gate" anti-pattern docs/preparing-your-mod-for-gen2.md warns
  -- against - every other read in this file (party, playTime,
  -- pokedex.seen, presence/friends/markers, every event) is already
  -- generation-agnostic and untouched.
  local function isGen2(version)
    return version == "GOLD" or version == "SILVER" or version == "CRYSTAL"
  end

  -- ---- HTTP plumbing ------------------------------------------------------
  -- SYNCHRONOUS as of this version - a Gen1Recomp engine update fully and
  -- permanently blocked love.thread from mod code (confirmed directly
  -- against the engine's real sandbox source, src/mods/Sandbox.lua:
  -- BLOCKED_LOVE.thread = true, with the comment "value is the replacement
  -- to name in the error, or true when there is none" - i.e. no facade, no
  -- workaround, by design, since "a LÖVE thread runs in a separate Lua
  -- state... which the sandbox in this state cannot reach, so a stand-in
  -- would be a hole rather than a reroute"). The previous version of this
  -- file ran every request on its own short-lived love.thread precisely so
  -- a slow/hanging request could never freeze the game - that approach is
  -- now impossible, not just harder.
  --
  -- What's NOT blocked: require("socket.http") itself still works directly
  -- on the main thread, gated by the same "network" permission this
  -- manifest.json already declares (Sandbox.lua's NETWORK table lists
  -- socket/http/etc., checked against permissionSet.network - nothing
  -- about that check requires a thread). So every request in this file now
  -- calls http.request(...) directly and blocks until it returns, instead
  -- of firing a thread and polling a channel for the result.
  --
  -- Real, unavoidable consequence: the game visibly pauses for the
  -- duration of every request (login, ping, friends fetch, add-friend,
  -- ...), not just a network hiccup on a background thread. HTTP_TIMEOUT
  -- is deliberately cut from the old 8s down to 2.5s specifically because
  -- of this - a normal fast response (the common case, usually well under
  -- 1s) still feels instant, but a genuinely slow or unreachable server
  -- now caps the worst-case freeze at 2.5s instead of a much longer one.
  -- socket.http.request's own connect+read timeout (http.TIMEOUT) is what
  -- actually enforces this bound; nothing here can time out a call that
  -- library doesn't itself give up on.
  local HTTP_TIMEOUT_SECONDS = 2.5

  -- Every result is still shaped exactly like the old thread-channel
  -- payload ("tag|status|body") and still consumed by the same
  -- drainHttpResults()/tag-dispatch logic further down, completely
  -- unchanged - only HOW a result gets produced changed (synchronously,
  -- right here, instead of asynchronously via a separate Lua state), so
  -- every call site and every screen's busy-flag/tag handling below needed
  -- no changes at all. HTTP_RESULT is now a plain local queue (a Lua
  -- array used FIFO) instead of a love.thread channel - pop() mirrors a
  -- channel's :pop() (returns nil, not blocks, when empty).
  local HTTP_RESULT = {}
  local function httpResultPop()
    return table.remove(HTTP_RESULT, 1)
  end

  -- Tiny hand-rolled querystring encoder - avoids a JSON/urlencode lib for
  -- a handful of known, already-sanitized fields.
  local function urlencode(s)
    return (tostring(s):gsub("[^%w%-%.%_%~]", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end

  local function encodeForm(fields)
    local parts = {}
    for k, v in pairs(fields) do
      parts[#parts + 1] = urlencode(k) .. "=" .. urlencode(tostring(v))
    end
    return table.concat(parts, "&")
  end

  -- Fires the actual request right now, synchronously, and pushes exactly
  -- one "tag|status|body" string onto HTTP_RESULT - the same format the
  -- old thread source used to push, so drainHttpResults doesn't need to
  -- know or care that this is no longer async under the hood. socket.http
  -- itself is required fresh on first use (pcall-guarded, same defensive
  -- style the old thread source used) rather than at file scope, in case
  -- the "network" permission is ever missing from manifest.json - that
  -- failure now surfaces as a normal ERR result through the usual
  -- tag-dispatch path instead of a raw require() error.
  local function runHttpRequest(tag, url, body)
    local ok, http = pcall(require, "socket.http")
    if not ok then
      table.insert(HTTP_RESULT, tag .. "|ERR|socket.http unavailable")
      return
    end
    http.TIMEOUT = HTTP_TIMEOUT_SECONDS
    local respBody, code = http.request(url, body)
    if not respBody then
      table.insert(HTTP_RESULT, tag .. "|ERR|" .. tostring(code))
    else
      table.insert(HTTP_RESULT, tag .. "|OK|" .. respBody)
    end
  end

  -- tag identifies which request a result belongs to when it comes back
  -- (login/register/ping/friends can all be "in flight" independently, in
  -- the sense of being distinguishable results in the queue - not actually
  -- concurrent anymore, since there's only the one main thread now).
  --
  -- httpPost stays fully synchronous, unconditionally, forever - this is
  -- the ONLY request shape allowed to carry a password (login.php/
  -- register.php) or a bare session token with nothing else sensitive
  -- attached (login_token.php), and mod.fetch (see below) is GET-only, so
  -- there is no async path for these three even once mod.fetch is
  -- available. A password must never appear in a URL/server log.
  local function httpPost(tag, path, fields)
    runHttpRequest(tag, API_BASE .. path, encodeForm(fields))
  end
  local function httpGet(tag, path, query)
    runHttpRequest(tag, API_BASE .. path .. "?" .. encodeForm(query))
  end

  -- ---- async fetch layer (mod.fetch) ---------------------------------------
  -- mod.fetch is a real, documented async-HTTP replacement for the
  -- love.thread capability blocked above (confirmed directly against
  -- docs/modding.md and the engine's own src/mods/Net.lua): mod.fetch:get
  -- returns a handle immediately, mod.fetch:poll(handle) never blocks, and
  -- its workers run ENGINE code, not the mod's, so this grants asynchrony
  -- without the reach love.thread would have. GET-only, http/https-only,
  -- and capped at 4 requests in flight PER MOD (Net.MAX_INFLIGHT) - a real
  -- ceiling shared with the launcher's own downloads, not just a courtesy
  -- limit, so going over it returns nil/a reason rather than queuing for you.
  --
  -- This whole layer is a pure enhancement: on a build/permission set
  -- without it (mod.fetch nil, or :available() false - e.g. no "network"
  -- permission, or an older engine build), httpAsyncGet below falls
  -- straight back to the old synchronous runHttpRequest path, so every
  -- endpoint still works exactly as before, just with the visible pause it
  -- always had.
  local FETCH_MAX_INFLIGHT = 4   -- mirrors Net.MAX_INFLIGHT (not itself queryable from mod code)

  local fetchAvailable = nil   -- nil = not probed yet; true/false once known
  local function isFetchAvailable()
    if fetchAvailable ~= nil then return fetchAvailable end
    local ok, avail = pcall(function() return mod.fetch and mod.fetch:available() end)
    fetchAvailable = (ok and avail == true)
    return fetchAvailable
  end

  local activeFetches = {}      -- handle -> tag, one entry per in-flight job
  local activeFetchCount = 0
  local fetchQueue = {}         -- array of { tag, url } waiting for a free inflight slot

  -- Drains fetchQueue into real mod.fetch:get() calls until either the
  -- queue is empty or the 4-in-flight ceiling is hit. pumpPresenceTimer
  -- alone can produce 5 simultaneous requests (ping+friends+pending+
  -- online_count+nearby) against that 4 ceiling, so the 5th deliberately
  -- waits here rather than being dropped - it's tried again the very next
  -- poll once any one of the other four completes and frees a slot,
  -- following this project's established "never silently lose a request"
  -- discipline (see pendingActivityQueue above).
  local function submitNextQueued()
    while activeFetchCount < FETCH_MAX_INFLIGHT and #fetchQueue > 0 do
      local item = fetchQueue[1]
      local ok, handle, reason = pcall(function()
        return mod.fetch:get(item.url, { maxSeconds = HTTP_TIMEOUT_SECONDS })
      end)
      if ok and handle then
        table.remove(fetchQueue, 1)
        activeFetches[handle] = item.tag
        activeFetchCount = activeFetchCount + 1
      else
        -- Ceiling hit (nil handle) or a genuine error (pcall failed) -
        -- either way, stop trying THIS poll and leave the item at the
        -- front of the queue for the next one. Logged once per failed
        -- attempt rather than silently, but not popped, so it's never lost.
        if not ok then mod.log:warn("SilphNet: mod.fetch:get failed: %s", tostring(handle)) end
        break
      end
    end
  end

  -- Polls every currently in-flight handle exactly once, pushing a
  -- "tag|OK|body" or "tag|ERR|reason" string onto the SAME HTTP_RESULT
  -- queue runHttpRequest already uses - drainHttpResults' tag-dispatch
  -- logic doesn't need to know or care whether a given result came from
  -- the synchronous path or from here. Never blocks (mod.fetch:poll is
  -- documented as non-blocking), safe to call every frame.
  local function pollFetches()
    for handle, tag in pairs(activeFetches) do
      local ok, result = pcall(function() return mod.fetch:poll(handle) end)
      if ok and type(result) == "table" and result.status ~= "pending" then
        activeFetches[handle] = nil
        activeFetchCount = activeFetchCount - 1
        if result.status == "ok" then
          table.insert(HTTP_RESULT, tag .. "|OK|" .. tostring(result.body or ""))
        else
          table.insert(HTTP_RESULT, tag .. "|ERR|" .. tostring(result.err or result.status or "fetch error"))
        end
        pcall(function() mod.fetch:release(handle) end)
      elseif not ok then
        -- A forged/foreign/unknown handle polls as an error per
        -- docs/modding.md - shouldn't happen for a handle this mod itself
        -- just got back from mod.fetch:get, but treated as a failed
        -- request (not a silent drop, not an infinite retry) if it ever does.
        activeFetches[handle] = nil
        activeFetchCount = activeFetchCount - 1
        table.insert(HTTP_RESULT, tag .. "|ERR|fetch poll failed")
      end
    end
    submitNextQueued()
  end

  -- The async-when-available GET request every endpoint EXCEPT login/
  -- register/login_token should use. Always GET+querystring shaped (never
  -- POST) since mod.fetch itself is GET-only - see the field-list comments
  -- on each fire* function below for exactly what each endpoint's PHP side
  -- now also accepts via $_GET (see server/web/api/*.php).
  local function httpAsyncGet(tag, path, query)
    local url = API_BASE .. path .. "?" .. encodeForm(query)
    if isFetchAvailable() then
      table.insert(fetchQueue, { tag = tag, url = url })
      submitNextQueued()
    else
      runHttpRequest(tag, url)   -- nil body => GET, same as the old httpGet
    end
  end

  -- Minimal hand-rolled JSON reader for exactly the shapes these five
  -- endpoints return - not a general JSON parser, just enough to pull
  -- flat string/number fields out of a known, server-controlled response,
  -- without adding a JSON dependency.
  local function jsonField(body, key)
    local s = string.match(body, '"' .. key .. '"%s*:%s*"([^"]*)"')
    if s then return s end
    local n = string.match(body, '"' .. key .. '"%s*:%s*(-?%d+%.?%d*)')
    return n
  end
  local function jsonIsOk(body) return string.match(body, '"ok"%s*:%s*true') ~= nil end

  -- Splits out each flat {...} object in a JSON array response into a Lua
  -- table of field->value pairs (all as strings - callers tonumber() what
  -- they need). Not a general JSON parser; good enough for these known,
  -- server-controlled response shapes.
  --
  -- Scans ONLY inside the first [...] array in the body, not the whole
  -- response - every caller's response shape is a wrapper object like
  -- {"ok":true,"friends":[...]} or {"ok":true,"requests":[...]}, and that
  -- OUTER object is itself a %{[^{}]-%} match. When the array is genuinely
  -- empty ([]), scanning the whole body previously matched the wrapper
  -- object itself as if it were a record, pulling out {ok = "true"} as a
  -- single bogus entry with no name/trainer_id fields - which is exactly
  -- what showed up as a phantom "REQUESTS 1" with a "?" name and "-----"
  -- Trainer ID after every real pending row had been deleted, and why
  -- pressing A on it silently did nothing (req.name was nil, failing the
  -- "if req and req.name" guard on the requests screen). Restricting the
  -- scan to between the array's [ and ] means an empty array correctly
  -- yields zero records instead of one fake one.
  -- Shared flat-record extraction, pulled out of parseObjects so it can
  -- also be reused by parseLeagueLeaderboardJson below on an array body
  -- that's already been located by name (rather than "the first [...]
  -- in the whole response", which is all parseObjects itself can find -
  -- see that function's own comment). Behaviour is unchanged from before
  -- this was split out - parseObjects still does exactly what it always
  -- did, just via this shared helper now.
  local function objectsFromArrayBody(arrayBody)
    local out = {}
    if not arrayBody then return out end
    for obj in string.gmatch(arrayBody, "%{[^{}]-%}") do
      local rec = {}
      for k, v in string.gmatch(obj, '"([%w_]+)"%s*:%s*"?([^",}]*)"?') do
        rec[k] = v
      end
      out[#out + 1] = rec
    end
    return out
  end

  local function parseObjects(body)
    return objectsFromArrayBody(string.match(body, "%[(.-)%]"))
  end

  -- league_leaderboard.php's response has TWO top-level flat-object
  -- arrays ("all" and "friends"), unlike every other endpoint parseObjects
  -- already covers (which only ever have one) - parseObjects itself only
  -- ever scans the FIRST [...] in a body, so reusing it directly here
  -- would silently read "all" twice and never see "friends" at all.
  -- Each array is located by name first (both are simple flat-object
  -- arrays with no further nesting, unlike friend_detail's per-entry
  -- sub-objects, so no brace-depth walk is needed here), then handed to
  -- the same flat-record extraction parseObjects itself uses via
  -- objectsFromArrayBody. The anchor after each array ("," for the one
  -- followed by another field, "}" + end-of-string for the last one)
  -- mirrors the exact same anchoring online_by_version's parsing already
  -- relies on to find ITS array boundary correctly.
  local function parseLeagueLeaderboardJson(body)
    local allBody = string.match(body, '"all"%s*:%s*%[(.-)%]%s*,%s*"friends"')
    local friendsBody = string.match(body, '"friends"%s*:%s*%[(.-)%]%s*}%s*$')
    return objectsFromArrayBody(allBody), objectsFromArrayBody(friendsBody)
  end

  -- Keyed by "account_id|game_version", not just account_id - a friend can
  -- have more than one active save (Red/Blue/Yellow), each pinging its own
  -- presence row (see ping.php/schema.sql's UNIQUE KEY (account_id,
  -- game_version)). Keying by account_id alone would let a later row for
  -- the same friend silently overwrite an earlier one here, hiding whichever
  -- version wasn't played most recently - this key keeps every version's
  -- last-known position visible instead of dropping all but the latest.
  local function parseFriendsJson(body)
    local out = {}
    for _, rec in ipairs(parseObjects(body)) do
      if rec.account_id then
        local key = rec.account_id .. "|" .. tostring(rec.game_version or "UNKNOWN")
        out[key] = rec
      end
    end
    return out
  end

  -- How many DISTINCT game_versions the friends list currently has ANY
  -- row for, for a given friend's account_id - used to decide whether the
  -- friends list should bother showing a version label at all (see
  -- SilphNetFriends' pageLabel). A friend with only one active version
  -- gets no "(BLUE)" clutter, since there's nothing to disambiguate; this
  -- only matters once a friend has genuinely played more than one
  -- version (e.g. finished a BLUE run, started a fresh YELLOW one).
  -- Recomputed on the fly rather than cached - `friends` itself is small
  -- (bounded by how many friends one account realistically has) and
  -- already fully rebuilt on every fireFriendsFetch response, so caching
  -- this separately would just be another thing to keep in sync for no
  -- real benefit.
  local function countFriendVersions(accountId)
    local seen = {}
    local n = 0
    for _, f in pairs(friends) do
      if f.account_id == accountId and not seen[f.game_version] then
        seen[f.game_version] = true
        n = n + 1
      end
    end
    return n
  end

  -- Deduped-by-account_id list of accepted friends' display names who
  -- have earned a specific badge, for the gym sign talk screen. `friends`
  -- is already accepted-only (friends.php filters status="accepted"
  -- server-side) and already keyed "account_id|game_version", so a
  -- friend with more than one active save can appear more than once here
  -- if left unchecked - deduped by account_id so someone who earned a
  -- badge on ANY one of their saves is listed exactly once, not once per
  -- save. badges_mask arrives from friends.php as a string (parseObjects
  -- reads every field as a string - see that function's own comment), so
  -- tonumber() here before maskHasBit, same as every other numeric field
  -- read out of a parsed HTTP response elsewhere in this file. Sorted
  -- alphabetically for a stable, predictable read order on the sign
  -- (rather than "whatever order the friends table happens to iterate
  -- in", which pairs() never guarantees).
  local function friendsWithBadge(badgeId)
    local bit = badgeId and BADGE_BIT_INDEX[badgeId]
    local names = {}
    if not bit then return names end
    local seen = {}
    for _, f in pairs(friends) do
      if f.account_id and not seen[f.account_id] then
        if maskHasBit(tonumber(f.badges_mask), bit) then
          seen[f.account_id] = true
          names[#names + 1] = f.name or "?"
        end
      end
    end
    table.sort(names)
    return names
  end

  -- ---- auth ---------------------------------------------------------------
  -- Same in-game NAME + PASSWORD fields as before; behind the scenes this
  -- now hits the web API instead of a game server. A cached session token
  -- (mod.save) skips retyping on every launch, same role the old device
  -- token played - see login_token.php.
  local function beginAuth()
    myName = resolveMyName()
    myPass = opt("password", "") or ""
    if not myName then
      authState = "need_creds"
      mod.log:warn("set MY NAME (and PASSWORD) in SilphNet options")
      return
    end

    local token = mod.save:get("token")
    authBusy = true
    if token then
      authState = "logging_in"
      httpPost("tok", "/login_token.php", { token = token })
    elseif myPass ~= "" then
      authState = "logging_in"
      httpPost("login", "/login.php", { name = myName, password = myPass })
    else
      authBusy = false
      authState = "need_creds"
      mod.log:warn("set a PASSWORD in SilphNet options to log in")
    end
  end

  local function doRegister()
    authBusy = true
    authState = "logging_in"
    httpPost("register", "/register.php", { name = myName, password = myPass })
  end

  -- Forward-declared: onAuthOk (right below) and handleHttpResult (further
  -- down) both need to trigger a fresh friends/pending fetch, but those
  -- functions live in the "presence" section further down still. Declaring
  -- the locals here, above BOTH callers, and assigning the real function
  -- bodies later keeps every closure correctly bound to the SAME locals
  -- (not globals) once they're assigned - the exact bug class that bit an
  -- earlier version of this file when a function was defined before the
  -- locals it referenced existed at all (caught via a lupa test harness).
  -- onAuthOk was added as a second caller after this comment was written,
  -- and initially called these two functions from ABOVE this declaration -
  -- silently closing over globals instead, the very bug this paragraph
  -- warns about. Moving the declaration up here (above both callers) is
  -- the actual fix; onAuthOk itself was never touched again.
  --
  -- drainHttpResults joined this forward-declaration for the exact same
  -- reason, caught the exact same way (checking every caller's line number
  -- against this declaration's) before it ever shipped: several screens
  -- (SilphNetStatus, SilphNetAddFriend, SilphNetRemoveFriendConfirm,
  -- SilphNetRequests) call it from their own update(dt) and are registered
  -- further down but still BEFORE drainHttpResults' real body was originally
  -- defined - which would have silently captured a nil global exactly like
  -- onAuthOk did, made worse by every call site wrapping it in pcall(), so
  -- it would have failed completely silently with no error ever logged.
  local fireFriendsFetch, firePendingFetch, drainHttpResults, fireOnlineCountFetch, fireNearbyFetch
  local fireLeagueLeaderboardFetch   -- same forward-declare reasoning as the line above - see the comment there
  local fireFriendDetailFetch, fireStatsUpload, fireOnlineByVersionFetch

  local function onAuthOk(accId, name, token, trainerId)
    accountId, myName = accId, name or myName
    if trainerId then myTrainerId = trainerId end
    authState, authBusy = "authed", false
    if token then pcall(function() mod.save:set("token", token) end) end
    mod.log:info("SilphNet: logged in as %s", tostring(myName))
    -- Fire both fetches immediately on login rather than waiting for the
    -- next 30s pump tick - previously a freshly-logged-in player could see
    -- FRIENDS 0 / REQUESTS 0 for up to PRESENCE_INTERVAL seconds even when
    -- the server already had real data, which looked like a bug (and did
    -- hide a real pending request from a friend who'd just registered).
    if not friendsBusy then fireFriendsFetch() end
    if not pendingBusy then firePendingFetch() end
  end

  local function handleHttpResult(tag, status, body)
    if tag == "tok" then
      authBusy = false
      if status == "OK" and jsonIsOk(body) then
        onAuthOk(jsonField(body, "account_id"), jsonField(body, "name"), nil, jsonField(body, "trainer_id"))
      else
        -- Cached token no longer valid - fall through to a real login if
        -- we have a password, otherwise ask for credentials.
        pcall(function() mod.save:set("token", nil) end)
        if myPass and myPass ~= "" then
          authBusy = true
          authState = "logging_in"
          httpPost("login", "/login.php", { name = myName, password = myPass })
        else
          authState = "need_creds"
          mod.log:warn("SilphNet: saved login expired - set PASSWORD to log in again")
        end
      end
    elseif tag == "login" then
      if status == "OK" and jsonIsOk(body) then
        authBusy = false
        onAuthOk(jsonField(body, "account_id"), myName, jsonField(body, "token"), jsonField(body, "trainer_id"))
      elseif status == "OK" then
        -- Valid HTTP response but ok:false - most likely "wrong name or
        -- password" for a name that doesn't exist yet. Rather than
        -- silently auto-creating an account here (the old behaviour - a
        -- real account, password, and Trainer ID could get created
        -- without the player ever seeing or confirming it happened),
        -- stop and show a confirmation screen; registration only
        -- actually fires if the player presses A on it.
        authBusy = false
        authState = "confirm_register"
      else
        authBusy = false
        authState = "failed"
        mod.log:warn("SilphNet: login request failed: %s", tostring(body))
      end
    elseif tag == "register" then
      authBusy = false
      if status == "OK" and jsonIsOk(body) then
        onAuthOk(jsonField(body, "account_id"), myName, jsonField(body, "token"), jsonField(body, "trainer_id"))
      else
        authState = "failed"
        mod.log:warn("SilphNet: register failed: %s", tostring(body))
      end
    elseif tag == "add_friend" then
      if status == "OK" and jsonIsOk(body) then
        -- "REQUEST SENT TO " alone is already 16 characters - the exact
        -- draw-time truncation budget (addFriendStatus:sub(1, 16)) - so
        -- appending any name here was ALWAYS going to get cut off entirely
        -- before a single character of it could show, no matter who was
        -- added. Ash's son saw exactly this: "REQUEST T" truncated further
        -- still by the in-game font row width. "SENT TO " (8 chars) leaves
        -- real room for names up to 8 characters before truncation kicks
        -- in again.
        addFriendStatus = "SENT TO " .. tostring(jsonField(body, "name"))
      else
        local err = jsonField(body, "error") or "FAILED"
        addFriendStatus = "ERROR: " .. tostring(err):upper()
      end
    elseif tag == "accept_friend" then
      if status == "OK" and jsonIsOk(body) then
        mod.log:info("SilphNet: friend request accepted")
      else
        mod.log:warn("SilphNet: accept failed: %s", tostring(body))
      end
      fireFriendsFetch()
      firePendingFetch()
    elseif tag == "remove_friend" then
      if status == "OK" and jsonIsOk(body) then
        mod.log:info("SilphNet: friend removed")
        removeFriendState = "done"
      else
        mod.log:warn("SilphNet: remove failed: %s", tostring(body))
        removeFriendState = "failed"
      end
      -- Re-fetch regardless of success/failure, same as accept_friend -
      -- if it actually succeeded server-side but the response got lost,
      -- this still leaves the client showing the true current state.
      fireFriendsFetch()
      firePendingFetch()
    end
  end

  -- ---- presence -----------------------------------------------------------
  local sincePresence = PRESENCE_INTERVAL   -- fire shortly after login, not immediately
  local presenceBusy   = false
  local friendsBusy     = false
  local pendingBusy      = false
  local onlineCountBusy   = false
  local nearbyBusy         = false
  local onlineByVersionBusy = false
  local statsUploadBusy     = false
  local statsUploadActivitySent = nil   -- the activity string currently in flight, or nil - see fireStatsUpload/drainHttpResults
  local sinceStats = 0            -- separate, slower cycle than PRESENCE_INTERVAL - see STATS_INTERVAL
  local STATS_INTERVAL = 180.0    -- 3 min - badges/dex/money/league wins don't need 30s freshness
  local leagueLeaderboardBusy = false   -- on-demand only, see fireLeagueLeaderboardFetch

  -- VANILLA fallback list, same 8 badges/order as the engine's own
  -- src/inventory/Badges.lua - only used if constants.badges is somehow
  -- empty/missing, exactly mirroring that module's own fallback behaviour
  -- (confirmed by reading Badges.lua directly - Badges.count() itself
  -- isn't on the mod-safe require allowlist, so this is a faithful
  -- reimplementation of its logic, not a guess: it walks constants.badges
  -- (or this fallback), resolves each entry's item id via entry.item or
  -- entry.id, and checks save.inventory[itemId] truthiness - identical to
  -- what the engine's own continue-screen code does).
  local VANILLA_BADGES = {
    { id = "BOULDERBADGE" }, { id = "CASCADEBADGE" }, { id = "THUNDERBADGE" },
    { id = "RAINBOWBADGE" }, { id = "SOULBADGE" },    { id = "MARSHBADGE" },
    { id = "VOLCANOBADGE" }, { id = "EARTHBADGE" },
  }
  local function countGen1Badges()
    local ok, list = pcall(function() return mod.content.constants:get("badges") end)
    if not ok or type(list) ~= "table" or #list == 0 then list = VANILLA_BADGES end
    local inv = game and game.save and game.save.inventory
    if not inv then return 0 end
    local n = 0
    for _, entry in ipairs(list) do
      if inv[entry.item or entry.id] then n = n + 1 end
    end
    return n
  end

  -- Gen 2 badges are NOT badge items in save.inventory at all - confirmed
  -- directly against src/core/gen2/Save.lua: "a Gen 2 slot carries no
  -- badge items" (the same comment SaveData.slotSummary uses to justify
  -- reading badges this exact way for its own launcher summary). Instead
  -- they're two separate boolean sets on save.player: save.player.badges
  -- (8 Johto badges) and save.player.kantoBadges (8 Kanto badges), summing
  -- to up to 16 - matching Continue_DisplayBadgeCount's real two-byte walk
  -- (engine/menus/intro_menu.asm:461-469). The Gen 1 constants.badges/
  -- inventory approach above genuinely does not apply here, not just as a
  -- fallback - this is a real second counting mechanism, not a guess.
  local function countGen2Badges()
    local p = game and game.save and game.save.player
    if type(p) ~= "table" then return 0 end
    local n = 0
    if type(p.badges) == "table" then
      for _, has in pairs(p.badges) do if has then n = n + 1 end end
    end
    if type(p.kantoBadges) == "table" then
      for _, has in pairs(p.kantoBadges) do if has then n = n + 1 end end
    end
    return n
  end

  local function countBadges()
    if isGen2(gameVersion) then return countGen2Badges() end
    return countGen1Badges()
  end

  -- Encodes WHICH specific badges this save has into one 16-bit mask (see
  -- BADGE_BIT_INDEX above) - a new function alongside countGen1Badges/
  -- countGen2Badges rather than a change to either, since those two are
  -- already relied on elsewhere for the plain BADGES count display and
  -- this needs to run alongside that, not replace it.
  --
  -- Gen1 branch reuses the EXACT SAME enumeration/lookup mechanism as
  -- countGen1Badges (constants.badges, or VANILLA_BADGES as a fallback;
  -- save.inventory[entry.item or entry.id] truthiness) - only Kanto
  -- badges ever apply on a Gen1 save (there is no Johto in Gen1), so
  -- every id this loop can find already falls in bits 0-7.
  --
  -- Gen2 branch reads the two real boolean sets directly off save.player
  -- (kantoBadges for bits 0-7, badges for bits 8-15) - the same two
  -- fields countGen2Badges already reads, confirmed directly against
  -- src/core/gen2/Save.lua (see that function's own comment for the
  -- full citation) - just keyed here by the specific badge id instead of
  -- merely counted.
  local function encodeBadgeMask()
    local mask = 0
    if isGen2(gameVersion) then
      local p = game and game.save and game.save.player
      if type(p) == "table" then
        if type(p.kantoBadges) == "table" then
          for id, bit in pairs(BADGE_BIT_INDEX) do
            if bit <= 7 and p.kantoBadges[id] then mask = mask + (2 ^ bit) end
          end
        end
        if type(p.badges) == "table" then
          for id, bit in pairs(BADGE_BIT_INDEX) do
            if bit >= 8 and p.badges[id] then mask = mask + (2 ^ bit) end
          end
        end
      end
    else
      local ok, list = pcall(function() return mod.content.constants:get("badges") end)
      if not ok or type(list) ~= "table" or #list == 0 then list = VANILLA_BADGES end
      local inv = game and game.save and game.save.inventory
      if inv then
        for _, entry in ipairs(list) do
          local id = entry.id
          local bit = id and BADGE_BIT_INDEX[id]
          if bit and inv[entry.item or entry.id] then mask = mask + (2 ^ bit) end
        end
      end
    end
    return mask
  end

  -- Reads everything the stats snapshot needs from game.save directly -
  -- see research/gen1-save-format-findings.md for how each field was
  -- confirmed. playTime isn't read here (not shown on the detail screen),
  -- but pokedex/hallOfFame/money/badges all are.
  -- save.playTime has TWO possible shapes, per research/gen1-save-format-
  -- findings.md: a plain seconds count (this engine's own Gen 1 saves),
  -- OR a { hours, minutes, seconds, frames } table (their Gen 2/Gold
  -- saves) - the engine's own code checks type(pt) == "table" before
  -- deciding how to read it, and this does the same rather than assuming
  -- one shape. Normalized to a single total-seconds integer here (not
  -- uploaded as a table) so friend_stats can store it as one plain
  -- column and every consumer (this function's caller, stats.php,
  -- SilphNetFriendDetail's draw) only ever deals with one shape. Frames
  -- are dropped (sub-second precision isn't meaningful to show a
  -- friend) rather than rounded into seconds, to avoid ever
  -- overstating play time by a fraction.
  local function readPlaySeconds()
    local pt = game and game.save and game.save.playTime
    if type(pt) == "table" then
      return (tonumber(pt.hours) or 0) * 3600 + (tonumber(pt.minutes) or 0) * 60 + (tonumber(pt.seconds) or 0)
    end
    return tonumber(pt) or 0
  end

  -- Encodes up to 6 party mons into ONE delimited string, following this
  -- project's established "no JSON library available" convention (same
  -- reasoning as activity's "\n"-joined two-line messages) rather than a
  -- JSON-shaped payload. Per-mon fields are comma-joined; mons themselves
  -- are semicolon-joined; a mon's moves are pipe-joined (a mon can have
  -- fewer than 4 moves, so this can't just be a fixed-count comma slot).
  -- Field order per mon: SPECIES,LEVEL,HP,MAXHP,MOVES - e.g.
  -- "BLASTOISE,64,145,168,HYDRO PUMP|BITE|SURF|ICE BEAM".
  --
  -- Field names confirmed directly from engine source (src/pokemon/
  -- Stats.lua, src/core/SaveData.lua), not guessed by analogy (this
  -- project has been burned by that before - see readStatsSnapshot's
  -- money comment): mon.hp is CURRENT hp (a top-level field, clamped to
  -- mon.stats.hp if stale/missing), mon.stats.hp is the CALCULATED MAX hp
  -- - there is no separate mon.maxHp field. mon.species and each
  -- mon.moves[i] (or mon.moves[i].id, if a mon happens to use the
  -- {id,pp} move-slot shape rather than a bare id - both are handled
  -- here) are already-resolved string ids, same as everywhere else in
  -- this file, so no lookup table is needed to turn either into display
  -- text.
  --
  -- Commas/semicolons/pipes can't appear in any real species or move
  -- name (all-caps, spaces and hyphens only, e.g. "DOUBLE-EDGE",
  -- "HYPER BEAM"), so none of these delimiters risk colliding with real
  -- field content - no escaping needed.
  local function encodePartySnapshot()
    local save = game and game.save
    if not save or type(save.party) ~= "table" then return "" end
    local out = {}
    for i, mon in ipairs(save.party) do
      if i > 6 then break end   -- real games cap parties at 6; defensive, not expected to ever trigger
      local species = tostring(mon.species or "?"):upper()
      local level = tonumber(mon.level) or 0
      local maxHp = (type(mon.stats) == "table" and tonumber(mon.stats.hp)) or 0
      local hp = tonumber(mon.hp)
      if not hp then hp = maxHp end   -- mirrors Stats.ensure's own clamp-to-max fallback for a missing/stale value
      local moveNames = {}
      if type(mon.moves) == "table" then
        for _, mv in ipairs(mon.moves) do
          local id = (type(mv) == "table") and mv.id or mv
          if id then moveNames[#moveNames + 1] = tostring(id):upper() end
        end
      end
      out[#out + 1] = table.concat({
        species, tostring(level), tostring(hp), tostring(maxHp), table.concat(moveNames, "|"),
      }, ",")
    end
    return table.concat(out, ";")
  end

  -- Decodes encodePartySnapshot's string format back into an array of
  -- { species, level, hp, maxHp, moves = {...} } - used client-side when
  -- drawing a FRIEND's party (the string this function receives comes
  -- back from friend_detail.php exactly as encodePartySnapshot produced
  -- it, unmodified server-side - see stats.php/friend_detail.php).
  local function decodePartySnapshot(str)
    local out = {}
    if type(str) ~= "string" or str == "" then return out end
    for monStr in string.gmatch(str, "([^;]+)") do
      local species, level, hp, maxHp, movesStr = string.match(monStr, "^([^,]*),([^,]*),([^,]*),([^,]*),(.*)$")
      if species then
        local moves = {}
        for mv in string.gmatch(movesStr or "", "([^|]+)") do moves[#moves + 1] = mv end
        out[#out + 1] = {
          species = species, level = tonumber(level) or 0,
          hp = tonumber(hp) or 0, maxHp = tonumber(maxHp) or 0, moves = moves,
        }
      end
    end
    return out
  end

  -- Gen 2 introduces gendered species variants whose ids spell the gender
  -- out in full - "OINKOLOGNE_FEMALE", "OINKOLOGNE_MALE" - rather than
  -- Gen 1's existing short "_M"/"_F" convention (NIDORAN_M/NIDORAN_F,
  -- which already fit every screen's budget and are left exactly as-is
  -- here, per direct request - the pattern below only matches a literal
  -- "_MALE"/"_FEMALE" suffix, not a bare "_M"/"_F" one, so Gen 1 species
  -- are genuinely untouched, not just coincidentally unaffected). A full
  -- "_FEMALE"/"_MALE" suffix can push a species name past the 16-char/
  -- line budget nearly every screen in this file respects, on its own,
  -- before a level or anything else is even added - confirmed by a real
  -- report: "OINKOLOGNE_FEMALE" (17 chars) silently lost its trailing "E"
  -- to queueCatchActivity's :sub(1,16) truncation, landing in
  -- friend_activity as "OINKOLOGNE_FEMAL".
  --
  -- Rendered as the real "\xE2\x99\x82"/"\xE2\x99\x80" (Unicode MALE/
  -- FEMALE SIGN, UTF-8) glyphs rather than a "(M)"/"(F)" suffix - not a
  -- guess: confirmed directly against the engine's own src/render/
  -- Font.lua, whose glyph-segmentation comment names "♂" as ITS OWN
  -- worked example of a multi-byte UTF-8 character the font draws as one
  -- glyph ("a multi-byte char ('é', '♂')... is one glyph"), the same
  -- symbol the real cartridges use for NIDORAN's own two forms. One
  -- glyph beats three characters for the budget too - "OINKOLOGNE♀" is
  -- 12 chars against "OINKOLOGNE (F)"'s 14.
  local GENDER_MALE = "\xE2\x99\x82"     -- ♂ U+2642
  local GENDER_FEMALE = "\xE2\x99\x80"   -- ♀ U+2640
  local function formatSpeciesName(species)
    local s = tostring(species or "?"):upper()
    -- Two separate matches, not one pattern with "(MALE|FEMALE)" - Lua
    -- patterns have no "|" alternation operator at all (unlike regex), so
    -- that reads as the literal 11-character sequence "MALE|FEMALE" and
    -- silently never matches anything real. Caught by a standalone test
    -- harness before this ever shipped, not by inspection - every case
    -- this was meant to fix came back FAIL on the first attempt.
    -- FEMALE checked before MALE only because "_FEMALE" is the longer,
    -- more specific suffix; neither can ever match the other's string.
    local base = s:match("^(.+)_FEMALE$")
    if base then return base .. GENDER_FEMALE end
    base = s:match("^(.+)_MALE$")
    if base then return base .. GENDER_MALE end
    return s
  end

  -- Reads everything the stats snapshot needs from game.save directly -
  -- see research/gen1-save-format-findings.md for how each field was
  -- confirmed. playTime isn't read here (not shown on the detail screen),
  -- but pokedex/hallOfFame/money/badges all are.
  --
  -- Three of these fields live at a genuinely different path on a Gen 2
  -- (Gold/Silver/Crystal) save - confirmed directly against
  -- src/core/gen2/Save.lua, not guessed. Crystal shares this exact same
  -- Save.lua module and field layout with Gold/Silver (its own extras -
  -- save.crystal, save.battleTower - are separate fields this mod never
  -- touches), so no Crystal-specific branch is needed here beyond isGen2()
  -- already recognizing it:
  --   money:         save.player.money on Gen 2 (Gen 1: top-level save.money)
  --   pokedexCaught: save.pokedex.caught on Gen 2 (Gen 1: save.pokedex.owned -
  --                  .seen is the same key on both, so that one's untouched)
  --   leagueWins:    save.hallOfFame.count on Gen 2, a { count, teams } table
  --                  (Gen 1: save.hallOfFame is a plain array, #save.hallOfFame
  --                  entries - the same #-on-a-non-array bug class this
  --                  project already fixed once for parseObjects' empty-array
  --                  case, caught here before shipping instead of after)
  -- party/playTime (encodePartySnapshot/readPlaySeconds) and pokedex.seen
  -- are already generation-agnostic - same field names both sides - so they
  -- need no branch here.
  local function readStatsSnapshot()
    local save = game and game.save
    if not save then return nil end
    local gen2 = isGen2(gameVersion)

    local seen, caught = 0, 0
    if type(save.pokedex) == "table" then
      if type(save.pokedex.seen) == "table" then for _ in pairs(save.pokedex.seen) do seen = seen + 1 end end
      local caughtSet = gen2 and save.pokedex.caught or save.pokedex.owned
      if type(caughtSet) == "table" then for _ in pairs(caughtSet) do caught = caught + 1 end end
    end

    local leagueWins = 0
    if gen2 then
      if type(save.hallOfFame) == "table" then leagueWins = tonumber(save.hallOfFame.count) or 0 end
    else
      if type(save.hallOfFame) == "table" then leagueWins = #save.hallOfFame end
      -- Real, confirmed root cause of a "YOUR CLEARS shows 0 despite
      -- genuinely beating the league" report: save.hallOfFame is NOT one
      -- of the fields Gen1's .sav import/export codec models at all
      -- (confirmed directly against the engine's own
      -- src/save_convert/GenSave.lua - 1146 lines, zero mentions of Hall
      -- of Fame in either direction). Any save that has EVER been
      -- exported to a .sav and/or re-imported loses this roster array
      -- completely, silently, even though the champion genuinely was
      -- beaten - this is a real gap in the base engine's .sav codec, not
      -- something introduced by this mod, and not something this mod can
      -- fix at the source (that codec lives in the engine, not here).
      --
      -- EVENT_BEAT_CHAMPION_RIVAL, by contrast, IS one of the fields that
      -- codec's eventFlags crosswalk explicitly preserves (confirmed in
      -- src/save_convert/data/event_flags.lua) - a real, permanent flag
      -- the game's own story scripts set once and never clear (see
      -- data/scripts/story.lua's own comment: "EVENT_BEAT_CHAMPION_RIVAL
      -- stays set" - deliberately distinct from the run-scoped
      -- _THIS_RUN variant used for re-entry dialogue). So when the
      -- roster array reads empty but this flag says the champion has
      -- genuinely been beaten at least once, floor the count at 1 rather
      -- than reporting a flatly false "never beaten the league."
      --
      -- This can only ever recover "at least 1", never the true original
      -- count if the real number was higher before an import wiped it -
      -- a boolean flag has no way to carry a count. Every REAL clear from
      -- here on (with no further imports) still increments the roster
      -- array normally on top of this floor, exactly as before.
      if leagueWins == 0 and type(save.flags) == "table" and save.flags.EVENT_BEAT_CHAMPION_RIVAL then
        leagueWins = 1
      end
    end

    local money
    if gen2 then
      money = tonumber(save.player and save.player.money) or 0
    else
      -- game.save.money, NOT save.player.money - confirmed by reading
      -- SaveData.lua's own newGame() table construction directly: money
      -- is a plain top-level key sibling to player/party/flags/pokedex on
      -- a GEN 1 save, not nested under player (player only holds
      -- map/x/y/facing/name/rival/id there). An earlier draft of this
      -- guessed save.player.money by analogy with save.player.name and
      -- would have silently read nil (falling back to 0) for every real
      -- Gen 1 player - caught before shipping by checking the actual
      -- source rather than assuming. Gen 2 really does nest it under
      -- save.player.money (see the branch above) - both are real, for
      -- different generations, not one guess and one fix.
      money = tonumber(save.money) or 0
    end

    return {
      badges = countBadges(),
      badgesMask = encodeBadgeMask(),
      pokedexSeen = seen,
      pokedexCaught = caught,
      leagueWins = leagueWins,
      money = money,
      playSeconds = readPlaySeconds(),
      party = encodePartySnapshot(),
    }
  end

  -- Activity message, queued by the real pokemon.caught event handler
  -- (see wiring section below) and drained/uploaded by pumpPresenceTimer -
  -- NOT a poll-and-diff against save.pokedex.owned like an earlier draft
  -- of this did. That draft could only ever report species, since
  -- pokedex.owned is just a set with no level field - switching to the
  -- real pokemon.caught event (documented payload: { battle, mon,
  -- species, isNew, ball, destination, game }) gets species from the
  -- payload's own `species` field and level from `mon.level` - `mon` is
  -- the same live party-mon object species/level/moves/etc. are read
  -- from everywhere else in this project (see
  -- research/gen1-save-format-findings.md), just not yet inserted into
  -- save.party at the moment this event fires.
  --
  -- Two separate lines, not one string with a space - a species name
  -- like BLASTOISE is long enough that "CAUGHT LVL 25 BLASTOISE" risks
  -- overflowing the 16-char/line budget every screen in this file
  -- respects, per direct feedback. Stored server-side as ONE string with
  -- a literal newline joining the two lines (stats.php doesn't need to
  -- know or care that it's two lines - it's still just "the activity
  -- message" as far as the database and endpoint are concerned), split
  -- back into two lines only where it's drawn (SilphNetFriendDetail).
  -- A small FIFO queue, NOT a single overwritable slot - a single slot
  -- had a real bug (caught during a live report of "one catch shows all
  -- day, then several catches never appear"): if a second catch happened
  -- before the first one's upload had finished (statsUploadBusy still
  -- true - see pumpPresenceTimer), the single slot got silently
  -- overwritten, permanently losing the first catch's activity with no
  -- way to ever send it. A FIFO means a fast second catch waits its turn
  -- instead of erasing the first. Capped at PENDING_ACTIVITY_MAX rather
  -- than unbounded - a genuine catching frenzy (several catches within
  -- one HTTP round-trip) can still lose the OLDEST entry once the queue
  -- is full, but that's a deliberate, bounded worst case instead of the
  -- previous unbounded "last one wins, always" behaviour.
  local PENDING_ACTIVITY_MAX = 5
  local pendingActivityQueue = {}   -- array of "CAUGHT LVL 25\nBLASTOISE" strings, oldest first
  local function queueCatchActivity(mon, species)
    local level = mon and tonumber(mon.level)
    local name = formatSpeciesName(species)
    local line1 = level and ("CAUGHT LVL " .. level) or "CAUGHT"
    -- Each line gets its own 16-char cap (this screen's real budget),
    -- not one combined 32-char cap - a long species name can't borrow
    -- room from the level line or vice versa, since they're drawn on
    -- separate rows.
    local message = line1:sub(1, 16) .. "\n" .. name:sub(1, 16)
    table.insert(pendingActivityQueue, message)
    if #pendingActivityQueue > PENDING_ACTIVITY_MAX then
      table.remove(pendingActivityQueue, 1)   -- drop the oldest, not the newest
    end
  end

  -- Global online count (everyone, not just friends) and who's on the
  -- CURRENT map (friend or not) - both use the same ~30s cycle as
  -- presence/friends/pending, same reasoning: cheap, small, gated behind
  -- PRESENCE_INTERVAL so standing still doesn't spam the server.
  local onlineCount = nil   -- nil until the first successful fetch
  local nearby = {}         -- array of { account_id, name, trainer_id }, current map only
  -- array of { game_version, count, players = {...} }, always exactly
  -- RED/BLUE/YELLOW/GOLD/SILVER in that order once fetched - see
  -- online_by_version.php.
  -- nil until the first successful fetch (SilphNetOnline's own screen,
  -- see below), same "nil means haven't heard back yet, distinct from an
  -- empty/zero real answer" convention as onlineCount.
  local onlineByVersion = nil

  -- { all = {...}, friends = {...} } from the last successful
  -- league_leaderboard.php fetch, each an array of { account_id, name,
  -- trainer_id, total } already sorted DESCENDING by the server (see
  -- that endpoint) - nil until the first successful fetch, same "nil
  -- means haven't heard back yet" convention as onlineByVersion/
  -- onlineCount. Ascending/descending is a pure client-side toggle (see
  -- SilphNetLeagueSign's leagueSortAsc below) - reversing this array in
  -- place rather than needing a second request for the opposite order.
  local leagueLeaderboard = nil

  local function firePresencePing()
    if authState ~= "authed" or not myMap then return end
    presenceBusy = true
    httpAsyncGet("ping", "/ping.php", {
      token = mod.save:get("token") or "",
      map_id = myMap, x = myX or 0, y = myY or 0,
      facing = myFacing or "down", game_version = gameVersion,
    })
  end

  fireFriendsFetch = function()
    if authState ~= "authed" then return end
    friendsBusy = true
    httpAsyncGet("friends", "/friends.php", { token = mod.save:get("token") or "" })
  end

  firePendingFetch = function()
    if authState ~= "authed" then return end
    pendingBusy = true
    httpAsyncGet("pending", "/pending_requests.php", { token = mod.save:get("token") or "" })
  end

  fireOnlineCountFetch = function()
    if authState ~= "authed" then return end
    onlineCountBusy = true
    httpAsyncGet("online_count", "/online_count.php", { token = mod.save:get("token") or "" })
  end

  -- Only meaningful in the overworld with a known map - same guard
  -- firePresencePing already uses, since "nearby" without a real map_id
  -- is a meaningless query.
  fireNearbyFetch = function()
    if authState ~= "authed" or not myMap then return end
    nearbyBusy = true
    httpAsyncGet("nearby", "/nearby.php", { token = mod.save:get("token") or "", map_id = myMap })
  end

  -- On-demand only - fired once when SilphNetOnline opens, NOT on the 30s
  -- presence cycle. Same reasoning as fireFriendDetailFetch below: this is
  -- about a screen the player has chosen to look at right now, not
  -- something every screen needs kept fresh in the background - unlike
  -- onlineCount (the OLD flat global number, still used elsewhere), this
  -- per-version breakdown with full player lists is more data than the
  -- background cycle should be pulling down every ~30s regardless of
  -- whether anyone's even looking at it.
  fireOnlineByVersionFetch = function()
    if authState ~= "authed" then return end
    onlineByVersionBusy = true
    httpAsyncGet("online_by_version", "/online_by_version.php", { token = mod.save:get("token") or "" })
  end

  -- On-demand only, same reasoning as fireOnlineByVersionFetch/
  -- fireFriendDetailFetch above - fired once when the league sign near
  -- INDIGO_PLATEAU_LOBBY successfully spawns (see the map.entered wiring
  -- further down) rather than kept on the background 30s cycle, since
  -- this is only ever useful right as a player is actually about to walk
  -- into the Elite Four. Also fired lazily from SilphNetLeagueSign's own
  -- update(dt) if leagueLeaderboard is still nil by the time the screen
  -- opens - the exact same "fetch on demand if a screen wants fresher
  -- data than it's already been given" fallback SilphNetOnline already
  -- uses for onlineByVersion.
  fireLeagueLeaderboardFetch = function()
    if authState ~= "authed" then return end
    leagueLeaderboardBusy = true
    httpAsyncGet("league_leaderboard", "/league_leaderboard.php", { token = mod.save:get("token") or "" })
  end

  -- On-demand only - fired once when SilphNetFriendDetail opens, NOT on
  -- the 30s presence cycle. Unlike friends/pending/online-count/nearby,
  -- this is about ONE specific friend the player has chosen to look at
  -- right now, not something every screen needs kept fresh in the
  -- background. Fetches ALL of that friend's versions in one request
  -- (see friend_detail.php) - the screen cycles through every version's
  -- STATS/ACTIVITY pages on a single button (A), so it needs the whole
  -- set upfront rather than firing a fresh request on every press.
  fireFriendDetailFetch = function(accountId)
    if authState ~= "authed" or not accountId then return end
    friendDetailBusy = true
    httpAsyncGet("friend_detail", "/friend_detail.php", {
      token = mod.save:get("token") or "", account_id = accountId,
    })
  end

  -- Uploads the caller's OWN stats snapshot and/or a fresh activity
  -- message - see stats.php. Called on a slower cycle than presence (see
  -- pumpPresenceTimer) for the stats fields, and immediately/independently
  -- whenever a new activity event is detected (see checkActivityEvents).
  -- statsFields and activity are both optional (pass nil to omit either)
  -- since a stats-cycle upload and an activity event don't necessarily
  -- happen at the same moment.
  fireStatsUpload = function(statsFields, activity)
    if authState ~= "authed" then return end
    local fields = { token = mod.save:get("token") or "", game_version = gameVersion }
    if statsFields then
      fields.badges = statsFields.badges
      fields.badges_mask = statsFields.badgesMask
      fields.pokedex_seen = statsFields.pokedexSeen
      fields.pokedex_caught = statsFields.pokedexCaught
      fields.league_wins = statsFields.leagueWins
      fields.money = statsFields.money
      fields.play_seconds = statsFields.playSeconds
      fields.party = statsFields.party
    end
    if activity then fields.activity = activity end
    statsUploadBusy = true
    statsUploadActivitySent = activity   -- remembered so drainHttpResults knows what to pop on success
    -- Logged specifically for diagnosing "my league wins/clears still
    -- show 0" reports - lets a real snapshot upload be confirmed (or
    -- ruled out) directly from the mod's own log, rather than guessing
    -- whether the 3-minute upload cycle has actually fired yet since a
    -- real Hall of Fame clear. Only logged when a real stats snapshot is
    -- attached (statsFields truthy) - an activity-only upload (a catch,
    -- fired independently of the stats cycle) has no leagueWins to report.
    if statsFields then
      mod.log:info("SilphNet: uploading stats snapshot (version=%s, leagueWins=%s, badges=%s)",
        tostring(gameVersion), tostring(statsFields.leagueWins), tostring(statsFields.badges))
    end
    httpAsyncGet("stats_upload", "/stats.php", fields)
  end

  local function fireAddFriend(trainerId)
    addFriendStatus = "SENDING..."
    httpAsyncGet("add_friend", "/add_friend.php", { token = mod.save:get("token") or "", trainer_id = trainerId })
  end

  -- accountId here is the OTHER person's account_id (see friends.php's
  -- "account_id" field on each entry) - remove_friend.php deletes both
  -- directions of an accepted friendship in one transaction, same
  -- reasoning as accept_friend.php inserting both directions on accept.
  local function fireRemoveFriend(accountId)
    httpAsyncGet("remove_friend", "/remove_friend.php", { token = mod.save:get("token") or "", account_id = accountId })
  end

  -- ---- friend silhouettes (static, one placement per poll, never tweened) -
  local function allocIndex(id)
    if not idToIndex[id] then idToIndex[id] = nextIndex; nextIndex = nextIndex + 1 end
    return idToIndex[id]
  end

  local function despawnMarker(id)
    local m = markers[id]
    if m and m.npcId ~= nil then pcall(mod.world.removeNpc, mod.world, m.npcId) end
    freeSlot(id)
    markers[id] = nil
  end
  local function despawnAllMarkers() for id in pairs(markers) do despawnMarker(id) end end

  local function spawnMarker(id, x, y, facing)   -- << VERIFY >> objDef shape
    local slot = allocSlot(id)
    if not slot then mod.log:warn("SilphNet: no free marker slot for %s (raise MARKER_SLOTS)", tostring(id)); return end
    local objDef = { index = allocIndex(id), x = x, y = y, sprite = MY_SPRITE,
                      movement = "STAY", range = "NONE", name = "SILPHNET_FRIEND_" .. id,
                      text = "TEXT_SILPHNET_MARKER_SLOT_" .. slot }
    local ok, npcId = pcall(mod.world.spawnNpc, mod.world, myMap, objDef)
    if not ok then mod.log:warn("SilphNet: marker spawn failed for %s: %s", tostring(id), tostring(npcId)); freeSlot(id); return end
    markers[id] = { npcId = npcId, mapId = myMap, x = x, y = y, slot = slot }
    local h
    pcall(function() h = mod.world:npc(myMap, "SILPHNET_FRIEND_" .. id) end)
    if h then pcall(h.face, h, facing) end
  end

  -- ---- gym sign + league leaderboard sign (runtime placement) -------------
  -- First cut of this just searched the 8 tiles immediately touching the
  -- player's own entry tile - which is, by definition, the doorway itself
  -- (that's the one tile guaranteed walkable without knowing the map).
  -- Reported back as "the sign is right in the way as soon as you walk
  -- in" - correct bug report: standing right next to the door is exactly
  -- where a real player needs to walk through a second later, and is
  -- nowhere near where a gym's own statues/plaques actually sit (further
  -- into the room, off to the side of the main aisle).
  --
  -- Fix: use the player's OWN facing at the moment they enter (every real
  -- door warp faces you further INTO the room you just entered - e.g.
  -- walking north through a gym's front door leaves you facing "up") to
  -- project a line a few tiles deeper into the room before searching at
  -- all, then search that anchor point's SIDEWAYS neighbours first (left/
  -- right of the direction you're walking), not its forward/backward
  -- ones - so the sign lands beside the aisle you'd naturally walk up,
  -- never sitting squarely on top of it. Still zero hardcoded coordinates
  -- (this project ships no ROM data - README/CLAUDE.md): every candidate
  -- tile is still verified walkable live via mod.world:mapOverview()
  -- before ever being used, exactly as before - only WHICH tiles get
  -- tried first has changed.
  --
  -- FORWARD_BY_FACING gives the (dx, dy) step for one tile in the
  -- direction the player is currently facing (engine facing strings are
  -- lowercase - confirmed via src/world/NPC.lua/OverworldController.lua).
  -- Falls back to "up" (the single most common real door-facing in this
  -- game) if a facing somehow comes back nil/unrecognised, rather than
  -- refusing to search at all.
  local FORWARD_BY_FACING = {
    up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
  }

  -- Built fresh per search (see findSafeSignTile) from whichever facing
  -- the player actually entered with, so "sideways" always means
  -- perpendicular to THAT specific entry, not a fixed screen direction.
  --
  -- IMPORTANT LIMITATION (confirmed directly against the engine's own
  -- MapOverview.build(), src/world/MapOverview.lua): the collision grid
  -- this whole search reads from (mod.world:mapOverview().rows) is built
  -- purely from STATIC map tile collision (map:isWalkableCell(x,y)) - it
  -- has no idea where any NPC or decoration currently stands, including a
  -- gym's own statues. Those are placed as ordinary map objects, not
  -- baked into the tile grid, so a tile directly under a statue still
  -- reads as walkable ground here even though something is visibly
  -- sitting on it. There is no mod-facing API to enumerate NPC positions
  -- on a map (WorldAPI only offers npc(mapId, nameOrIndex) - a lookup by
  -- name, not a "list everything here" call) - so this project can't
  -- detect that case in general without hardcoding a specific map's real
  -- layout, which it deliberately never does (ships no ROM data).
  --
  -- Widened side range (1-3, was 1-2) and search depth (2-8, was 2-6)
  -- after a real report (Viridian Gym) of the sign landing on top of a
  -- statue - purely a numbers-game mitigation (more candidate tiles tried
  -- = lower odds of hitting the one a statue happens to occupy), not a
  -- guarantee. SIGN_AVOID_TILES below is the actual fix path for a
  -- specific reported overlap: once a player names the exact spot, that
  -- one tile gets excluded outright rather than relying on chance.
  local function buildSignSearchOffsets(facing)
    local fwd = FORWARD_BY_FACING[facing] or FORWARD_BY_FACING.up
    -- Perpendicular unit vector (rotate fwd 90 degrees) - "left of the
    -- aisle" and "right of the aisle" from the player's own point of view.
    local side = { -fwd[2], fwd[1] }
    local offsets = {}
    -- Anchor a few tiles past the doorway (distance 2-8), never distance
    -- 0-1, so nothing can ever land in the door tile or its immediate
    -- threshold. At each depth, try sideways-of-the-aisle first (1-3
    -- tiles either side, furthest first), straight ahead only as a last
    -- resort at that depth, before moving deeper and repeating - this
    -- consistently prefers "beside the path a few steps in" over
    -- "blocking the path" or "still basically in the doorway."
    for depth = 2, 8 do
      local ax, ay = fwd[1] * depth, fwd[2] * depth
      for _, s in ipairs({ 3, -3, 2, -2, 1, -1 }) do
        offsets[#offsets + 1] = { ax + side[1] * s, ay + side[2] * s }
      end
      offsets[#offsets + 1] = { ax, ay } -- dead ahead, only if nothing beside it worked
    end
    return offsets
  end

  -- Specific tiles a real player has actually reported a sign overlapping
  -- something on (a statue, a gym leader's own spot, etc.) - keyed by
  -- mapId, each entry a set of "x,y" strings. Deliberately NOT populated
  -- from any pre-existing map data or test fixture (this project ships no
  -- ROM data) - every entry here is a specific tile a real person on a
  -- real device actually saw a problem on and reported back, the same
  -- category of information as a player telling us a map's in-game name.
  -- Empty for now - add an entry here (see the comment above
  -- findSafeSignTile for how) once a report includes exact coordinates,
  -- e.g. from the mod.log:info() line spawnGymSign/spawnLeagueSign now
  -- emit on every spawn.
  local SIGN_AVOID_TILES = {}

  -- Last-resort offsets if nothing in the forward/sideways search (out to
  -- depth 6) turned up a walkable, unoccupied tile - e.g. a very small
  -- one-room gym. Falls back to the original "immediately beside the
  -- player" ring rather than spawning nothing at all.
  local SIGN_SEARCH_FALLBACK_OFFSETS = {
    { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 },
    { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
  }

  -- overview.rows[y+1]:sub(x+1,x+1) per MapOverview's own build() contract
  -- (confirmed directly against the engine's real src/world/MapOverview.lua):
  -- "." plain walkable ground, "~" walkable water, "+" a warp tile, " " a
  -- blocked/wall cell. Warp tiles are excluded here simply by never being
  -- one of the two accepted characters - not a separate check against
  -- overview.markers - since the collision grid itself already encodes
  -- "is this a warp" directly in the same character every other
  -- walkability check here already reads.
  local function isWalkableSignChar(c)
    return c == "." or c == "~"
  end

  -- occupied is an optional set of "x,y" keys (current friend markers on
  -- this map, say) to also treat as unavailable, so a sign never lands
  -- exactly on top of an already-spawned friend silhouette. Returns
  -- x, y (both nil if genuinely nothing safe was found within the
  -- searched neighbourhood - callers must handle that by simply not
  -- spawning a sign at all, never by falling back to a guessed tile).
  local function findSafeSignTile(mapId, occupied)
    local cur = mod.world:current()
    if not cur or cur.mapId ~= mapId or not cur.x or not cur.y then return nil end
    local ok, overview = pcall(mod.world.mapOverview, mod.world)
    if not ok or not overview or type(overview.rows) ~= "table" then return nil end

    local avoid = SIGN_AVOID_TILES[mapId]
    local function tryOffsets(offsets)
      for _, off in ipairs(offsets) do
        local x, y = cur.x + off[1], cur.y + off[2]
        if x >= 0 and y >= 0 and y < #overview.rows then
          local row = overview.rows[y + 1]
          local c = row and row:sub(x + 1, x + 1)
          if c and isWalkableSignChar(c) then
            local key = x .. "," .. y
            if not (occupied and occupied[key]) and not (avoid and avoid[key]) then return x, y end
          end
        end
      end
      return nil
    end

    -- Preferred: a few tiles deeper into the room, beside the natural
    -- walking line, never in the doorway itself (see buildSignSearchOffsets
    -- above for why). Only falls back to the old "right beside the
    -- player" ring if that entire deeper search comes up empty (e.g. a
    -- cramped one-room map where depth 2-6 runs off the map edge).
    local x, y = tryOffsets(buildSignSearchOffsets(cur.facing))
    if x then return x, y end
    return tryOffsets(SIGN_SEARCH_FALLBACK_OFFSETS)
  end

  -- Current gym-sign state, read by SilphNetGymSign at push time (same
  -- "look it up live, don't freeze it at registration" pattern
  -- SilphNetMarkerTalk already uses for slotToKey/friends) - only one
  -- gym sign can meaningfully exist at once (you're only ever standing
  -- in one gym), so this is a single slot, not a table keyed by map.
  local gymSignNpc = nil          -- { npcId, mapId } or nil
  local currentGymBadge = nil     -- badge id string the sign currently describes, or nil

  local function despawnGymSign()
    if gymSignNpc and gymSignNpc.npcId ~= nil then pcall(mod.world.removeNpc, mod.world, gymSignNpc.npcId) end
    gymSignNpc = nil
    currentGymBadge = nil
  end

  -- Not a per-friend spawn like spawnMarker (one NPC, one slot, one
  -- specific friend) - one single sign NPC whose talk screen reads the
  -- WHOLE deduped friend list for this gym's badge at push time
  -- (currentGymFriends is recomputed fresh every time SilphNetGymSign
  -- opens anyway, via friendsWithBadge, so this doesn't even need to be
  -- cached here - only currentGymBadge, so the screen knows which badge
  -- to ask about).
  local function spawnGymSign(mapId, badgeId)
    local occupied = {}
    for _, m in pairs(markers) do
      if m.mapId == mapId then occupied[m.x .. "," .. m.y] = true end
    end
    local x, y = findSafeSignTile(mapId, occupied)
    if not x then
      mod.log:warn("SilphNet: no safe tile found for gym sign on %s", tostring(mapId))
      return
    end
    local objDef = { index = allocIndex("SILPHNET_GYM_SIGN"), x = x, y = y, sprite = MY_SPRITE,
                      movement = "STAY", range = "NONE", name = "SILPHNET_GYM_SIGN",
                      text = "TEXT_SILPHNET_GYM_SIGN" }
    local ok, npcId = pcall(mod.world.spawnNpc, mod.world, mapId, objDef)
    if not ok then
      mod.log:warn("SilphNet: gym sign spawn failed on %s: %s", tostring(mapId), tostring(npcId))
      return
    end
    gymSignNpc = { npcId = npcId, mapId = mapId }
    currentGymBadge = badgeId
    -- Logged so a real overlap report (sign on top of a statue etc.) can
    -- include the exact tile - see SIGN_AVOID_TILES above for why this is
    -- the actual fix path rather than trying to guess harder up front.
    mod.log:info("SilphNet: gym sign placed on %s at (%d,%d)", tostring(mapId), x, y)
  end

  -- League leaderboard sign - same single-slot shape as the gym sign
  -- above, just for one fixed map (LEAGUE_SIGN_MAP_ID) instead of
  -- whichever gym GYM_MAP_TO_BADGE currently matches.
  local leagueSignNpc = nil   -- { npcId, mapId } or nil

  local function despawnLeagueSign()
    if leagueSignNpc and leagueSignNpc.npcId ~= nil then pcall(mod.world.removeNpc, mod.world, leagueSignNpc.npcId) end
    leagueSignNpc = nil
  end

  local function spawnLeagueSign(mapId)
    local occupied = {}
    for _, m in pairs(markers) do
      if m.mapId == mapId then occupied[m.x .. "," .. m.y] = true end
    end
    local x, y = findSafeSignTile(mapId, occupied)
    if not x then
      mod.log:warn("SilphNet: no safe tile found for league sign on %s", tostring(mapId))
      return
    end
    local objDef = { index = allocIndex("SILPHNET_LEAGUE_SIGN"), x = x, y = y, sprite = MY_SPRITE,
                      movement = "STAY", range = "NONE", name = "SILPHNET_LEAGUE_SIGN",
                      text = "TEXT_SILPHNET_LEAGUE_SIGN" }
    local ok, npcId = pcall(mod.world.spawnNpc, mod.world, mapId, objDef)
    if not ok then
      mod.log:warn("SilphNet: league sign spawn failed on %s: %s", tostring(mapId), tostring(npcId))
      return
    end
    leagueSignNpc = { npcId = npcId, mapId = mapId }
    mod.log:info("SilphNet: league sign placed on %s at (%d,%d)", tostring(mapId), x, y)
    fireLeagueLeaderboardFetch()
  end

  -- Deterministic civil-date -> days-since-epoch conversion (Howard
  -- Hinnant's well-known algorithm), with NO dependency on os.time/os.date
  -- or the process's local timezone at all. Needed because the previous
  -- approach here (comparing os.time(os.date("!*t")) against
  -- os.time(os.date("*t")) to derive a "local minus UTC" offset) was
  -- fundamentally unreliable: os.time() ALWAYS interprets whatever table
  -- it's given as LOCAL time, with no way to tell it "these fields are
  -- already UTC" - so both sides of that subtraction went through the
  -- same reinterpretation and could silently cancel to a wrong answer.
  -- Confirmed on a real BST (UTC+1) system: that old code returned an
  -- offset of exactly 0 (it should have been 3600), entirely because of
  -- how the isdst field happens to affect mktime, not because the
  -- calculation was actually timezone-aware - which is why friends who
  -- HAD just pinged (confirmed fresh in the database, e.g. 17 seconds old)
  -- still displayed as OFFLINE / "1 HR AGO" on-device: every last_seen was
  -- silently off by a full hour once BST began.
  -- Lua 5.1/LuaJIT has no // floor-division operator (that's Lua 5.3+) -
  -- an earlier draft of this used // throughout and passed a Lua 5.4-based
  -- test harness in the sandbox used to verify it, but the real engine
  -- (LOVE 11 / LuaJIT) rejected it outright with a real syntax error on
  -- load ("unexpected symbol near '/'"), which took the mod down entirely
  -- for every player until fixed - a gap in how this was verified before
  -- shipping. floor() here is explicit for exactly that reason: every
  -- division in this function needs floor (not Lua 5.1's default true
  -- division, which returns a float) since daysFromCivil is pure integer
  -- arithmetic throughout.
  --
  -- Moved above refreshMarkers (was previously defined after it) because
  -- refreshMarkers now needs parseMysqlDatetimeUtc too (see below) - a
  -- local function's name only exists in scope from its own declaration
  -- onward, so calling it from a function defined earlier in the file
  -- would have resolved to a nil global at runtime. This exact ordering
  -- mistake has broken this file before (drainHttpResults, forward-
  -- declared in a shared local line for that reason) - moving the
  -- definition up avoids needing yet another forward-declare pair.
  local function daysFromCivil(y, m, d)
    y = (m <= 2) and (y - 1) or y
    local era = math.floor((y >= 0 and y or y - 399) / 400)
    local yoe = y - era * 400
    local mp = (m + 9) % 12
    local doy = math.floor((153 * mp + 2) / 5) + d - 1
    local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
    return era * 146097 + doe - 719468
  end

  -- last_seen from the API is a MySQL DATETIME string ("YYYY-MM-DD
  -- HH:MM:SS"), always UTC (NOW() on the server, confirmed via
  -- NOW()/UTC_TIMESTAMP() both matching on the real server). Converts
  -- directly to a true UTC unix timestamp with no timezone-dependent step
  -- anywhere in the calculation, so ONLINE/OFFLINE and "N MIN AGO" are
  -- correct regardless of the player's local timezone or DST state.
  local function parseMysqlDatetimeUtc(s)
    if not s then return nil end
    local y, mo, d, h, mi, se = string.match(s, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if not y then return nil end
    local days = daysFromCivil(tonumber(y), tonumber(mo), tonumber(d))
    return days * 86400 + tonumber(h) * 3600 + tonumber(mi) * 60 + tonumber(se)
  end

  -- How many distinct FRIENDS (people, not friends[] entries - a friend
  -- with two active saves shouldn't count twice) are currently ONLINE,
  -- computed entirely client-side from the `friends` table this device
  -- already has (no separate server round-trip) - same ONLINE definition
  -- (OFFLINE_AFTER, 5 minutes) every other online/offline check in this
  -- file already uses (refreshMarkers, SilphNetFriends' isOnline).
  --
  -- Added to replace online_count.php's GLOBAL count on the status
  -- screen's A:FRIENDS hint - reported directly as confusing: a player
  -- with zero friends online but who was themselves within the 5-minute
  -- window would see "A:FRIENDS(1 ON)" (that global count includes the
  -- caller) sitting right next to a friends list showing everyone
  -- OFFLINE, easy to misread as "one of my friends is online". This
  -- function answers the question that hint line is actually asking -
  -- online_count.php's global count (which does still include the
  -- caller - see that file) moved to its own separate "SN ONLINE" Start
  -- Menu row instead, well away from anything friends-specific.
  local function countFriendsOnline()
    local seenPeople, n = {}, 0
    for _, f in pairs(friends) do
      if f.account_id and not seenPeople[f.account_id] then
        local lastSeenUnix = parseMysqlDatetimeUtc(f.last_seen)
        if lastSeenUnix and (os.time() - lastSeenUnix) <= OFFLINE_AFTER then
          seenPeople[f.account_id] = true
          n = n + 1
        end
      end
    end
    return n
  end

  -- Reconciles the friend-marker set against `friends` + the current map -
  -- called once per friends-fetch completion and once on map.entered, NOT
  -- per-tick. Each friend gets at most one static marker, only when their
  -- last-known map matches the one you're standing on right now AND their
  -- last ping is recent enough to count as ONLINE (same OFFLINE_AFTER
  -- threshold the friends list already uses for the ONLINE/OFFLINE label -
  -- see isOnline in SilphNetFriends' draw()). Without this check a marker
  -- for a now-offline friend would just sit there forever on whatever map
  -- they were last seen on, since map_id never changes again once they've
  -- logged off - caught on-device: ARCHADA still shown OFFLINE "8 MIN AGO"
  -- on Route 8, yet his marker was still standing there.
  local function refreshMarkers()
    if not inOverworld then despawnAllMarkers(); return end
    local wanted = {}
    for id, f in pairs(friends) do
      -- f.last_seen is a raw MySQL datetime string (e.g. "2026-08-11
      -- 12:34:56"), not a unix timestamp - must go through
      -- parseMysqlDatetimeUtc first, exactly like SilphNetFriends' isOnline
      -- check does, or this comparison is comparing a number to a string.
      local lastSeenUnix = parseMysqlDatetimeUtc(f.last_seen)
      local online = lastSeenUnix and (os.time() - lastSeenUnix) <= OFFLINE_AFTER
      if online and f.map_id == myMap then
        local x, y = tonumber(f.x), tonumber(f.y)
        if x and y then wanted[id] = { x = x, y = y, facing = f.facing or "down" } end
      end
    end
    for id in pairs(markers) do
      local w = wanted[id]
      if not w or markers[id].mapId ~= myMap or markers[id].x ~= w.x or markers[id].y ~= w.y then
        despawnMarker(id)
      end
    end
    for id, w in pairs(wanted) do
      if not markers[id] then spawnMarker(id, w.x, w.y, w.facing) end
    end
  end

  -- ---- friends list / status text -----------------------------------------
  local function timeAgoText(lastSeenUnix)
    if not lastSeenUnix then return "UNKNOWN" end
    local secs = os.time() - lastSeenUnix
    if secs < 0 then secs = 0 end
    if secs < 60 then return secs .. "S AGO" end
    if secs < 3600 then return math.floor(secs / 60) .. " MIN AGO" end
    return math.floor(secs / 3600) .. " HR AGO"
  end

  -- Formats a total-seconds play time as "TIME <h>H <m>M" - checked by
  -- hand against extreme values (999999 seconds = "TIME 277H 46M", 13
  -- chars) to confirm this stays under the 16-char budget even at play
  -- times far beyond what's realistic, not just typical ones.
  local function playTimeText(totalSeconds)
    local secs = tonumber(totalSeconds) or 0
    if secs < 0 then secs = 0 end
    local h = math.floor(secs / 3600)
    local m = math.floor((secs % 3600) / 60)
    return "TIME " .. h .. "H " .. m .. "M"
  end

  -- "SN" here, not "SILPHNET" - reported on a real device running a UI
  -- mod that chops long Start Menu labels off entirely rather than
  -- truncating with an ellipsis, so "SILPHNET <name>" could disappear
  -- altogether depending on name length. Matches the "SN NEARBY" row
  -- already added below, so both SilphNet rows share the same short
  -- prefix rather than one being "SILPHNET" and the other "SN".
  local function statusLabel()
    if authState == "authed" then return "SN " .. myName end
    if authState == "confirm_register" then return "SN NEW ACCT?" end
    if authState == "need_creds" then return "SN SET NAME/PASS" end
    if authState == "failed" then return "SN LOGIN FAIL" end
    if authState == "logging_in" then return "SN ..." end
    return "SN OFF"
  end

  -- Doesn't repeat myName here even when logged in - the NAME row right
  -- above this on the status screen already shows it, and "LOGGED IN AS "
  -- (13 chars) plus any real name reliably overflowed the 16-char budget,
  -- which is what made ASHJAM render as the confusing, truncated "LOGGED
  -- IN AS ASH" on a real device (13 + "ASHJAM" cut at 16 = "...AS ASH").
  local function statusText()
    if authState == "authed" then return "LOGGED IN" end
    if authState == "confirm_register" then return "PRESS A: NEW ACCT" end
    if authState == "need_creds" then return "SET NAME/PASS" end
    if authState == "failed" then return "LOGIN FAILED" end
    if authState == "logging_in" then return "LOGGING IN.." end
    return "OFFLINE"
  end

  local function performReset()
    pcall(function() mod.save:set("token", nil) end)
    mod.log:info("SilphNet: reset confirmed - cleared cached login")
    authState, authBusy = "need_creds", false
    friends = {}
    pendingRequests = {}
    myTrainerId = nil
    despawnAllMarkers()
  end

  -- ---- status + reset-confirm + friends-list screens -----------------------
  -- Registered here (not at the top of the file) so these closures capture
  -- the *local* state variables declared above as upvalues - Lua binds a
  -- `local` lexically from the point it's declared, so a function literal
  -- written before those declarations would close over globals of the same
  -- name instead (this bit a presence helper earlier in development -
  -- caught only via a lupa test harness, since it fails silently rather
  -- than erroring). << VERIFY >> mod.content.screens / mod.ui.push on-device.
  pcall(function()
    mod.content.screens:register("SilphNetStatus", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        -- Kick a fresh pending/friends fetch every time this screen opens,
        -- not just on the 30s pump timer - previously opening this screen
        -- (or SilphNetRequests via LEFT) right after logging in, or right
        -- after a friend's request actually landed server-side, could show
        -- stale (often empty) data for up to PRESENCE_INTERVAL seconds,
        -- which looked exactly like a dead/broken button or a missing
        -- request rather than what it actually was: data that just hadn't
        -- been fetched yet.
        if authState == "authed" then
          if not friendsBusy then fireFriendsFetch() end
          if not pendingBusy then firePendingFetch() end
        end
        function self:update(dt)
          -- Drains HTTP_RESULT directly here too, not just via
          -- world.stepped - this is the screen a fresh login sits on, and
          -- update(dt) fires every frame regardless of whether the player
          -- is standing still, unlike world.stepped which needs an actual
          -- step. Without this, a login started right at boot (before any
          -- movement) could complete server-side but sit unpopped in the
          -- channel, showing "LOGGING IN.." forever until the player
          -- happened to walk somewhere - the exact bug reported on-device.
          pcall(drainHttpResults)
          local input = g.input
          -- A/START swapped from the original layout: A now opens the
          -- friends list (feels more natural - it's the "confirm/select"
          -- button everywhere else in this mod, e.g. accepting a request,
          -- confirming a removal), and START is re-auth. Only swapped
          -- while authed, though - pre-login there's no friends list to
          -- show yet, so A keeps doing the one thing that's actually
          -- useful at that point (retry login, or confirm account
          -- creation), exactly as before. This avoids a confusing state
          -- where A opens an empty/broken friends screen before you've
          -- even logged in.
          if authState == "authed" then
            if input:wasPressed("a") then mod.ui.push(g, "SilphNetFriends") end
            if input:wasPressed("start") then beginAuth() end
          else
            if input:wasPressed("a") then
              if authState == "confirm_register" then
                mod.ui.push(g, "SilphNetRegisterConfirm")
              else
                beginAuth()
              end
            end
          end
          if input:wasPressed("b") then g.stack:pop() end
          if input:wasPressed("right") then addFriendStatus = ""; mod.ui.push(g, "SilphNetAddFriend") end
          -- Always opens, even with 0 pending - previously gated behind
          -- #pendingRequests > 0, which meant LEFT silently did nothing
          -- at 0 with no feedback at all (looked like a dead/broken
          -- button). SilphNetRequests already has a proper "NONE PENDING"
          -- empty state, so there's no reason to hide it instead of
          -- showing that.
          if input:wasPressed("left") then mod.ui.push(g, "SilphNetRequests") end
          -- RESET lives here, on SELECT, rather than as a mod option - see
          -- the options:define comment above for why.
          if input:wasPressed("select") then mod.ui.push(g, "SilphNetResetConfirm") end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("- SILPHNET -", 16, 8)
          -- The box is drawn at 20x18 TILES (8px each) starting at pixel 0,
          -- but every line of text here starts at x=16 (2 tiles in), not
          -- x=0 - so the true remaining width is AT MOST 160-16=144px
          -- (18 8px characters), not the full 20 the box itself spans. An
          -- earlier pass budgeted lines at 20 chars and missed this inset
          -- entirely, which is why "A:LOGIN ST:FRIENDS" (19 chars) still
          -- got clipped on real hardware even after being "shortened."
          --
          -- That 18-char figure ALSO assumes each glyph is exactly 8px,
          -- which isn't confirmed anywhere in the engine docs - so rather
          -- than cut it exactly to the calculated limit a second time,
          -- every line here is deliberately kept to <= 16 characters, two
          -- shorter than the calculated boundary, as a real safety margin
          -- against being wrong about glyph width again. << VERIFY >> on a
          -- real device - if this still clips, the true per-character
          -- width is bigger than 8px and this margin needs to grow further.
          -- Vertical layout hit the same margin problem as the horizontal
          -- one: the box is 18 tiles / 144px tall, and the last line was
          -- drawn at y=136 - its own 8px glyph height lands its bottom
          -- edge EXACTLY on the box's bottom border with zero margin,
          -- which is what clipped "B:BACK SL:RESET" on real hardware.
          -- Every row below is shifted up by 8px (one line) to leave a
          -- real gap above the border, same conservative-margin approach
          -- as the horizontal character budget. << VERIFY >> on-device.
          --
          -- The name sits directly under the SILPHNET title with no "NAME"
          -- label - saves a full row versus a separate labelled line. It
          -- doesn't fit on the SAME line as the title ("SILPHNET - " is 11
          -- chars, leaving only 5 for a name that can be up to 10), so
          -- this is the two-line version of that idea instead.
          Font.draw((myName or "----"):sub(1, 16), 16, 16)
          Font.draw("ID   " .. (myTrainerId or "-----"), 16, 32)
          Font.draw("STATUS", 16, 48)
          Font.draw(statusText():sub(1, 16), 16, 56)
          -- Counts distinct PEOPLE, not distinct friends[] entries - an
          -- entry exists per (friend, game_version), so a friend with two
          -- active saves would otherwise be double-counted here.
          local seenPeople, n = {}, 0
          for _, f in pairs(friends) do
            if f.account_id and not seenPeople[f.account_id] then
              seenPeople[f.account_id] = true; n = n + 1
            end
          end
          -- Reverted to the original "FRIENDS n" spacing (readable, not
          -- squashed) - the online count moved down onto the A:FRIENDS
          -- hint line instead of squeezing onto this one, per direct
          -- feedback that "FRIENDS3" (glued together) looked worse than
          -- either line looked before this feature existed.
          Font.draw("FRIENDS " .. n, 16, 72)
          Font.draw("REQUESTS " .. #pendingRequests, 16, 80)
          -- "RT"/"LT" here mean the D-PAD's right/left, NOT shoulder
          -- buttons - this device has no L/R at all (D-pad, A, B, SELECT,
          -- START only), and the actual input:wasPressed() calls above are
          -- already bound to "right"/"left" on the D-pad, never a shoulder
          -- button. The old labels ("RT:ADD", "LT:REQUEST") were just a
          -- confusing abbreviation left over from shortening this line to
          -- fix the overflow - relabeled below to say D-PAD explicitly so
          -- this doesn't read as a control that doesn't exist.
          if authState == "confirm_register" then
            Font.draw("NO ACCOUNT FOUND", 16, 96)
            Font.draw("FOR THIS NAME", 16, 104)
            Font.draw("A:CREATE ACCOUNT", 16, 112)
          elseif authState ~= "authed" then
            Font.draw("A:RETRY LOGIN", 16, 96)
            Font.draw("SET NAME+PASS IN", 16, 104)
            Font.draw("MOD OPTIONS MENU", 16, 112)
          else
            -- Online count moved here, onto the A:FRIENDS hint line
            -- itself, rather than squeezed onto the FRIENDS/REQUESTS
            -- data line above (which came out "FRIENDS3" - digits glued
            -- straight onto the label with no space, reported as looking
            -- worse than before this feature existed) or given its own
            -- ST:RE-AUTH line (also reported as too squashed, and that
            -- hint didn't exist on this screen before - re-auth already
            -- works fine unlabelled, so it's dropped rather than adding
            -- a line that wasn't there previously).
            --
            -- Now a FRIENDS-only online count (countFriendsOnline(),
            -- computed client-side from the friends list this device
            -- already has), NOT the global online_count.php figure this
            -- used to show. Reported directly as confusing: the global
            -- count includes the caller, so a player with zero friends
            -- online but who was themselves within the 5-minute window
            -- saw "A:FRIENDS(1 ON)" right next to a friends list showing
            -- everyone OFFLINE - easy to misread as "one of my friends is
            -- online" when it was actually always just them. This hint
            -- line sits directly against the friends list, so it should
            -- answer the friends-specific question; the global,
            -- self-inclusive count still exists, just moved to its own
            -- "SN ONLINE" Start Menu row instead (see below), away from
            -- anything friends-related.
            --
            -- The "(N ON)" suffix is still dropped ENTIRELY whenever
            -- nobody relevant is online (this count is 0) - per the
            -- original direct feedback this behavior was built for, it
            -- used to always show something here (even "(- ON)" before
            -- the first fetch landed, or "(0 ON)" once it landed with
            -- nobody online), which read as a placeholder rather than a
            -- real "someone's online" indicator. Still no space after the
            -- colon when it IS shown ("FRIENDS(" not "FRIENDS (") to keep
            -- this at 16 chars even at a double-digit count.
            local friendsOnlineCount = countFriendsOnline()
            local suffix = (friendsOnlineCount > 0) and ("(" .. tostring(friendsOnlineCount) .. " ON)") or ""
            Font.draw(("A:FRIENDS" .. suffix):sub(1, 16), 16, 96)
            Font.draw("DPAD R:ADD L:REQ", 16, 104)
          end
          Font.draw("B:BACK SL:RESET", 16, 120)
          -- mod.version is read straight from manifest.json, so this can
          -- never drift out of sync with a real release the way a
          -- hand-typed string would. y=128 (not 136) leaves one clear
          -- line of margin above the box's 144px bottom edge - the exact
          -- same zero-margin mistake that clipped B:BACK/SL:RESET before
          -- would repeat at y=136 (136+8=144, flush with the border).
          Font.draw("V" .. tostring(mod.version or "?"), 16, 128)
        end
        return self
      end,
    })
  end)

  -- Shown once, only when a login attempt comes back "no such account" -
  -- registration used to fire immediately and silently at that point (a
  -- real account, password hash, and Trainer ID created without the
  -- player seeing or agreeing to it). Now it only happens if the player
  -- explicitly presses A here; B backs out without creating anything,
  -- leaving authState as "confirm_register" so the player can go change
  -- MY NAME first if this wasn't the name they meant to use.
  pcall(function()
    mod.content.screens:register("SilphNetRegisterConfirm", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          local input = g.input
          if input:wasPressed("a") then doRegister(); g.stack:pop() end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("CREATE ACCOUNT?", 16, 8)
          Font.draw("NAME", 16, 32)
          Font.draw((myName or "----"):sub(1, 16), 16, 40)
          Font.draw("NO SILPHNET ACCT", 16, 56)
          Font.draw("EXISTS FOR THIS", 16, 64)
          Font.draw("NAME. A NEW ONE", 16, 72)
          Font.draw("WILL BE MADE.", 16, 80)
          Font.draw("A:CREATE", 16, 120)
          Font.draw("B:CANCEL", 16, 128)
        end
        return self
      end,
    })
  end)

  pcall(function()
    mod.content.screens:register("SilphNetResetConfirm", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          local input = g.input
          if input:wasPressed("a") then performReset(); g.stack:pop() end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("RESET SILPHNET?", 16, 8)
          -- Kept to <= 16 chars/line, same conservative margin as
          -- SilphNetStatus - MY NAME can be up to 10 chars (FIELD_MAXLEN),
          -- so "NAME   " (7 chars) + a full-length name would overflow.
          Font.draw("NAME", 16, 32)
          Font.draw((myName or "----"):sub(1, 16), 16, 40)
          Font.draw("CLEARS SAVED", 16, 56)
          Font.draw("LOGIN ON THIS", 16, 64)
          Font.draw("DEVICE ONLY", 16, 72)
          Font.draw("A:CONFIRM RESET", 16, 120)
          Font.draw("B:CANCEL", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Simple paged list - one friend per screen, LEFT/RIGHT (or A) to page
  -- through, since there's no scrolling list widget documented in the mod
  -- UI API. Good enough for the friend-counts expected here.
  pcall(function()
    mod.content.screens:register("SilphNetFriends", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, page = 1 }
        local function sortedIds()
          local ids = {}
          for id in pairs(friends) do ids[#ids + 1] = id end
          table.sort(ids, function(a, b) return (friends[a].name or "") < (friends[b].name or "") end)
          return ids
        end
        function self:update(dt)
          local input = g.input
          local ids = sortedIds()
          -- A used to double as "page right" here (alongside DPAD RIGHT) -
          -- moved to DPAD-only paging now that A opens the new friend
          -- detail screen instead, same reasoning as the Nearby screen
          -- (which already paged on DPAD RIGHT/LEFT, not A, from the
          -- start) - A needed to mean one thing consistently, not
          -- "page" on this screen and "open" on the next one.
          if input:wasPressed("right") then
            self.page = (#ids == 0) and 1 or (self.page % #ids) + 1
          end
          if input:wasPressed("left") then
            self.page = (#ids == 0) and 1 or ((self.page - 2) % #ids) + 1
          end
          -- A opens the detail screen for whoever's currently on screen -
          -- pendingFriendDetail set here, same "set state, then push"
          -- pattern as pendingRemoveFriend/SELECT below. Fires a fresh
          -- fetch immediately rather than waiting on whatever's left over
          -- from a previous visit to a DIFFERENT friend's detail screen.
          if input:wasPressed("a") and #ids > 0 then
            local f = friends[ids[self.page]]
            if f and f.account_id then
              -- game_version no longer part of pendingFriendDetail - the
              -- detail screen now fetches and cycles through ALL of this
              -- friend's versions in one go (see friend_detail.php),
              -- rather than being pointed at one specific version up
              -- front. Which friends-list ROW you pressed A on no longer
              -- matters for what the detail screen shows - a friend with
              -- two versions shows the exact same detail screen whether
              -- you opened it from their BLUE row or their YELLOW row.
              pendingFriendDetail = { account_id = f.account_id, name = f.name or "?" }
              friendDetail = nil
              friendDetailState = "loading"
              fireFriendDetailFetch(f.account_id)
              mod.ui.push(g, "SilphNetFriendDetail")
            end
          end
          -- SELECT opens a confirm screen for the friend currently on
          -- screen, same "don't delete on one button press" pattern as
          -- SilphNetResetConfirm. pendingRemoveFriend is a module-level
          -- local (declared near the other pending* state) so the confirm
          -- screen, opened fresh via mod.ui.push, knows who it's about
          -- without needing extra plumbing through the push call itself.
          if input:wasPressed("select") and #ids > 0 then
            local f = friends[ids[self.page]]
            if f and f.account_id then
              pendingRemoveFriend = { account_id = f.account_id, name = f.name or "?" }
              mod.ui.push(g, "SilphNetRemoveFriendConfirm")
            end
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          local ids = sortedIds()
          if #ids == 0 then
            Font.draw("FRIENDS", 16, 8)
            Font.draw("NO FRIENDS YET", 16, 40)
          else
            local id = ids[self.page]
            local f = friends[id]
            local lastSeenUnix = parseMysqlDatetimeUtc(f.last_seen)
            local ago = timeAgoText(lastSeenUnix)
            local isOnline = lastSeenUnix and (os.time() - lastSeenUnix) <= OFFLINE_AFTER
            -- "FRIENDS" is back on this line alongside the counter now
            -- that the version tag moved down onto the ONLINE/OFFLINE
            -- line instead (see below) - "FRIENDS 1/3" is only 11 chars
            -- (worst realistic case "FRIENDS 99/99" is 13), comfortably
            -- under the 16-char budget now that this line isn't also
            -- carrying a version tag. Dropped briefly in an earlier
            -- round specifically because "FRIENDS 1/3 (YELLOW)" would
            -- have overflowed - that reason no longer applies once the
            -- version moved elsewhere, so the title text is restored.
            Font.draw("FRIENDS " .. (self.page) .. "/" .. #ids, 16, 8)
            -- This screen is genuinely at its 144px limit (18 rows,
            -- same real box every screen in this file uses) - moving the
            -- counter up here only frees ONE row (8px), not room for a
            -- generically taller layout. name/id keep their original
            -- spacing below (40/48) since that was never what was
            -- reported as squashed - the actual complaint was
            -- specifically the GAP between the last data row ("N HR
            -- AGO") and the first hint row, which used to be only 8px
            -- (104 -> 112). The one reclaimed row goes exactly there
            -- instead: ago stays at 104, but the hint block now starts
            -- at 120 instead of 112, giving that specific gap real
            -- clearance. This is why A:DETAIL and LEFT/RIGHT:PAGE are
            -- now combined onto one line below - keeping all 3 hint
            -- lines separate AND adding this clearance would have
            -- overflowed the box; combining two of them was the only way
            -- to free a full row for where the complaint actually was.
            Font.draw((f.name or "?"):sub(1, 16), 16, 40)
            -- friends.php already returns trainer_id (zero-padded, same as
            -- everywhere else it's shown).
            Font.draw("ID   " .. (f.trainer_id or "-----"), 16, 48)
            -- Version tag now lives HERE, next to ONLINE, not on the page
            -- counter line - checked by hand against every real version
            -- name: RED=12, BLUE=13, YELLOW=15, GOLD=13, SILVER=15,
            -- CRYSTAL=16 (the longest - "ONLINE (CRYSTAL)" lands exactly
            -- on the 16-char/line budget, not past it, the same way other
            -- exactly-16-char lines elsewhere in this file already do).
            -- Still only shown while this specific entry is ONLINE -
            -- offline, no version at all, regardless of how many
            -- versions this friend has (per earlier direct feedback:
            -- "when they are online, it should show the version they are
            -- playing, simple, offline, no version at all").
            if isOnline then
              Font.draw(("ONLINE (" .. (f.game_version or "UNKNOWN") .. ")"):sub(1, 16), 16, 56)
            else
              Font.draw("OFFLINE", 16, 56)
            end
            if f.map_id then
              Font.draw(friendlyMapName(f.map_id):sub(1, 16), 16, 72)
              Font.draw("(" .. tostring(f.x) .. "," .. tostring(f.y) .. ")", 16, 88)
              Font.draw(ago, 16, 104)
            else
              Font.draw("NEVER SEEN YET", 16, 72)
            end
          end
          -- A:DETAIL and LEFT/RIGHT:PAGE combined onto ONE hint line
          -- ("A:DETAIL LR:PAGE", exactly 16 chars) instead of two
          -- separate lines - see the long comment above for why: this
          -- screen has no spare row left to add real clearance above the
          -- hint block AND keep 3 separate hint lines, so two were
          -- merged to free the row that clearance needed. Shown only
          -- with >=1 friend (nothing to open/page with none).
          -- LEFT/RIGHT:PAGE part only actually applies with >1 friend,
          -- but it's cheap/harmless to show "LR:PAGE" even with exactly
          -- 1 friend (pressing it just does nothing) - simpler than
          -- drawing two different variants of this merged line.
          if #ids > 0 then Font.draw("A:DETAIL LR:PAGE", 16, 120) end
          Font.draw("B:BACK SL:REMOVE", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Per-friend detail screen - pushed via A on a friend in SilphNetFriends.
  -- Two pages, DPAD LEFT/RIGHT between them (same paging convention as
  -- every other multi-page screen in this file): STATS (badges, Pokedex
  -- seen/caught, League wins, money - all self-reported by the friend's
  -- own client via stats.php, since a mod can only ever read ITS OWN
  -- game.save, never a friend's) and ACTIVITY (their latest status
  -- message with its OWN time-ago, plus last-seen repeated from the main
  -- friends screen - deliberately not moved off that screen, just also
  -- shown here). These are two genuinely different timestamps - catching
  -- something and being last seen online are different moments (a friend
  -- could catch something then go offline, or still be walking around
  -- minutes after) - so they're never collapsed into one "X AGO" line.
  pcall(function()
    mod.content.screens:register("SilphNetFriendDetail", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, slot = 1, partyIndex = 1 }
        -- Builds the flat A-press cycle from friendDetail.versions: THREE
        -- slots per version now (STATS, then PARTY, then ACTIVITY), in
        -- whatever order friend_detail.php returned versions (already
        -- sorted alphabetically server-side). A version with neither
        -- stats nor activity was already excluded server-side (see
        -- friend_detail.php), so every version reaching this point gets
        -- all three of its slots - "NO STATS YET"/"NO ACTIVITY YET"/
        -- "NO PARTY DATA" still cover the case where a version has some
        -- but not all of the three. PARTY rides the same "stats" upload
        -- (see readStatsSnapshot's party field) rather than being its own
        -- separate slot source, so it's driven off v.stats.party here,
        -- not a fourth top-level friendDetail field. Recomputed fresh
        -- each call rather than cached on self, since friendDetail can
        -- change (a fresh fetch lands) without this screen being
        -- re-created.
        local function slots()
          local out = {}
          for _, v in ipairs((friendDetail and friendDetail.versions) or {}) do
            -- v is { game_version, stats, activity } per version (see
            -- drainHttpResults' friend_detail parsing) - each slot
            -- carries its OWN copy of stats/activity straight from that
            -- version entry, not a shared/looked-up reference, so
            -- draw() below never has to re-match version strings.
            out[#out + 1] = { kind = "STATS", version = v.game_version, stats = v.stats, activity = v.activity }
            out[#out + 1] = { kind = "PARTY", version = v.game_version, stats = v.stats, activity = v.activity }
            out[#out + 1] = { kind = "ACTIVITY", version = v.game_version, stats = v.stats, activity = v.activity }
          end
          return out
        end
        function self:update(dt)
          -- Same reasoning as every other screen here that waits on a
          -- network result while sitting still (SilphNetStatus, Add
          -- Friend, Remove Friend confirm) - without this, a fetch that
          -- finishes while the player isn't walking would sit fully
          -- complete but undrained until they happened to step
          -- somewhere else first.
          pcall(drainHttpResults)
          local input = g.input
          -- A is the ONLY navigation button on this screen now - cycles
          -- STATS -> ACTIVITY -> next version's STATS -> ACTIVITY -> ...
          -- and wraps back to the first slot, in one flat loop, per
          -- direct feedback requesting exactly this instead of the
          -- previous two-axis LEFT/RIGHT-for-page + SELECT-for-version
          -- scheme. Only versions with real stats/activity data appear
          -- at all (enforced server-side by friend_detail.php) - a
          -- friend who's only ever played one version just gets a
          -- 2-slot loop (STATS, ACTIVITY), identical in feel to how this
          -- screen worked before this change.
          if input:wasPressed("a") then
            local s = slots()
            if #s > 0 then
              self.slot = (self.slot % #s) + 1
              -- Sub-paging within a friend's party (which mon of up to
              -- 6 is showing) is independent of the main A-press cycle -
              -- reset back to the first mon every time A moves onto a
              -- NEW slot (whether that's this same friend's PARTY page
              -- on a different version, or landing back on PARTY after
              -- cycling all the way around), so this never leaves a
              -- stale "mon 4 of 6" position sitting behind a page that
              -- looks freshly opened.
              self.partyIndex = 1
            end
          end
          -- LEFT/RIGHT only do anything while sitting on a PARTY slot -
          -- paging between this friend's individual party mons, one per
          -- screen (per direct feedback: "one mon per screen, paged is
          -- the best"). Distinct axis from A's STATS/PARTY/ACTIVITY
          -- cycle, same convention SilphNetFriends already uses (A for
          -- one axis, LEFT/RIGHT for a different, narrower one).
          local s = slots()
          local cur = (#s > 0 and self.slot <= #s) and s[self.slot] or nil
          if cur and cur.kind == "PARTY" then
            local partyStr = cur.stats and cur.stats.party
            local mons = decodePartySnapshot(partyStr)
            if #mons > 0 then
              if input:wasPressed("left") then
                self.partyIndex = self.partyIndex - 1
                if self.partyIndex < 1 then self.partyIndex = #mons end
              elseif input:wasPressed("right") then
                self.partyIndex = (self.partyIndex % #mons) + 1
              end
            end
          end
          if input:wasPressed("b") then
            pendingFriendDetail = nil
            g.stack:pop()
          end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          local name = (pendingFriendDetail and pendingFriendDetail.name or "?"):sub(1, 16)
          -- Set below, only when currently sitting on a PARTY slot with
          -- more than one real mon to page through - read by the hint
          -- line at the very bottom of this function. Declared here
          -- (rather than re-deriving from slots()/self.slot a second
          -- time down there) so the hint line doesn't need its own
          -- redundant slots() call and version of this same check.
          local showsPartyPaging = false
          if friendDetailState == "loading" then
            Font.draw(name, 16, 8)
            Font.draw("LOADING...", 16, 40)
          elseif friendDetailState == "failed" then
            Font.draw(name, 16, 8)
            Font.draw("COULDN'T LOAD", 16, 40)
            Font.draw("TRY AGAIN LATER", 16, 48)
          else
            local s = slots()
            if #s == 0 then
              -- Accepted friend, but genuinely nothing to show yet on
              -- ANY version (never uploaded stats or activity at all) -
              -- distinct from "NO STATS YET" on a specific version's
              -- page, since there isn't even a page to land on here.
              Font.draw(name, 16, 8)
              Font.draw("NO DATA YET", 16, 32)
              Font.draw("(NOT UPLOADED", 16, 40)
              Font.draw("BY THEM YET)", 16, 48)
            else
              if self.slot > #s then self.slot = 1 end
              local cur = s[self.slot]
              -- Title is "<name> STATS"/"<name> ACTIVITY" (y=8), with the
              -- game version on its OWN line right underneath (y=16) -
              -- e.g. "ARCHADA STATS" / "BLUE" - rather than folded onto
              -- the same line or onto a hint line further down, per
              -- direct feedback ("wouldn't it just be better if it
              -- said... ARCHADA STATS / BLUE"). Shown for every friend,
              -- even ones with only one version - it's now just part of
              -- reading the page, not a conditional disambiguation hint.
              Font.draw((name .. " " .. cur.kind):sub(1, 16), 16, 8)
              Font.draw(cur.version:sub(1, 16), 16, 16)
              if cur.kind == "STATS" then
                -- 5 data rows, y=32 to y=96 (16px apart) - checked
                -- against a real pixel mockup after an earlier draft
                -- collided its own LEAGUE WINS/MONEY lines with the
                -- hint row below. Shifted down from where they sat
                -- before the version got its own title line (was y=8
                -- start with data from y=32; version's extra line
                -- didn't need to push these down further since y=16 was
                -- already spare room above y=32).
                local st = cur.stats
                if not st then
                  Font.draw("NO STATS YET", 16, 32)
                  Font.draw("(NOT UPLOADED", 16, 40)
                  Font.draw("BY THEM YET)", 16, 48)
                else
                  -- "BADGES" + right-padded count, same left-label/
                  -- right-value layout as every stats-style line
                  -- elsewhere in this file (e.g. FRIENDS/REQUESTS). Max
                  -- is 8 on a Gen 1 save but 16 on Gen 2 (8 Johto + 8
                  -- Kanto, see countGen2Badges) - a real bug caught here
                  -- (not by testing, by being asked directly whether Gen 2
                  -- badges displayed sensibly): this used to hardcode "/8"
                  -- unconditionally, which would have shown something
                  -- like "BADGES     12/8" for a Gold/Silver friend.
                  -- cur.version is this specific page's own game_version
                  -- (e.g. "BLUE" or "GOLD"), already in scope - "BADGES
                  -- 16/16" is 16 chars exactly, still comfortably within
                  -- budget at the maximum either way.
                  local badgeMax = isGen2(cur.version) and 16 or 8
                  Font.draw("BADGES     " .. tostring(tonumber(st.badges) or 0) .. "/" .. badgeMax, 16, 32)
                  Font.draw("SEEN     " .. tostring(tonumber(st.pokedex_seen) or 0), 16, 48)
                  Font.draw("CAUGHT   " .. tostring(tonumber(st.pokedex_caught) or 0), 16, 64)
                  Font.draw("LEAGUE WINS " .. tostring(tonumber(st.league_wins) or 0), 16, 80)
                  -- Money can be up to 6 digits (real games cap at
                  -- 999999) - "MONEY  " (7 chars) + 6 digits = 13,
                  -- comfortably under 16 even at the maximum.
                  Font.draw("MONEY  " .. tostring(tonumber(st.money) or 0), 16, 96)
                  -- Time played - the one spare row this page had left
                  -- (y=112, between MONEY and the old hint line) before
                  -- the hint line moved down to y=120 to make room (see
                  -- below). Requested directly ("I wanted to add TIME
                  -- PLAYED, but I think we missed it" - save.playTime was
                  -- confirmed readable in the original save-format
                  -- research but never actually wired into the stats
                  -- upload/schema/screen until now).
                  Font.draw(playTimeText(st.play_seconds), 16, 112)
                end
              elseif cur.kind == "PARTY" then
                -- One mon per screen, paged with LEFT/RIGHT (see
                -- self:update's partyIndex handling above) - per direct
                -- feedback ("one mon per screen, paged is the best"),
                -- not a compact truncated list. No sprite - the mod API
                -- has no documented way to draw a species sprite outside
                -- the overworld NPC system (mod.world:spawnNpc), only
                -- text via Font.draw/drawBox, confirmed by checking the
                -- wiki's Reference-Mod-Object page directly rather than
                -- guessing a plausible-sounding call - so this stays
                -- text-only, same as every other screen in this file.
                local mons = decodePartySnapshot(cur.stats and cur.stats.party)
                showsPartyPaging = #mons > 1
                if #mons == 0 then
                  Font.draw("NO PARTY DATA", 16, 32)
                  Font.draw("(NOT UPLOADED", 16, 40)
                  Font.draw("BY THEM YET)", 16, 48)
                else
                  if self.partyIndex > #mons then self.partyIndex = 1 end
                  local mon = mons[self.partyIndex]
                  -- Version line (already drawn above, shared with
                  -- STATS/ACTIVITY) gets "n/total" appended rather than
                  -- its own extra row - this screen has one row less of
                  -- headroom than STATS/ACTIVITY once 4 move lines are
                  -- accounted for (32 through 112 = 6 rows exactly:
                  -- species+level, HP, then 4 moves), so the version
                  -- line is overwritten here with the combined form
                  -- instead of adding a 7th row. "BLUE 1/6" style,
                  -- comfortably under 16 chars even at the max (a 2-char
                  -- version name would be unusual, but even "YELLOW 6/6"
                  -- is only 10 chars).
                  Font.draw((cur.version .. " " .. self.partyIndex .. "/" .. #mons):sub(1, 16), 16, 16)
                  -- Species + level, one line - longest real Gen 1
                  -- species name (TENTACRUEL, 10 chars) + " LV" + up to
                  -- 3 digits comfortably fits 16 chars (10+3+3=16 at the
                  -- absolute worst case, checked by hand, not assumed).
                  -- formatSpeciesName shortens a Gen 2 "_MALE"/"_FEMALE"
                  -- suffix to a real ♂/♀ glyph first - mon.species here is the
                  -- raw id decodePartySnapshot returned unchanged, same as
                  -- what's actually stored server-side (see
                  -- encodePartySnapshot's own comment on why the wire
                  -- format stays raw) - so this is still :sub(1,16)
                  -- afterward purely as the same defensive cap every
                  -- other line here already has, not expected to
                  -- routinely cut anything short now.
                  Font.draw((formatSpeciesName(mon.species) .. " LV" .. mon.level):sub(1, 16), 16, 32)
                  Font.draw("HP " .. mon.hp .. "/" .. mon.maxHp, 16, 48)
                  -- Up to 4 moves, one per line, packed at consecutive
                  -- 8px rows (y=64,72,80,88) instead of the previous
                  -- double-height 16px spacing (y=64,80,96,112) - caught
                  -- directly via a real report that the 4th move (at the
                  -- old y=112) sat right on top of the hint line at
                  -- y=120, with no visible gap between them. Each move is
                  -- one short line with nothing else on its row, so a
                  -- full 16px (two GB text rows) per move was never
                  -- actually needed - packing them tight frees three
                  -- clear rows (y=96/104/112) versus the old layout, all
                  -- unused now rather than crowding the hint. The longest
                  -- real Gen 1 move names (e.g. "DOUBLE-EDGE",
                  -- "SOLARBEAM") are comfortably under 16 chars on their
                  -- own line without truncation; :sub(1,16) here is
                  -- purely defensive, not expected to ever actually cut a
                  -- real move name short.
                  for i = 1, 4 do
                    if mon.moves[i] then
                      Font.draw(mon.moves[i]:sub(1, 16), 16, 64 + (i - 1) * 8)
                    end
                  end
                end
              else
                local act = cur.activity
                if act and act.message then
                  -- Two lines, not one - a species name like BLASTOISE
                  -- is long enough that cramming "CAUGHT LVL 25
                  -- BLASTOISE" onto one line risked overflowing the
                  -- 16-char budget, per direct feedback. Stored
                  -- server-side as one string joined by a literal "\n"
                  -- (see queueCatchActivity) - split back into two lines
                  -- only here, where it's drawn. A pre-v1.5.0
                  -- single-line activity message (no newline in it)
                  -- still draws fine - line2 is just "" in that case.
                  local line1, line2 = act.message:match("^([^\n]*)\n?(.*)$")
                  Font.draw((line1 or ""):sub(1, 16), 16, 32)
                  Font.draw((line2 or ""):sub(1, 16), 16, 40)
                  Font.draw(timeAgoText(parseMysqlDatetimeUtc(act.created_at)), 16, 48)
                else
                  Font.draw("NO ACTIVITY YET", 16, 32)
                end
                -- Last-seen repeated here from the main friends screen -
                -- NOT moved, that screen still shows it exactly as
                -- before. This is the single most-recent presence row
                -- across ALL of this friend's versions (see
                -- friend_detail.php), not scoped to the version this
                -- particular ACTIVITY page happens to be showing - "last
                -- seen" means "when were they last online AT ALL",
                -- which is a property of the friend, not of one save.
                -- Deliberately its own time-ago, not the activity
                -- message's - they can genuinely differ (catching
                -- something and going offline are different moments).
                local pr = friendDetail and friendDetail.presence
                if pr and pr.map_id then
                  Font.draw("LAST SEEN", 16, 72)
                  Font.draw(friendlyMapName(pr.map_id):sub(1, 16), 16, 80)
                  Font.draw(timeAgoText(parseMysqlDatetimeUtc(pr.last_seen)), 16, 88)
                else
                  Font.draw("NEVER SEEN YET", 16, 72)
                end
              end
            end
          end
          -- Hint line moved down from y=112 to y=120 - that row is now
          -- TIME PLAYED's spot on the STATS page (see above). Still one
          -- clear line of margin above the box's 144px bottom edge, same
          -- rule every screen in this file follows.
          --
          -- Only the PARTY page (with more than one real mon to page
          -- through) adds "LR:MON" to the hint and a second hint row -
          -- STATS/ACTIVITY/NO-DATA cases (and a single-mon PARTY page,
          -- which has nothing to page between) have no LEFT/RIGHT
          -- behavior to advertise, so their hint stays exactly as it
          -- was before this page existed.
          if friendDetailState == "idle" then
            Font.draw(showsPartyPaging and "LR:MON A:NEXT" or "A:NEXT B:BACK", 16, 120)
          else
            Font.draw("B:BACK", 16, 120)
          end
          if showsPartyPaging then Font.draw("B:BACK", 16, 128) end
        end
        return self
      end,
    })
  end)

  -- Nearby players - who else (friend or not) is currently on YOUR map,
  -- reached via its own Start Menu row ("SN NEARBY") rather than a mode
  -- toggle bolted onto SilphNetFriends. Deliberately much simpler than
  -- Friends - just a name and Trainer ID per page, no map/tile/time-ago,
  -- since these are people you haven't added yet and the mod has no
  -- relationship with them beyond "currently on your map". Add-by-ID
  -- still goes through the existing Add Friend screen (DPAD RIGHT from
  -- the SilphNet status screen) using the Trainer ID shown here - no
  -- separate "add" action wired up directly from this screen, to avoid
  -- duplicating that flow in two places.
  pcall(function()
    mod.content.screens:register("SilphNetNearby", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, page = 1 }
        -- A nearby entry is only "account_id" - friends are keyed on
        -- "account_id|game_version" (one friend can have several active
        -- saves), so this checks by account_id alone across every
        -- friends[] entry rather than reconstructing that composite key.
        -- Without this, a friend standing right next to you would have
        -- shown "NOT YET A FRIEND" here, which is wrong - caught before
        -- shipping by walking through what this screen would say for
        -- someone you'd already added.
        -- Moved above self:update (was below, after draw's own copy was
        -- written) so update can use it too now that START triggers a
        -- real add-friend action here - a nested function can only see a
        -- local declared before it lexically, not one declared later in
        -- the same enclosing scope, regardless of call order.
        local function isAlreadyFriend(accountId)
          if not accountId then return false end
          for _, f in pairs(friends) do
            if f.account_id == accountId then return true end
          end
          return false
        end
        function self:update(dt)
          local input = g.input
          if input:wasPressed("right") or input:wasPressed("a") then
            self.page = (#nearby == 0) and 1 or (self.page % #nearby) + 1
          end
          if input:wasPressed("left") then
            self.page = (#nearby == 0) and 1 or ((self.page - 2) % #nearby) + 1
          end
          -- START jumps straight to Add Friend with this entry's Trainer
          -- ID already filled in - added directly in response to a
          -- report that the old hint text implied a one-button add that
          -- didn't actually exist (see SilphNetAddFriend's prefillId
          -- handling). Only wired up when there's a real, addable entry
          -- on screen - a no-op otherwise, same as every other button
          -- here already guards against an empty list.
          if input:wasPressed("start") then
            local n = nearby[self.page]
            if n and n.trainer_id and not isAlreadyFriend(n.account_id) then
              addFriendStatus = ""
              mod.ui.push(g, "SilphNetAddFriend", { prefillId = n.trainer_id })
            end
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          -- Two-line title, matching the "- X -" framing used elsewhere in
          -- this file (e.g. SilphNetAbout's "- SILPHNET -"): the count on
          -- the first line answers "how many people" before you even page
          -- through, the current map on the second says where they are -
          -- both real, useful context that a bare "NEARBY" didn't give.
          -- No "- X -" framing on the map name line - every real map name
          -- in FRIENDLY_MAP_NAMES fits in 16 chars on its own (longest are
          -- CINNABAR ISLAND / VIRIDIAN FOREST at 15), but the dash framing
          -- ("- " + " -" = 4 chars) would have pushed those over. The
          -- title line keeps its dashes since "NEARBY (n)" is always
          -- short. sub(1, 16) stays as a backstop in case a map id ever
          -- falls through to the unmapped fallback (mapId with
          -- underscores swapped for spaces) and comes out longer than
          -- every name in the real table.
          Font.draw("- NEARBY (" .. #nearby .. ") -", 16, 8)
          Font.draw(friendlyMapName(myMap):sub(1, 16), 16, 16)
          if #nearby == 0 then
            Font.draw("NO ONE ELSE HERE", 16, 48)
          else
            local n = nearby[self.page]
            Font.draw((self.page) .. "/" .. #nearby, 16, 40)
            Font.draw((n.name or "?"):sub(1, 16), 16, 48)
            Font.draw("ID   " .. (n.trainer_id or "-----"), 16, 56)
            if isAlreadyFriend(n.account_id) then
              Font.draw("ALREADY A FRIEND", 16, 72)
            else
              Font.draw("NOT YET A FRIEND", 16, 72)
              -- Was "RIGHT:ADD FRIEND" / "ON STATUS SCREEN" - genuinely
              -- misleading, reported directly: RIGHT is ALREADY bound on
              -- this very screen (paging to the next nearby entry), so
              -- the hint read as "press RIGHT to add this friend" when
              -- RIGHT does something else entirely here. Briefly
              -- reworded to describe going to the Status screen instead,
              -- then upgraded again to a REAL working shortcut once
              -- START (genuinely unbound on this screen) turned out to
              -- be free: it now pushes SilphNetAddFriend with this
              -- entry's Trainer ID already filled in, so the hint can
              -- finally name a button that actually does the thing it
              -- says.
              Font.draw("START:ADD FRIEND", 16, 80)
            end
          end
          if #nearby > 1 then Font.draw("LEFT/RIGHT:PAGE", 16, 112) end
          Font.draw("B:BACK", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Confirm-before-delete for removing a friend, opened from SilphNetFriends
  -- via SELECT - same reasoning as SilphNetResetConfirm: a destructive
  -- action gets its own screen rather than firing on a single button press
  -- on the list itself. pendingRemoveFriend is set by SilphNetFriends right
  -- before this screen is pushed (see above).
  pcall(function()
    mod.content.screens:register("SilphNetRemoveFriendConfirm", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          -- Same reasoning as SilphNetStatus/SilphNetAddFriend above -
          -- without this, "REMOVING..." could hang the same way "SENDING..."
          -- did, waiting on a step that might not come for a while.
          pcall(drainHttpResults)
          local input = g.input
          -- Once A has been pressed, removeFriendState moves to "removing"
          -- and this screen waits for the REAL server result (set by the
          -- remove_friend handler in handleHttpResult) before popping -
          -- rather than popping immediately and leaving SilphNetFriends
          -- showing the just-"removed" friend for the brief window before
          -- the async HTTP result (and its own fireFriendsFetch/
          -- firePendingFetch) actually lands, which could read as "that
          -- didn't work." B still cancels immediately at any point before
          -- a removal is actually in flight.
          if removeFriendState == "idle" then
            if input:wasPressed("a") then
              if pendingRemoveFriend then
                fireRemoveFriend(pendingRemoveFriend.account_id)
                removeFriendState = "removing"
              else
                g.stack:pop()
              end
            end
            if input:wasPressed("b") then pendingRemoveFriend = nil; g.stack:pop() end
          elseif removeFriendState == "done" or removeFriendState == "failed" then
            -- The remove_friend handler (handleHttpResult) sets this state
            -- AND fires fireFriendsFetch()/firePendingFetch() in the same
            -- moment - but those are separate async HTTP calls that only
            -- START here, they don't finish here. Popping straight back to
            -- SilphNetFriends at this point meant it redrew from the OLD
            -- in-memory `friends` table (still containing the just-removed
            -- friend) until that third round-trip eventually landed - the
            -- exact bug reported on-device: the removed friend stayed
            -- visible until backing out and back in, or removing again.
            -- Waiting here for friendsBusy/pendingBusy to clear means this
            -- screen only pops once the friends list is ACTUALLY current.
            if not friendsBusy and not pendingBusy then
              pendingRemoveFriend = nil
              removeFriendState = "idle"
              g.stack:pop()
            end
          end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("REMOVE FRIEND?", 16, 8)
          Font.draw("NAME", 16, 32)
          Font.draw(((pendingRemoveFriend and pendingRemoveFriend.name) or "?"):sub(1, 16), 16, 40)
          if removeFriendState == "removing" or removeFriendState == "done" or removeFriendState == "failed" then
            -- Covers the whole wait, not just the first round-trip - once
            -- remove_friend.php responds, this screen still waits for the
            -- follow-up friends/pending re-fetch to land (see the update()
            -- comment above) before popping, so it should keep showing a
            -- busy state the whole time rather than flashing back to the
            -- original confirmation text for that gap.
            Font.draw("REMOVING...", 16, 56)
          else
            Font.draw("THEY WON'T SEE", 16, 56)
            Font.draw("YOUR POSITION", 16, 64)
            Font.draw("ANYMORE", 16, 72)
          end
          Font.draw("A:CONFIRM REMOVE", 16, 120)
          Font.draw("B:CANCEL", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Add a friend by Trainer ID - a 5-digit spinner (D-pad UP/DOWN changes
  -- the selected digit 0-9, LEFT/RIGHT moves which digit is selected, A
  -- confirms, B cancels). Deliberately not a text-entry screen: Trainer ID
  -- is numbers-only, so a purpose-built digit spinner needs no naming-grid
  -- (or unverified mod.ui.NamingScreen) at all - just game.input polling,
  -- the same pattern every other screen in this file already uses.
  pcall(function()
    mod.content.screens:register("SilphNetAddFriend", {
      -- args.prefillId (added for the SN NEARBY/SN ONLINE "START:ADD
      -- FRIEND" shortcuts): a Trainer ID string to load straight into
      -- the digit spinner on open, so the player doesn't have to retype
      -- an ID they were just looking at on another screen. Same
      -- args-reaching-new() mechanism SilphNetMarkerTalk already relies
      -- on (args.slot there) - not re-verifying it here since that
      -- screen's own use of it already ships and works.
      new = function(g, args)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, digits = { 0, 0, 0, 0, 0 }, cursor = 1 }
        local prefillId = args and args.prefillId
        if prefillId then
          -- Defensive against anything other than a clean 5-digit
          -- string: strip non-digits, left-pad short values (a real
          -- Trainer ID can start with leading zeros, e.g. "00423"), and
          -- keep only the rightmost 5 characters of anything longer
          -- rather than erroring or leaving digits blank.
          local s = tostring(prefillId):gsub("%D", "")
          if #s > 0 then
            if #s < 5 then s = string.rep("0", 5 - #s) .. s end
            s = s:sub(-5)
            for i = 1, 5 do
              self.digits[i] = tonumber(s:sub(i, i)) or 0
            end
          end
        end
        function self:update(dt)
          -- Same reasoning as SilphNetStatus above: drains HTTP_RESULT
          -- directly so a request that finishes while sitting on this
          -- screen (not walking) resolves the SAME frame it completes on,
          -- rather than getting stuck on "SENDING..." until the player
          -- happens to take a step elsewhere - the second on-device bug
          -- report, same root cause as the login one.
          pcall(drainHttpResults)
          local input = g.input
          if input:wasPressed("up") then
            self.digits[self.cursor] = (self.digits[self.cursor] + 1) % 10
          end
          if input:wasPressed("down") then
            self.digits[self.cursor] = (self.digits[self.cursor] - 1) % 10
          end
          if input:wasPressed("right") then self.cursor = (self.cursor % 5) + 1 end
          if input:wasPressed("left") then self.cursor = ((self.cursor - 2) % 5) + 1 end
          if input:wasPressed("a") then
            local idStr = table.concat(self.digits)
            fireAddFriend(idStr)
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("ADD FRIEND", 16, 8)
          Font.draw("ENTER TRAINER ID", 16, 32)
          local row = ""
          for i = 1, 5 do
            row = row .. tostring(self.digits[i]) .. (i == self.cursor and "^" or " ")
          end
          Font.draw(row, 16, 56)
          -- addFriendStatus can be "REQUEST SENT TO <name>" or "ERROR:
          -- <server text>" - both unbounded in length, so truncated to
          -- the same conservative 16-char budget as every other line.
          if addFriendStatus ~= "" then Font.draw(addFriendStatus:sub(1, 16), 16, 80) end
          Font.draw("UP/DOWN:DIGIT", 16, 104)
          Font.draw("LEFT/RIGHT:MOVE", 16, 112)
          Font.draw("A:SEND  B:BACK", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Incoming friend requests - same one-per-screen paging as SilphNetFriends.
  -- A accepts (fires accept_friend.php, then re-fetches both pending and
  -- friends lists), B goes back without deciding either way.
  pcall(function()
    mod.content.screens:register("SilphNetRequests", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, page = 1 }
        -- Same reasoning as SilphNetStatus above: fetch fresh the moment
        -- this screen opens, not just on the 30s timer, so pressing LEFT
        -- from the status screen always shows the true current pending
        -- list rather than whatever was last polled (which could be
        -- several seconds - or, right after login, a full PRESENCE_INTERVAL
        -- - out of date).
        if authState == "authed" and not pendingBusy then firePendingFetch() end
        function self:update(dt)
          -- Same reasoning as SilphNetStatus/SilphNetAddFriend above - this
          -- screen stays open after A (doesn't pop), so without this the
          -- accepted request could keep showing here until the player
          -- happened to take a step elsewhere.
          pcall(drainHttpResults)
          local input = g.input
          local n = #pendingRequests
          if input:wasPressed("right") then self.page = (n == 0) and 1 or (self.page % n) + 1 end
          if input:wasPressed("left") then self.page = (n == 0) and 1 or ((self.page - 2) % n) + 1 end
          if input:wasPressed("a") and n > 0 then
            local req = pendingRequests[self.page]
            if req and req.name then
              httpAsyncGet("accept_friend", "/accept_friend.php",
                { token = mod.save:get("token") or "", requester_name = req.name })
            end
            if self.page > 1 then self.page = self.page - 1 end
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("REQUESTS", 16, 8)
          local n = #pendingRequests
          if n == 0 then
            Font.draw("NONE PENDING", 16, 40)
          else
            local req = pendingRequests[self.page]
            Font.draw(self.page .. "/" .. n, 16, 32)
            Font.draw(tostring(req.name or "?"):sub(1, 16), 16, 40)
            Font.draw("ID " .. tostring(req.trainer_id or "-----"), 16, 48)
            Font.draw("A:ACCEPT", 16, 104)
          end
          Font.draw("B:BACK", 16, 128)
        end
        return self
      end,
    })
  end)

  -- ---- pump ---------------------------------------------------------------
  -- Split into two pieces on purpose, after a real bug report: a player
  -- stuck on "LOGGING IN.." forever, and another stuck on "SENDING..."
  -- forever, on the exact build that drove EVERYTHING (including draining
  -- HTTP_RESULT) off world.stepped. That event only fires while physically
  -- taking a step in the overworld (Reference-Events) - so a result that
  -- finished while sitting on the status screen at boot, or the Add Friend
  -- screen mid-request, could sit fully complete in the channel but never
  -- get popped and applied until the player happened to walk somewhere.
  -- Checked the engine's real mod-object reference for a genuine per-frame
  -- hook independent of movement - there isn't one; every documented hook/
  -- event is tied to a specific gameplay moment, not a generic tick. The
  -- one thing that DOES reliably run every frame regardless of movement is
  -- a screen's own update(dt) (ordinary UI state callback), so:
  --
  --   * drainHttpResults() - ONLY pops HTTP_RESULT and applies results.
  --     Cheap, side-effect-free if the channel's empty, safe to call from
  --     anywhere, as often as needed.
  --   * pumpPresenceTimer() - the presence/friends/pending 30s schedule,
  --     still driven off world.stepped (see the previous version of this
  --     comment for why input.step was dropped in favour of it) - fine to
  --     stay step-gated, since "last known position" data doesn't need to
  --     update while standing still.
  --
  -- Every screen below that's actually waiting on a network result (status
  -- screen while logging in, Add Friend while sending, the remove-friend
  -- confirm while removing) now also calls drainHttpResults() directly from
  -- its own update(dt), so those specific waits resolve on the very next
  -- frame regardless of whether the player is standing still.
  drainHttpResults = function()
    -- Advances every in-flight mod.fetch job one poll's worth (never
    -- blocks) and submits anything still queued behind the 4-in-flight
    -- ceiling - BEFORE draining HTTP_RESULT, so a job that just finished
    -- gets dispatched to its tag handler in this same call rather than
    -- waiting a full extra frame. No-op entirely (cheap) when mod.fetch
    -- isn't available on this build - see isFetchAvailable/httpAsyncGet.
    pcall(pollFetches)
    local r = httpResultPop()
    while r do
      local tag, status, body = string.match(r, "^([^|]*)|([^|]*)|(.*)$")
      if tag then
        if tag == "ping" then
          presenceBusy = false
          if not (status == "OK" and jsonIsOk(body)) then
            mod.log:info("SilphNet: presence ping failed: %s", tostring(body))
          end
        elseif tag == "friends" then
          friendsBusy = false
          if status == "OK" and jsonIsOk(body) then
            friends = parseFriendsJson(body)
            refreshMarkers()
          else
            mod.log:info("SilphNet: friends fetch failed: %s", tostring(body))
          end
        elseif tag == "pending" then
          pendingBusy = false
          if status == "OK" and jsonIsOk(body) then
            pendingRequests = parseObjects(body)
          else
            mod.log:info("SilphNet: pending-requests fetch failed: %s", tostring(body))
          end
        elseif tag == "online_count" then
          onlineCountBusy = false
          if status == "OK" and jsonIsOk(body) then
            onlineCount = tonumber(jsonField(body, "online"))
          else
            mod.log:info("SilphNet: online-count fetch failed: %s", tostring(body))
          end
        elseif tag == "nearby" then
          nearbyBusy = false
          if status == "OK" and jsonIsOk(body) then
            nearby = parseObjects(body)
          else
            mod.log:info("SilphNet: nearby fetch failed: %s", tostring(body))
          end
        elseif tag == "stats_upload" then
          statsUploadBusy = false
          if status == "OK" and jsonIsOk(body) then
            -- Only pop the activity we actually just sent successfully -
            -- and only if it's still at the front of the queue (it always
            -- should be, nothing else pops index 1, but checking rather
            -- than blindly table.remove(1) costs nothing and guards
            -- against ever silently dropping the wrong entry if this
            -- logic changes later). A failed send leaves the queue
            -- untouched entirely, so the same activity is retried next
            -- tick instead of being lost.
            if statsUploadActivitySent and pendingActivityQueue[1] == statsUploadActivitySent then
              table.remove(pendingActivityQueue, 1)
            end
          else
            mod.log:info("SilphNet: stats upload failed: %s", tostring(body))
          end
          statsUploadActivitySent = nil
        elseif tag == "friend_detail" then
          friendDetailBusy = false
          if status == "OK" and jsonIsOk(body) then
            -- friend_detail.php now returns ALL of a friend's versions in
            -- one response: {"versions":[{"game_version",
            -- "stats":{...}|null,"activity":{...}|null}, ...],
            -- "presence":{...}|null} - a genuinely nested shape (an array
            -- of objects, each with two of ITS OWN nested objects) that
            -- none of the existing helpers cover: parseObjects assumes
            -- flat records (no nesting), and the single-object "nested"
            -- helper an earlier version of this used only pulled one
            -- level, not an array of them. Pulled apart in three steps:
            -- extract "presence" the same single-nested-object way as
            -- before, then scan "versions" for each top-level {...}
            -- entry via balanced brace matching (needed because each
            -- entry itself contains nested {...} for stats/activity - a
            -- naive %b{} scan would still work here since Lua's %b syntax
            -- IS brace-balanced, but it can't be combined with gmatch
            -- directly, so this walks the string by hand instead), then
            -- runs the same flat-field extraction on each entry AND on
            -- its two nested sub-objects.
            local function nestedObj(str, key)
              local obj = string.match(str, '"' .. key .. '"%s*:%s*(%{[^{}]-%})')
              if not obj then return nil end
              local rec = {}
              -- Two separate gmatch passes, not one combined pattern -
              -- the "party" field's value can itself contain literal
              -- commas ("BLASTOISE,64,145,168,..." - see
              -- encodePartySnapshot), which the old single pattern
              -- (stopping a quoted value at the first "," it saw) would
              -- have silently truncated party at its first comma. A
              -- quoted JSON string value only ever really ends at its
              -- closing quote, so this now matches quoted values by
              -- stopping there instead - the same distinction jsonField
              -- already draws between its quoted-string and bare-number
              -- patterns, just applied inside a nested object here too.
              -- Quoted values are tried first (a field can't match both
              -- patterns for the same key, since a quoted value's first
              -- char is `"`, which the bare-number pattern's %s*:%s*
              -- lookahead won't accept).
              for k, v in string.gmatch(obj, '"([%w_]+)"%s*:%s*"([^"]*)"') do rec[k] = v end
              for k, v in string.gmatch(obj, '"([%w_]+)"%s*:%s*(-?%d+%.?%d*)[,}]') do
                if rec[k] == nil then rec[k] = v end
              end
              return rec
            end
            local presence = nestedObj(body, "presence")
            local versionsArrayBody = string.match(body, '"versions"%s*:%s*%[(.-)%]%s*,%s*"presence"')
            local versions = {}
            if versionsArrayBody then
              -- Walk the array body character by character, tracking
              -- brace depth, so each ENTRY (itself containing nested
              -- {...} for stats/activity) is extracted whole rather than
              -- a naive %{[^{}]-%} match stopping at the first inner
              -- closing brace.
              local depth, entryStart = 0, nil
              for i = 1, #versionsArrayBody do
                local c = versionsArrayBody:sub(i, i)
                if c == "{" then
                  if depth == 0 then entryStart = i end
                  depth = depth + 1
                elseif c == "}" then
                  depth = depth - 1
                  if depth == 0 and entryStart then
                    local entry = versionsArrayBody:sub(entryStart, i)
                    local gv = string.match(entry, '"game_version"%s*:%s*"([^"]*)"')
                    if gv then
                      versions[#versions + 1] = {
                        game_version = gv,
                        stats = nestedObj(entry, "stats"),
                        activity = nestedObj(entry, "activity"),
                      }
                    end
                    entryStart = nil
                  end
                end
              end
            end
            friendDetail = { versions = versions, presence = presence }
            friendDetailState = "idle"
          else
            friendDetailState = "failed"
            mod.log:info("SilphNet: friend detail fetch failed: %s", tostring(body))
          end
        elseif tag == "online_by_version" then
          onlineByVersionBusy = false
          if status == "OK" and jsonIsOk(body) then
            -- online_by_version.php returns {"versions":[{"game_version",
            -- "count", "players":[{...}, ...]}, ...]} - each entry's OWN
            -- "players" is a flat array of flat records (account_id/name/
            -- trainer_id, no further nesting), so unlike friend_detail's
            -- stats/activity sub-objects, parseObjects (already handles
            -- "scan the first [...] in a string") can be reused directly
            -- on each entry's substring rather than needing a bespoke
            -- nested-array walker - unlike friend_detail's per-entry
            -- nested OBJECTS (stats/activity), this is a per-entry nested
            -- ARRAY, which parseObjects already covers on its own once
            -- handed just that entry's text.
            local versionsArrayBody = string.match(body, '"versions"%s*:%s*%[(.-)%]%s*}%s*$')
            local out = {}
            if versionsArrayBody then
              local depth, entryStart = 0, nil
              for i = 1, #versionsArrayBody do
                local c = versionsArrayBody:sub(i, i)
                if c == "{" then
                  if depth == 0 then entryStart = i end
                  depth = depth + 1
                elseif c == "}" then
                  depth = depth - 1
                  if depth == 0 and entryStart then
                    local entry = versionsArrayBody:sub(entryStart, i)
                    local gv = string.match(entry, '"game_version"%s*:%s*"([^"]*)"')
                    local count = tonumber(string.match(entry, '"count"%s*:%s*(%d+)')) or 0
                    if gv then
                      out[#out + 1] = { game_version = gv, count = count, players = parseObjects(entry) }
                    end
                    entryStart = nil
                  end
                end
              end
            end
            onlineByVersion = out
          else
            mod.log:info("SilphNet: online-by-version fetch failed: %s", tostring(body))
          end
        elseif tag == "league_leaderboard" then
          leagueLeaderboardBusy = false
          if status == "OK" and jsonIsOk(body) then
            local all, friendsList = parseLeagueLeaderboardJson(body)
            leagueLeaderboard = { all = all, friends = friendsList }
          else
            -- Deliberately no state change beyond clearing the busy flag -
            -- leagueLeaderboard is left however it was (nil on a first
            -- failed attempt, or the last good snapshot on a later one),
            -- same "keep showing the last known-good data rather than
            -- blanking it on one bad request" convention friends/nearby
            -- already follow elsewhere in this file.
            mod.log:info("SilphNet: league leaderboard fetch failed: %s", tostring(body))
          end
        else
          handleHttpResult(tag, status, body)
        end
      end
      r = httpResultPop()
    end
  end

  -- Uses os.time() (real wall-clock seconds) rather than an accumulated dt,
  -- since world.stepped's payload carries no delta-time field to accumulate
  -- (see Reference-Events) - each call reads "how many seconds actually
  -- passed" directly from the OS clock instead.
  local lastPumpAt = nil
  local function pumpPresenceTimer()
    if authState ~= "authed" or not inOverworld then return end
    local now = os.time()
    if not lastPumpAt then lastPumpAt = now end
    local elapsed = now - lastPumpAt
    sincePresence = sincePresence + elapsed
    sinceStats = sinceStats + elapsed
    lastPumpAt = now
    if sincePresence >= PRESENCE_INTERVAL then
      sincePresence = 0
      if not presenceBusy then firePresencePing() end
      if not friendsBusy then fireFriendsFetch() end
      if not pendingBusy then firePendingFetch() end
      if not onlineCountBusy then fireOnlineCountFetch() end
      if not nearbyBusy then fireNearbyFetch() end
    end
    -- pendingActivityQueue is filled by the real pokemon.caught event
    -- handler (see wiring section), not polled here - this just drains
    -- the OLDEST queued entry, uploading it right away rather than
    -- waiting for the next 3-minute stats cycle. Stats themselves
    -- (badges/dex counts/money/league wins) stay on the slower
    -- STATS_INTERVAL cycle below - none of those need to be as fresh as
    -- "just caught something."
    --
    -- Peek, don't pop - the entry is only removed from the queue once
    -- drainHttpResults confirms the server actually accepted it (see the
    -- "stats_upload" case there). If this fires but statsUploadBusy is
    -- still true from a previous in-flight upload, the peeked activity
    -- simply isn't sent THIS tick - it stays at the front of the queue
    -- and gets tried again next tick, still intact, rather than being
    -- lost the way a single overwritable slot used to lose it.
    local activity = pendingActivityQueue[1]
    if sinceStats >= STATS_INTERVAL or activity then
      if not statsUploadBusy then
        local snap = (sinceStats >= STATS_INTERVAL) and readStatsSnapshot() or nil
        if snap or activity then
          fireStatsUpload(snap, activity)
          if sinceStats >= STATS_INTERVAL then sinceStats = 0 end
        end
      end
    end
  end

  -- ---- wiring ---------------------------------------------------------------
  mod.events:on("game.ready", function(ev)
    game = ev.game
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
    myName = resolveMyName()
    gameVersion = resolveGameVersion()
    beginAuth()
  end)

  mod.events:on("mod.options_changed", function(ev)
    local k = ev and ev.key
    if k == "name" or k == "password" then
      pcall(function() mod.save:set("token", nil) end)   -- credentials changed - stop trusting the old session
      beginAuth()
    end
  end)

  mod.events:on("map.entered", function(ev)
    despawnAllMarkers()
    despawnGymSign()
    despawnLeagueSign()
    inOverworld = true
    myMap = ev.mapId
    local cur = mod.world:current()
    if cur then myX, myY, myFacing = cur.x, cur.y, cur.facing end
    refreshMarkers()

    -- Gym sign: only ever attempted on a map GYM_MAP_TO_BADGE actually
    -- lists (every real gym across Gen1 Kanto/Gen2 Johto/Gen2 Kanto - see
    -- that table's own comment) - wrapped in pcall same as the league
    -- sign below, since findSafeSignTile/spawnNpc both touch live engine
    -- state (mapOverview, current()) that this file has no way to fully
    -- guarantee never errors on every build.
    local badgeId = GYM_MAP_TO_BADGE[myMap]
    if badgeId then
      pcall(spawnGymSign, myMap, badgeId)
    end

    -- League leaderboard sign: registered UNCONDITIONALLY (this hook
    -- always runs, on every map.entered, regardless of generation) - see
    -- LEAGUE_SIGN_MAP_ID's own comment for why this deliberately does
    -- NOT try to guess a separate Gen2 map id. The whole attempt is
    -- wrapped in pcall specifically so a build where this map id simply
    -- doesn't exist (or behaves unexpectedly) silently no-ops instead of
    -- erroring - myMap simply won't equal the one real confirmed id on
    -- such a build, so this is normally just a cheap string comparison
    -- that does nothing at all.
    if myMap == LEAGUE_SIGN_MAP_ID then
      pcall(spawnLeagueSign, myMap)
    end
  end)

  mod.events:on("map.exited", function()
    inOverworld = false
    despawnAllMarkers()
    despawnGymSign()
    despawnLeagueSign()
  end)

  -- Real, documented event (Reference-Events: payload { battle, mon,
  -- species, isNew, ball, destination, game }) - not a poll-and-diff
  -- against save.pokedex.owned like an earlier draft used, which had no
  -- way to get a level at all. Fires for every catch, not just NEW
  -- species (isNew is available if this ever needs to filter to
  -- first-time catches only, but "just caught a Pokemon" reads fine
  -- either way - a friend re-catching a species they already have is
  -- still real, current activity worth showing).
  mod.events:on("pokemon.caught", function(ev)
    pcall(queueCatchActivity, ev and ev.mon, ev and ev.species)
  end)

  mod.events:on("world.stepped", function(ev)
    myMap, myX, myY = ev.mapId, ev.x, ev.y
    local cur = mod.world:current(); if cur then myFacing = cur.facing end
    -- Presence/friends/pending pumping and HTTP draining moved to the
    -- core.update hook below (see its own comment for why) - this handler
    -- now only tracks the player's own position, which is correctly
    -- step-gated (there's nothing to update here while standing still).
  end)

  -- Reported bug: standing still in the overworld for more than a few
  -- minutes gets you marked OFFLINE server-side, even though the game is
  -- genuinely still open and being played - not walking away, just not
  -- moving. Root cause: pumpPresenceTimer (and drainHttpResults) were only
  -- ever invoked from world.stepped, and world.stepped is documented
  -- (Reference-Events) to fire ONLY on an actual step - so a player who
  -- simply stops walking stops ticking the 30s ping timer at all, and
  -- last_seen on the server eventually falls outside the 300s online
  -- window (see online_by_version.php/public_online_status.php) even
  -- though they never left.
  --
  -- Checked every other documented event for something that fires on a
  -- real-time interval independent of movement - there isn't one among
  -- Reference-Events (map/battle/pokemon/script events are all tied to a
  -- specific gameplay moment). core.update, however, is a documented HOOK
  -- (Reference-Hooks), not an event - confirmed directly against the
  -- engine's own src/core/PlatformHooks.lua: `ModRuntime.call("core.update",
  -- function(g, d) g:update(d) end, game, dt)` wraps the game's own
  -- love.update-driven tick itself, completely independent of whether the
  -- player is standing still, in a menu, or mid-battle. This is exactly
  -- the per-frame, movement-independent hook the earlier pump() comment
  -- (see drainHttpResults above) said didn't exist among events - it just
  -- wasn't a hook this file had wired up yet.
  --
  -- MUST always call nextFn(g, dt) - skipping it would stop the entire
  -- game from updating, not just this mod's own logic. Wrapped in its own
  -- pcall (not nextFn's call, which must never be swallowed) so a genuine
  -- error in pumpPresenceTimer/drainHttpResults can never take the whole
  -- game down from inside a hook that runs every single frame.
  --
  -- pumpPresenceTimer itself already measures real elapsed OS seconds
  -- (os.time(), not an accumulated dt - see its own comment) and no-ops
  -- entirely unless authState == "authed" and inOverworld, so calling it
  -- up to 60x/sec here is cheap and never double-fires the 30s cycle
  -- early - it still only actually pings once PRESENCE_INTERVAL real
  -- seconds have genuinely passed, standing still or not. The existing
  -- "goes offline after ~5 minutes of no ping" server-side rule is
  -- completely unchanged (see online_by_version.php's own comment on that
  -- window) - this only fixes the client still SENDING that ping while
  -- idle, never touches what counts as stale on the server.
  mod.hooks:wrap("core.update", function(nextFn, g, dt)
    nextFn(g, dt)
    pcall(drainHttpResults)
    pcall(pumpPresenceTimer)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, g, items)
    pcall(function()
      -- Same class of bug documented above drainHttpResults(): a login
      -- result can finish (HTTP_RESULT fully populated) while the player
      -- is standing still at boot, sitting on the title/intro, or just
      -- hasn't taken a world.stepped-triggering step yet - world.stepped
      -- is the only thing that normally drains that channel. Without this,
      -- the Start Menu opened THIS SESSION's first time can show a stale
      -- "SN ..."/"SN SET NAME/PASS" label even though auth already
      -- finished, and it wouldn't self-correct until something else (e.g.
      -- opening the status screen, which drains it in its own update(dt))
      -- happened to drain the channel first - reported on-device as the
      -- label only ever updating after going into "SN ..." and backing
      -- out. Draining here, right before statusLabel() is read, means the
      -- very first Start Menu open after a completed login already shows
      -- the correct name.
      pcall(drainHttpResults)
      mod.ui.insertBefore(items, "QUIT", { label = statusLabel(),
        onSelect = function() mod.ui.push(g, "SilphNetStatus") end })
      -- A second, separate Start Menu row for Nearby - rather than
      -- cramming every new feature into the one SILPHNET row (or bolting
      -- a mode toggle onto the Friends screen, which is what an earlier
      -- version of this did before it was simplified back out), each
      -- major feature gets its own row as the mod grows. "SN" (not the
      -- full "SILPHNET") keeps this within the same conservative label
      -- length every other row here uses. Anchored on "QUIT" too, same
      -- as the row above, so both SilphNet rows land together just above
      -- it regardless of what other mods insert between them.
      mod.ui.insertBefore(items, "QUIT", { label = "SN NEARBY",
        onSelect = function() mod.ui.push(g, "SilphNetNearby") end })
      -- Third Start Menu row for About - moved here from the mod
      -- manager's OPTIONS screen (see removed ui.options.rows hook
      -- below this comment used to sit above), which is where an
      -- earlier version of this put it on the reasoning that the
      -- in-game GB screen was already at its 16-char/144px budget.
      -- Reported on-device as a real bug, not a design tradeoff:
      -- selecting "ABOUT SILPHNET" from the options screen closed the
      -- Start Menu/options UI entirely rather than opening the About
      -- screen - mod.ui.push(g, "SilphNetAbout") pushing a genuine
      -- gameplay-style screen onto a stack the mod manager's own
      -- options UI wasn't necessarily expecting to receive a push from,
      -- unlike the Start Menu (an established, already-working push
      -- site for SilphNetStatus/SilphNetNearby above). Moving About to
      -- its own Start Menu row - the exact same site the two rows above
      -- already use successfully - sidesteps that entirely rather than
      -- trying to debug the options screen's own push handling.
      -- Global (self-inclusive) online-players row - moved here from the
      -- status screen's A:FRIENDS hint line, which now shows a
      -- friends-only count instead (see countFriendsOnline()).
      -- Deliberately its own separate row, not folded onto any of the
      -- two above - the whole reason this moved at all was that the
      -- friends-list-adjacent hint line was easy to misread as a
      -- friends-online count when it was really global and
      -- self-inclusive, so this stays on a screen that has nothing to do
      -- with friends at all.
      --
      -- Inserted BEFORE "SN ABOUT" (i.e. this call runs before that
      -- one), not after - each insertBefore(items, "QUIT", ...) call
      -- lands its row immediately above QUIT, pushing any row inserted
      -- by an EARLIER call further up the list (see the comment above
      -- the SN NEARBY insert: "both SilphNet rows land together just
      -- above it" - later calls end up closer to QUIT/the bottom, not
      -- further from it). Ordering these calls ONLINE-then-ABOUT (rather
      -- than the reverse) is what keeps About pinned as the last
      -- SilphNet row, per direct request ("About should always be the
      -- bottom menu item").
      mod.ui.insertBefore(items, "QUIT", { label = "SN ONLINE",
        onSelect = function() mod.ui.push(g, "SilphNetOnline") end })
      mod.ui.insertBefore(items, "QUIT", { label = "SN ABOUT",
        onSelect = function() mod.ui.push(g, "SilphNetAbout") end })
    end)
    return nextFn(g, items)
  end)

  pcall(function()
    mod.content.screens:register("SilphNetAbout", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          if g.input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          -- Uppercase throughout, not each link's real casing - Gen 1's
          -- GB font is uppercase-only in most contexts (menus, most
          -- dialogue; a few special text boxes support lowercase in the
          -- real game), and this couldn't be verified on-device here, so
          -- this plays it safe rather than risk missing/garbled
          -- lowercase glyphs. << VERIFY >> whether mod.ui.Font.draw
          -- actually supports lowercase - if confirmed, these could go
          -- back to their real casing (ashjamgram, ashjam, etc.).
          --
          -- GitHub/Instagram/TikTok added directly on request ("Include
          -- all the details you have there, and github and socials
          -- aswell") - each shown as a short label + the real handle,
          -- same left-label style already used elsewhere in this file.
          -- No Discord row - not created yet as of this addition; add
          -- one here once it exists rather than showing a handle that
          -- doesn't resolve to anything.
          --
          -- GitHub shown as just the handle ("GH ASHJAMB"), not the full
          -- "AshJamB/SilphNet" repo path - the full path is exactly 16
          -- chars (fits with zero margin), but using it here would have
          -- meant dropping "THANKS FOR PLAYING!" to stay within the
          -- box's 144px limit, and keeping that line (already part of
          -- this screen before this change) mattered more than spelling
          -- out the repo name in full - the handle alone is enough to
          -- find the right GitHub profile.
          Font.draw("- SILPHNET -", 16, 8)
          Font.draw("ASH BRITTAIN", 16, 24)
          Font.draw("(ASHJAM)", 16, 32)
          Font.draw("ASH.JAMTV.CO.UK", 16, 48)
          Font.draw("GH ASHJAMB", 16, 64)
          Font.draw("IG @ASHJAMGRAM", 16, 80)
          Font.draw("TT @ASHJAM", 16, 96)
          -- :sub(1,16) here is a real, not purely defensive, safeguard -
          -- unlike most other :sub(1,16) calls in this file, a future
          -- version number genuinely could push this line past 16 chars
          -- (e.g. "PLAYING! V10.10.10" is 18 chars), where every other
          -- capped line in this file is only ever at risk from unusually
          -- long real-world input, not its own version string growing.
          Font.draw("THANKS FOR", 16, 112)
          Font.draw(("PLAYING! V" .. tostring(mod.version or "?")):sub(1, 16), 16, 120)
          Font.draw("B:BACK", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Global (self-inclusive) online-players screen, pushed from the "SN
  -- ONLINE" Start Menu row - see that row's comment for why this moved
  -- off the status screen's A:FRIENDS hint (that hint is now
  -- friends-only, via countFriendsOnline()).
  --
  -- Two independent paging axes, per direct request ("split this into
  -- categories... navigate left and right to more pages... then the
  -- option to add the players like the NEARBY screen"):
  --   * self.verPage: 0 = Gen 1 summary (RED/BLUE/YELLOW counts), 1 = Gen 2
  --     summary (GOLD/SILVER/CRYSTAL counts), 2..N+1 = that version's own
  --     page (onlineByVersion[verPage-1]), where N is however many
  --     versions online_by_version.php actually returned (6 as of Crystal
  --     support). LEFT/RIGHT cycles this axis, wrapping 0->1->...->N+1->0
  --     (see pageCount below, not a hardcoded count).
  --
  --     Used to be ONE summary page listing every version together, but
  --     Crystal made 6 rows - reported directly as "Crystal has now been
  --     pushed down and is overlapping the mappings at the bottom" (the
  --     6th row landed exactly on the footer hint text at y=120). Split
  --     into two summary pages by generation (isGen2()) instead of trying
  --     to squeeze a 6th row in - each still opens with the SAME combined
  --     TOTAL ONLINE figure across every game, not just that half, so
  --     neither page reads as "this is the whole total."
  --   * self.playerIndex: which player (1-based) is showing WITHIN the
  --     current version's page - UP/DOWN cycles this axis, independent
  --     of LEFT/RIGHT, same "two axes on one screen" convention the
  --     friend detail screen's PARTY page already established (A cycles
  --     STATS/PARTY/ACTIVITY, LEFT/RIGHT pages within PARTY specifically).
  --
  -- Uses online_by_version.php (full per-version player lists), NOT
  -- online_count.php (a single flat number, still used elsewhere e.g.
  -- if ever needed again) - this screen needs the actual player list per
  -- version to support the add-friend flow, which a bare count can't
  -- provide.
  pcall(function()
    mod.content.screens:register("SilphNetOnline", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, verPage = 0, playerIndex = 1 }
        -- Fires once, right when the screen opens - same "fetch on
        -- demand when a screen wants fresher data than the background
        -- cycle already provides" pattern SilphNetFriendDetail already
        -- uses for friend_detail. onlineByVersion is NOT on the
        -- background ~30s cycle (see fireOnlineByVersionFetch's own
        -- comment), so without this the screen would show "CHECKING..."
        -- forever until something else happened to trigger a fetch.
        if not onlineByVersionBusy then fireOnlineByVersionFetch() end
        -- A friend's own account_id may appear on more than one
        -- friends[] entry (several active saves) - checked by account_id
        -- alone, same helper SilphNetNearby already defines for the
        -- identical purpose (kept as its own local copy here rather than
        -- hoisted into a shared upvalue, since neither screen needs the
        -- other's).
        local function isAlreadyFriend(accountId)
          if not accountId then return false end
          for _, f in pairs(friends) do
            if f.account_id == accountId then return true end
          end
          return false
        end
        function self:update(dt)
          pcall(drainHttpResults)
          local input = g.input
          -- Page count is 2 (Gen 1 summary, Gen 2 summary) + however many
          -- versions the server actually returned, NOT a hardcoded number -
          -- that was a real bug this Gen 2 pass caught before (it silently
          -- assumed exactly 3 tracked versions), and the two-summary-page
          -- split above is the fix for the SAME class of bug resurfacing
          -- with Crystal (a 6th row, not a 6th page). Before the first
          -- successful fetch (onlineByVersion still nil) this pins to the
          -- 2 summary pages, so LEFT/RIGHT can't page into version data
          -- that doesn't exist yet.
          local pageCount = 2 + (onlineByVersion and #onlineByVersion or 0)
          if input:wasPressed("right") then
            self.verPage = (self.verPage + 1) % pageCount
            self.playerIndex = 1
          elseif input:wasPressed("left") then
            self.verPage = (self.verPage - 1) % pageCount
            self.playerIndex = 1
          end
          if self.verPage > 1 and onlineByVersion then
            local v = onlineByVersion[self.verPage - 1]
            local n = v and #v.players or 0
            if n > 0 then
              if input:wasPressed("down") then
                self.playerIndex = (self.playerIndex % n) + 1
              elseif input:wasPressed("up") then
                self.playerIndex = self.playerIndex - 1
                if self.playerIndex < 1 then self.playerIndex = n end
              end
            end
          end
          -- START jumps straight to Add Friend with the player currently
          -- shown on this page's Trainer ID already filled in - same
          -- shortcut SilphNetNearby gained for the same reason (the old
          -- hint text implied a one-button add that didn't actually
          -- exist). Only wired up on a real, addable per-version player
          -- page - a no-op on either summary page, on an empty version, or
          -- on your own "(YOU)" row.
          if self.verPage > 1 and onlineByVersion then
            local v = onlineByVersion[self.verPage - 1]
            local p = v and v.players and v.players[self.playerIndex]
            if input:wasPressed("start") and p and p.trainer_id and p.is_you ~= "true"
                and not isAlreadyFriend(p.account_id) then
              addFriendStatus = ""
              mod.ui.push(g, "SilphNetAddFriend", { prefillId = p.trainer_id })
            end
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          if onlineByVersion == nil then
            -- Same "nil means haven't heard back yet" convention as
            -- onlineCount/friendDetail/etc elsewhere in this file -
            -- distinct from a genuine zero-everywhere answer.
            Font.draw("- ONLINE -", 16, 8)
            Font.draw("CHECKING...", 16, 72)
          elseif self.verPage <= 1 then
            -- Two summary pages, split by generation (isGen2()) - used to
            -- be one page listing every tracked version together, but a
            -- 6th row (Crystal) landed right on top of the footer hint at
            -- y=120, reported directly as "Crystal has now been pushed
            -- down and is overlapping the mappings at the bottom." Rather
            -- than shrinking rows to fit 6, this splits into a Gen 1 page
            -- (RED/BLUE/YELLOW) and a Gen 2 page (GOLD/SILVER/CRYSTAL),
            -- each with real clearance - 3 rows is exactly what this
            -- screen already handled fine before Crystal existed.
            --
            -- TOTAL ONLINE is the SAME combined number on both pages
            -- (every tracked version summed, not just the half being
            -- shown) - directly requested ("This is total across all
            -- games by the way, not just gen 1 or 2") so neither page
            -- reads as if it were the whole total.
            local isGen1Page = (self.verPage == 0)
            local total = 0
            local rows = {}
            for _, v in ipairs(onlineByVersion) do
              total = total + (tonumber(v.count) or 0)
              if isGen2(v.game_version) ~= isGen1Page then
                rows[#rows + 1] = v
              end
            end
            Font.draw(("TOTAL ONLINE: " .. total):sub(1, 16), 16, 8)
            Font.draw(isGen1Page and "- GEN 1 -" or "- GEN 2 -", 16, 24)
            for i, v in ipairs(rows) do
              Font.draw((v.game_version .. ": " .. v.count):sub(1, 16), 16, 40 + (i - 1) * 16)
            end
            if #onlineByVersion > 0 then Font.draw("LR:PAGE", 16, 120) end
            Font.draw("B:BACK", 16, 128)
            return
          else
            -- Per-version page: title is "<VERSION> ONLINE" (e.g. "RED
            -- ONLINE"), mirroring SilphNetNearby's list-one-per-screen
            -- layout and add-friend flow almost exactly - the same
            -- underlying question ("is this person already my friend")
            -- answered the same way, just scoped to a game version
            -- instead of a map.
            local v = onlineByVersion[self.verPage - 1]
            local title = (v.game_version .. " ONLINE"):sub(1, 16)
            Font.draw(title, 16, 8)
            -- Checked against #v.players (the actual array length),
            -- NOT v.count - v.count is a server-reported convenience
            -- field that SHOULD always match #v.players, but indexing
            -- v.players[self.playerIndex] off a mismatched v.count
            -- instead of the real array length risks a nil index if
            -- they're ever out of sync (e.g. a partial/malformed
            -- response) - the array's own length is the one thing that
            -- can never lie about how many real entries are there to
            -- read. self.playerIndex is also re-clamped here defensively
            -- (not just relying on update()'s own wrap-around logic
            -- always running before draw() first does).
            local n = #v.players
            if self.playerIndex > n then self.playerIndex = 1 end
            if n == 0 then
              Font.draw("NONE ONLINE", 16, 40)
            else
              local p = v.players[self.playerIndex]
              Font.draw((self.playerIndex) .. "/" .. n, 16, 24)
              Font.draw((p.name or "?"):sub(1, 16), 16, 48)
              Font.draw("ID   " .. (p.trainer_id or "-----"), 16, 56)
              -- The caller's own entry is included in this list now (see
              -- online_by_version.php - this screen answers "how many
              -- people total are online, including me", not just
              -- "everyone else"), flagged is_you by the server rather
              -- than re-derived client-side by comparing account_id
              -- (accountId is already known locally, but trusting the
              -- server's own flag keeps this screen's "is this me" logic
              -- in exactly one place rather than two that could drift).
              -- Shown as "(YOU)" instead of a friend-status prompt -
              -- add_friend.php already rejects a self-add server-side
              -- ("cannot friend yourself"), but there's no reason to even
              -- show an ADD FRIEND hint on your own row in the first
              -- place.
              if p.is_you == "true" then
                Font.draw("(YOU)", 16, 72)
              elseif isAlreadyFriend(p.account_id) then
                Font.draw("ALREADY A FRIEND", 16, 72)
              else
                Font.draw("NOT YET A FRIEND", 16, 72)
                -- Was "RIGHT:ADD FRIEND" / "ON STATUS SCREEN" - the exact
                -- bug reported directly against this screen: RIGHT is
                -- ALREADY bound here (paging to the next tracked game
                -- version), so the hint read as an instruction to press
                -- RIGHT to add this friend when RIGHT does something
                -- else entirely. Same upgrade as SN NEARBY: START was
                -- genuinely free on this screen too, so it now pushes
                -- SilphNetAddFriend with this player's Trainer ID
                -- already filled in (see self:update above) instead of
                -- just describing where to go.
                Font.draw("START:ADD FRIEND", 16, 80)
              end
            end
          end
          if onlineByVersion and self.verPage > 1 then
            local v = onlineByVersion[self.verPage - 1]
            -- Both hints combined onto one line when there's more than
            -- one player to page between (LR for version, UD for
            -- player) - separate lines only when UD:PAGE wouldn't mean
            -- anything (0 or 1 player on this version's page), same
            -- "don't advertise a control that does nothing right now"
            -- rule SilphNetNearby's own LEFT/RIGHT:PAGE hint follows.
            if v and #v.players > 1 then
              Font.draw("LR:VER UD:PAGE", 16, 112)
            else
              Font.draw("LR:VERSION", 16, 112)
            end
          end
          Font.draw("B:BACK", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Friend-marker "who is this" screen (point 3 from testing feedback).
  -- Pushed by the per-slot talk scripts registered in ensureMapScripted -
  -- see the long comment above MARKER_SLOTS for why this is slot-based
  -- rather than per-friend TEXT ids. The name is looked up HERE, at push
  -- time, from slotToKey/friends - never frozen at registration - so it's
  -- always the current occupant of that slot, even if markers were
  -- despawned/respawned (friend moved, or a different friend now sits on
  -- this exact slot) since the talk script itself was registered.
  -- << VERIFY >> the push_screen script command's second arg reaching new()
  -- as-is; mod.ui.push(game, screenId, ...) is documented as variadic
  -- (Reference-Mod-Object), so this reads args defensively either way.
  pcall(function()
    mod.content.screens:register("SilphNetMarkerTalk", {
      new = function(g, args)
        local Font = mod.ui.Font
        local slot = args and args.slot
        local key = slot and slotToKey[slot]
        local f = key and friends[key]
        local name = (f and f.name) or "?"
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          if g.input:wasPressed("b") or g.input:wasPressed("a") then g.stack:pop() end
        end
        function self:draw()
          -- 6 rows tall (48px), not 4 - the original 4-row box left no
          -- clearance between the "A/B:CLOSE" line and the box's own
          -- bottom border, so the text rendered jammed against/behind the
          -- frame line (reported on-device as "chopped off, almost
          -- struck-through"). Every other screen in this file keeps one
          -- full clear row above the bottom border - this now matches
          -- that same rule.
          Font.drawBox(0, 0, 20, 6)
          Font.draw(name:sub(1, 16), 16, 8)
          Font.draw("A/B:CLOSE", 16, 32)
        end
        return self
      end,
    })
  end)

  -- Gym sign talk screen - pushed by TEXT_SILPHNET_GYM_SIGN (registered
  -- on every map up front, see registerAllMarkerTalkScripts) whenever the
  -- player talks to the sign spawnGymSign placed near where they walked
  -- into a gym (see the map.entered wiring). currentGymBadge is looked
  -- up HERE, at push time, same "never frozen at registration" rule
  -- SilphNetMarkerTalk already follows for its own slot lookup - the
  -- friend list itself (friendsWithBadge) is recomputed fresh on push
  -- too, then snapshotted into `names` for this screen's own lifetime so
  -- self.index always indexes into a stable list even if a background
  -- friends re-fetch changes the live `friends` table while this screen
  -- happens to be open.
  --
  -- Only ever displays server-known friend display names - no free text
  -- of any kind (see this project's no-chat/no-DM policy) - each name
  -- here is exactly the same already-validated display name shown
  -- everywhere else a friend's name appears in this file.
  pcall(function()
    mod.content.screens:register("SilphNetGymSign", {
      new = function(g)
        local Font = mod.ui.Font
        local badgeId = currentGymBadge
        local names = friendsWithBadge(badgeId)
        local self = { game = g, isOpaque = true, index = 1 }
        function self:update(dt)
          local n = #names
          if n > 0 then
            if g.input:wasPressed("down") then
              self.index = (self.index % n) + 1
            elseif g.input:wasPressed("up") then
              self.index = self.index - 1
              if self.index < 1 then self.index = n end
            end
          end
          if g.input:wasPressed("b") or g.input:wasPressed("a") then g.stack:pop() end
        end
        function self:draw()
          -- Full 20x18-tile box, matching every other screen in this file
          -- (SilphNetResetConfirm/SilphNetCreateAccount etc.) - an earlier
          -- version of this screen used a much shorter custom box (20x8)
          -- sized just to its own content, which left the footer button
          -- hints sitting right on top of the box's own bottom border
          -- instead of below it, since drawBox's border occupies row
          -- (th-1) - reported as the footer looking "chopped off." Every
          -- other screen avoids this by always drawing the full-height
          -- box and leaving a large gap before its footer text (y=120+),
          -- so this now matches that same safe convention exactly.
          Font.drawBox(0, 0, 20, 18)
          -- Every real badge id is well under the 16-char/line budget
          -- (CASCADEBADGE/RAINBOWBADGE/VOLCANOBADGE/MINERALBADGE/
          -- GLACIERBADGE are the longest at 12 chars) - :sub(1,16) is
          -- purely the same defensive cap every other title line in this
          -- file already applies, not expected to ever actually truncate.
          Font.draw((badgeId or "GYM BADGE"):sub(1, 16), 16, 8)
          local n = #names
          if n == 0 then
            Font.draw("NO FRIENDS HAVE", 16, 40)
            Font.draw("THIS BADGE YET", 16, 48)
          else
            if self.index > n then self.index = 1 end
            Font.draw(self.index .. "/" .. n, 16, 32)
            Font.draw(names[self.index]:sub(1, 16), 16, 48)
            if n > 1 then Font.draw("UD:PAGE", 16, 64) end
          end
          Font.draw("A/B:CLOSE", 16, 128)
        end
        return self
      end,
    })
  end)

  -- League leaderboard sign talk screen - pushed by TEXT_SILPHNET_LEAGUE_SIGN
  -- near the Elite Four entrance (see spawnLeagueSign/LEAGUE_SIGN_MAP_ID).
  -- Two independent axes, same "two axes on one screen" convention
  -- SilphNetOnline already established (LEFT/RIGHT there cycles versions,
  -- UP/DOWN cycles players within one) - here LEFT/RIGHT flips between
  -- the ALL PLAYERS and FRIENDS pages, UP/DOWN pages through whichever
  -- list is currently showing, and SELECT toggles ascending/descending
  -- (an already-established "extra button beyond A/B/D-pad for a
  -- secondary per-screen action" convention - SilphNetFriends already
  -- uses SELECT for its own reset-confirm shortcut).
  --
  -- Sorting is entirely client-side (see league_leaderboard.php's own
  -- comment - the server only ever returns ONE order, descending) -
  -- ascending is just that same array read back to front into a fresh
  -- table, never a re-sort and never a second request, so toggling is
  -- instant regardless of how many rows came back.
  --
  -- Only ever displays server-computed names/trainer ids/numbers - no
  -- free text of any kind, same no-chat/no-DM policy as the gym sign
  -- screen above.
  pcall(function()
    mod.content.screens:register("SilphNetLeagueSign", {
      new = function(g)
        local Font = mod.ui.Font
        -- Same "fetch on demand when a screen wants fresher data than
        -- the background cycle already provides" pattern SilphNetOnline
        -- already uses for onlineByVersion - fired every time this
        -- screen opens (not just once, ever), so revisiting the sign
        -- later in the same session shows updated totals rather than a
        -- permanently stale first snapshot.
        if not leagueLeaderboardBusy then fireLeagueLeaderboardFetch() end
        -- Own league-clear count, shown on this screen per the owner's
        -- request ("show somewhere your own amount of league wins").
        --
        -- Deliberately NOT the local save's own #save.hallOfFame/
        -- save.hallOfFame.count - that's scoped to THIS ONE cartridge
        -- only, while every other number on this screen (and the
        -- leaderboard rank itself) is the COMBINED total across every
        -- game_version this account has ever uploaded (see
        -- league_leaderboard.php's own comment on why "collapse across
        -- saves" is the right call for a leaderboard specifically). A
        -- player who cleared the league on RED but is standing at this
        -- sign on a fresh YELLOW save would otherwise see "YOUR CLEARS 0"
        -- right next to a leaderboard that already credits them with 1 -
        -- confusingly inconsistent, and exactly what was reported back
        -- ("it says 0, but I have beaten the league" - true for the
        -- save they were standing in, not for their account overall).
        --
        -- So this reads the SAME combined number every other row on this
        -- screen already comes from: look the caller's own accountId up
        -- inside leagueLeaderboard.all (already fetched for the ALL
        -- PLAYERS page, no second request needed) once it's arrived.
        -- Falls back to the local single-save reading only until that
        -- fetch has come back at least once, so this screen never shows
        -- a blank/dash before the network round trip completes.
        local function myLeagueClears()
          if leagueLeaderboard and leagueLeaderboard.all then
            for _, row in ipairs(leagueLeaderboard.all) do
              if row.account_id and accountId and tostring(row.account_id) == tostring(accountId) then
                return tonumber(row.total) or 0
              end
            end
            -- Fetched, but this account has a combined total of 0 (never
            -- cleared on ANY save) - league_leaderboard.php excludes 0
            -- totals from the list entirely, so "not found" here
            -- genuinely means 0, not "still loading."
            return 0
          end
          -- Leaderboard hasn't come back yet - best available answer is
          -- this one save's own count, same as before this fix.
          local mine = 0
          pcall(function() mine = readStatsSnapshot().leagueWins or 0 end)
          return mine
        end
        local self = { game = g, isOpaque = true, page = 1, index = 1, sortAsc = false }
        local function currentList()
          if not leagueLeaderboard then return nil end
          local base = (self.page == 1) and leagueLeaderboard.all or leagueLeaderboard.friends
          if not base or not self.sortAsc then return base end
          local rev = {}
          for i = #base, 1, -1 do rev[#rev + 1] = base[i] end
          return rev
        end
        function self:update(dt)
          pcall(drainHttpResults)
          local input = g.input
          if input:wasPressed("left") or input:wasPressed("right") then
            self.page = (self.page == 1) and 2 or 1
            self.index = 1
          end
          if input:wasPressed("select") then
            self.sortAsc = not self.sortAsc
            self.index = 1
          end
          local list = currentList()
          local n = list and #list or 0
          if n > 0 then
            if input:wasPressed("down") then
              self.index = (self.index % n) + 1
            elseif input:wasPressed("up") then
              self.index = self.index - 1
              if self.index < 1 then self.index = n end
            end
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          -- Full 20x18-tile box (see SilphNetGymSign's own comment on this
          -- same change) - the previous 20x11 box put the footer button
          -- hints right on top of the box's own bottom border instead of
          -- below it, which is what "the nav bits are chopped off" was.
          Font.drawBox(0, 0, 20, 18)
          -- A persistent top-line title makes clear what this whole
          -- screen is about even before reading any row - the ALL
          -- PLAYERS/FRIENDS toggle alone didn't say "league clears"
          -- anywhere, which was the "doesn't clearly say its league wins"
          -- report. "SN LEAGUE CLEARS" is 16 chars exactly.
          Font.draw("SN LEAGUE CLEARS", 16, 8)
          local subtitle = (self.page == 1) and "ALL PLAYERS" or "FRIENDS"
          Font.draw(("- " .. subtitle .. " -"):sub(1, 16), 16, 16)
          -- Own clear count, always visible regardless of which list/sort
          -- is showing - per the owner's request to surface this
          -- somewhere on this screen.
          Font.draw(("YOUR CLEARS " .. tostring(myLeagueClears())):sub(1, 16), 16, 32)
          if leagueLeaderboard == nil then
            -- Same "nil means haven't heard back yet" convention as
            -- onlineByVersion/onlineCount elsewhere in this file.
            Font.draw("CHECKING...", 16, 56)
          else
            local list = currentList()
            local n = list and #list or 0
            if self.index > n then self.index = 1 end
            if n == 0 then
              Font.draw("NO CLEARS YET", 16, 56)
            else
              local row = list[self.index]
              -- The TRUE rank (1 = top scorer overall) is always
              -- derived from the list's real DESCENDING position, even
              -- while sortAsc is showing the reversed read order - so
              -- "#1" always means the actual top scorer, never "first
              -- one shown on this particular page flip."
              -- Was "#<rank>  <index>/<n>" - two numbers that say almost
              -- the same thing whenever sorted descending (rank and the
              -- browsing position ARE the same number then), reported
              -- directly as "just looks a bit untidy and repetitive." The
              -- separate browsing position only ever differed from rank
              -- while sorted ascending (see the comment above on why rank
              -- has to be derived rather than just being self.index), and
              -- that difference isn't something a player needs spelled
              -- out as its own number - "<rank> OF <n>" alone still
              -- always reads as the real leaderboard position, in both
              -- sort orders, with nothing repeated.
              --
              -- NOT "#<rank>" - confirmed directly against the engine's
              -- own src/render/Font.lua: "#" is not a real glyph in this
              -- font at all, it's a deliberate macro (MACRO_TEXT) that
              -- expands to the literal 4 characters "POKe" (with the
              -- accent), mirroring the real cartridge's own charmap quirk
              -- where the ROM's font has ONE character code for the whole
              -- "POKe" string (as in "POKeMON"/"POKe BALL"). Reported
              -- directly on-device as "POKe1   1/2" where "#1  1/2" was
              -- expected - this port genuinely reproduces that Game Boy
              -- font behaviour on purpose, it isn't a rendering bug in the
              -- engine. First time this file ever put a literal "#" into
              -- a drawn string rather than using it as Lua's length
              -- operator in code - every other "#" in this file is that,
              -- never text on screen.
              local rank = self.sortAsc and (n - self.index + 1) or self.index
              Font.draw(("RANK " .. rank .. " OF " .. n):sub(1, 16), 16, 56)
              Font.draw((row.name or "?"):sub(1, 16), 16, 72)
              Font.draw("ID   " .. (row.trainer_id or "-----"), 16, 80)
              Font.draw(("CLEARS " .. tostring(row.total or 0)):sub(1, 16), 16, 88)
              if n > 1 then Font.draw("UD:PAGE", 16, 104) end
            end
          end
          Font.draw("LR:LIST SEL:SORT", 16, 120)
          Font.draw("B:BACK", 16, 128)
        end
        return self
      end,
    })
  end)
end
