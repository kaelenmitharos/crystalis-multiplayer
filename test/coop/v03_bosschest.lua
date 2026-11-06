-- Co-op v0.3 test: a boss's reward chest appears while player 2 is joined.
-- The chest spawner (ObjectActionJump_6c) waits until the enemy slots hold
-- no enemies; it counted player 2's sprite as one, so in v0.2 the Rabbit
-- Boots after Vampire 1 only appeared once player 2 left.
--  1. Boot, teleport to Vampire 1's room ($0a, entrance 1, just above
--     Vampire 1), player 2 joins.
--  2. Player 1 kills Vampire 1 (held in front of them with 1 HP).
--  3. The reward chest appears (the waiting object turns into a chest:
--     sprite $aa, collision $8d) with player 2 still joined.
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 100 + n stuck at step
-- n, 200 + n check failed at step n.  Details go to v03_bosschest.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v03_bosschest.log", "w") end)
local function log(s) emu.log(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end
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
local P2Down, P2DownTimer = 0x62c4, 0x6287
local MainLoopMode, CurLoc = 0x40, 0x6c

local frame, stepFrame, step, done = 0, 0, 1, false
local pad1, pad2 = {}, {}
local s = {warps = 0}
local hits, last, hist = 0, 0, {}
emu.addMemoryCallback(function() hits = hits + 1 end, EXEC, 0xcb62, 0xcb62)
local atSafePoint = nil
emu.addMemoryCallback(function()
  -- Keep enemies from deciding the test: player 2 can't be hit while
  -- the test holds them still, and player 1 stays at full HP.
  wr(0x62c0, 0x3c)               -- P2Invuln
  wr(0x03c1, rd(0x03c0))
  if atSafePoint then pcall(atSafePoint) end
end, EXEC, 0xcb6e, 0xcb6e)
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(MainLoopMode) == 1 and n >= 15
end
local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log(string.format("  P2Active %d P2HP %d/%d down %d slot %02x", rd(P2Active), rd(P2HP), rd(P2MaxHP), rd(P2Down), rd(P2Slot)))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  step = step + 1; stepFrame = frame; atSafePoint = nil
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
local function p2pos() return rd(P2Ground + 1) * 256 + rd(P2Ground), rd(P2Ground + 3) * 240 + rd(P2Ground + 2) end
-- Leave (Start) at 0..2, join again (Start) at 30..32.
local function leaveAndRejoin(t)
  if t < 3 or (t >= 30 and t < 33) then pad2 = {start = true} end
end

local FRONT = {[0] = {0, -14}, [1] = {10, -10}, [2] = {14, 0}, [3] = {10, 10},
               [4] = {0, 14}, [5] = {-10, 10}, [6] = {-14, 0}, [7] = {-10, -10}}
local function chests()
  local n = 0
  for e = 0x0d, 0x1e do if rd(0x04a0 + e) == 0x78 then n = n + 1 end end
  return n
end

local steps = {
  -- 1: boot (with the Wind Sword), teleport to $0a, join.
  function()
    if not s.booted then
      if inGame() then s.booted = true; s.t = frame; wr(0x6430, 0x00); wr(0x0711, 0x01) end
      if (rd(MainLoopMode) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
      return
    end
    local t = frame - s.t
    if t == 5 then wr(CurLoc, 0x0a); wr(0x6d, 1); wr(0x41, 1) end  -- entrance 1: right above Vampire 1
    if not s.jf and t > 150 and inGame() and rd(CurLoc) == 0x0a then s.jf = frame end
    if s.jf then
      local j = frame - s.jf
      if j < 3 then pad2 = {start = true} end
      if j == 40 then
        if rd(P2Active) ~= 1 or rd(P2Slot) == 0 then return fail("player 2 did not join") end
        s.chests0 = chests()
        return nextStep(string.format("in Vampire 1's room with player 2 joined (%d chests)", s.chests0))
      end
    end
    if t > 2000 then return fail("teleport failed") end
  end,
  -- 2: Vampire 1 is beaten: it is removed, and the game's boss chest
  --    object (action $6f) is put in a free slot, as the boss death
  --    sequence does.
  function()
    if since() == 1 then
      for e = 0x0d, 0x1e do
        if e ~= rd(P2Slot) and rd(0x04a0 + e) ~= 0 and (rd(0x04a0 + e) & 0x7f) ~= 0x78 then s.npc = e; break end
      end
      if not s.npc then return fail("no Vampire 1") end
      local x, y = rd(0x70 + s.npc), rd(0xb0 + s.npc)
      local xh, yh = rd(0x90 + s.npc), rd(0xd0 + s.npc)
      wr(0x04a0 + s.npc, 0)
      for e = 0x0d, 0x1e do
        if rd(0x04a0 + e) == 0 and e ~= rd(P2Slot) and e ~= rd(0x62c1) then s.spawner = e; break end
      end
      local e = s.spawner
      wr(0x70 + e, x); wr(0x90 + e, xh); wr(0xb0 + e, y); wr(0xd0 + e, yh)
      for _, f in ipairs({0x0300, 0x0320, 0x0340, 0x0360, 0x0380, 0x03a0, 0x03c0, 0x0560, 0x0580, 0x0600, 0x0620}) do wr(f + e, 0) end
      wr(0x04a0 + e, 0x6f)
      log(string.format("  Vampire 1 (slot %02x) removed; chest spawner in slot %02x; player 2 in slot %02x",
        s.npc, e, rd(P2Slot)))
      return nextStep("Vampire 1 beaten")
    end
  end,
  -- 3: the chest appears, player 2 still joined.
  function()
    if since() % 30 < 2 then pad1 = {a = true} end  -- dismiss messages
    -- The waiting object turns into the chest in place: chest sprite
    -- ($0300 = $aa), collision $8d, $0620 counted up.
    local e = s.spawner
    if rd(0x0620 + e) ~= 0 and rd(0x0300 + e) == 0xaa and rd(0x03a0 + e) == 0x8d then
      if rd(P2Active) ~= 1 then return fail("player 2 is no longer joined") end
      pcall(function() local f = io.open(DIR .. "v03_bosschest.png", "wb"); f:write(emu.takeScreenshot()); f:close() end)
      return nextStep(string.format("the reward chest appeared after %d frames with player 2 joined (slot %02x action %02x)",
        since(), s.spawner, rd(0x04a0 + s.spawner)))
    end
    if since() > 1200 then return fail(string.format("no reward chest after 20 s with player 2 joined (chest object action %02x)", rd(0x04a0 + s.spawner))) end
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
  if not done and since() > 4000 then finish(100 + step, "TIMEOUT") end
end, emu.eventType.startFrame)

log("v03 boss chest test started")
