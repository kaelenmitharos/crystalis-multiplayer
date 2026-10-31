-- M3b co-op test: charge shots for player 2 (slots 8..$b; player 1 keeps 4..7)
-- without drawing over player 1's charge meter; the shots hurt enemies.
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see
-- its header for the MesenCE / Mesen 0.9.9 commands).
--
-- Enemies are moved into place with RAM writes, done right after the co-op
-- hook returns ($cb6e) so player 2 is never swapped into slot 0 then.
--
-- Result is the exit code:
--   0          all checks passed
--   99         Lua error (see the log)
--   100 + n    stuck at step n (timeout)
--   200 + n    check failed at step n
-- Details go to m3b_charge.log next to this script, plus m3b_charge.png.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "m3b_charge.log", "w") end)
local function log(s) emu.log(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end
local function shot(name)
  pcall(function()
    local f = io.open(DIR .. name, "wb"); f:write(emu.takeScreenshot()); f:close()
  end)
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
local P2Invuln, P2SwordSlot, P2Down = 0x62c0, 0x62c1, 0x62c4
local PlayerHP, PlayerMaxHP, MainLoopMode, CurLoc = 0x03c1, 0x03c0, 0x40, 0x6c

local frame, stepFrame, step = 0, 0, 1
local pad1, pad2 = {}, {}
local mode8Hits, done = 0, false
local s = {warps = 0}

-- Work done at the safe point each frame (set by the steps).
local atSafePoint = nil
emu.addMemoryCallback(function() mode8Hits = mode8Hits + 1 end, EXEC, 0xcb62, 0xcb62)
-- Values that player 2 swaps in during their update (PlayerStatus,
-- PlayerHP) are only meaningful at the safe point, never mid-frame.
local SAFE = {}
emu.addMemoryCallback(function()
  SAFE.status, SAFE.hp, SAFE.gm = rd(0x0710), rd(0x03c1), rd(0x41)
  if atSafePoint then pcall(atSafePoint) end
end, EXEC, 0xcb6e, 0xcb6e)

local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log(string.format("  P2HP %d/%d down %d  PlayerHP %d/%d  P2 slot %02x sword %02x",
    rd(P2HP), rd(P2MaxHP), rd(P2Down), rd(PlayerHP), rd(PlayerMaxHP), rd(P2Slot), rd(P2SwordSlot)))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  step = step + 1; stepFrame = frame; atSafePoint = nil
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
local hist, lastHits = {}, 0
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(MainLoopMode) == 1 and n >= 15
end

-- An enemy: active, shares the hero's collision plane, has HP, and isn't a
-- coin, a projectile or player 2's own objects.
local function findEnemy(exclude)
  local plane = rd(0x03a1) & 0xf0
  for e = 0x0d, 0x1e do
    if e ~= rd(P2Slot) and e ~= rd(P2SwordSlot) and e ~= exclude then
      local act = rd(0x04a0 + e)
      if act ~= 0 and (act & 0x7f) ~= 0x7b and (act & 0x7f) ~= 0x10
         and (rd(0x03a0 + e) & plane) ~= 0 and rd(0x03c0 + e) > 0 and rd(0x0540 + e) ~= 0xff then
        return e
      end
    end
  end
  return nil
end
-- Put object e at player 2's ground position plus (dx, dy).
local function putNearP2(e, dx, dy)
  local x = rd(P2Ground + 1) * 256 + rd(P2Ground) + dx
  local ylo, yhi = rd(P2Ground + 2) + dy, rd(P2Ground + 3)
  if ylo < 0 then ylo = ylo + 240; yhi = yhi - 1 elseif ylo >= 240 then ylo = ylo - 240; yhi = yhi + 1 end
  wr(0x70 + e, x % 256); wr(0x90 + e, math.floor(x / 256))
  wr(0xb0 + e, ylo); wr(0xd0 + e, yhi % 256)
end
-- Offsets in front of player 2, by facing ($0360: 0 up, 2 right, 4 down, 6 left).
local FRONT = {[0] = {0, -14}, [1] = {10, -10}, [2] = {14, 0}, [3] = {10, 10},
               [4] = {0, 14}, [5] = {-10, 10}, [6] = {-14, 0}, [7] = {-10, -10}}

local PPU = CE and emu.memType.nesPpuMemory or emu.memType.ppu
local function meter()
  local t = {}
  for i = 0, 6 do t[#t + 1] = string.format("%02x", emu.read(0x2b43 + i, PPU)) end
  return table.concat(t, " ")
end
local function shotsIn(a, b)
  local t = {}
  for sl = a, b do if rd(0x04a0 + sl) ~= 0 then t[#t + 1] = string.format("%02x:%02x", sl, rd(0x04a0 + sl)) end end
  return t
end

local steps = {
  -- 1: boot; give player 1 the Wind Sword.
  function()
    if inGame() then
      wr(0x6430, 0x00); wr(0x0711, 0x01)
      return nextStep("in normal play")
    end
    if (rd(MainLoopMode) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
  end,
  -- 2: wild warp to location $03 (has enemies).
  function()
    if since() == 1 then s.wf = 0 end
    s.wf = s.wf + 1
    if s.wf < 12 then pad1 = {a = true, b = true} end
    if s.wf >= 6 and s.wf < 9 then pad1 = {a = true, b = true, start = true} end
    if s.wf > 90 and inGame() then
      s.warps = s.warps + 1
      if rd(CurLoc) == 0x03 then return nextStep("on location 03") end
      if s.warps >= 16 then return fail("never reached location 03") end
      s.wf = 0
    end
  end,
  -- 3: join.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 30 then
      if rd(P2Slot) == 0 then return fail("player 2 did not spawn") end
      s.meter = meter()
      return nextStep("joined; player 1's charge meter: " .. s.meter)
    end
  end,
  -- 4: player 2 charges (hold B); player 1's meter doesn't move.
  function()
    atSafePoint = function() wr(P2Invuln, 0x3c) end
    pad2 = {b = true}
    if meter() ~= s.meter then return fail("player 1's charge meter changed: " .. meter()) end
    if since() == 80 then
      s.charge = rd(P2Ground + 15)
      if s.charge < 8 then return fail("player 2's charge is only " .. s.charge) end
      s.before = #shotsIn(0x08, 0x0b)
      return nextStep(string.format("player 2 charged to %d; player 1's meter unchanged", s.charge))
    end
  end,
  -- 5: release: player 2's shot lands in slots 8..$b, not 4..7.
  function()
    local hi, lo = shotsIn(0x08, 0x0b), shotsIn(0x04, 0x07)
    if #lo > 0 then return fail("a shot in player 1's slots: " .. table.concat(lo, " ")) end
    if #hi > s.before then
      return nextStep("player 2's shot in " .. table.concat(hi, " "))
    end
    if since() > 30 then return fail("no shot from player 2") end
  end,
  -- 6: player 1 charges and fires: their shot stays in 4..7.
  function()
    if since() < 50 then pad1 = {b = true} end
    if since() >= 50 then
      local lo = shotsIn(0x04, 0x07)
      if #lo > 0 then return nextStep("player 1's shot in " .. table.concat(lo, " ")) end
      if since() > 80 then return fail("no shot from player 1 in 4..7 (8..b: " .. table.concat(shotsIn(0x08, 0x0b), " ") .. ")") end
    end
  end,
  -- 7: player 2's charged shot hurts an enemy held 40 px in front of them.
  function()
    if since() == 1 then
      for sl = 0x04, 0x0b do wr(0x04a0 + sl, 0) end -- clear old shots
      s.e = findEnemy()
      if not s.e then return fail("no enemy") end
      s.hp0, s.act0 = rd(0x03c0 + s.e), rd(0x04a0 + s.e)
      atSafePoint = function()
        wr(P2Invuln, 0x3c)
        if rd(0x04a0 + s.e) == s.act0 then
          local f = FRONT[rd(P2Ground + 6) & 7]
          putNearP2(s.e, f[1] * 3, f[2] * 3)
        end
      end
    end
    local t = since() % 60
    if t < 45 then pad2 = {b = true} end
    local hp, act = rd(0x03c0 + s.e), rd(0x04a0 + s.e)
    if act ~= s.act0 or hp < s.hp0 then
      shot("m3b_charge.png")
      return nextStep(string.format("enemy hit by player 2's shot: HP %d -> %d, action %02x -> %02x", s.hp0, hp, s.act0, act))
    end
    if since() > 600 then return fail("player 2's shots never hurt the enemy") end
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
  table.insert(hist, mode8Hits > lastHits and 1 or 0); lastHits = mode8Hits
  if #hist > 30 then table.remove(hist, 1) end
  local ok, err = pcall(steps[step])
  if not ok then return finish(99, "LUA ERROR " .. tostring(err)) end
  if not done and since() > 4000 then finish(100 + step, "TIMEOUT") end
end, emu.eventType.startFrame)

log("m3b charge test started")
