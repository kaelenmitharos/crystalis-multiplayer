-- M2b co-op test: midpoint camera, leash, Select teleport, hiding player 2
-- during set pieces.  Build with --flags="Dn Ec Et Vemsw Cp"; run like
-- m1_input.lua (see its header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code:
--   0          all checks passed
--   99         Lua error (see the log)
--   100 + n    stuck at step n (timeout)
--   200 + n    check failed at step n
-- Details go to m2b_camera.log next to this script, plus m2b_*.png.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "m2b_camera.log", "w") end)
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

local P2Active, P2Slot, P2Ground = 0x6280, 0x628a, 0x6294
local MainLoopMode, CurLoc, PlayerStatus = 0x40, 0x6c, 0x0710

-- Snapshot right after the co-op hook returns ($cb6e), so we never read
-- positions while player 2 is swapped into slot 0 (see m2_walk.lua).
local SNAP = {}
local function snapshot()
  for _, b in ipairs({0x70, 0x90, 0xb0, 0xd0}) do
    for s = 0, 0x1f do SNAP[b + s] = rd(b + s) end
  end
  for a = 0x02, 0x05 do SNAP[a] = rd(a) end
  for a = P2Ground, P2Ground + 3 do SNAP[a] = rd(a) end
  SNAP.slot = rd(P2Slot)
end
local function signed(v) if v >= 0x80 then return v - 256 end return v end
local function scrX() return (SNAP[0x03] or 0) * 256 + (SNAP[0x02] or 0) end
local function scrY() return signed(SNAP[0x05] or 0) * 240 + (SNAP[0x04] or 0) end
local function p1() return SNAP[0x90] * 256 + SNAP[0x70], SNAP[0xd0] * 240 + SNAP[0xb0] end
local function p2()
  return SNAP[P2Ground + 1] * 256 + SNAP[P2Ground], SNAP[P2Ground + 3] * 240 + SNAP[P2Ground + 2]
end
local function where()
  if not SNAP[0x70] then return "(no snapshot yet)" end
  local x1, y1 = p1(); local x2, y2 = p2()
  return string.format("P1 (%d,%d) P2 (%d,%d) slot %02x screen (%d,%d) loc %02x",
    x1, y1, x2, y2, SNAP.slot or 0, scrX(), scrY(), rd(CurLoc))
end
-- On screen = inside the hero's invisible wall (X $0a..$fc, Y $18..$d0).
local function onScreen(x, y)
  local rx, ry = x - scrX(), y - scrY()
  return rx >= 0x0a and rx < 0xfc and ry >= 0x18 and ry < 0xd0
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

local s = {warps = 0}
-- Hold a direction until the position stops changing for 30 frames.
local function holdUntilStill(set, getPos, name)
  set()
  local x, y = getPos()
  if s.lx == x and s.ly == y then s.still = (s.still or 0) + 1 else s.still = 0 end
  s.lx, s.ly = x, y
  if since() > 900 then fail(name .. " never stopped") return false end
  return s.still >= 30
end

local steps = {
  -- 1: boot to normal play.
  function()
    if inGame() then return nextStep("in normal play") end
    if (rd(MainLoopMode) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
  end,
  -- 2: wild warp to location $03 (5 x 7 screens; the camera is free in X
  --    on arrival).  Other warp points leave the camera pinned at an edge.
  function()
    if since() == 1 then s.wf = 0 end
    s.wf = s.wf + 1
    if s.wf < 12 then pad1 = {a = true, b = true} end
    if s.wf >= 6 and s.wf < 9 then pad1 = {a = true, b = true, start = true} end
    if s.wf > 90 and inGame() then
      s.warps = s.warps + 1
      local w, h = rd(0x62fc), rd(0x62fd)
      log(string.format("  warp %d: location %02x size %d x %d", s.warps, rd(CurLoc), w + 1, h + 1))
      if rd(CurLoc) == 0x03 then return nextStep("on location 03, which scrolls both ways") end
      if s.warps >= 16 then return fail("never reached location 03") end
      s.wf = 0
    end
  end,
  -- 2b: the warp lands near the bottom of the map, so walk player 1 up
  --     towards the middle first.
  function()
    if since() <= 90 then pad1 = {up = true} end
    if since() == 130 then return nextStep("player 1 moved off the map edge") end
  end,
  -- 3: join; player 2 appears one tile beside player 1 (or on top).
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 30 then
      if rd(P2Active) ~= 1 or (SNAP.slot or 0) == 0 then return fail("player 2 did not spawn") end
      local x1, y1 = p1(); local x2, y2 = p2()
      local d = math.abs(x2 - x1) + math.abs(y2 - y1)
      if d ~= 16 and d ~= 0 then return fail("spawn not one tile beside player 1 (distance " .. d .. ")") end
      return nextStep(string.format("spawned %d px from player 1", d))
    end
  end,
  -- 4: player 2 walks right, player 1 stands; the camera tracks the
  --    midpoint (inside the camera's dead zone) rather than player 1.
  function()
    if since() == 1 then s.sx = scrX(); s.p1x = p1() end
    if since() <= 50 then pad2 = {right = true} end
    if since() == 140 then
      local x1, y1 = p1(); local x2, y2 = p2()
      if x1 ~= s.p1x then return fail("player 1 moved") end
      local mid = math.floor((x1 + x2) / 2)
      local rel = mid - scrX()
      log(string.format("  camera moved %d px; midpoint at screen x %d; P1 at %d", scrX() - s.sx, rel, x1 - scrX()))
      if scrX() == s.sx and x2 - x1 > 0x40 then return fail("camera did not follow the midpoint") end
      if rel < 0x66 or rel > 0xa2 then return fail("midpoint outside the camera dead zone ($68..$a0)") end
      shot("m2b_midpoint.png")
      return nextStep("camera follows the midpoint")
    end
  end,
  -- 5: leash, X: player 2 keeps walking right until stopped.
  function()
    if holdUntilStill(function() pad2 = {right = true} end, p2, "player 2") then
      local x1, y1 = p1(); local x2, y2 = p2()
      local dx = math.abs(x2 - x1)
      if dx > 178 then return fail("player 2 went past the leash, dx " .. dx) end
      if not onScreen(x1, y1) or not onScreen(x2, y2) then return fail("a hero is off screen") end
      return nextStep("player 2 stopped at dx " .. dx)
    end
  end,
  -- 6: leash, X: player 1 walks left away from player 2.
  function()
    if holdUntilStill(function() pad1 = {left = true} end, p1, "player 1") then
      local x1, y1 = p1(); local x2, y2 = p2()
      local dx = math.abs(x2 - x1)
      if dx > 178 then return fail("player 1 went past the leash, dx " .. dx) end
      if not onScreen(x1, y1) or not onScreen(x2, y2) then return fail("a hero is off screen") end
      shot("m2b_leash_x.png")
      return nextStep("player 1 stopped at dx " .. dx)
    end
  end,
  -- 7: Select on pad 2 brings player 2 next to player 1.
  function()
    if since() < 3 then pad2 = {select = true} end
    if since() == 15 then
      local x1, y1 = p1(); local x2, y2 = p2()
      if math.abs(x2 - x1) > 16 or math.abs(y2 - y1) > 16 then return fail("Select did not bring player 2 back") end
      return nextStep(string.format("Select: player 2 at (%+d,%+d) from player 1", x2 - x1, y2 - y1))
    end
  end,
  -- 8: leash, Y: player 2 walks down until stopped.
  function()
    if holdUntilStill(function() pad2 = {down = true} end, p2, "player 2") then
      local x1, y1 = p1(); local x2, y2 = p2()
      local dy = math.abs(y2 - y1)
      if dy > 130 then return fail("player 2 went past the leash, dy " .. dy) end
      if not onScreen(x1, y1) or not onScreen(x2, y2) then return fail("a hero is off screen") end
      return nextStep("player 2 stopped at dy " .. dy)
    end
  end,
  -- 9: leash, Y: player 1 walks up away from player 2.
  function()
    if holdUntilStill(function() pad1 = {up = true} end, p1, "player 1") then
      local x1, y1 = p1(); local x2, y2 = p2()
      local dy = math.abs(y2 - y1)
      if dy > 130 then return fail("player 1 went past the leash, dy " .. dy) end
      if not onScreen(x1, y1) or not onScreen(x2, y2) then return fail("a hero is off screen") end
      shot("m2b_leash_y.png")
      return nextStep("player 1 stopped at dy " .. dy)
    end
  end,
  -- 10: player 1 "rides the dolphin" (status poke): player 2 hides.
  function()
    if since() == 1 then s.status = rd(PlayerStatus) end
    if since() <= 20 then wr(PlayerStatus, s.status | 0x40) end
    if since() == 20 then
      if rd(P2Active) ~= 1 then return fail("P2Active lost") end
      if rd(P2Slot) ~= 0 then return fail("player 2 still shown on the dolphin") end
      wr(PlayerStatus, s.status)
    end
    if since() == 50 then
      if (SNAP.slot or 0) == 0 then return fail("player 2 did not come back") end
      local x1, y1 = p1(); local x2, y2 = p2()
      if math.abs(x2 - x1) > 16 or math.abs(y2 - y1) > 16 then return fail("player 2 not back beside player 1") end
      return nextStep("hidden on the dolphin, back beside player 1 after")
    end
  end,
  -- 11: same for Change.
  function()
    if since() == 1 then s.status = rd(PlayerStatus) end
    if since() <= 20 then wr(PlayerStatus, s.status | 0x80) end
    if since() == 20 then
      if rd(P2Slot) ~= 0 then return fail("player 2 still shown while changed") end
      wr(PlayerStatus, s.status)
    end
    if since() == 50 then
      if (SNAP.slot or 0) == 0 then return fail("player 2 did not come back") end
      return nextStep("hidden while changed, back after")
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

log("m2b test started")
