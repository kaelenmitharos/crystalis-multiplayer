-- Co-op v0.3 test: a wall broken by player 2's charge shot crumbles like
-- one broken by player 1's.  (The testers saw a wall break without the
-- crumble animation; this checks the game side: the wall's slot loads its
-- crumble object, action $08, as it does for player 1.)
-- In Sealed Cave 3 ($09) with the Wind Sword and the Ball of Wind
-- equipped, the cave's wind wall is held 40 px in front of the shooter,
-- who charges to level 2 and fires.  Run 1: player 1 shoots; run 2:
-- player 2 shoots.  Build with --flags="Dn Ec Et Vemsw Cp"; run like
-- m1_input.lua.  Exit code: 0 pass, 1 setup failed, 2 a wall didn't
-- crumble, 99 Lua error.  Details in v03_wallbreak.log, screenshots
-- v03_wallbreak_p*.png.
local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local CE = emu.memType.nesMemory ~= nil
local M = CE and emu.memType.nesMemory or emu.memType.cpu
local EXEC = CE and emu.callbackType.exec or emu.memCallbackType.cpuExec
local function setPad(port, t) if CE then emu.setInput(t, port, port) else emu.setInput(port, t) end end
local function rd(a) return emu.read(a, M) end
local function wr(a, v) emu.write(a, v, M) end
local L = io.open(DIR .. "v03_wallbreak.log", "w")
local function log(s) L:write(s .. "\n"); L:flush() end
local function shot(tag)
  pcall(function() local f = io.open(DIR .. "v03_wallbreak_p" .. WHO .. "_" .. tag .. ".png", "wb"); f:write(emu.takeScreenshot()); f:close() end)
end
WHO = 1
local results = {}
local hits, last, hist = 0, 0, {}
emu.addMemoryCallback(function() hits = hits + 1 end, EXEC, 0xcb62, 0xcb62)
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(0x40) == 1 and n >= 15
end
local frame, phase, t0 = 0, "boot", 0
local pad1, pad2 = {}, {}
local wall = nil
local hold = false
local FRONT = {[0] = {0, -40}, [2] = {40, 0}, [4] = {0, 40}, [6] = {-40, 0}}
moveP1 = false
emu.addMemoryCallback(function()
  wr(0x03c1, rd(0x03c0)); wr(0x62c0, 0x3c)
  if moveP1 then
    moveP1 = false
    for _, sl in ipairs({0, 1}) do
      wr(0x70 + sl, s_wx); wr(0x90 + sl, s_wxh)
      local y = s_wy + 64
      local yh = s_wyh
      if y >= 240 then y = y - 240; yh = yh + 1 end
      wr(0xb0 + sl, y); wr(0xd0 + sl, yh)
    end
  end
  if hold and wall and (rd(0x04a0 + wall) & 0x7f) == 0x07 then
    local gx, gy, gyh, gxh, face
    if WHO == 1 then gx, gxh, gy, gyh, face = rd(0x70), rd(0x90), rd(0xb0), rd(0xd0), rd(0x0360) & 6
    else gx, gxh, gy, gyh, face = rd(0x6294), rd(0x6295), rd(0x6296), rd(0x6297), rd(0x629a) & 6 end
    local f = FRONT[face]
    local x = gxh * 256 + gx + f[1]
    wr(0x70 + wall, x % 256); wr(0x90 + wall, math.floor(x / 256))
    wr(0xb0 + wall, (gy + f[2]) % 240); wr(0xd0 + wall, gyh)
  end
end, EXEC, 0xcb6e, 0xcb6e)
emu.addEventCallback(function() setPad(0, pad1); setPad(1, pad2) end, emu.eventType.inputPolled)
local lastAct = -1
emu.addEventCallback(function()
  frame = frame + 1
  pad1, pad2 = {}, {}
  table.insert(hist, hits > last and 1 or 0); last = hits
  if #hist > 30 then table.remove(hist, 1) end
  local f = frame - t0
  if phase == "boot" then
    if inGame() then phase = "warp"; t0 = frame end
    if (rd(0x40) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
  elseif phase == "warp" then
    if f == 2 and WHO == 2 and rd(0x6280) == 0 then end
    if f == 2 then
      wr(0x6430, 0x00); wr(0x0711, 0x01)   -- Wind Sword
      wr(0x643c, 0x05); wr(0x0718, 1); wr(0x0719, 1)  -- Ball of Wind, equipped
      wr(0x6c, 0x09); wr(0x6d, 0); wr(0x41, 1)
    end
    if f > 150 and inGame() then phase = "setup"; t0 = frame end
  elseif phase == "setup" then
    if f < 3 and rd(0x6280) == 0 then pad2 = {start = true} end
    if f == 40 then
      for e = 0x0d, 0x1e do if rd(0x06c0 + e) & 0x20 ~= 0 and (rd(0x04a0 + e) & 0x7f) == 0x07 then wall = e end end
      log(string.format("player %d; P2Active %d; wall slot %s", WHO, rd(0x6280), tostring(wall)))
      if not wall then log("no wall"); L:close(); emu.stop(1); return end
      s_wx, s_wxh, s_wy, s_wyh = rd(0x70 + wall), rd(0x90 + wall), rd(0xb0 + wall), rd(0xd0 + wall)
    end
    if f == 70 then
      log("facing up; holding the wall in front of the shooter; wall slot now " .. tostring(wall))
      if not wall then log("no wall"); L:close(); emu.stop(1); return end
      if WHO == 2 then pad2 = {up = true} end
      hold = true
      phase = "charge"; t0 = frame
    end
    if f > 40 and f < 70 and f % 10 < 3 then pad1 = {up = true}; pad2 = {up = true} end
    if f == 200 then log("wall never woke: act " .. string.format("%02x", rd(0x04a0 + wall))); shot("nowake"); L:close(); emu.stop(1) end
  elseif phase == "charge" then
    -- hold B 100 frames (level 2), release
    if f < 100 then if WHO == 1 then pad1 = {b = true} else pad2 = {b = true} end end
    if f == 99 then log(string.format("charge: P1 %02x P2 %02x", rd(0x0600), rd(0x62a3))) end
    local a = rd(0x04a0 + wall)
    if a ~= lastAct then
      log(string.format("f %d wall slot act %02x 300 %02x 4c0 %02x 6c0 %02x 3a0 %02x", f, a, rd(0x0300 + wall), rd(0x04c0 + wall), rd(0x06c0 + wall), rd(0x03a0 + wall)))
      lastAct = a
      if f > 100 then hold = false end
    end
    if f == 120 then shot("120") end
    if a == 0x08 and not crumbled then crumbled = f end
    if f == 300 then
      log(string.format("player %d: %s", WHO, crumbled and ("the wall crumbled (action 08) at frame " .. crumbled) or "NO crumble"))
      results[WHO] = crumbled ~= nil
      if WHO == 1 then
        WHO = 2; wall = nil; hold = false; crumbled = nil; lastAct = -1
        phase = "warp"; t0 = frame
      else
        local ok = results[1] and results[2]
        log(ok and "ALL PASS" or "FAIL")
        L:close(); emu.stop(ok and 0 or 2)
      end
    end
  end
end, emu.eventType.startFrame)
