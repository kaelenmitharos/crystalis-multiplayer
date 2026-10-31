-- M3b co-op test: status effects for player 2 (poison, paralysis, curse)
-- without touching player 1 or showing the status message; poison drains
-- P2HP; reviving clears the status.  Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see
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
-- Details go to m3b_status.log next to this script, plus m3b_status.png.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "m3b_status.log", "w") end)
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
-- Is object e still a live enemy (not dying, $7d, or gone)?
local function alive(e)
  local act = e and rd(0x04a0 + e) or 0
  return act ~= 0 and (act & 0x7f) ~= 0x7d and rd(0x03c0 + e) ~= 0xff
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

local P2Status, PlayerStatus = 0x6286, 0x0710
local function status(v) return v & 0x0f end
-- Checks that must hold on every frame of the test.
local function invariants()
  if SAFE.gm == 0x10 then return "the game switched to the status message" end
  if s.p1status and SAFE.status ~= s.p1status then
    return string.format("PlayerStatus changed %02x -> %02x", s.p1status, SAFE.status)
  end
  if s.p1hp and SAFE.hp ~= s.p1hp then return "PlayerHP changed" end
  return nil
end
-- Turn enemy e into a status shot (as vanilla projectiles are: $0540 = $ff,
-- status in $0560) and keep it on player 2.
-- If the enemy despawns before it reaches player 2, use another.
local function statusShot(e, st)
  wr(0x0540 + e, 0xff); wr(0x0560 + e, st)
  local used = false
  atSafePoint = function()
    if not alive(s.e) and not used and status(rd(P2Status)) ~= st then
      local n = findEnemy()
      if n then s.e = n; wr(0x0540 + n, 0xff); wr(0x0560 + n, st) end
    end
    if status(rd(P2Status)) == st then used = true end
    e = s.e
    if rd(0x04a0 + e) ~= 0 then putNearP2(e, 0, 0) end
    wr(P2Invuln, 0)
    -- Other enemies may wander in too: don't let them take player 2 down.
    if rd(P2Down) == 0 and rd(P2HP) < 30 then wr(P2HP, 40) end
  end
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
      s.p1status, s.p1hp = rd(PlayerStatus), rd(PlayerHP)
      s.p1atk, s.p1arm, s.p1shd = rd(0x03e1), rd(0x0401), rd(0x0400)
      s.speed0 = rd(P2Ground + 5) & 0x0f
      return nextStep(string.format("joined; player 1 status %02x, player 2 speed %d", s.p1status, s.speed0))
    end
  end,
  -- 4: a poisonous enemy (level bit 7) poisons player 2, not player 1.
  function()
    if since() == 1 then
      s.e = findEnemy()
      if not s.e then return fail("no enemy") end
      wr(0x0420 + s.e, rd(0x0420 + s.e) | 0x80)
      atSafePoint = function()
        if rd(0x04a0 + s.e) ~= 0 then putNearP2(s.e, 0, 0) end
        wr(P2Invuln, 0)
        if rd(P2HP) < 30 then wr(P2HP, 40) end
      end
    end
    local bad = invariants(); if bad then return fail(bad) end
    if status(rd(P2Status)) == 3 then
      wr(0x04a0 + s.e, 0) -- remove the enemy
      return nextStep(string.format("player 2 poisoned after %d frames", since()))
    end
    if since() > 600 then return fail("player 2 never got poisoned") end
  end,
  -- 5: poison drains 4 HP every 32 frames.
  function()
    if since() == 1 then
      atSafePoint = function() if rd(P2HP) < 20 then wr(P2HP, 40) end end
    end
    if since() == 10 then s.hp0 = rd(P2HP) end
    local bad = invariants(); if bad then return fail(bad) end
    if since() == 10 + 64 then
      local drop = s.hp0 - rd(P2HP)
      if drop ~= 8 then return fail("poison took " .. drop .. " HP in 64 frames, want 8") end
      return nextStep("poison took 8 HP in 64 frames")
    end
  end,
  -- 6: poison takes player 2 down; reviving beside player 1 clears it.
  function()
    if since() == 1 then
      atSafePoint = function() if rd(P2Down) == 0 and rd(P2HP) > 4 then wr(P2HP, 4) end end
    end
    local bad = invariants(); if bad then return fail(bad) end
    if rd(P2Down) ~= 0 and not s.downAt then
      s.downAt = since()
      atSafePoint = function()
        local x = rd(P2Ground + 1) * 256 + rd(P2Ground) + 16
        for _, sl in ipairs({0, 1}) do
          wr(0x70 + sl, x % 256); wr(0x90 + sl, math.floor(x / 256))
          wr(0xb0 + sl, rd(P2Ground + 2)); wr(0xd0 + sl, rd(P2Ground + 3))
        end
      end
    end
    if s.downAt and rd(P2Down) == 0 then
      if status(rd(P2Status)) ~= 0 then return fail("revived still poisoned") end
      atSafePoint = nil
      return nextStep("poison took player 2 down; revived without the poison")
    end
    if since() > 600 then return fail("player 2 never went down or revived") end
  end,
  -- 6b: move player 2 away from player 1, so the status shots below can't
  --     touch player 1 too.
  function()
    if since() == 1 then
      atSafePoint = function()
        local x = rd(0x90) * 256 + rd(0x70) - 64
        local p = rd(P2Slot)
        wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
        wr(P2Ground + 2, rd(0xb0)); wr(P2Ground + 3, rd(0xd0))
        if p ~= 0 then
          wr(0x70 + p, x % 256); wr(0x90 + p, math.floor(x / 256))
          wr(0xb0 + p, rd(0xb0)); wr(0xd0 + p, rd(0xd0))
        end
        atSafePoint = nil
      end
    end
    if since() == 10 then return nextStep("player 2 moved 64 px from player 1") end
  end,
  -- 7: a paralysis shot paralyzes player 2 and is used up.  (Vanilla
  --    paralysis doesn't change speed; it is a status flag that blocks the
  --    Warrior Ring's free charge level until Lysis Plant cures it.)
  function()
    if since() == 1 then
      s.e = findEnemy()
      if not s.e then return fail("no enemy for the paralysis shot") end
      statusShot(s.e, 1)
    end
    local bad = invariants(); if bad then return fail(bad) end
    if status(rd(P2Status)) == 1 and not s.paraAt then
      if rd(0x04a0 + s.e) ~= 0 then return fail("the shot was not used up") end
      atSafePoint = nil
      s.paraAt = since()
    end
    if s.paraAt then pad2 = {down = true} end
    if s.paraAt and since() == s.paraAt + 40 then
      if status(rd(P2Status)) ~= 1 then return fail("paralysis wore off") end
      return nextStep("paralyzed (shot used up); player 1 unaffected")
    end
    if since() > 600 then return fail("player 2 never got paralyzed") end
  end,
  -- 8: a curse shot turns player 2 into a slime; player 1's equipment stays.
  function()
    if since() == 1 then
      wr(P2Status, 0)
      s.e = findEnemy()
      if not s.e then return fail("no enemy for the curse shot") end
      statusShot(s.e, 4)
    end
    local bad = invariants(); if bad then return fail(bad) end
    if status(rd(P2Status)) == 4 and not s.curseAt then
      atSafePoint = nil
      s.curseAt = since()
    end
    if s.curseAt then pad2 = {left = true} end
    if s.curseAt and since() == s.curseAt + 20 then
      local spr = rd(0x0300 + rd(P2Slot))
      if spr ~= 0x53 then return fail(string.format("player 2's sprite is %02x, want the slime 53", spr)) end
      if rd(0x03e1) ~= s.p1atk or rd(0x0401) ~= s.p1arm or rd(0x0400) ~= s.p1shd then
        return fail("player 1's attack or defense changed")
      end
      shot("m3b_status.png")
      return nextStep("cursed: player 2 is a slime; player 1's equipment unchanged")
    end
    if since() > 600 then return fail("player 2 never got cursed") end
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

log("m3b status test started")
