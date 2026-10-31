-- M3b co-op test: player 2's HP readout in the status bar ("2" and a
-- life bar of 8 tiles, 32 HP each, at PPU $2b6c; digits before v0.2).  Build with --flags="Dn Ec Et Vemsw Cp" (needs the updated HUD,
-- i.e. no Vh); run like m1_input.lua (see its header for the commands).
--
-- Result is the exit code:
--   0          all checks passed
--   99         Lua error (see the log)
--   100 + n    stuck at step n (timeout)
--   200 + n    check failed at step n
-- Details go to m3b_hud.log next to this script, plus m3b_hud.png.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "m3b_hud.log", "w") end)
local function log(s) emu.log(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end
local function shot(name)
  pcall(function()
    local f = io.open(DIR .. name, "wb"); f:write(emu.takeScreenshot()); f:close()
  end)
end

local CE = emu.memType.nesMemory ~= nil
local CPU = CE and emu.memType.nesMemory or emu.memType.cpu
local PPU = CE and emu.memType.nesPpuMemory or emu.memType.ppu
local EXEC = CE and emu.callbackType.exec or emu.memCallbackType.cpuExec
local function setPad(port, t)
  if CE then emu.setInput(t, port, port) else emu.setInput(port, t) end
end
local function rd(a) return emu.read(a, CPU) end
local function wr(a, v) emu.write(a, v, CPU) end
local function tiles(addr, n)
  local t = {}
  for i = 0, n - 1 do t[#t + 1] = emu.read(addr + i, PPU) end
  return t
end
local function hex(t)
  local s = {}
  for _, v in ipairs(t) do s[#s + 1] = string.format("%02x", v) end
  return table.concat(s, " ")
end
log("emulator: " .. (CE and "MesenCE" or "Mesen 0.9.x"))

local P2Active, P2HP, P2MaxHP = 0x6280, 0x6281, 0x6282
local READOUT = 0x2b6c

local frame, stepFrame, step = 0, 0, 1
local pad1, pad2 = {}, {}
local mode8Hits, done = 0, false
emu.addMemoryCallback(function() mode8Hits = mode8Hits + 1 end, EXEC, 0xcb62, 0xcb62)

local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log("  readout: " .. hex(tiles(READOUT, 9)) .. "   P1 bar: " .. hex(tiles(0x2b22, 8)))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  step = step + 1; stepFrame = frame
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
local hist, lastHits = {}, 0
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(0x40) == 1 and n >= 15
end
-- Expected tiles for "2" and the bar: max/32 tiles (rounded up); full
-- tiles ($88) for each 32 HP, then the remainder in quarters ($8b..$89,
-- at least $8b if any HP is left), then empty tiles ($8c), then blanks.
local function expect(hp, max)
  local tiles = math.floor(max / 32) + ((max % 32 > 0) and 1 or 0)
  local full = math.floor(hp / 32)
  local q = math.floor((hp % 32) / 8)
  if q == 0 and hp % 32 > 0 then q = 1 end
  local partial = ({0x8c, 0x8b, 0x8a, 0x89})[q + 1]
  local t = {0x02}
  for i = 0, 7 do
    if i < full then t[#t + 1] = 0x88
    elseif i >= tiles then t[#t + 1] = 0x20
    elseif i == full then t[#t + 1] = partial
    else t[#t + 1] = 0x8c end
  end
  return t
end
local function same(t, u)
  for i = 1, #u do if t[i] ~= u[i] then return false end end
  return true
end
local BLANK = {0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20}

local s = {}
local steps = {
  -- 1: boot to normal play; the readout area is blank.
  function()
    if inGame() then
      s.bar = tiles(0x2b22, 8)
      if not same(tiles(READOUT, 9), BLANK) then return fail("readout area not blank before joining") end
      return nextStep("in normal play, readout blank; P1 bar " .. hex(s.bar))
    end
    if (rd(0x40) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
  end,
  -- 2: join; the readout shows P2HP/P2MaxHP.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 20 then
      local want = expect(rd(P2HP), rd(P2MaxHP))
      if not same(tiles(READOUT, 9), want) then return fail("readout " .. hex(tiles(READOUT, 9)) .. ", want " .. hex(want)) end
      if not same(tiles(0x2b22, 8), s.bar) then return fail("player 1's bar changed") end
      shot("m3b_hud.png")
      return nextStep(string.format("readout shows %d/%d", rd(P2HP), rd(P2MaxHP)))
    end
  end,
  -- 3: P2HP changes; the readout follows within a few frames.
  function()
    if since() == 1 then wr(P2HP, 37) end
    if since() == 10 then
      local want = expect(37, rd(P2MaxHP))
      if not same(tiles(READOUT, 9), want) then return fail("readout " .. hex(tiles(READOUT, 9)) .. ", want " .. hex(want)) end
      return nextStep("readout updated to 37")
    end
  end,
  -- 4: leave; the readout is cleared.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 20 then
      if rd(P2Active) ~= 0 then return fail("still joined") end
      if not same(tiles(READOUT, 9), BLANK) then return fail("readout not cleared: " .. hex(tiles(READOUT, 9))) end
      if not same(tiles(0x2b22, 8), s.bar) then return fail("player 1's bar changed") end
      return nextStep("readout cleared on leave")
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

log("m3b hud test started")
