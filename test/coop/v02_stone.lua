-- Co-op v0.2 test: the stone-grey fix (an original-game bug).
-- Stone tints the hero grey ($07e4 = $4d) and freezes them ($05a0).
-- Vanilla clears the tint only when stone wears off while the status is
-- still stone, so a poison hit while stoned left the hero grey for good.
-- Cases, each with player 2 not joined and then joined:
--   normal: a stone shot; the tint is cleared when stone wears off, like
--           vanilla (status back to 0, tint gone).
--   poison: a stone shot, then a poison hit while stoned (status 3): the
--           tint is cleared and the poison stays.
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 201 a check failed,
-- 202 never got going.  Details go to v02_stone.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v02_stone.log", "w") end)
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
-- The hero's sprite palette (PPU $3f11..$3f13), MesenCE only.
local function heroPal()
  if not CE then return "" end
  return string.format(" palette %02x%02x%02x", emu.read(0x11, emu.memType.nesPaletteRam),
    emu.read(0x12, emu.memType.nesPaletteRam), emu.read(0x13, emu.memType.nesPaletteRam))
end

local Status, Tint, Delay = 0x0710, 0x07e4, 0x05a0
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

-- The stone shot is an enemy turned into a projectile ($0540 = $ff,
-- status 2 in $0560), held on player 1 at the safe point.
local shotSlot = nil
emu.addMemoryCallback(function()
  wr(0x03c1, rd(0x03c0))  -- keep player 1 alive
  if shotSlot and rd(0x04a0 + shotSlot) ~= 0 then
    wr(0x70 + shotSlot, rd(0x70)); wr(0x90 + shotSlot, rd(0x90))
    wr(0xb0 + shotSlot, rd(0xb0)); wr(0xd0 + shotSlot, rd(0xd0))
    wr(0x071a, 0)
  end
end, EXEC, 0xcb6e, 0xcb6e)
local function stoneShot()
  for e = 0x0d, 0x1e do
    if rd(0x04a0 + e) ~= 0 and rd(0x03c0 + e) > 0 and e ~= rd(0x628a) and rd(0x0540 + e) ~= 0xff then
      wr(0x0540 + e, 0xff); wr(0x0560 + e, 2)
      return e
    end
  end
end

local pad1, pad2 = {}, {}
local CASES = {{"normal", false}, {"poison", false}, {"normal", true}, {"poison", true}}
local ci, phase, t0 = 1, "boot", 0
local fails = 0
local c = {}
local function check(ok, msg)
  log((ok and "  ok   " or "  FAIL ") .. msg)
  if not ok then fails = fails + 1 end
end

local function step()
  local f = frame - t0
  if phase == "boot" then
    if inGame() then wr(0x6430, 0x00); wr(0x0711, 0x01); phase, t0 = "warp", frame end
    if (rd(0x40) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
    if frame > 4000 then return finish(202, "never reached normal play") end
  elseif phase == "warp" then
    -- Sealed Cave 2 has slimes to turn into stone shots.  A fresh warp per
    -- case brings the enemies back.
    if f == 2 then wr(0x6c, 0x05); wr(0x6d, 0); wr(0x41, 1) end
    if f > 150 and inGame() then
      local join = CASES[ci][2]
      if join and rd(0x6280) == 0 and f < 154 then pad2 = {start = true} end
      if f == 190 then
        if join and rd(0x6280) ~= 1 then return finish(201, "player 2 did not join") end
        c = {name = CASES[ci][1], join = join}
        log(string.format("case %s, player 2 %s: status %02x tint %02x%s", c.name, join and "joined" or "not joined",
          rd(Status), rd(Tint), heroPal()))
        c.pal0 = heroPal()
        shotSlot = stoneShot()
        if not shotSlot then return finish(202, "no enemy for the stone shot") end
        phase, t0 = "stone", frame
      end
    end
    if f > 2000 then return finish(202, "warp failed") end
  elseif phase == "stone" then
    if f % 30 < 2 then pad1 = {a = true} end  -- dismiss the status message
    if (rd(Status) & 0x0f) == 2 and not c.stoneAt then
      c.stoneAt = f
      wr(0x04a0 + shotSlot, 0)  -- remove the shot, so it can't stone again
      shotSlot = nil
      log(string.format("  stoned after %d frames: tint %02x delay %02x%s", f, rd(Tint), rd(Delay), heroPal()))
      check(rd(Tint) == 0x4d, "stone tints the hero grey")
    end
    if c.stoneAt then
      local g = f - c.stoneAt
      -- Once the "stoned" message is gone (normal play again), a poison
      -- hit while still stoned.
      if c.name == "poison" and not c.poisonAt and rd(0x41) == 8 and g > 30 then
        c.poisonAt = g
        wr(Status, (rd(Status) & 0xf0) | 3)
        log(string.format("  poisoned while stoned: status %02x tint %02x delay %02x", rd(Status), rd(Tint), rd(Delay)))
      end
      if c.name == "poison" and c.poisonAt and g == c.poisonAt + 10 then
        check(rd(Tint) == 0, string.format("poison while stoned: tint cleared (tint %02x%s)", rd(Tint), heroPal()))
        check((rd(Status) & 0x0f) == 3, string.format("poison while stoned: still poisoned (status %02x)", rd(Status)))
        if CE then check(heroPal() == c.pal0, "poison while stoned: hero palette back to normal" .. heroPal()) end
        phase, t0 = "next", frame
      end
      if c.name == "normal" and (rd(Status) & 0x0f) == 0 and not c.freeAt then
        c.freeAt = g
        log(string.format("  stone wore off after %d frames", g))
      end
      if c.name == "normal" and c.freeAt and g == c.freeAt + 5 then
        check(rd(Tint) == 0, string.format("normal stone: tint cleared when it wore off (tint %02x%s)", rd(Tint), heroPal()))
        if CE then check(heroPal() == c.pal0, "normal stone: hero palette back to normal" .. heroPal()) end
        phase, t0 = "next", frame
      end
      if g > 1500 then check(false, "stone never wore off"); phase, t0 = "next", frame end
    end
    if f > 600 and not c.stoneAt then check(false, "never stoned"); phase, t0 = "next", frame end
  elseif phase == "next" then
    -- Cure the poison and wait until player 1 can move before the next case.
    if f == 1 then wr(Status, rd(Status) & 0xf0) end
    if f % 30 < 2 then pad1 = {a = true} end
    if f >= 30 and rd(Delay) == 0 and rd(0x41) == 8 and not c.readyAt then c.readyAt = f end
    if f > 3000 then return finish(202, "player 1 still frozen") end
    if c.readyAt and f == c.readyAt + 10 then
      ci = ci + 1
      if ci > #CASES then
        if fails > 0 then return finish(201, string.format("FAIL %d checks failed", fails)) end
        return finish(0, "ALL PASS")
      end
      phase, t0 = "warp", frame
    end
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

log("v02 stone test started")
