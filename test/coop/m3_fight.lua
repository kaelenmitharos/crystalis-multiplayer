-- M3a co-op test: player 2's sword hurts enemies, enemies hurt player 2
-- (P2HP, not PlayerHP), player 2 goes down at 0 HP and revives next to
-- player 1.  Build with --flags="Dn Vmsw Cp"; run like m1_input.lua (see
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
-- Details go to m3_fight.log next to this script, plus m3_*.png.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "m3_fight.log", "w") end)
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

local steps = {
  -- 1: boot to normal play; give player 1 the Wind Sword.
  function()
    if inGame() then
      wr(0x6430, 0x00); wr(0x0711, 0x01)
      return nextStep("in normal play, Wind Sword equipped")
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
  -- 3: join; player 2 starts with player 1's max HP.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 30 then
      if rd(P2Slot) == 0 then return fail("player 2 did not spawn") end
      if rd(P2HP) == 0 or rd(P2HP) ~= rd(PlayerMaxHP) then return fail("P2HP not full on join") end
      s.p1hp = SAFE.hp
      return nextStep(string.format("joined with P2HP %d", rd(P2HP)))
    end
  end,
  -- 4: player 2's sword hurts an enemy held in front of them.
  function()
    if since() == 1 then
      s.e = findEnemy()
      if not s.e then return fail("no enemy on this map") end
      s.hp0, s.act0, s.exp0 = rd(0x03c0 + s.e), rd(0x04a0 + s.e), rd(0x0704) + 256 * rd(0x0705)
      log(string.format("  enemy slot %02x action %02x HP %d", s.e, s.act0, s.hp0))
      atSafePoint = function()
        if rd(0x04a0 + s.e) == s.act0 then
          local f = FRONT[rd(P2Ground + 6) & 7]
          putNearP2(s.e, f[1], f[2])
        end
        wr(P2Invuln, 0x3c) -- keep player 2 safe while swinging
      end
    end
    if since() % 12 < 2 then pad2 = {b = true} end
    local hp, act = rd(0x03c0 + s.e), rd(0x04a0 + s.e)
    if act ~= s.act0 or hp < s.hp0 then
      if SAFE.hp ~= s.p1hp then return fail("player 1 lost HP") end
      shot("m3_hit.png")
      local exp = rd(0x0704) + 256 * rd(0x0705)
      return nextStep(string.format("enemy hit by player 2: HP %d -> %d, action %02x -> %02x, exp %d -> %d",
        s.hp0, hp, s.act0, act, s.exp0, exp))
    end
    if since() > 600 then return fail("player 2's sword never hurt the enemy") end
  end,
  -- 5: an enemy on player 2's body lowers P2HP, not PlayerHP.
  function()
    if since() == 1 then
      s.e = findEnemy()
      if not s.e then return fail("no enemy left") end
      s.p2hp, s.p1hp = rd(P2HP), SAFE.hp
      wr(P2Invuln, 0)
      log(string.format("  enemy slot %02x action %02x attack %d", s.e, rd(0x04a0 + s.e), rd(0x03e0 + s.e)))
      -- Player 2's last swing from step 4 may still kill this one: then
      -- take the next enemy.
      atSafePoint = function()
        if not alive(s.e) then s.e = findEnemy() or s.e end
        putNearP2(s.e, 0, 0)
      end
    end
    if rd(P2HP) < s.p2hp then
      if SAFE.hp ~= s.p1hp then return fail("PlayerHP changed too") end
      return nextStep(string.format("P2HP %d -> %d, PlayerHP still %d", s.p2hp, rd(P2HP), SAFE.hp))
    end
    if since() > 300 then return fail("the enemy never hurt player 2") end
  end,
  -- 5b: a poisonous enemy (level bit 7, 50% per hit) keeps hitting player 2:
  --     player 2 takes damage, but player 1 is never poisoned and the game
  --     never stops for the "poisoned" status message (GameMode $10).
  function()
    if since() == 1 then
      if not alive(s.e) then s.e = findEnemy() end
      if not s.e then return fail("no enemy left") end
      s.status, s.hits, s.lastHP = SAFE.status, 0, rd(P2HP)
      atSafePoint = function()
        if not alive(s.e) then s.e = findEnemy() or s.e end
        wr(0x0420 + s.e, rd(0x0420 + s.e) | 0x80)
        if alive(s.e) then putNearP2(s.e, 0, 0) end
        wr(P2Invuln, 0)
        if rd(P2HP) < 20 then wr(P2HP, 40) end
      end
    end
    if SAFE.gm == 0x10 then return fail("game switched to the status message") end
    if SAFE.status ~= s.status then return fail(string.format("PlayerStatus changed %02x -> %02x", s.status, SAFE.status)) end
    if rd(P2HP) < s.lastHP then s.hits = s.hits + 1 end
    s.lastHP = rd(P2HP)
    if since() == 300 then
      if s.hits < 4 then return fail("player 2 was only hit " .. s.hits .. " times") end
      return nextStep(string.format("%d poisonous hits on player 2; player 1 not poisoned, no status message", s.hits))
    end
  end,
  -- 6: at 0 HP player 2 is down (still joined); player 1 is unaffected.
  function()
    if since() == 1 then
      s.p1hp = SAFE.hp
      atSafePoint = function()
        if rd(P2Down) == 0 then
          wr(P2HP, 1); wr(P2Invuln, 0)
          if s.e and rd(0x04a0 + s.e) ~= 0 then putNearP2(s.e, 0, 0) end
        end
      end
    end
    if since() > 1 and not (s.e and rd(0x04a0 + s.e) ~= 0) then s.e = findEnemy() end
    if rd(P2Down) ~= 0 then
      if rd(P2HP) ~= 0 then return fail("down with HP left") end
      if rd(P2Active) ~= 1 then return fail("P2Active lost") end
      if SAFE.hp ~= s.p1hp then return fail("PlayerHP changed") end
      shot("m3_down.png")
      return nextStep("player 2 is down, still joined")
    end
    if since() > 300 then return fail("player 2 never went down") end
  end,
  -- 7: clear the enemies, put player 1 beside player 2: revive after ~60 frames.
  function()
    if since() == 1 then
      s.loc = rd(CurLoc)
      log(string.format("  P1 (%d,%d) P2 ground (%d,%d) loc %02x", rd(0x90)*256+rd(0x70), rd(0xd0)*240+rd(0xb0), rd(P2Ground+1)*256+rd(P2Ground), rd(P2Ground+3)*240+rd(P2Ground+2), s.loc))
      for e = 0x0d, 0x1e do
        if e ~= rd(P2Slot) and rd(0x04a0 + e) ~= 0 then wr(0x04a0 + e, 0) end
      end
      atSafePoint = function()
        local x = rd(P2Ground + 1) * 256 + rd(P2Ground) + 16
        for _, sl in ipairs({0, 1}) do
          wr(0x70 + sl, x % 256); wr(0x90 + sl, math.floor(x / 256))
          wr(0xb0 + sl, rd(P2Ground + 2)); wr(0xd0 + sl, rd(P2Ground + 3))
        end
      end
    end
    if rd(P2Down) == 0 then
      local want = math.max(1, math.floor(rd(P2MaxHP) / 4))
      if since() < 50 then return fail(string.format("revived too early (%d frames; location %02x, was %02x)", since(), rd(CurLoc), s.loc or 0)) end
      if rd(P2HP) ~= want then return fail(string.format("revived with %d HP, want %d", rd(P2HP), want)) end
      return nextStep(string.format("revived after %d frames with %d HP", since(), rd(P2HP)))
    end
    if since() > 300 then return fail("player 2 never revived") end
  end,
  -- 9: down again, away from player 1 (no proximity revive); a map
  --     change (wild warp) revives player 2 beside player 1.
  function()
    if since() == 1 then
      s.loc = rd(CurLoc)
      atSafePoint = function()
        if rd(CurLoc) == s.loc and rd(P2Down) == 0 and not s.downed then
          local x = rd(0x90) * 256 + rd(0x70) + 64
          wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
          wr(P2HP, 0); wr(P2Down, 1); wr(0x6287, 0)
          s.downed = true
        end
      end
    end
    if since() >= 30 and since() < 42 then pad1 = {a = true, b = true} end
    if since() >= 36 and since() < 39 then pad1 = {a = true, b = true, start = true} end
    if since() == 29 and rd(P2Down) == 0 then return fail("player 2 not down before the warp") end
    if rd(CurLoc) ~= s.loc and inGame() and since() > 60 then
      if rd(P2Down) ~= 0 then return fail("still down on the new map") end
      local want = math.max(1, math.floor(rd(P2MaxHP) / 4))
      if rd(P2HP) ~= want then return fail(string.format("HP %d after the map change, want %d", rd(P2HP), want)) end
      return nextStep(string.format("map %02x -> %02x revived player 2 with %d HP", s.loc, rd(CurLoc), rd(P2HP)))
    end
    if since() > 1500 then return fail("no map change") end
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

log("m3 test started")
