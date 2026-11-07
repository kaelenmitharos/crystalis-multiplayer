-- M3b co-op test: player 2's HP readout in the status bar at PPU $2b6c:
-- "2", then a life bar in player 1's style ("Lf", up to 7 tiles, the end
-- cap $8d), filled in proportion to HP (v0.3; digits before v0.2).
-- Checks full, half, low, 1 and 0 HP, a bigger max HP, the redraw after a
-- full status bar redraw (the inventory menu), and the clear on leaving.
-- Screenshots m3b_hud_*.png.  Build with --flags="Dn Ec Et Vemsw Cp" (needs the updated HUD,
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
local N = 10  -- tiles in the readout

local frame, stepFrame, step = 0, 0, 1
local pad1, pad2 = {}, {}
local mode8Hits, done = 0, false
emu.addMemoryCallback(function() mode8Hits = mode8Hits + 1 end, EXEC, 0xcb62, 0xcb62)

local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log("  readout: " .. hex(tiles(READOUT, N)) .. "   P1 bar: " .. hex(tiles(0x2b22, 8)))
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
-- Expected tiles: "2", "Lf", then W = min(7, ceil(max / 32)) bar tiles
-- filled with q = floor(HP * 4W / max) quarters (at least 1 while HP is
-- left): $88 full, then $8c/$8b/$8a/$89 for 0..3 quarters, then the end
-- cap $8d right after the bar, then blanks.
local function expect(hp, max)
  local w = math.min(7, math.ceil(max / 32))
  local q = max > 0 and math.floor(hp * 4 * w / max) or 0
  if q == 0 and hp > 0 then q = 1 end
  local t = {0x02, 0x80}
  for i = 0, 7 do
    if i < w then
      if q >= 4 then t[#t + 1] = 0x88; q = q - 4
      else t[#t + 1] = ({0x8c, 0x8b, 0x8a, 0x89})[q + 1]; q = 0 end
    elseif i == w then t[#t + 1] = 0x8d
    else t[#t + 1] = 0x20 end
  end
  return t
end
local function same(t, u)
  for i = 1, #u do if t[i] ~= u[i] then return false end end
  return true
end
local BLANK = {0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20}

local s = {}
local steps = {
  -- 1: boot to normal play; the readout area is blank.
  function()
    if inGame() then
      s.bar = tiles(0x2b22, 8)
      if not same(tiles(READOUT, N), BLANK) then return fail("readout area not blank before joining") end
      return nextStep("in normal play, readout blank; P1 bar " .. hex(s.bar))
    end
    if (rd(0x40) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
  end,
  -- 2: join; the readout shows P2HP/P2MaxHP.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 20 then
      local want = expect(rd(P2HP), rd(P2MaxHP))
      if not same(tiles(READOUT, N), want) then return fail("readout " .. hex(tiles(READOUT, N)) .. ", want " .. hex(want)) end
      if not same(tiles(0x2b22, 8), s.bar) then return fail("player 1's bar changed") end
      shot("m3b_hud.png")
      return nextStep(string.format("readout shows %d/%d", rd(P2HP), rd(P2MaxHP)))
    end
  end,
  -- 3: HP and max HP change; the readout follows within a few frames.
  function()
    local CASES = {{37, 48, "37"}, {24, 48, "half"}, {5, 48, "low"}, {1, 48, "1"}, {0, 48, "0"},
                   {200, 200, "full200"}, {100, 200, "half200"}, {255, 255, "full255"}, {130, 255, "130of255"}}
    local i = math.floor((since() - 1) / 12) + 1
    local k = (since() - 1) % 12
    if i > #CASES then return nextStep("readout right for all HP values") end
    local hp, max, tag = CASES[i][1], CASES[i][2], CASES[i][3]
    if k == 0 then wr(0x03c0, max); wr(P2MaxHP, max); wr(P2HP, hp) end  -- max HP follows player 1's
    if k == 10 then
      local want = expect(hp, max)
      if not same(tiles(READOUT, N), want) then return fail(string.format("%d/%d: readout %s, want %s", hp, max, hex(tiles(READOUT, N)), hex(want))) end
      log(string.format("  %d/%d: %s", hp, max, hex(want)))
      shot("m3b_hud_" .. tag .. ".png")
    end
  end,
  -- 3b: a full status bar redraw (open and close the inventory) wipes the
  --     row; the readout comes back right away.
  function()
    if since() == 1 then wr(0x03c0, 48); wr(P2MaxHP, 48); wr(P2HP, 30) end
    if since() >= 20 and since() < 23 then pad1 = {select = true} end
    if since() >= 80 and since() < 83 then pad1 = {select = true} end
    if since() > 83 and rd(0x41) == 8 and not s.backAt then s.backAt = since() end
    if s.backAt and since() == s.backAt + 10 then
      local want = expect(30, 48)
      if not same(tiles(READOUT, N), want) then return fail("after the menu: readout " .. hex(tiles(READOUT, N)) .. ", want " .. hex(want)) end
      shot("m3b_hud_after_menu.png")
      return nextStep("readout redrawn 10 frames after the menu closed")
    end
    if since() > 600 then return fail("menu never closed") end
  end,
  -- 4: leave; the readout is cleared.
  function()
    if since() < 3 then pad2 = {start = true} end
    if since() == 20 then
      if rd(P2Active) ~= 0 then return fail("still joined") end
      if not same(tiles(READOUT, N), BLANK) then return fail("readout not cleared: " .. hex(tiles(READOUT, N))) end
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
