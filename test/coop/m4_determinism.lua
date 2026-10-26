-- M4 co-op test (MesenCE only: it needs save states from Lua).
--
-- 1. Regression: a scripted pad-1 run (no player 2) on the co-op-off ROM
--    and on the co-op ROM must give the same RAM, apart from co-op RAM
--    ($6280..$62db).  Run this script on the co-op-off build first
--    (--flags="Dn Vmsw"): it writes m4_regress_off.log.  Then run it on
--    the co-op build (--flags="Dn Vmsw Cp"): it writes m4_regress_coop.log
--    and compares the two.
-- 2. Determinism (co-op ROM only): from a save state, play the same
--    two-player script twice (both heroes moving and swinging near
--    enemies, player 2 knocked down and revived, a map change) and log a
--    RAM hash every 600 game frames; the two logs must match.
--
-- Inputs are scheduled by controller polls (game frames that read the pads,
-- dialogs included), not NES frames, so lag frames can't shift them.
--
-- Run (MesenCE 2.2.x; see m1_input.lua for the switches):
--   Mesen.exe --testRunner --doNotSaveSettings
--     --debug.scriptWindow.allowIoOsAccess=true
--     --nes.port2.type=NesController --timeout=600 m4_determinism.lua rom.nes
--
-- Result is the exit code: 0 pass, 99 Lua error, 201 regression mismatch,
-- 202 determinism mismatch, 203 no off-ROM log to compare with (run the
-- co-op-off build first).  Details go to m4_determinism.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = io.open(DIR .. "m4_determinism.log", "w")
local function log(s) LOG:write(s .. "\n"); LOG:flush() end
local M = emu.memType.nesMemory
local PRG = emu.memType.nesPrgRom
local function rd(a) return emu.read(a, M) end
local function wr(a, v) emu.write(a, v, M) end
local function setPad(port, t) emu.setInput(t, port, port) end

-- Co-op builds stamp "COOP" at PRG $2573c (under RANDOMIZER).
local COOP = emu.read(0x2573c, PRG) == 0x43 and emu.read(0x2573d, PRG) == 0x4f
log("ROM: " .. emu.getRomInfo().name .. (COOP and " (co-op)" or " (co-op off)"))

-- Start from blank battery RAM, like a new cartridge: each ROM has its own
-- save file from earlier runs, and stale saves would make the runs differ.
-- Write the save RAM directly: through the CPU, $6000..$7fff only works
-- once the game has enabled it in the mapper.
for a = 0, 0x1fff do emu.write(a, 0, emu.memType.nesSaveRam) end

-- RAM regions hashed separately, so a mismatch says where.  The stack page
-- ($0100..$01ff) is left out: it holds stale bytes below the stack pointer,
-- which differ with call depth.  Co-op RAM is left out of the regression.
local REGIONS = {
  {"zeropage", 0x0000, 0x00ff}, {"oam", 0x0200, 0x02ff}, {"objects", 0x0300, 0x06ff},
  {"globals", 0x0700, 0x07ff}, {"stage", 0x6000, 0x60ff}, {"attrib", 0x6100, 0x613f},
  {"6140", 0x6140, 0x627f},
  {"62dc", 0x62dc, 0x63ff}, {"save", 0x6400, 0x7fff},
}
local function hashRange(a, b)
  local h = 2166136261
  for x = a, b do
    h = h ~ rd(x)
    h = (h * 16777619) % 4294967296
  end
  return h
end
local function sample()
  local t = {}
  for _, r in ipairs(REGIONS) do t[#t + 1] = string.format("%s=%08x", r[1], hashRange(r[2], r[3])) end
  return table.concat(t, " ")
end
local function coopHash() return string.format("%08x", hashRange(0x6280, 0x62db)) end

local it = 0            -- controller polls (game frames)
local done = false
local phase = "regress"
local p1, p2 = {}, {}
local lines = {}        -- this phase's samples
local runA = nil
local state = nil
local phaseStart = 0

local function finish(code, msg)
  if done then return end
  done = true
  log(msg .. string.format(" (exit %d)", code))
  LOG:close()
  emu.stop(code)
end

-- Pad-1 script for the regression run, by iteration.
local function regressInput(i)
  if rd(0x40) ~= 1 then
    if i % 40 < 2 then return {start = true} end
    return {}
  end
  local k = i % 1200
  if k < 120 then return {down = true}
  elseif k < 240 then return {left = true, b = (k % 30 < 3)}
  elseif k < 360 then return {up = true}
  elseif k < 480 then return {right = true, b = (k % 30 < 3)}
  elseif k < 600 then return {b = true}               -- charge
  elseif k >= 900 and k < 912 then
    local t = {a = true, b = true}
    if k >= 906 and k < 909 then t.start = true end   -- wild warp
    return t
  end
  return {}
end

-- Two-player script for the determinism runs, by iteration since the save
-- state.  Both move and swing; at 1500 player 2 is knocked down (poke) and
-- revived by player 1 standing next to them; at 2400 a wild warp.
local DIRS = {{left = true}, {down = true}, {right = true}, {up = true}}
local function duoInput(i)
  local a = DIRS[(math.floor(i / 50) % 4) + 1]
  local b = DIRS[(math.floor(i / 35) % 4) + 1]
  local t1 = {left = a.left, right = a.right, up = a.up, down = a.down, b = (i % 40 < 3)}
  local t2 = {left = b.left, right = b.right, up = b.up, down = b.down, b = (i % 27 < 3)}
  if i >= 1500 and i < 1700 then t1 = {}; t2 = {} end   -- player 1 waits beside player 2
  if i >= 2400 and i < 2412 then
    t1 = {a = true, b = true}
    if i >= 2406 and i < 2409 then t1.start = true end
  end
  return t1, t2
end
local DUO_LEN = 3000

local function compareWithOff()
  local f = io.open(DIR .. "m4_regress_off.log", "r")
  if not f then return finish(203, "no m4_regress_off.log: run this on the co-op-off ROM first") end
  local off = {}
  for line in f:lines() do off[#off + 1] = line end
  f:close()
  -- Allowed to differ (explained):
  --  stage:  the $6000 staging buffer still holds the title screen text,
  --          which says COOP instead of BETA in co-op builds.
  --  attrib: MapTilesToAttributesFor*Scroll ($ee80/$eea4) build the
  --          attribute bytes for the rows behind the status bar from
  --          metatile IDs read out of that same staging buffer, so they
  --          inherit the title-text difference.  Not visible: the status
  --          bar covers those rows.
  local ALLOWED = {stage = true, attrib = true}
  local function regions(line)
    local t = {}
    for k, v in (line or ""):gmatch("(%w+)=(%x+)") do t[k] = v end
    return t
  end
  local bad, allowed = 0, 0
  for n, line in ipairs(lines) do
    local a, b = regions(off[n]), regions(line)
    for _, r in ipairs(REGIONS) do
      local name = r[1]
      if a[name] ~= b[name] then
        if ALLOWED[name] then
          allowed = allowed + 1
        else
          bad = bad + 1
          log(string.format("  sample %d: %s differs ($%04x..$%04x)", n, name, r[2], r[3]))
        end
      end
    end
  end
  if bad > 0 then return false end
  log(string.format("regression: %d samples match the co-op-off ROM (%d allowed differences in the staging/attribute buffers)",
                    #lines, allowed))
  return true
end

-- Everything runs at each controller poll (once per game frame that reads
-- the pads, including dialogs and other loops that don't return to the
-- main loop).  Save states can only be made or loaded in a CPU exec
-- callback, so those are requested here and done at MainLoop ($c916).
local wantSave, wantLoad = false, false

local function step()
  it = it + 1
  if phase == "regress" then
    p1, p2 = regressInput(it), {}
    if it % 600 == 0 then lines[#lines + 1] = string.format("%6d %s", it, sample()) end
    if it == 6000 then
      local name = COOP and "m4_regress_coop.log" or "m4_regress_off.log"
      local o = io.open(DIR .. name, "w")
      for _, l in ipairs(lines) do o:write(l .. "\n") end
      o:close()
      if not COOP then return finish(0, "co-op-off regression trace written: " .. #lines .. " samples") end
      if not compareWithOff() then return finish(201, "regression FAILED") end
      phase, phaseStart, p1, p2 = "join", it, {}, {}
    end
  elseif phase == "join" then
    local i = it - phaseStart
    p1, p2 = {}, (i < 3) and {start = true} or {}
    if i == 60 then wantSave, phase = true, "wait" end
  elseif phase == "duo" then
    local i = it - phaseStart
    p1, p2 = duoInput(i)
    if i == 1500 then wr(0x6281, 0); wr(0x62c4, 1); wr(0x6287, 0) end  -- player 2 down
    if i % 600 == 0 then
      lines[#lines + 1] = string.format("%5d %s coop=%s p2down=%d p2hp=%d loc=%02x", i, sample(), coopHash(),
                                       rd(0x62c4), rd(0x6281), rd(0x6c))
    end
    if i == DUO_LEN then
      if not runA then
        runA = lines
        for _, l in ipairs(runA) do log("  A " .. l) end
        wantLoad, phase = true, "wait"
      else
        local bad = 0
        for n, l in ipairs(lines) do
          if runA[n] ~= l then bad = bad + 1; log("  B " .. l .. "   <- differs") end
        end
        if bad > 0 or #lines ~= #runA then return finish(202, "determinism FAILED") end
        return finish(0, string.format("ALL PASS: determinism, %d samples identical in both runs", #lines))
      end
    end
  else -- "wait": nothing pressed until the save state is made or loaded
    p1, p2 = {}, {}
  end
end

emu.addEventCallback(function()
  if done then return end
  local ok, err = pcall(step)
  if not ok then return finish(99, "LUA ERROR " .. tostring(err)) end
  setPad(0, p1); setPad(1, p2)
end, emu.eventType.inputPolled)

emu.addMemoryCallback(function()
  if done then return end
  local ok, err = pcall(function()
    if wantSave then
      wantSave = false
      state = emu.createSavestate()
      phase, phaseStart, lines = "duo", it, {}
      log("save state taken; running the two-player script")
    elseif wantLoad then
      wantLoad = false
      emu.loadSavestate(state)
      phase, phaseStart, lines = "duo", it, {}
      log("save state loaded; second run")
    end
  end)
  if not ok then finish(99, "LUA ERROR " .. tostring(err)) end
end, emu.callbackType.exec, 0xc916, 0xc916)

log("m4 determinism test started")
