-- M2a co-op test: player 2 spawns, walks with pad 2, stops at walls,
-- despawns on leave and respawns next to player 1 after a map change.
-- Build the ROM with --flags="Dn Vmsw Cp".  Run it like m1_input.lua (see
-- that file's header for the MesenCE / Mesen 0.9.9 command lines).
--
-- Result is the exit code:
--   0          all checks passed
--   99         Lua error (see the log)
--   100 + n    stuck at step n (timeout)
--   200 + n    check failed at step n
-- Details go to m2_walk.log next to this script (positions are logged so a
-- failure can be read without rerunning), plus m2_*.png screenshots.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "m2_walk.log", "w") end)
local function log(s) emu.log(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end
local function shot(name)
  pcall(function()
    local f = io.open(DIR .. name, "wb"); f:write(emu.takeScreenshot()); f:close()
  end)
end

-- API differences between MesenCE and Mesen 0.9.9 (see m1_input.lua).
local CE = emu.memType.nesMemory ~= nil
local CPU = CE and emu.memType.nesMemory or emu.memType.cpu
local EXEC = CE and emu.callbackType.exec or emu.memCallbackType.cpuExec
local function setPad(port, t)
  if CE then emu.setInput(t, port, port) else emu.setInput(port, t) end
end
local function rd(a) return emu.read(a, CPU) end
log("emulator: " .. (CE and "MesenCE" or "Mesen 0.9.x"))

local P2Active, P2Slot = 0x6280, 0x628a
local MainLoopMode, CurLoc = 0x40, 0x6c

-- Positions as 16-bit values: X = hi*256 + lo; Y = hi*240 + lo (screens are
-- 240 px tall).
--
-- Crystalis often runs longer than a frame, so a frame boundary can fall
-- while player 2 is swapped into slots 0/1.  Positions are therefore read
-- from a snapshot taken right after the co-op hook returns ($cb6e, the
-- instruction after "jsr CoopUpdateObjects" in game mode 8).
local SNAP = {}
local function snapshot()
  for _, b in ipairs({0x70, 0x90, 0xb0, 0xd0}) do
    for s = 0, 0x1f do SNAP[b + s] = rd(b + s) end
  end
end
local function xOf(s) local v = SNAP[0x90 + s]; if not v then return -1 end return v * 256 + SNAP[0x70 + s] end
local function yOf(s) local v = SNAP[0xd0 + s]; if not v then return -1 end return v * 240 + SNAP[0xb0 + s] end
local function p2() local s = rd(P2Slot); return s, xOf(s), yOf(s) end
local function where()
  local s, x, y = p2()
  return string.format("P1 (%d,%d) P2 slot %02x (%d,%d) act=%02x loc=%02x",
    xOf(1), yOf(1), s, x, y, s > 0 and rd(0x04a0 + s) or 0, rd(CurLoc))
end

local frame, stepFrame, step = 0, 0, 1
local pad1, pad2 = {}, {}
local mode8Hits, done = 0, false
emu.addMemoryCallback(function() mode8Hits = mode8Hits + 1 end, EXEC, 0xcb62, 0xcb62)
emu.addMemoryCallback(function() snapshot() end, EXEC, 0xcb6e, 0xcb6e)

local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log("  " .. where())
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  log("  " .. where())
  step = step + 1; stepFrame = frame
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
local hist, lastHits = {}, 0
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(MainLoopMode) == 1 and n >= 15
end

local s = {}
local function near(dist)
  local slot, x, y = p2()
  return slot ~= 0 and math.abs(x - xOf(1)) <= dist and math.abs(y - yOf(1)) <= dist
end

local steps = {
  -- 1: boot to normal play.
  function()
    if inGame() then return nextStep("in normal play") end
    if (rd(MainLoopMode) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
  end,
  -- 2: join; player 2 appears in a slot next to player 1.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 20 then
      local slot = rd(P2Slot)
      if rd(P2Active) ~= 1 then return fail("P2Active not set") end
      if slot < 0x0d or slot > 0x1d then return fail(string.format("bad P2 slot %02x", slot)) end
      if rd(0x04a0 + slot) ~= 0x09 then return fail("P2 slot action not 09") end
      if (rd(0x03a0 + slot) & 0xf0) ~= 0 then return fail("P2 slot has a collision plane") end
      if not near(16) then return fail("P2 not next to P1") end
      shot("m2_join.png")
      return nextStep("player 2 spawned")
    end
  end,
  -- 3: hold pad 2 Down for 30 frames: P2 Y goes up, P1 stays still.  (Right is
  -- blocked by the capsule platform in the shrine.)
  function()
    if since() == 1 then s.p1x, s.p1y = xOf(0), yOf(0); local _, _, y = p2(); s.y0 = y end
    if since() <= 30 then pad2 = {down = true} end
    if since() == 50 then
      local _, _, y = p2()
      if y - s.y0 < 16 then return fail(string.format("P2 Y moved only %d", y - s.y0)) end
      if xOf(0) ~= s.p1x or yOf(0) ~= s.p1y then return fail("P1 moved") end
      shot("m2_walk.png")
      return nextStep(string.format("P2 walked down %d px, P1 still", y - s.y0))
    end
  end,
  -- 4: hold pad 2 Up until P2 stops: a wall (not the screen clamp) stops them.
  function()
    pad2 = {up = true}
    local _, _, y = p2()
    if since() == 1 then s.lastY, s.still = y, 0 end
    if y == s.lastY then s.still = s.still + 1 else s.still = 0 end
    s.lastY = y
    if s.still >= 30 then
      -- Y relative to the top of the screen (screens are 240 px tall).
      local hi = rd(0x05); if hi >= 0x80 then hi = hi - 256 end -- ScreenYHi is signed
      local rel = y - (hi * 240 + rd(0x04))
      if rel <= 0x22 then return fail(string.format("stopped at the screen clamp (rel y %d), not a wall", rel)) end
      shot("m2_wall.png")
      return nextStep(string.format("P2 stopped by a wall at y=%d (rel %d)", y, rel))
    end
    if since() > 600 then return fail("P2 never stopped walking up") end
  end,
  -- 5: leave; player 2's object goes away.
  function()
    if since() == 1 then s.slot = rd(P2Slot) end
    if since() < 3 then pad2 = {start = true} end
    if since() == 20 then
      if rd(P2Active) ~= 0 then return fail("P2Active still set") end
      if rd(P2Slot) ~= 0 then return fail("P2Slot not cleared") end
      if rd(0x04a0 + s.slot) == 0x09 then return fail("P2 object still present") end
      return nextStep("player 2 despawned")
    end
  end,
  -- 6: rejoin, then player 1 walks down out of the shrine.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 1 then s.loc = rd(CurLoc) end
    if since() > 20 then pad1 = {down = true} end
    if rd(CurLoc) ~= s.loc then return nextStep(string.format("map changed %02x -> %02x", s.loc, rd(CurLoc))) end
    if since() > 1500 then return fail("player 1 never left the map") end
  end,
  -- 7: back in normal play on the new map: player 2 respawned next to P1.
  function()
    if inGame() and since() > 30 then
      if rd(P2Active) ~= 1 then return fail("P2Active lost over the map change") end
      local slot = rd(P2Slot)
      if slot == 0 or rd(0x04a0 + slot) ~= 0x09 then return fail("P2 not respawned") end
      if not near(24) then return fail("P2 not next to P1 after the map change") end
      shot("m2_respawn.png")
      return nextStep("player 2 respawned next to player 1")
    end
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

log("m2 test started")
