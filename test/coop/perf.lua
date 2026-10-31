-- CPU headroom check for co-op (MesenCE only; uses its setInput and
-- callbackType API).  Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua.
-- Wild warps 4 times (to location $14), then measures 600 frames each:
-- player 1 standing alone, player 1 walking a square alone (the camera
-- scrolls, which costs CPU in vanilla too), and player 2 walking the same
-- square while player 1 stands (with the midpoint camera, that scrolls by
-- about half as much).  Results go to perf.log next to this script.
local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local L = io.open(DIR .. "perf.log", "w")
local function log(s) L:write(s .. "\n"); L:flush() end
local M = emu.memType.nesMemory
local function rd(a) return emu.read(a, M) end
local function pad(port, t) emu.setInput(t, port, port) end
local EX = emu.callbackType.exec

local cycKey = nil
for k, v in pairs(emu.getState()) do
  if type(v) == "number" and k:lower():find("cpu") and k:lower():find("cycle") then cycKey = k; break end
end
log("cycle key: " .. tostring(cycKey))
local function cyc() return emu.getState()[cycKey] end

local hits, hist, last = 0, {}, 0
local t0, costs = nil, {}
emu.addMemoryCallback(function() hits = hits + 1 end, EX, 0xcb62, 0xcb62)
emu.addMemoryCallback(function() t0 = cyc() end, EX, 0xcb6b, 0xcb6b)
emu.addMemoryCallback(function() if t0 then costs[#costs+1] = cyc() - t0; t0 = nil end end, EX, 0xcb6e, 0xcb6e)
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(0x40) == 1 and n >= 15
end
local function busy() local n = 0; for s = 0x0d, 0x1e do if rd(0x04a0 + s) ~= 0 then n = n + 1 end end; return n end

local frame, phase, pf0, warps = 0, "boot", 0, 0
local in1, in2 = {}, {}
local m = {}
local function startMeasure(name) m = {name = name, frames = 0, lag = 0, other = 0, busy = 0}; costs = {} end
-- A lag frame is one in normal play (GameMode 8, or 7 on a trigger tile)
-- where the game mode 8 handler did not run.  Frames in other modes
-- (dialogs, menus, map changes) are counted separately.
local function tally(ran)
  local gm = rd(0x41)
  if gm == 8 or gm == 7 then m.lag = m.lag + (1 - ran) else m.other = m.other + 1 end
end
local function report()
  table.sort(costs)
  local sum = 0; for _, c in ipairs(costs) do sum = sum + c end
  log(string.format("%-12s frames=%d other-mode=%d lag=%d (%.1f%%) objects avg=%.1f  step cycles: mean=%d median=%d p95=%d max=%d (n=%d)",
    m.name, m.frames, m.other, m.lag, 100 * m.lag / math.max(1, m.frames - m.other), m.busy / m.frames,
    #costs > 0 and math.floor(sum / #costs) or 0, costs[math.floor(#costs / 2) + 1] or 0,
    costs[math.floor(#costs * 0.95)] or 0, costs[#costs] or 0, #costs))
end

emu.addEventCallback(function() pad(0, in1); pad(1, in2) end, emu.eventType.inputPolled)
emu.addEventCallback(function()
  local ok, err = pcall(function()
    frame = frame + 1
    local ran = hits > last and 1 or 0
    table.insert(hist, ran); last = hits
    if #hist > 30 then table.remove(hist, 1) end
    in1, in2 = {}, {}
    local pf = frame - pf0
    if phase == "boot" then
      if (rd(0x40) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then in1 = {start = true} end
      if inGame() then phase, pf0 = "warp", frame end
    elseif phase == "warp" then
      if pf < 12 then in1 = {a = true, b = true} end
      if pf >= 6 and pf < 9 then in1 = {a = true, b = true, start = true} end
      if pf > 60 and inGame() then
        warps = warps + 1
        log(string.format("warp %d -> location %02x, %d objects", warps, rd(0x6c), busy()))
        if warps >= 4 then phase, pf0 = "settle", frame else pf0 = frame end
      end
    elseif phase == "settle" then
      if pf == 60 then phase, pf0 = "solo", frame; startMeasure("P1 only") end
    elseif phase == "solo" then
      m.frames = m.frames + 1; tally(ran); m.busy = m.busy + busy()
      if pf == 600 then report(); phase, pf0 = "join", frame end
    elseif phase == "solowalk" then
      -- Same pattern as player 2 below, so the camera scrolls about as much.
      local dirs = {{left=true},{down=true},{right=true},{up=true}}
      in1 = dirs[(math.floor(pf / 25) % 4) + 1]
      m.frames = m.frames + 1; tally(ran); m.busy = m.busy + busy()
      if pf == 600 then report(); L:close(); emu.stop(0) end
    elseif phase == "join" then
      if pf < 3 then in2 = {start = true} end
      if pf == 30 then phase, pf0 = "duo", frame; startMeasure("P1 + P2") end
    elseif phase == "duo" then
      local dirs = {{left=true},{down=true},{right=true},{up=true}}
      in2 = dirs[(math.floor(pf / 25) % 4) + 1]
      m.frames = m.frames + 1; tally(ran); m.busy = m.busy + busy()
      if pf == 600 then report(); phase, pf0 = "leave", frame end
    elseif phase == "leave" then
      if pf < 3 then in2 = {start = true} end
      if pf == 30 then phase, pf0 = "solowalk", frame; startMeasure("P1 walking") end
    end
    if frame > 20000 then log("frame limit in " .. phase); L:close(); emu.stop(98) end
  end)
  if not ok then log("LUA ERROR " .. tostring(err)); L:close(); emu.stop(99) end
end, emu.eventType.startFrame)
