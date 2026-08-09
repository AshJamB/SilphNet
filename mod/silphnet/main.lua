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

  pcall(function()
    mod.options:define({
      { key = "enabled",    type = "toggle", label = "SILPHNET ON",     default = true },
      { key = "name",       type = "text",   label = "MY NAME",         default = "" },
      { key = "passphrase", type = "text",   label = "PASSPHRASE",      default = "" },
      { key = "host",       type = "text",   label = "SERVER HOST",     default = "192.168.1.100" },
      { key = "port",       type = "number", label = "SERVER PORT",     default = 7788, min = 1, max = 65535, step = 1 },
      { key = "use_octets", type = "toggle", label = "HOST AS NUMBERS", default = false },
      { key = "o1", type = "number", label = "HOST NUM 1", default = 192, min = 0, max = 255, step = 1 },
      { key = "o2", type = "number", label = "HOST NUM 2", default = 168, min = 0, max = 255, step = 1 },
      { key = "o3", type = "number", label = "HOST NUM 3", default = 1,   min = 0, max = 255, step = 1 },
      { key = "o4", type = "number", label = "HOST NUM 4", default = 100, min = 0, max = 255, step = 1 },
    })
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

  local function resolveHost()
    if opt("use_octets", false) then
      return string.format("%d.%d.%d.%d", opt("o1",192), opt("o2",168), opt("o3",1), opt("o4",100))
    end
    return opt("host", "192.168.1.100")
  end

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
  local function getHandle(id)
    local ok, h = pcall(function() return mod.world:npc(myMap, "SILPHNET_" .. id) end)
    if ok then return h end
    return nil
  end
  local function despawnRemote(id)
    local r = remotes[id]
    if r and r.npcId ~= nil then pcall(function() mod.world:removeNpc(r.npcId) end) end
    remotes[id] = nil
  end
  local function despawnAll() for id in pairs(remotes) do despawnRemote(id) end end
  local function spawnRemote(id, name, sprite, x, y, facing)   -- << VERIFY >> objDef shape
    local objDef = { index = allocIndex(id), x = x, y = y, sprite = sprite or MY_SPRITE,
                     movement = "STAY", range = "NONE", name = "SILPHNET_" .. id }
    local ok, npcId = pcall(function() return mod.world:spawnNpc(myMap, objDef) end)
    if not ok then mod.log:warn("spawnNpc failed for %s: %s", tostring(id), tostring(npcId)); return end
    remotes[id] = { name = name, sprite = sprite, npcId = npcId, shownX = x, shownY = y,
                    facing = facing, stuck = 0 }
    local h = getHandle(id); if h then pcall(function() h:face(facing) end) end
  end
  local function applyPeer(id, name, sprite, x, y, facing)
    local r = remotes[id]
    if not r then spawnRemote(id, name, sprite, x, y, facing); return end
    r.name, r.sprite = name, sprite
    if x == r.shownX and y == r.shownY then
      if facing ~= r.facing then
        local h = getHandle(id); if h then pcall(function() h:face(facing) end) end
        r.facing = facing
      end
      r.stuck = 0; return
    end
    local dir = stepDir(x - r.shownX, y - r.shownY)
    local h = getHandle(id)
    if dir and h then
      local cx, cy; local okp = pcall(function() cx, cy = h:position() end)
      if okp and cx == r.shownX and cy == r.shownY then
        pcall(function() h:scriptMove(dir, 1) end)
        r.shownX, r.shownY, r.facing, r.stuck = x, y, facing, 0
      else
        r.stuck = (r.stuck or 0) + 1
        if r.stuck > STUCK_TICKS then despawnRemote(id); spawnRemote(id, name, sprite, x, y, facing) end
      end
    else
      despawnRemote(id); spawnRemote(id, name, sprite, x, y, facing)
    end
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

  -- ---- per-frame pump -------------------------------------------------------
  local function pump()
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
    local cur = mod.world and mod.world:current()
    if not cur then return end
    if not authed then return end

    if cur.mapId ~= myMap then
      despawnAll()
      myMap, myX, myY, myFacing = cur.mapId, cur.x, cur.y, cur.facing
      sendPos()
    elseif cur.x ~= myX or cur.y ~= myY or cur.facing ~= myFacing then
      myX, myY, myFacing = cur.x, cur.y, cur.facing
      sendPos()
    end

    local dt = (love.timer and love.timer.getDelta and love.timer.getDelta()) or 0.016
    sinceKeepalive = sinceKeepalive + dt
    if sinceKeepalive >= KEEPALIVE then sinceKeepalive = 0; sendPos() end

    if latestState then applyState(latestState) end
  end

  local function statusLabel()
    if authed then return "SILPHNET " .. peerCount end
    if authState == "need_creds" then return "SILPHNET SET NAME/PASS" end
    if authState == "failed" then return "SILPHNET LOGIN FAIL" end
    if connected then return "SILPHNET ..." end
    return "SILPHNET OFF"
  end

  local function reconnect()
    authed, authState = false, "idle"
    despawnAll()
    myName = sanitizeName(opt("name", "")) or (game and game.save and game.save.player and sanitizeName(game.save.player.name))
    myPass = opt("passphrase", "") or ""
    CTL:push({ cmd = "connect", host = resolveHost(), port = opt("port", 7788) })
  end

  -- ---- wiring ---------------------------------------------------------------
  mod.events:on("game.ready", function(ev)
    game = ev.game
    silphOn = opt("enabled", true) and true or false
    math.randomseed(os.time() + math.floor((os.clock() or 0) * 1000))
    if not silphOn then mod.log:info("disabled in options"); return end
    reconnect()
    mod.log:info("connecting to %s:%s", tostring(resolveHost()), tostring(opt("port", 7788)))
  end)

  mod.events:on("mod.options_changed", function(ev)
    local k = ev and ev.key
    if k == "host" or k == "port" or k == "use_octets" or k == "o1" or k == "o2"
       or k == "o3" or k == "o4" or k == "name" or k == "passphrase" or k == "enabled" then
      silphOn = opt("enabled", true) and true or false
      if silphOn then reconnect() else CTL:push({ cmd = "disconnect" }); authed = false; despawnAll() end
    end
  end)

  mod.events:on("map.entered", function(ev)
    despawnAll()
    myMap = ev.mapId
    local cur = mod.world:current()
    if cur then myX, myY, myFacing = cur.x, cur.y, cur.facing end
    sendPos()
  end)

  mod.events:on("map.exited", function() despawnAll() end)

  mod.events:on("world.stepped", function(ev)
    myMap, myX, myY = ev.mapId, ev.x, ev.y
    local cur = mod.world:current(); if cur then myFacing = cur.facing end
    sendPos()
  end)

  mod.hooks:wrap("render.letterbox", function(nextFn, ctx)
    nextFn(ctx)
    pcall(pump)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, g, items)
    pcall(function()
      mod.ui.insertBefore(items, "QUIT", { label = statusLabel(), onSelect = reconnect })
    end)
    return nextFn(g, items)
  end)
end
