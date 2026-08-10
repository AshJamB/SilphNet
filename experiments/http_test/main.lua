-- SilphNet HTTP Test - throwaway diagnostic mod
-- =============================================================================
-- Answers exactly one question: can this device reach a plain http://
-- endpoint from inside the game? LOVE 11 has no TLS, so https:// is out
-- (that's why Gen1Online failed on Android) - but LuaSocket's http module
-- opens a raw socket directly, the same as the raw TCP SilphNet already
-- uses successfully, rather than going through Android's Java HTTP stack
-- (HttpURLConnection/okhttp) - which is specifically what Android's
-- cleartext-traffic block targets. So plain http:// SHOULD work even
-- though https:// can't. This mod finds out for real.
--
-- SET THIS to your uploaded silphnet_test.php's plain-http URL before
-- installing:
--   http://yourdomain.com/silphnet_test.php
-- Plain http, NOT https - that's the entire point of the test.
-- =============================================================================

return function(mod)
  local TEST_URL = "http://CHANGE-ME.example.com/silphnet_test.php"   -- << EDIT ME

  -- The request runs on a background thread so a slow/hanging connection
  -- can't freeze the game - same pattern the real SilphNet mod uses for
  -- its TCP thread.
  local THREAD_SRC = [==[
    local url = ...
    local RESULT = love.thread.getChannel("httptest_result")
    local ok, http = pcall(require, "socket.http")
    if not ok then
      RESULT:push("ERR: socket.http unavailable - " .. tostring(http))
      return
    end
    local body, code, headers, statusline = http.request(url)
    if not body then
      -- `code` carries the error string (e.g. "connection refused",
      -- "timeout") when the request never got a response at all.
      RESULT:push("ERR: " .. tostring(code))
    else
      RESULT:push("OK " .. tostring(code) .. ": " .. tostring(body):sub(1, 200))
    end
  ]==]

  local RESULT = love.thread.getChannel("httptest_result")
  local status = "not tested yet"
  local lastFull = ""

  local function runTest()
    status = "testing..."
    local t = love.thread.newThread(THREAD_SRC)
    t:start(TEST_URL)
  end

  local function pump()
    local r = RESULT:pop()
    while r do
      lastFull = r
      status = r:sub(1, 40)
      mod.log:info("httptest: %s", r)
      r = RESULT:pop()
    end
  end

  pcall(function()
    mod.content.screens:register("SilphNetHttpTestScreen", {
      new = function(g)
        local Font = mod.ui.Font
        local self = { game = g, isOpaque = true }
        function self:update(dt)
          local input = g.input
          if input:wasPressed("a") then runTest() end
          if input:wasPressed("b") then g.stack:pop() end
        end
        function self:draw()
          Font.drawBox(0, 0, 20, 18)
          Font.draw("HTTP TEST", 16, 8)
          -- word-wrap the result into the box by hand: crude but enough
          -- for a throwaway diagnostic screen
          local text = lastFull ~= "" and lastFull or "no result yet"
          local width = 16
          local y = 32
          local i = 1
          while i <= #text and y < 104 do
            Font.draw(text:sub(i, i + width - 1), 16, y)
            i = i + width
            y = y + 8
          end
          Font.draw("A:RUN TEST", 16, 112)
          Font.draw("B:BACK", 16, 120)
        end
        return self
      end,
    })
  end)

  mod.events:on("game.ready", function(ev)
    runTest()
  end)

  mod.hooks:wrap("input.step", function(nextFn, g, dt)
    pcall(pump)
    return nextFn(g, dt)
  end)

  mod.hooks:wrap("ui.start_menu.items", function(nextFn, g, items)
    pcall(function()
      mod.ui.insertBefore(items, "QUIT", { label = "HTTP TEST: " .. status,
        onSelect = function() mod.ui.push(g, "SilphNetHttpTestScreen") end })
    end)
    return nextFn(g, items)
  end)
end
