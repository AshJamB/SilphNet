-- SilphNet - Milestone 1 (shared overworld) + Phase 1 (accounts)
-- =============================================================================
-- See other trainers walk the same map in real time, behind an account that
-- follows you across devices and reinstalls.
--
-- TRANSPORT: a background love.thread owns a PLAIN TCP socket (luasocket). No
-- HTTPS/TLS - which is why this works on Android (LOVE 11 has no SSL there).
--
-- AUTH (passphrase never crosses the wire):
--   * Set MY NAME + PASSPHRASE in the Mod Manager options.
--   * First login on a name auto-creates the account; later logins prove it
--     with a SHA-256 challenge-response; a device token is cached so you don't
--     retype every launch. On a new device, enter the same name + passphrase.
--   * See ../../SECURITY.md and ../../ACCOUNTS.md for the model and its limits.
--
-- WIRE PROTOCOL (newline-delimited; see server/silphnet_server.py)
--   send: HI|2  REG|name|sprite|salt|pwHash  LOGIN|name  AUTH|proof
--         TOK|name|token   P|map|x|y|facing   B
--   recv: CHAL|salt|nonce  OK|id|name|token  ERR|code|msg
--         S|map|id,name,sprite,x,y,facing;...
--
-- Engine specifics I couldn't run here are marked << VERIFY >>.
-- =============================================================================

return function(mod)
  local MY_SPRITE   = "SPRITE_RED"   -- << VERIFY >> a valid overworld sprite id
  local KEEPALIVE   = 1.0
  local STUCK_TICKS = 20

  -- Release build ships against one known server - no HOST/PORT fields in
  -- the menu to fumble on a phone keyboard. Change these two lines and
  -- rebuild if the server ever moves.
  local SERVER_HOST = "192.168.40.7"
  local SERVER_PORT = 7788

  -- Text fields default to Gen 1's classic 7-char name cap and the naming
  -- grid has no digits at all (vanilla trainer names never needed them) - so
  -- typing a passphrase with numbers in it couldn't be done however long the
  -- field was. maxLen asks for a longer field (the engine reads it straight
  -- off this row: see ManagerState.buildOptionRows, `maxLen = row.maxLen or
  -- 7`); the ui.naming.grid hook below adds a 0-9 row when one of THESE
  -- fields is the one open. See README.md for exactly how to enter it
  -- in-game. << VERIFY >> on real hardware.
  local FIELD_MAXLEN = { ["MY NAME"] = 10, ["PASSPHRASE"] = 12 }

  pcall(function()
    mod.options:define({
      -- Off by default: this is the experimental real-time live-position
      -- feature (a live TCP thread + spawnNpc + a hand-rolled walk tween
      -- reaching into unsupported engine internals - see the "Remote
      -- trainer movement is experimental" section of README.md). It's an
      -- opt-in extra now, not the mod's main purpose - that's shifting
      -- toward an async, MySQL-backed "last known sighting" model instead
      -- (no live socket, no per-tick engine hooks, none of the judder/
      -- collision problems this real-time path fought all session).
      { key = "enabled",    type = "toggle", label = "SILPHNET LIVE (EXPERIMENTAL)", default = false },
      { key = "name",       type = "text",   label = "MY NAME",     default = "", maxLen = FIELD_MAXLEN["MY NAME"] },
      { key = "passphrase", type = "text",   label = "PASSPHRASE",  default = "", maxLen = FIELD_MAXLEN["PASSPHRASE"] },
    })
  end)
  -- Deliberately NOT a fourth "reset" option row here (an earlier build had
  -- one). The Manager auto-appends its own RESET DEFAULTS row to every
  -- mod's options screen, and its RESET DEFAULTS loops through this exact
  -- schema and fires mod.options_changed once per row, using each row's own
  -- `default` - including a "reset" row, if one existed here. That meant
  -- pressing the engine's RESET DEFAULTS also fired OUR reset handler as a
  -- side effect (confirm screen and all), while simultaneously wiping
  -- NAME/PASSPHRASE to blank unconditionally and before that confirm screen
  -- even showed - so declining our confirm did nothing to undo the part
  -- RESET DEFAULTS had already done. Two reset-shaped things sharing one
  -- options schema always collide like this. The reset action lives on the
  -- SilphNetStatus screen instead (SELECT), which the Manager's options
  -- reset can't reach at all.

  -- Add a digits row (and keep the existing "." for the host field) to the
  -- naming-grid screen, but ONLY when it's one of our own fields open -
  -- every other naming screen in the game (trainer name, nicknames, ...)
  -- must stay exactly vanilla.
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

  -- ---- background TCP thread (transport only) --------------------------------
  local THREAD_SRC = [==[
    require("love.timer")
    local socket = require("socket")
    local CTL = love.thread.getChannel("silphnet_ctl")
    local OUT = love.thread.getChannel("silphnet_out")
    local IN  = love.thread.getChannel("silphnet_in")
    local DBG = love.thread.getChannel("silphnet_dbg")

    local sock, host, port
    local connected, wantConnect = false, false
    local recvBuf, nextAttempt = "", 0
    local function log(s) DBG:push(s) end
    local function closeSock()
      if sock then pcall(function() sock:close() end) end
      sock, connected, recvBuf = nil, false, ""
    end
    local function tryConnect()
      closeSock()
      local s = socket.tcp(); if not s then log("err:no-socket"); return end
      s:settimeout(3)
      local ok, cerr = s:connect(host, port)
      if not ok then log("err:connect:" .. tostring(cerr)); pcall(function() s:close() end); return end
      s:settimeout(0); pcall(function() s:setoption("tcp-nodelay", true) end)
      sock, connected = s, true; log("connected")
    end
    local function sendAll(data)
      local i, n = 1, #data
      while i <= n do
        local sent, err, last = sock:send(data, i)
        if sent then i = sent + 1
        elseif err == "timeout" then i = (last or (i - 1)) + 1; love.timer.sleep(0.002)
        else log("err:send:" .. tostring(err)); closeSock(); return false end
      end
      return true
    end
    while true do
      local ctl = CTL:pop()
      while ctl do
        if ctl.cmd == "connect" then host, port, wantConnect, nextAttempt = ctl.host, ctl.port, true, 0
        elseif ctl.cmd == "disconnect" then wantConnect = false; closeSock()
        elseif ctl.cmd == "stop" then closeSock(); return end
        ctl = CTL:pop()
      end
      if wantConnect and not connected and love.timer.getTime() >= nextAttempt then
        tryConnect(); if not connected then nextAttempt = love.timer.getTime() + 2.0 end
      end
      if connected then
        local line = OUT:pop()
        while line do if not sendAll(line .. "\n") then break end; line = OUT:pop() end
      end
      if connected then
        local data, err, partial = sock:receive(4096)
        local got = data or partial
        if got and #got > 0 then recvBuf = recvBuf .. got end
        if err == "closed" then log("closed"); closeSock() end
        while true do
          local nl = string.find(recvBuf, "\n", 1, true)
          if not nl then break end
          local one = string.sub(recvBuf, 1, nl - 1)
          recvBuf = string.sub(recvBuf, nl + 1)
          if #one > 0 then IN:push(one) end
        end
      end
      love.timer.sleep(0.02)
    end
  ]==]

  local CTL = love.thread.getChannel("silphnet_ctl")
  local OUT = love.thread.getChannel("silphnet_out")
  local IN  = love.thread.getChannel("silphnet_in")
  local DBG = love.thread.getChannel("silphnet_dbg")
  love.thread.newThread(THREAD_SRC):start()

  -- ---- state ----------------------------------------------------------------
  local game
  local silphOn   = true
  local connected = false
  local authed    = false
  local authState = "idle"          -- idle|need_creds|wait_tok|wait_chal|wait_auth|wait_reg|authed|failed
  local accountId, myName, myPass
  local myMap, myX, myY, myFacing
  local inOverworld = false
  local sinceKeepalive = 0
  local peerCount = 0

  local remotes = {}
  local idToIndex, nextIndex = {}, 9000

  -- ---- small helpers --------------------------------------------------------
  local function sanitizeName(s)
    if not s or s == "" then return nil end
    s = tostring(s):gsub("[|;,\r\n]", ""):sub(1, 10)
    if s == "" then return nil end
    return s
  end

  -- Hardcoded (see SERVER_HOST/SERVER_PORT at the top) - kept as functions
  -- rather than inlining the constants everywhere so the status screen and
  -- reconnect() don't need to change if this ever needs to read from
  -- somewhere else again (e.g. a baked-in default with an override).
  local function resolveHost() return SERVER_HOST end
  local function resolvePort() return SERVER_PORT end

  local function randByte()
    if love.math and love.math.random then return love.math.random(0, 255) end
    return math.random(0, 255)
  end
  local function randHex(nbytes)
    local t = {}
    for i = 1, nbytes do t[i] = string.format("%02x", randByte()) end
    return table.concat(t)
  end

  -- SHA-256 hex via LOVE's data module (available on LOVE 11, incl. Android)
  local function sha256hex(s)   -- << VERIFY >> love.data.hash availability/shape
    local raw
    pcall(function() raw = love.data.hash("sha256", s) end)
    if not raw then return nil end
    local hex
    pcall(function() hex = love.data.encode("string", "hex", raw) end)
    if hex then return hex end
    return (raw:gsub(".", function(c) return string.format("%02x", string.byte(c)) end))
  end

  local function send(line) OUT:push(line) end

  local function sendPos()
    if not authed or not myMap then return end
    send(string.format("P|%s|%d|%d|%s", myMap, myX or 0, myY or 0, myFacing or "down"))
  end

  -- ---- auth -----------------------------------------------------------------
  local function beginAuth()
    send("HI|2")
    myName = sanitizeName(opt("name", "")) or sanitizeName(myName) or nil
    myPass = opt("passphrase", "") or ""
    local token     = mod.save:get("token")
    local tokenName = mod.save:get("tokenName")
    if not myName then
      authState = "need_creds"
      mod.log:warn("set MY NAME (and PASSPHRASE) in SilphNet options")
      return
    end
    if token and tokenName == myName then
      send(string.format("TOK|%s|%s", myName, token)); authState = "wait_tok"
    elseif myPass ~= "" then
      send(string.format("LOGIN|%s", myName)); authState = "wait_chal"
    else
      authState = "need_creds"
      mod.log:warn("set a PASSPHRASE in SilphNet options to log in")
    end
  end

  local function doRegister()
    local salt = randHex(8)
    local pwHash = sha256hex(salt .. myPass)
    if not pwHash then authState = "failed"; mod.log:error("hashing unavailable"); return end
    send(string.format("REG|%s|%s|%s|%s", myName, MY_SPRITE, salt, pwHash))
    authState = "wait_reg"
  end

  local function handleAuthLine(line)
    local tag = string.match(line, "^([^|]*)|") or line
    if tag == "CHAL" then
      local salt, nonce = string.match(line, "^CHAL|([^|]*)|([^|]*)$")
      if salt and nonce and myPass and myPass ~= "" then
        local pwHash = sha256hex(salt .. myPass)
        local proof  = pwHash and sha256hex(pwHash .. nonce)
        if proof then send("AUTH|" .. proof); authState = "wait_auth"
        else authState = "failed"; mod.log:error("hashing unavailable") end
      else
        authState = "need_creds"
      end
    elseif tag == "OK" then
      local id, name, token = string.match(line, "^OK|([^|]*)|([^|]*)|([^|]*)$")
      accountId, myName = id, name or myName
      authed, authState = true, "authed"
      if token then
        pcall(function() mod.save:set("token", token) end)
        pcall(function() mod.save:set("tokenName", myName) end)
      end
      mod.log:info("logged in as %s", tostring(myName))
      sendPos()
    elseif tag == "ERR" then
      local code = string.match(line, "^ERR|([^|]*)|") or "?"
      if authState == "wait_tok" and code == "BAD_TOKEN" then
        pcall(function() mod.save:set("token", nil) end)
        if myPass and myPass ~= "" then send("LOGIN|" .. myName); authState = "wait_chal"
        else authState = "need_creds"; mod.log:warn("token expired - set PASSPHRASE to log in") end
      elseif code == "NO_ACCOUNT" and authState == "wait_chal" then
        doRegister()                       -- first login on this name -> create it
      elseif code == "NAME_TAKEN" then
        authState = "failed"; mod.log:warn("name taken - choose another MY NAME")
      elseif code == "BAD_AUTH" then
        authState = "failed"; mod.log:warn("wrong passphrase")
      else
        authState = "failed"; mod.log:warn("auth error: %s", tostring(code))
      end
    end
  end

  -- ---- remote trainers ------------------------------------------------------
  -- Currently unused now that advanceRemote snaps position directly instead
  -- of calling scriptMove(dir, ...) - kept for a follow-up that adds real
  -- pixel interpolation on top of the snap (see snapRemote below), which
  -- would need a direction again to tween px/py toward the target tile.
  local function stepDir(dx, dy)
    if dx == 1 and dy == 0 then return "right" end
    if dx == -1 and dy == 0 then return "left" end
    if dx == 0 and dy == 1 then return "down" end
    if dx == 0 and dy == -1 then return "up" end
    return nil
  end
  local function allocIndex(id)
    if not idToIndex[id] then idToIndex[id] = nextIndex; nextIndex = nextIndex + 1 end
    return idToIndex[id]
  end
  -- `mod.world:npc()` does a linear scan of every NPC on the map (see the
  -- engine's WorldAPI), so calling it fresh on every position update - once
  -- or twice per peer per tick while they're moving - is wasted repeat work.
  -- Resolve the handle ONCE at spawn time and cache it on the remote's
  -- entry; only re-resolve if a cached call actually fails.
  -- pcall(fn, args...) below (never pcall(function() fn(args) end)) - the
  -- latter allocates a brand-new throwaway closure on every single call,
  -- which in the hot per-peer-update path means real, avoidable GC
  -- pressure landing right when a stutter would be most visible.
  local function lookupHandle(id)
    local ok, h = pcall(mod.world.npc, mod.world, myMap, "SILPHNET_" .. id)
    if ok then return h end
    return nil
  end
  local function getHandle(id)
    local r = remotes[id]
    if not r then return lookupHandle(id) end
    if not r.handle then r.handle = lookupHandle(id) end
    return r.handle
  end
  local function invalidateHandle(id)
    local r = remotes[id]
    if r then r.handle = nil end
  end
  local function despawnRemote(id)
    local r = remotes[id]
    if r and r.npcId ~= nil then pcall(mod.world.removeNpc, mod.world, r.npcId) end
    remotes[id] = nil
  end
  local function despawnAll() for id in pairs(remotes) do despawnRemote(id) end end

  local function spawnRemote(id, name, sprite, x, y, facing)   -- << VERIFY >> objDef shape
    local objDef = { index = allocIndex(id), x = x, y = y, sprite = sprite or MY_SPRITE,
                     movement = "STAY", range = "NONE", name = "SILPHNET_" .. id }
    local ok, npcId = pcall(mod.world.spawnNpc, mod.world, myMap, objDef)
    if not ok then mod.log:warn("spawnNpc failed for %s: %s", tostring(id), tostring(npcId)); return end
    remotes[id] = { name = name, sprite = sprite, npcId = npcId,
                    shownX = x, shownY = y, targetX = x, targetY = y,
                    facing = facing, targetFacing = facing,
                    stuck = 0, handle = nil, animProgress = 0 }
    local h = getHandle(id); if h then pcall(h.face, h, facing) end
  end

  -- Cheap and network-driven: just records where the server says this peer
  -- IS now. Never moves anything directly - advanceRemote (below) is the
  -- only thing that moves a trainer.
  local function applyPeer(id, name, sprite, x, y, facing)
    local r = remotes[id]
    if not r then spawnRemote(id, name, sprite, x, y, facing); return end
    r.name, r.sprite = name, sprite
    r.targetX, r.targetY, r.targetFacing = x, y, facing
  end

  -- ---- EXPERIMENTAL: bypass scriptMove, hand-roll the walk tween --------
  -- CONFIRMED on-device (v0.11.0-experimental): bypassing handle:scriptMove
  -- and writing the NPC's position fields directly eliminated the judder
  -- that survived every earlier fix here - scriptMove itself really was
  -- the cause. That build snapped tile-to-tile with no walk animation as
  -- the trade-off; this restores the animation ourselves instead of ever
  -- calling scriptMove again, by tweening npc.px/py exactly the way the
  -- player's own movement does (src/world/Player.lua Player:update():
  -- cellX/cellY hold the OLD tile for the whole step, px/py interpolate
  -- toward the new one over STEP_FRAMES=16 ticks, and cellX/cellY only
  -- flip to the destination once the tween completes).
  --
  -- Still UNSUPPORTED: this reaches past the documented Handle API
  -- (scriptMove/marchInPlace/face/position) into the raw npc table -
  -- Reference-Mod-Object.md calls exactly this kind of reach-in
  -- "unsupported engine internals." Field names (cellX/cellY/px/py/facing)
  -- are confirmed to exist and matter for THIS engine build (v0.11.0-
  -- experimental's snap was visibly correct on-device), but could still
  -- change on an engine update with no warning beyond a mod-manager error.
  -- Every write stays behind a pcall; a failure invalidates the handle and
  -- falls through to the existing stuck-counter respawn, same as any other
  -- handle failure - worst case is a trainer that stops animating and gets
  -- respawned, never a crash.
  local MOVE_ANIM_TICKS = 16   -- matches Player.lua's STEP_FRAMES

  local function snapRemote(id, x, y, facing)
    local h = getHandle(id)
    if not h or not h.npc then invalidateHandle(id); return false end
    local ok = pcall(function()
      h.npc.cellX, h.npc.cellY = x, y
      h.npc.px, h.npc.py = x * 16, y * 16
      h.npc.facing = facing
    end)
    if not ok then invalidateHandle(id); return false end
    return true
  end

  -- Advances one in-flight tween tick, or starts a new one. Only one
  -- tile-move animates at a time per remote; anything queued in
  -- targetX/Y/Facing (see applyPeer) is picked up once the current tween
  -- finishes, same "at most one move in flight" pacing the old
  -- cooldown-based version had - just driven by our own tween progress
  -- instead of a fixed timer.
  local function advanceRemote(id, r)
    local h = getHandle(id)
    if not h or not h.npc then
      invalidateHandle(id)
      r.stuck = (r.stuck or 0) + 1
      if r.stuck > STUCK_TICKS then
        local name, sprite, tx, ty, tf = r.name, r.sprite, r.targetX, r.targetY, r.targetFacing
        despawnRemote(id)
        spawnRemote(id, name, sprite, tx, ty, tf)
      end
      return
    end

    -- Not mid-tween: either apply a pending facing-only update, start a
    -- new tile move, or do nothing. Starting a move falls straight through
    -- into the tween step below instead of returning, so the first
    -- visible movement happens on the SAME tick the move is requested
    -- (setting animProgress here and returning would waste a tick doing
    -- nothing visible before the tween actually starts advancing).
    if not r.animProgress or r.animProgress <= 0 then
      if r.targetX == r.shownX and r.targetY == r.shownY then
        if r.targetFacing and r.targetFacing ~= r.facing then
          local okf = pcall(h.face, h, r.targetFacing)
          if not okf then invalidateHandle(id) end
          r.facing = r.targetFacing
        end
        r.stuck = 0
        return
      end

      local dx, dy = r.targetX - r.shownX, r.targetY - r.shownY
      -- The server only ever sends whole-tile positions, so a normal step
      -- is exactly one tile in one axis. If a missed/coalesced update ever
      -- made this more than one tile away, animating it as a single
      -- 16-tick step would look like teleporting-in-slow-motion, not
      -- walking - snap straight there instead, same as the stuck-timeout
      -- respawn path does.
      if math.abs(dx) > 1 or math.abs(dy) > 1 then
        if snapRemote(id, r.targetX, r.targetY, r.targetFacing) then
          r.shownX, r.shownY, r.facing = r.targetX, r.targetY, r.targetFacing
          r.stuck = 0
        else
          r.stuck = (r.stuck or 0) + 1
        end
        return
      end

      local okf = pcall(function() h.npc.facing = r.targetFacing end)
      if not okf then invalidateHandle(id); return end
      r.animFromX, r.animFromY = r.shownX, r.shownY
      r.animDX, r.animDY = dx, dy
      r.shownX, r.shownY, r.facing = r.targetX, r.targetY, r.targetFacing
      r.animProgress = 0   -- becomes 1 in the tween step immediately below
    end

    -- One tween step, covering both a move that just started above and one
    -- already in flight from a previous tick.
    r.animProgress = r.animProgress + 1
    local done = r.animProgress >= MOVE_ANIM_TICKS
    local ok = pcall(function()
      if done then
        h.npc.cellX, h.npc.cellY = r.shownX, r.shownY
        h.npc.px, h.npc.py = r.shownX * 16, r.shownY * 16
      else
        local px = math.floor(r.animProgress * 16 / MOVE_ANIM_TICKS)
        h.npc.px = r.animFromX * 16 + r.animDX * px
        h.npc.py = r.animFromY * 16 + r.animDY * px
      end
    end)
    if not ok then invalidateHandle(id); return end
    if done then r.animProgress = 0; r.stuck = 0 end
  end

  local function advanceAllRemotes()
    for id, r in pairs(remotes) do advanceRemote(id, r) end
  end

  local function applyState(line)
    local mapId, rest = string.match(line, "^S|([^|]*)|(.*)$")
    if not mapId or mapId ~= myMap then return end
    local present = {}
    for chunk in string.gmatch(rest, "([^;]+)") do
      local id, name, sprite, x, y, facing =
        string.match(chunk, "^([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*)$")
      if id then
        x, y = tonumber(x), tonumber(y)
        if x and y then present[id] = true; applyPeer(id, name, sprite, x, y, facing) end
      end
    end
    for id in pairs(remotes) do if not present[id] then despawnRemote(id) end end
    peerCount = 0; for _ in pairs(remotes) do peerCount = peerCount + 1 end
  end

  -- ---- per-tick pump ----------------------------------------------------
  -- Runs off `input.step` (Game:step, src/core/Game.lua), NOT the draw-only
  -- render.letterbox hook this used to piggyback on. input.step fires every
  -- deterministic FixedStep logic tick, before drawing, unconditionally
  -- regardless of what's on screen - it's the engine's real per-tick
  -- extension point for exactly this kind of background "tool" mod (see the
  -- comment at Game:step's call site). Mutating world state (spawning/
  -- moving remote trainers) from the correct update-time slot, instead of
  -- mid-draw, is the architecturally correct fix for the frame stutter that
  -- showed up specifically whenever a peer moved. It isn't in the curated
  -- wiki hook reference (undocumented, but real and present in engine
  -- source) - << VERIFY >> this keeps working across engine updates.
  local function pump(dt)
    local d = DBG:pop()
    while d do
      if d == "connected" then connected = true; beginAuth()
      elseif d == "closed" then connected, authed, authState = false, false, "idle"; despawnAll()
      else mod.log:info("net %s", tostring(d)) end
      d = DBG:pop()
    end

    local latestState, line = nil, IN:pop()
    while line do
      if string.sub(line, 1, 2) == "S|" then if authed then latestState = line end
      else handleAuthLine(line) end
      line = IN:pop()
    end

    if not silphOn then return end
    if not authed then return end

    -- Position sync is primarily EVENT-driven (world.stepped / map.entered,
    -- wired below) - immediate, no polling. mod.world:current() allocates a
    -- fresh table on every call (see the engine's WorldAPI:current()), so
    -- it's only polled once a second here, as a safety net for anything an
    -- event might miss (e.g. turning in place without moving a tile).
    dt = dt or 1/60
    sinceKeepalive = sinceKeepalive + dt
    if sinceKeepalive >= KEEPALIVE then
      sinceKeepalive = 0
      if inOverworld then
        local cur = mod.world and mod.world:current()
        if cur then
          if cur.mapId ~= myMap then
            despawnAll(); myMap, myX, myY, myFacing = cur.mapId, cur.x, cur.y, cur.facing
          elseif cur.x ~= myX or cur.y ~= myY or cur.facing ~= myFacing then
            myX, myY, myFacing = cur.x, cur.y, cur.facing
          end
        end
      end
      sendPos()
    end

    if inOverworld and latestState then applyState(latestState) end
    -- Runs every tick regardless of whether a new S| line arrived this
    -- tick - a remote's queued move (recorded by applyPeer/applyState above)
    -- gets played out at its own paced cooldown, not bursty with however
    -- often the network happens to deliver updates.
    if inOverworld then advanceAllRemotes() end
  end

  local function statusLabel()
    if authed then return "SILPHNET " .. peerCount end
    if authState == "need_creds" then return "SILPHNET SET NAME/PASS" end
    if authState == "failed" then return "SILPHNET LOGIN FAIL" end
    if connected then return "SILPHNET ..." end
    return "SILPHNET OFF"
  end

  local function reconnect()
    authed, authState, connected = false, "idle", false
    despawnAll()
    myName = sanitizeName(opt("name", "")) or (game and game.save and game.save.player and sanitizeName(game.save.player.name))
    myPass = opt("passphrase", "") or ""
    -- The thread only opens a NEW socket when it isn't already connected
    -- (see THREAD_SRC), so a bare "connect" while already connected is a
    -- silent no-op - the old session just sits there while we've locally
    -- marked ourselves unauthed and stopped sending positions, and it times
    -- out server-side ~20s later. Force-close first so "connect" actually
    -- re-dials.
    CTL:push({ cmd = "disconnect" })
    CTL:push({ cmd = "connect", host = resolveHost(), port = resolvePort() })
  end

  local function statusText()
    if authed then return "ONLINE " .. peerCount end
    if authState == "need_creds" then return "SET NAME/PASS" end
    if authState == "failed" then return "LOGIN FAILED" end
    if connected then return "LOGGING IN.." end
    return "OFFLINE"
  end

  -- Actually performs the reset (called only after the confirm screen's
  -- A press - see SilphNetResetConfirm below). Clears the cached device
  -- token (not the name/passphrase option values) and then goes OFFLINE
  -- rather than immediately reconnecting - the token you just wiped would
  -- otherwise silently re-auth using the passphrase a second later, which
  -- defeats the point of a deliberate reset action. Flip SILPHNET ON off
  -- then on again (or hit A on the status screen) when you're ready to log
  -- back in.
  -- << VERIFY >> mod.options only documents :define/:get, not :set
  -- (Reference-Mod-Object.md), so there is no supported way for the mod
  -- itself to flip the "SILPHNET ON" row's displayed value to OFF here -
  -- only the actual connection goes offline. The row may still visibly
  -- read ON in the Manager until you touch it yourself; silphOn (internal)
  -- is what actually gates reconnecting.
  local function performReset()
    pcall(function() mod.save:set("token", nil) end)
    pcall(function() mod.save:set("tokenName", nil) end)
    mod.log:info("SilphNet: reset confirmed - cleared cached token, going offline")
    silphOn = false
    CTL:push({ cmd = "disconnect" })
    authed, authState, connected = false, "idle", false
    despawnAll()
  end

  -- ---- status + reset-confirm screens (Tutorial 11: screens registry) --------
  -- Registered here (not at the top of the file) so the closures below
  -- capture the *local* state variables declared above as upvalues, rather
  -- than resolving to globals - Lua binds a `local` lexically from the point
  -- it's declared, so a function literal written earlier in the file could
  -- not see these. Registration itself still runs once, synchronously,
  -- during this same entry-chunk call, which is all "entry-chunk-only"
  -- requires. << VERIFY >> mod.content.screens / mod.ui.push on-device.
  pcall(function()
    mod.content.screens:register("SilphNetStatus", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          local input = g.input
          if input:wasPressed("a") then reconnect() end
          if input:wasPressed("b") then g.stack:pop() end
          -- RESET lives here, on SELECT, rather than as a mod option - the
          -- Manager's own RESET DEFAULTS row loops over every option this
          -- mod defines and fires mod.options_changed for each one, so a
          -- "reset" option row got triggered as an unwanted side effect of
          -- pressing that unrelated engine button (see the options:define
          -- comment above). A button on our own screen has no such seam.
          if input:wasPressed("select") then mod.ui.push(g, "SilphNetResetConfirm") end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("SILPHNET", 16, 8)
          Font.draw("NAME   " .. (myName or "----"), 16, 32)
          Font.draw("STATUS " .. statusText(), 16, 48)
          Font.draw("SERVER " .. tostring(resolveHost()), 16, 64)
          Font.draw("PORT   " .. tostring(resolvePort()), 16, 80)
          Font.draw("A:RECONNECT", 16, 112)
          Font.draw("B:BACK", 16, 120)
          Font.draw("SELECT:RESET", 16, 128)
        end
        return self
      end,
    })
  end)

  -- Shown instead of resetting immediately when SELECT is pressed on the
  -- status screen - gives you a chance to screenshot your NAME + PASSPHRASE
  -- (both already stored in plaintext locally; this doesn't expose
  -- anything new to anyone but you) before the cached login token is
  -- cleared. B cancels with no changes made at all.
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
          Font.draw("PASS   " .. (myPass ~= "" and myPass or "----"), 16, 48)
          Font.draw("SCREENSHOT NOW", 16, 72)
          Font.draw("IF YOU NEED THIS", 16, 88)
          Font.draw("A:CONFIRM RESET", 16, 120)
          Font.draw("B:CANCEL", 16, 128)
        end
        return self
      end,
    })
  end)

  -- ---- wiring ---------------------------------------------------------------
  mod.events:on("game.ready", function(ev)
    game = ev.game
    silphOn = opt("enabled", true) and true or false
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
    if not silphOn then mod.log:info("disabled in options"); return end
    reconnect()
    mod.log:info("connecting to %s:%s", tostring(resolveHost()), tostring(resolvePort()))
  end)

  mod.events:on("mod.options_changed", function(ev)
    local k = ev and ev.key
    if k == "name" or k == "passphrase" or k == "enabled" then
      silphOn = opt("enabled", true) and true or false
      if silphOn then reconnect() else CTL:push({ cmd = "disconnect" }); authed = false; despawnAll() end
    end
  end)

  mod.events:on("map.entered", function(ev)
    despawnAll()
    inOverworld = true
    myMap = ev.mapId
    local cur = mod.world:current()
    if cur then myX, myY, myFacing = cur.x, cur.y, cur.facing end
    sendPos()
  end)

  mod.events:on("map.exited", function() inOverworld = false; despawnAll() end)

  mod.events:on("world.stepped", function(ev)
    myMap, myX, myY = ev.mapId, ev.x, ev.y
    local cur = mod.world:current(); if cur then myFacing = cur.facing end
    sendPos()
  end)

  -- input.step (Game:step) fires every deterministic FixedStep logic tick,
  -- BEFORE drawing, unconditionally (overworld, battle, menu, cutscene -
  -- see src/core/Game.lua). It's undocumented in the curated wiki hook
  -- reference but real and present in engine source, explicitly meant for
  -- "tool mods" (autoplay/accessibility/input drivers) that "act on the same
  -- fixed-step boundary as a physical controller" - which matches our own
  -- manifest category ("TOOL") exactly. Running our world-mutating network
  -- sync here, instead of inside the draw-only render.letterbox hook we used
  -- previously, keeps that work out of the draw pipeline entirely, which is
  -- the real fix for the stutter that only showed up while a peer moved.
  -- << VERIFY >> input.step isn't in Reference-Hooks.md; recheck this call
  -- site if the engine is updated.
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

  -- Remote trainers are rendered with mod.world:spawnNpc, which is a real
  -- NPC on the map's collision list (src/world/OverworldController.lua:
  -- self.entities = { player } .. self.npcs) - so by default they're solid
  -- to the PLAYER's own movement (blocked step + bump sound), the same as
  -- any vanilla trainer NPC, even though their own scripted walking doesn't
  -- collision-check the player back (that asymmetry is what made BOB able
  -- to walk through you while you couldn't walk through him).
  --
  -- Rather than abandon spawnNpc for a hand-drawn sprite overlay (losing
  -- the walk-cycle animation, facing, etc. it gives for free, and needing
  -- our own camera-to-screen math with no documented accessor for it),
  -- this uses the engine's own movement.collision hook
  -- (src/world/Collision.lua: Collision.canMove) - the single, documented
  -- seam for exactly this ("World" section, Reference-Hooks.md). It fires
  -- with the reason a move was allowed/blocked (bounds/tile/entity) and can
  -- rewrite the verdict. We only flip a "blocked by an entity standing
  -- there" verdict, and only when that entity's cell is one of OUR remote
  -- trainers' last-known positions (tracked in `remotes` already, for
  -- their own movement) - never when it's a wall/water/out-of-bounds, so
  -- this can't let anyone walk through terrain. A tile a live NPC is
  -- standing on is walkable by construction, so "entity" is the only
  -- possible reason the engine could have blocked a step onto exactly that
  -- tile, and that's the one situation we choose to allow.
  --
  -- This doesn't gate on WHO is moving (ctx.mover) - the mod API exposes no
  -- way to compare that against "the player" by identity - so any other
  -- NPC's scripted movement would also be free to step onto a remote
  -- trainer's tile. That's a harmless side effect (it already happens the
  -- other direction - remote trainers walk through the player - and a
  -- wandering vanilla NPC gliding past a remote trainer instead of pacing
  -- into it is arguably an improvement), not something worth restricting
  -- given the API has no cheaper way to check it.
  mod.hooks:wrap("movement.collision", function(nextFn, allowed, ctx)
    allowed = nextFn(allowed, ctx)
    if not allowed and ctx and ctx.reason == "entity" then
      for _, r in pairs(remotes) do
        if r.shownX == ctx.toX and r.shownY == ctx.toY then
          return true
        end
      end
    end
    return allowed
  end)
end
