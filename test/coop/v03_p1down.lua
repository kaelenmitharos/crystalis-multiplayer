-- Co-op v0.3 test: player 1 goes down instead of the game being over.
--  1. Boot (Wind Sword), wild warp to $03, player 2 joins.
--  2. An enemy hits player 1 at 1 HP: player 1 is down, not dead (no game
--     over, mode stays 8), frozen (Right doesn't move them), and the
--     enemies can't hurt them.
--  3. Player 2 stands next to player 1 for a second: player 1 is back with
--     a quarter of their max HP; player 2's HP is unchanged.
--  4. Player 1 down again, then a map change: back on the new map with a
--     quarter of their max HP.
--  5. Player 1 down again, then player 2 goes down too: game over (mode 3).
-- Then, as a separate check in the same run (after the game over, the game
-- is restarted with Start): 6. player 2 not joined, player 1 at 0 HP: game
-- over, as vanilla.
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 100 + n stuck at step n,
-- 200 + n check failed at step n.  Details go to v03_p1down.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v03_p1down.log", "w") end)
local function log(s) emu.log(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end
local function shot(name)
  pcall(function() local f = io.open(DIR .. name, "wb"); f:write(emu.takeScreenshot()); f:close() end)
end
local CE = emu.memType.nesMemory ~= nil
local CPU = CE and emu.memType.nesMemory or emu.memType.cpu
local EXEC = CE and emu.callbackType.exec or emu.memCallbackType.cpuExec
local function setPad(port, t)
  if CE then emu.setInput(t, port, port) else emu.setInput(port, t) end
end
local function rd(a) return emu.read(a, CPU) end
local function wr(a, v) emu.write(a, v, CPU) end
log("emulator: " .. (CE and "MesenCE" or "Mesen 0.9.x"))

local P2Active, P2HP, P2MaxHP, P2Slot, P2Ground = 0x6280, 0x6281, 0x6282, 0x628a, 0x6294
local P2Down, P2DownTimer, P2Invuln = 0x62c4, 0x6287, 0x62c0
local P1Down = 0x62d5
local HP, MaxHP, GameMode, CurLoc = 0x03c1, 0x03c0, 0x41, 0x6c

local frame, stepFrame, step, done = 0, 0, 1, false
local pad1, pad2 = {}, {}
local s = {warps = 0}
local hits, last, hist = 0, 0, {}
emu.addMemoryCallback(function() hits = hits + 1 end, EXEC, 0xcb62, 0xcb62)
local atSafePoint = nil
emu.addMemoryCallback(function()
  if atSafePoint then pcall(atSafePoint) end
end, EXEC, 0xcb6e, 0xcb6e)
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(0x40) == 1 and n >= 15
end
local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log(string.format("  P1 %d/%d down %d  P2 %d/%d down %d active %d  gm %02x/%02x loc %02x",
    rd(HP), rd(MaxHP), rd(P1Down), rd(P2HP), rd(P2MaxHP), rd(P2Down), rd(P2Active), rd(0x40), rd(GameMode), rd(CurLoc)))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  step = step + 1; stepFrame = frame; atSafePoint = nil; s.t = {}
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
local function p1x() return rd(0x90) * 256 + rd(0x70) end
local function p1y() return rd(0xd0) * 240 + rd(0xb0) end
local function enemy()
  local plane = rd(0x03a1) & 0xf0
  for e = 0x0d, 0x1e do
    if e ~= rd(P2Slot) and e ~= rd(0x62c1) then
      local a = rd(0x04a0 + e)
      if a ~= 0 and (a & 0x7f) ~= 0x7b and (a & 0x7f) ~= 0x7d and (a & 0x7f) ~= 0x10
         and (rd(0x03a0 + e) & plane) ~= 0 and rd(0x03c0 + e) > 0 and rd(0x03c0 + e) ~= 0xff and rd(0x0540 + e) ~= 0xff then
        return e
      end
    end
  end
end
-- Put player 2 (ground position) dx pixels right of player 1.
local function p2Beside(dx)
  local x = p1x() + dx
  wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
  wr(P2Ground + 2, rd(0xb0)); wr(P2Ground + 3, rd(0xd0))
end
-- An enemy held on player 1 until player 1 is down.
local function knockDown()
  s.t.e = s.t.e or enemy()
  atSafePoint = function()
    wr(P2Invuln, 0x3c)
    if rd(P1Down) == 0 then
      if rd(HP) > 1 then wr(HP, 1) end
      wr(0x071a, 0)
      local e = s.t.e
      if not e or rd(0x04a0 + e) == 0 or rd(0x03c0 + e) == 0 or rd(0x03c0 + e) == 0xff then e = enemy(); s.t.e = e end
      if e then
        wr(0x70 + e, rd(0x70)); wr(0x90 + e, rd(0x90)); wr(0xb0 + e, rd(0xb0)); wr(0xd0 + e, rd(0xd0))
      end
    end
    if s.t.keepAway then p2Beside(64) end
  end
end

local steps = {
  -- 1: boot, warp to $03, join.
  function()
    if not s.booted then
      if inGame() then s.booted = true; s.wf = 0; wr(0x6430, 0x00); wr(0x0711, 0x01) end
      if (rd(0x40) ~= 1 or rd(GameMode) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
      return
    end
    if not s.warped then
      s.wf = s.wf + 1
      if s.wf < 12 then pad1 = {a = true, b = true} end
      if s.wf >= 6 and s.wf < 9 then pad1 = {a = true, b = true, start = true} end
      if s.wf > 90 and inGame() then
        s.warps = s.warps + 1
        if rd(CurLoc) == 0x03 then s.warped = true; s.jf = frame
        elseif s.warps >= 16 then return fail("never reached location 03")
        else s.wf = 0 end
      end
      return
    end
    local t = frame - s.jf
    if t < 3 then pad2 = {start = true} end
    if t == 40 then
      if rd(P2Active) ~= 1 or rd(P2Slot) == 0 then return fail("player 2 did not join") end
      return nextStep("joined")
    end
  end,
  -- 2: an enemy hits player 1 at 1 HP: down, not dead; frozen; safe.
  function()
    if since() == 1 then s.t.keepAway = true; knockDown(); s.p2hp = nil end
    if rd(GameMode) == 3 then return fail("game over: player 1 died") end
    if rd(P1Down) ~= 0 and not s.t.downAt then
      s.t.downAt = since(); s.p2hp = rd(P2HP)
      log(string.format("  player 1 down after %d frames: HP %d", since(), rd(HP)))
    end
    if s.t.downAt then
      local g = since() - s.t.downAt
      -- (the hit that downed them still knocks them back a little)
      if g == 25 then s.t.x, s.t.y = p1x(), p1y() end
      if g > 25 and g < 65 then pad1 = {right = true, b = (g % 10 < 2)} end
      if g == 30 then shot("v03_p1down.png") end
      if g == 70 then
        if rd(GameMode) ~= 8 then return fail(string.format("mode %02x while player 1 is down", rd(GameMode))) end
        if rd(P1Down) == 0 then return fail("player 1 got up by themself") end
        if p1x() ~= s.t.x or p1y() ~= s.t.y then return fail(string.format("player 1 moved while down: (%d,%d) -> (%d,%d)", s.t.x, s.t.y, p1x(), p1y())) end
        if rd(HP) ~= 1 then return fail("player 1's HP changed while down: " .. rd(HP)) end
        return nextStep("player 1 is down (1 HP), frozen, not hurt, no game over")
      end
    end
    if since() > 1500 then return fail("player 1 never went down") end
  end,
  -- 3: player 2 next to player 1 for a second: player 1 is back.
  function()
    if since() == 1 then
      s.p2hp = rd(P2HP)
      atSafePoint = function() wr(P2Invuln, 0x3c); p2Beside(12) end
    end
    if rd(P1Down) == 0 then
      local want = math.max(1, math.floor(rd(MaxHP) / 4))
      if since() < 50 then return fail(string.format("revived too early (%d frames)", since())) end
      if rd(HP) ~= want then return fail(string.format("player 1 back with %d HP, want %d", rd(HP), want)) end
      s.t.back = s.t.back or since()
    end
    if s.t.back and since() == s.t.back + 20 then
      if rd(P2HP) ~= s.p2hp then return fail(string.format("player 2's HP changed %d -> %d on the revive", s.p2hp, rd(P2HP))) end
      local x = p1x()
      s.t.x = x
    end
    if s.t.back and since() > s.t.back + 20 and since() < s.t.back + 50 then pad1 = {left = true} end
    if s.t.back and since() == s.t.back + 55 then
      if p1x() == s.t.x then return fail("player 1 still frozen after the revive") end
      return nextStep(string.format("player 2 revived player 1 after %d frames with %d HP; player 1 can move", s.t.back, rd(HP)))
    end
    if since() > 600 then return fail("player 1 never revived") end
  end,
  -- 4: down again, then a map change: back on the new map.
  function()
    if since() == 1 then s.t.keepAway = true; knockDown() end
    if rd(P1Down) ~= 0 and not s.t.downAt then s.t.downAt = since(); s.t.loc = rd(CurLoc) end
    if s.t.downAt and since() == s.t.downAt + 20 then
      atSafePoint = function() wr(P2Invuln, 0x3c) end
      wr(CurLoc, 0x05); wr(0x6d, 0); wr(GameMode, 1)
    end
    if s.t.downAt and since() > s.t.downAt + 40 and rd(CurLoc) == 0x05 and inGame() and not s.t.arrived then s.t.arrived = since() end
    if s.t.arrived and since() == s.t.arrived + 10 then
      local want = math.max(1, math.floor(rd(MaxHP) / 4))
      if rd(P1Down) ~= 0 then return fail("player 1 still down on the new map") end
      if rd(HP) ~= want then return fail(string.format("player 1 has %d HP on the new map, want %d", rd(HP), want)) end
      return nextStep(string.format("map change %02x -> 05 revived player 1 with %d HP", s.t.loc, rd(HP)))
    end
    if since() > 2500 then return fail("no down or no map change") end
  end,
  -- 5: down again, then player 2 goes down too: game over.
  function()
    if since() == 1 then s.t.keepAway = true; knockDown() end
    if rd(P1Down) ~= 0 and not s.t.downAt then s.t.downAt = since() end
    if s.t.downAt and since() == s.t.downAt + 20 then
      atSafePoint = function()
        p2Beside(64)
        if not s.t.p2down then wr(P2HP, 0); wr(P2Down, 1); wr(P2DownTimer, 0); s.t.p2down = true end
      end
    end
    if rd(GameMode) == 3 then
      if not s.t.downAt then return fail("game over before player 1 was down") end
      return nextStep(string.format("both down: game over %d frames later", since() - s.t.downAt - 20))
    end
    if since() > 1500 then return fail("no game over with both down") end
  end,
  -- 6: back to the title (Start through the game over), new game; player 1
  --    alone at 0 HP: game over, as vanilla.
  function()
    if not s.t.booted then
      if rd(0x40) == 1 and inGame() and rd(GameMode) == 8 and since() > 300 then
        s.t.booted = since()
        if rd(P2Active) ~= 0 then return fail("player 2 still joined after the game over") end
      end
      if (rd(0x40) ~= 1 or rd(GameMode) ~= 8) and since() % 40 < 2 then pad1 = {start = true} end
      if since() > 6000 then return fail("never got back to normal play") end
      return
    end
    if since() == s.t.booted + 30 then
      atSafePoint = function() wr(HP, 0) end
    end
    if since() > s.t.booted + 30 and rd(GameMode) == 3 then
      return nextStep("player 1 alone at 0 HP: game over, as vanilla")
    end
    if since() > s.t.booted + 600 then return fail("no game over for player 1 alone") end
  end,
  function() finish(0, "ALL PASS") end,
}

emu.addEventCallback(function()
  if done then return end
  setPad(0, pad1); setPad(1, pad2)
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if done then return end
  frame = frame + 1
  pad1, pad2 = {}, {}
  table.insert(hist, hits > last and 1 or 0); last = hits
  if #hist > 30 then table.remove(hist, 1) end
  local ok, err = pcall(steps[step])
  if not ok then return finish(99, "LUA ERROR " .. tostring(err)) end
  if not done and since() > 8000 then finish(100 + step, "TIMEOUT") end
end, emu.eventType.startFrame)

log("v03 player 1 down test started")
