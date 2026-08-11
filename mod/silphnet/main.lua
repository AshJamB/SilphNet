-- SilphNet - async presence + friends (v1.0.0)
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
--     socket, no per-tick movement sync.
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
  local gameVersion = "UNKNOWN"   -- << VERIFY >> however the engine exposes RED/BLUE/YELLOW, if at all

  -- authState: idle|logging_in|need_creds|failed|authed
  local authState = "idle"
  local authBusy  = false

  -- Keyed by "account_id|game_version" (see parseFriendsJson), NOT bare
  -- account_id - one friend can have multiple entries here if they have
  -- more than one active save.
  local friends = {}   -- "account_id|game_version" -> { account_id, name, game_version, map_id, x, y, facing, last_seen (unix) }
  local markers = {}   -- same key -> { npcId, mapId, x, y }  (spawned silhouettes on the CURRENT map only)
  local idToIndex, nextIndex = {}, 9000

  local pendingRequests = {}   -- array of { name, trainer_id } - incoming requests awaiting YOUR accept
  local addFriendStatus = ""   -- last add-friend result, shown briefly on the Add Friend screen

  local function sanitizeName(s)
    if not s or s == "" then return nil end
    s = tostring(s):gsub("[|;,\r\n]", ""):sub(1, 10)
    if s == "" then return nil end
    return s
  end

  local function resolveMyName()
    return sanitizeName(opt("name", ""))
        or (game and game.save and game.save.player and sanitizeName(game.save.player.name))
        or nil
  end

  -- ---- HTTP plumbing ------------------------------------------------------
  -- One short-lived love.thread per request (same pattern proven in
  -- experiments/http_test) - these fire at most every few seconds, so
  -- there's no benefit to a persistent thread, and a short-lived one can't
  -- wedge the pump loop if a single request hangs.
  local HTTP_POST_SRC = [==[
    local url, body = ...
    local RESULT = love.thread.getChannel("silphnet_http_result")
    local ok, http = pcall(require, "socket.http")
    if not ok then RESULT:push("TAG_PLACEHOLDER|ERR|socket.http unavailable"); return end
    http.TIMEOUT = 8
    local respBody, code = http.request(url, body)
    if not respBody then RESULT:push("TAG_PLACEHOLDER|ERR|" .. tostring(code))
    else RESULT:push("TAG_PLACEHOLDER|OK|" .. respBody) end
  ]==]

  local HTTP_GET_SRC = [==[
    local url = ...
    local RESULT = love.thread.getChannel("silphnet_http_result")
    local ok, http = pcall(require, "socket.http")
    if not ok then RESULT:push("TAG_PLACEHOLDER|ERR|socket.http unavailable"); return end
    http.TIMEOUT = 8
    local body, code = http.request(url)
    if not body then RESULT:push("TAG_PLACEHOLDER|ERR|" .. tostring(code))
    else RESULT:push("TAG_PLACEHOLDER|OK|" .. body) end
  ]==]

  local HTTP_RESULT = love.thread.getChannel("silphnet_http_result")

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

  -- tag identifies which request a result belongs to when it comes back
  -- (login/register/ping/friends can all be in flight independently).
  -- Substitutes the literal string "TAG_PLACEHOLDER" in the thread source
  -- for the real tag before starting it, since love.thread sources are
  -- plain strings compiled fresh per thread - simplest way to get a
  -- distinguishable prefix back out without a shared upvalue (threads
  -- don't share Lua state).
  local function httpPost(tag, path, fields)
    local src = HTTP_POST_SRC:gsub("TAG_PLACEHOLDER", tag)
    love.thread.newThread(src):start(API_BASE .. path, encodeForm(fields))
  end
  local function httpGet(tag, path, query)
    local src = HTTP_GET_SRC:gsub("TAG_PLACEHOLDER", tag)
    love.thread.newThread(src):start(API_BASE .. path .. "?" .. encodeForm(query))
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
  local function parseObjects(body)
    local out = {}
    for obj in string.gmatch(body, "%{[^{}]-%}") do
      local rec = {}
      for k, v in string.gmatch(obj, '"([%w_]+)"%s*:%s*"?([^",}]*)"?') do
        rec[k] = v
      end
      out[#out + 1] = rec
    end
    return out
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

  local function onAuthOk(accId, name, token, trainerId)
    accountId, myName = accId, name or myName
    if trainerId then myTrainerId = trainerId end
    authState, authBusy = "authed", false
    if token then pcall(function() mod.save:set("token", token) end) end
    mod.log:info("SilphNet: logged in as %s", tostring(myName))
  end

  -- Forward-declared: handleHttpResult (below) needs to trigger a fresh
  -- friends/pending fetch right after an accept, but those functions live
  -- in the "presence" section further down. Declaring the locals here and
  -- assigning the real function bodies later keeps handleHttpResult's
  -- closure correctly bound to the SAME locals (not globals) once they're
  -- assigned - the exact bug class that bit an earlier version of this
  -- file when a function was defined before the locals it referenced
  -- existed at all (caught via a lupa test harness).
  local fireFriendsFetch, firePendingFetch

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
        -- password" for a name that doesn't exist yet. First login on a
        -- new name auto-creates the account, same as before.
        doRegister()
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
        addFriendStatus = "REQUEST SENT TO " .. tostring(jsonField(body, "name"))
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
    end
  end

  -- ---- presence -----------------------------------------------------------
  local sincePresence = PRESENCE_INTERVAL   -- fire shortly after login, not immediately
  local presenceBusy   = false
  local friendsBusy     = false
  local pendingBusy      = false

  local function firePresencePing()
    if authState ~= "authed" or not myMap then return end
    presenceBusy = true
    httpPost("ping", "/ping.php", {
      token = mod.save:get("token") or "",
      map_id = myMap, x = myX or 0, y = myY or 0,
      facing = myFacing or "down", game_version = gameVersion,
    })
  end

  fireFriendsFetch = function()
    if authState ~= "authed" then return end
    friendsBusy = true
    httpGet("friends", "/friends.php", { token = mod.save:get("token") or "" })
  end

  firePendingFetch = function()
    if authState ~= "authed" then return end
    pendingBusy = true
    httpGet("pending", "/pending_requests.php", { token = mod.save:get("token") or "" })
  end

  local function fireAddFriend(trainerId)
    addFriendStatus = "SENDING..."
    httpPost("add_friend", "/add_friend.php", { token = mod.save:get("token") or "", trainer_id = trainerId })
  end

  -- ---- friend silhouettes (static, one placement per poll, never tweened) -
  local function allocIndex(id)
    if not idToIndex[id] then idToIndex[id] = nextIndex; nextIndex = nextIndex + 1 end
    return idToIndex[id]
  end

  local function despawnMarker(id)
    local m = markers[id]
    if m and m.npcId ~= nil then pcall(mod.world.removeNpc, mod.world, m.npcId) end
    markers[id] = nil
  end
  local function despawnAllMarkers() for id in pairs(markers) do despawnMarker(id) end end

  local function spawnMarker(id, x, y, facing)   -- << VERIFY >> objDef shape
    local objDef = { index = allocIndex(id), x = x, y = y, sprite = MY_SPRITE,
                      movement = "STAY", range = "NONE", name = "SILPHNET_FRIEND_" .. id }
    local ok, npcId = pcall(mod.world.spawnNpc, mod.world, myMap, objDef)
    if not ok then mod.log:warn("SilphNet: marker spawn failed for %s: %s", tostring(id), tostring(npcId)); return end
    markers[id] = { npcId = npcId, mapId = myMap, x = x, y = y }
    local h
    pcall(function() h = mod.world:npc(myMap, "SILPHNET_FRIEND_" .. id) end)
    if h then pcall(h.face, h, facing) end
  end

  -- Reconciles the friend-marker set against `friends` + the current map -
  -- called once per friends-fetch completion and once on map.entered, NOT
  -- per-tick. Each friend gets at most one static marker, only when their
  -- last-known map matches the one you're standing on right now.
  local function refreshMarkers()
    if not inOverworld then despawnAllMarkers(); return end
    local wanted = {}
    for id, f in pairs(friends) do
      if f.map_id == myMap then
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

  -- last_seen from the API is a MySQL DATETIME string ("YYYY-MM-DD
  -- HH:MM:SS"), always UTC (NOW() on the server). Converts to a unix
  -- timestamp using os.time with explicit UTC fields so ONLINE/OFFLINE and
  -- "N MIN AGO" are correct regardless of the player's local timezone.
  local function parseMysqlDatetimeUtc(s)
    if not s then return nil end
    local y, mo, d, h, mi, se = string.match(s, "(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)")
    if not y then return nil end
    -- os.time uses the LOCAL calendar interpretation of the given fields,
    -- so build the UTC instant by comparing against os.date("!*t") (UTC
    -- "now") and os.time with the same fields, correcting for the offset
    -- between local and UTC epoch interpretations.
    local utcNow = os.time(os.date("!*t"))
    local localNow = os.time(os.date("*t"))
    local offset = localNow - utcNow
    local t = os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                         hour = tonumber(h), min = tonumber(mi), sec = tonumber(se) })
    return t + offset
  end

  local function statusLabel()
    if authState == "authed" then return "SILPHNET " .. myName end
    if authState == "need_creds" then return "SILPHNET SET NAME/PASS" end
    if authState == "failed" then return "SILPHNET LOGIN FAIL" end
    if authState == "logging_in" then return "SILPHNET ..." end
    return "SILPHNET OFF"
  end

  local function statusText()
    if authState == "authed" then return "LOGGED IN AS " .. tostring(myName) end
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
        function self:update(dt)
          local input = g.input
          if input:wasPressed("a") then beginAuth() end
          if input:wasPressed("b") then g.stack:pop() end
          if input:wasPressed("start") then mod.ui.push(g, "SilphNetFriends") end
          if input:wasPressed("right") then addFriendStatus = ""; mod.ui.push(g, "SilphNetAddFriend") end
          if input:wasPressed("left") and #pendingRequests > 0 then mod.ui.push(g, "SilphNetRequests") end
          -- RESET lives here, on SELECT, rather than as a mod option - see
          -- the options:define comment above for why.
          if input:wasPressed("select") then mod.ui.push(g, "SilphNetResetConfirm") end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("SILPHNET", 16, 8)
          -- Box is 20 characters wide - every line here must fit within
          -- that, including the value (e.g. myName, statusText()), or it
          -- gets clipped at the box edge instead of wrapping. NAME and
          -- STATUS values get their own line below the label for this
          -- reason, since myName can be up to 10 chars and statusText()
          -- can return "LOGGED IN AS <name>" (well over 20 on its own).
          Font.draw("NAME", 16, 24)
          Font.draw((myName or "----"):sub(1, 20), 16, 32)
          Font.draw("ID   " .. (myTrainerId or "-----"), 16, 48)
          Font.draw("STATUS", 16, 64)
          Font.draw(statusText():sub(1, 20), 16, 72)
          -- Counts distinct PEOPLE, not distinct friends[] entries - an
          -- entry exists per (friend, game_version), so a friend with two
          -- active saves would otherwise be double-counted here.
          local seenPeople, n = {}, 0
          for _, f in pairs(friends) do
            if f.account_id and not seenPeople[f.account_id] then
              seenPeople[f.account_id] = true; n = n + 1
            end
          end
          Font.draw("FRIENDS  " .. n, 16, 88)
          Font.draw("REQUESTS " .. #pendingRequests, 16, 96)
          Font.draw("A:LOGIN ST:FRIENDS", 16, 112)
          Font.draw("RT:ADD  LT:REQUEST", 16, 120)
          Font.draw("B:BACK  SL:RESET", 16, 128)
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
          Font.draw("NAME   " .. (myName or "----"), 16, 32)
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
          if input:wasPressed("right") or input:wasPressed("a") then
            self.page = (#ids == 0) and 1 or (self.page % #ids) + 1
          end
          if input:wasPressed("left") then
            self.page = (#ids == 0) and 1 or ((self.page - 2) % #ids) + 1
          end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("FRIENDS", 16, 8)
          local ids = sortedIds()
          if #ids == 0 then
            Font.draw("NO FRIENDS YET", 16, 40)
          else
            local id = ids[self.page]
            local f = friends[id]
            local lastSeenUnix = parseMysqlDatetimeUtc(f.last_seen)
            local ago = timeAgoText(lastSeenUnix)
            local isOnline = lastSeenUnix and (os.time() - lastSeenUnix) <= OFFLINE_AFTER
            Font.draw((self.page) .. "/" .. #ids .. "  " .. (f.name or "?"), 16, 32)
            Font.draw(isOnline and "STATUS ONLINE" or "STATUS OFFLINE", 16, 48)
            if f.map_id then
              Font.draw(friendlyMapName(f.map_id), 16, 64)
              Font.draw("(" .. tostring(f.x) .. "," .. tostring(f.y) .. ")", 16, 80)
              Font.draw(ago, 16, 96)
              -- No game-version line here on purpose: the engine has no way
              -- for a mod to detect which cartridge (Red/Blue/Yellow) is
              -- running, and there's no in-game self-select for it yet
              -- either, so every ping is tagged the same placeholder value
              -- server-side. Showing that placeholder to the player just
              -- reads as a bug ("why does it say UNKNOWN?") rather than a
              -- real feature - better to say nothing until there's a real
              -- value. Revisit once a version picker exists (see main.lua
              -- git history / project notes for that discussion).
            else
              Font.draw("NEVER SEEN YET", 16, 64)
            end
          end
          Font.draw("B:BACK", 16, 128)
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
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true, digits = { 0, 0, 0, 0, 0 }, cursor = 1 }
        function self:update(dt)
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
          if addFriendStatus ~= "" then Font.draw(addFriendStatus, 16, 80) end
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
        function self:update(dt)
          local input = g.input
          local n = #pendingRequests
          if input:wasPressed("right") then self.page = (n == 0) and 1 or (self.page % n) + 1 end
          if input:wasPressed("left") then self.page = (n == 0) and 1 or ((self.page - 2) % n) + 1 end
          if input:wasPressed("a") and n > 0 then
            local req = pendingRequests[self.page]
            if req and req.name then
              httpPost("accept_friend", "/accept_friend.php",
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
            Font.draw(self.page .. "/" .. n .. "  " .. tostring(req.name or "?"), 16, 32)
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
  -- Runs off `input.step` (Game:step, src/core/Game.lua) - fires every
  -- deterministic FixedStep logic tick, before drawing, unconditionally.
  -- Undocumented in the curated wiki hook reference but real and present in
  -- engine source, explicitly meant for exactly this kind of background
  -- "tool" mod. << VERIFY >> this keeps working across engine updates.
  local function pump(dt)
    local r = HTTP_RESULT:pop()
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
        else
          handleHttpResult(tag, status, body)
        end
      end
      r = HTTP_RESULT:pop()
    end

    if authState ~= "authed" or not inOverworld then return end
    sincePresence = sincePresence + (dt or 1/60)
    if sincePresence >= PRESENCE_INTERVAL then
      sincePresence = 0
      if not presenceBusy then firePresencePing() end
      if not friendsBusy then fireFriendsFetch() end
      if not pendingBusy then firePendingFetch() end
    end
  end

  -- ---- wiring ---------------------------------------------------------------
  mod.events:on("game.ready", function(ev)
    game = ev.game
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
    myName = resolveMyName()
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
    inOverworld = true
    myMap = ev.mapId
    local cur = mod.world:current()
    if cur then myX, myY, myFacing = cur.x, cur.y, cur.facing end
    refreshMarkers()
  end)

  mod.events:on("map.exited", function() inOverworld = false; despawnAllMarkers() end)

  mod.events:on("world.stepped", function(ev)
    myMap, myX, myY = ev.mapId, ev.x, ev.y
    local cur = mod.world:current(); if cur then myFacing = cur.facing end
  end)

  mod.hooks:wrap("input.step", function(nextFn, g, dt)
    pcall(pump, dt)
    return nextFn(g, dt)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, g, items)
    pcall(function()
      mod.ui.insertBefore(items, "QUIT", { label = statusLabel(),
        onSelect = function() mod.ui.push(g, "SilphNetStatus") end })
    end)
    return nextFn(g, items)
  end)
end
