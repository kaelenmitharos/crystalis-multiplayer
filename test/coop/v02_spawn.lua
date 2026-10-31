-- Co-op v0.2 test: player 2 never starts inside a wall after a map change.
-- Teleports to every cave in the first half of the game (entrances 0 and
-- 1) with player 2 joined.  Once player 2 has spawned and settled, tries
-- to walk them a few pixels in each direction from their spawn point.
-- Inside a wall they can only move one way (out), so fewer than two free
-- directions counts as stuck, unless player 1 can't move there either (a
-- bad teleport spot) or player 2 is on top of player 1 (the fallback when
-- nothing nearby is free and on screen).  v0.1 fails this.
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 201 player 2 stuck
-- somewhere, 202 never reached normal play.  Details go to v02_spawn.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v02_spawn.log", "w") end)
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

local P2Active, P2Slot, P2Ground, P2Down = 0x6280, 0x628a, 0x6294, 0x62c4
local LOCS = {}
for l = 0x04, 0x0e do if l ~= 0x0a and l ~= 0x0b then LOCS[#LOCS + 1] = l end end  -- not the Vampire rooms
LOCS[#LOCS + 1] = 0x10
for l = 0x11, 0x11 do LOCS[#LOCS + 1] = l end
for l = 0x22, 0x27 do LOCS[#LOCS + 1] = l end
for l = 0x2a, 0x39 do if l ~= 0x36 and l ~= 0x37 then LOCS[#LOCS + 1] = l end end
for l = 0x44, 0x4f do if l ~= 0x47 then LOCS[#LOCS + 1] = l end end
for l = 0x54, 0x57 do LOCS[#LOCS + 1] = l end

local frame, done = 0, false
local hits, last, hist = 0, 0, {}
emu.addMemoryCallback(function() hits = hits + 1 end, EXEC, 0xcb62, 0xcb62)
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(0x40) == 1 and n >= 15
end
local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d: %s (exit %d)", frame, msg, code))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function pos() return rd(P2Ground + 1) * 256 + rd(P2Ground), rd(P2Ground + 3) * 240 + rd(P2Ground + 2) end

-- Writes to player 2's position happen at the safe point after the co-op
-- update ($cb6e), never in the middle of it.
local restore = nil
emu.addMemoryCallback(function()
  -- Keep player 1 alive (some caves have bosses or traps).
  if rd(0x40) == 1 then wr(0x03c1, rd(0x03c0)) end
  if restore then
    for i = 0, 3 do wr(P2Ground + i, restore[i + 1]) end
    restore = nil
  end
end, EXEC, 0xcb6e, 0xcb6e)

local pad1, pad2 = {}, {}
local phase, t0, li, ent = "boot", 0, 1, 0
local home, free, dirIdx, stuck, tested = nil, 0, 1, 0, 0
local shotTaken = false
local p1free, p1home = 0, nil
local DIRS = {{left = true}, {right = true}, {up = true}, {down = true}}
local function step()
  local f = frame - t0
  if phase == "boot" then
    if inGame() then
      wr(0x6430, 0x00); wr(0x0711, 0x01)
      phase, t0 = "join", frame
    end
    if (rd(0x40) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
    if frame > 4000 then return finish(202, "never reached normal play") end
  elseif phase == "join" then
    if f < 3 then pad2 = {start = true} end
    if f == 30 then
      if rd(P2Active) ~= 1 then return finish(201, "player 2 did not join") end
      phase, t0 = "warp", frame
    end
  elseif phase == "warp" then
    if f == 2 then wr(0x6c, LOCS[li]); wr(0x6d, ent); wr(0x41, 1) end
    if f > 30 and inGame() and rd(0x6c) == LOCS[li] and rd(P2Slot) ~= 0 and f > 120 then
      phase, t0, dirIdx, free, p1free = "p1probe", frame, 1, 0, 0
    end
    -- Clear dialogs (the Windmill guard talks, bosses announce themselves).
    if f > 60 and not inGame() and f % 30 < 2 then pad1 = {a = true} end
    if f > 600 then
      log(string.format("  %02x/%d: no normal play with player 2 (loc %02x, mode %02x/%02x, slot %02x)",
        LOCS[li], ent, rd(0x6c), rd(0x40), rd(0x41), rd(P2Slot)))
      if not shotTaken then
        shotTaken = true
        pcall(function() local fh = io.open(DIR .. "v02_spawn_stuck.png", "wb"); fh:write(emu.takeScreenshot()); fh:close() end)
      end
      phase, t0 = "next", frame
    end
  elseif phase == "p1probe" then
    -- Can player 1 move here?  Each direction: 8 frames there, 8 back.
    local k = f % 20
    if k == 1 then p1home = {rd(0x90) * 256 + rd(0x70), rd(0xd0) * 240 + rd(0xb0)} end
    if k >= 1 and k < 9 then pad1 = DIRS[dirIdx] end
    if k == 9 then
      local x, y = rd(0x90) * 256 + rd(0x70), rd(0xd0) * 240 + rd(0xb0)
      if math.abs(x - p1home[1]) + math.abs(y - p1home[2]) >= 4 then p1free = p1free + 1 end
    end
    if k >= 10 and k < 18 then pad1 = DIRS[({2, 1, 4, 3})[dirIdx]] end
    if k == 19 then
      dirIdx = dirIdx + 1
      if dirIdx > 4 then
        phase, t0, dirIdx = "probe", frame, 1
        home = {rd(P2Ground), rd(P2Ground + 1), rd(P2Ground + 2), rd(P2Ground + 3)}
      end
    end
  elseif phase == "probe" then
    -- Each direction: 10 frames held, then back to the spawn point.
    local k = f % 20
    if k < 10 then pad2 = DIRS[dirIdx] end
    if k == 12 then
      local x, y = pos()
      local hx, hy = home[2] * 256 + home[1], home[4] * 240 + home[3]
      if math.abs(x - hx) + math.abs(y - hy) >= 4 then free = free + 1 end
      restore = home
    end
    if k == 19 then
      dirIdx = dirIdx + 1
      if dirIdx > 4 then
        tested = tested + 1
        local hx, hy = home[2] * 256 + home[1], home[4] * 240 + home[3]
        local p1x, p1y = rd(0x90) * 256 + rd(0x70), rd(0xd0) * 240 + rd(0xb0)
        -- Only count it when player 1 can move freely here (some
        -- teleport entrances leave player 1 stuck too).
        -- On top of player 1 is the fallback when no spot nearby is free
        -- and on screen (e.g. a door at the bottom edge of the screen):
        -- player 2 is placed properly once player 1 walks in.
        local onP1 = hx == p1x and hy == p1y
        local bad = free < 2 and p1free >= 2 and not onP1
        if bad then stuck = stuck + 1 end
        log(string.format("  %s %02x/%d: player 2 at (%d,%d), player 1 at (%d,%d), %d free directions (player 1: %d)",
          bad and "STUCK" or (p1free < 2 and "skip " or (onP1 and free < 2 and "on p1" or "ok   ")),
          LOCS[li], ent, hx, hy, p1x, p1y, free, p1free))
        phase, t0 = "next", frame
      end
    end
  elseif phase == "next" then
    ent = ent + 1
    if ent > 1 then ent = 0; li = li + 1 end
    if li > #LOCS then
      if stuck > 0 then return finish(201, string.format("FAIL player 2 stuck at %d of %d entrances", stuck, tested)) end
      return finish(0, string.format("ALL PASS: player 2 not stuck in a wall at any of %d entrances", tested))
    end
    phase, t0 = "warp", frame
  end
end

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
  local ok, err = pcall(step)
  if not ok then finish(99, "LUA ERROR " .. tostring(err)) end
end, emu.eventType.startFrame)

log("v02 spawn test started")
