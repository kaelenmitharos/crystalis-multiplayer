-- M1 co-op input test (player 2 join/leave, pad 1 shortcuts, reset init).
-- Run with Mesen 0.9.9:  Mesen.exe /testrunner <Cp rom>.nes m1_input.lua
-- Build the ROM with: --flags="Dn Vmsw Cp" (needs the default controller
-- shortcuts; a Qc build has no Select+B / Start+A+B shortcuts).
-- Result is the exit code:
--   0          all checks passed
--   100 + n    stuck at step n (timeout)
--   200 + n    check failed at step n
-- Details also go to a log file next to this script if Lua io is available.

local LOG = nil
pcall(function()
  local dir = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
  LOG = io.open(dir .. "m1_input.log", "w")
end)
local function log(s) emu.log(s); if LOG then LOG:write(s .. "\n"); LOG:flush() end end

local CPU = emu.memType.cpu
local function rd(a) return emu.read(a, CPU) end
local function wr(a, v) emu.write(a, v, CPU) end

local P2Active, P2Held, P2Pressed = 0x6280, 0x6288, 0x6289
local MainLoopMode, GameMode, CurLoc = 0x40, 0x41, 0x6c

local frame, stepFrame, step = 0, 0, 1
local pad1, pad2 = {}, {}
local mode8Hits = 0          -- executions of the game mode 8 entry ($cb62)
local done = false

emu.addMemoryCallback(function() mode8Hits = mode8Hits + 1 end,
                      emu.memCallbackType.cpuExec, 0xcb62)

local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  step = step + 1; stepFrame = frame
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
-- Gameplay = main loop mode 1 and the game mode 8 handler ($cb62) ran on
-- 15+ of the last 30 frames (it skips lag frames).  (GameMode itself reads 7 on the spawn trigger
-- tile and 8 during the opening flash, so it is not a good signal.)
local hist, lastHits = {}, 0
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(MainLoopMode) == 1 and n >= 15
end

local gameFrames = 0
local hitsAtStart = 0
local saved = {}

local steps = {
  -- 1: boot to gameplay: pulse pad 1 Start on the title screens only (main
  -- loop mode not 1), then wait for normal play.
  function()
    if inGame() then
      if rd(P2Active) ~= 0 then return fail("P2Active not 0 at game start") end
      return nextStep("in normal play, P2Active = 0")
    end
    if frame % 200 == 0 then
      local n = 0; for _, v in ipairs(hist) do n = n + v end
      log(string.format("  f%d ml=%02x gm=%02x handler %d/30", frame, rd(MainLoopMode), rd(GameMode), n))
    end
    -- Start on the title screens and on the opening flash (GameMode $13).
    if (rd(MainLoopMode) ~= 1 or rd(GameMode) == 0x13) and frame % 40 < 2 then
      pad1 = {start = true}
    end
  end,
  -- 2: settle for 60 frames with no input.
  function()
    if since() >= 60 then
      if not inGame() then return fail("left normal play while idle") end
      return nextStep("settled")
    end
  end,
  -- 3: pad 2 Start (3 frames) -> P2Active 1, no menu, game loop keeps running.
  function()
    if since() == 1 then hitsAtStart = mode8Hits; saved.held = false end
    if since() < 3 then pad2 = {start = true} end
    if since() >= 1 and since() <= 4 and rd(P2Held) == 0x10 then saved.held = true end
    if since() >= 40 then
      if not saved.held then return fail("P2Held never showed Start (10)") end
      if rd(P2Held) ~= 0 then return fail(string.format("P2Held = %02x after release", rd(P2Held))) end
      if rd(P2Active) ~= 1 then return fail(string.format("P2Active = %d after join", rd(P2Active))) end
      if not inGame() then return fail("left normal play after pad 2 Start") end
      if mode8Hits - hitsAtStart < 20 then return fail("game loop stalled (menu or pause?) hits=" .. (mode8Hits - hitsAtStart)) end
      if rd(0x43) ~= 0 then return fail("pad 1 state changed by pad 2") end
      return nextStep("pad 2 Start joined, no menu")
    end
  end,
  -- 4: pad 2 B (vanilla pause button) must not pause.
  function()
    if since() == 1 then hitsAtStart = mode8Hits end
    if since() < 3 then pad2 = {b = true} end
    if since() >= 40 then
      if mode8Hits - hitsAtStart < 20 then return fail("pad 2 B paused the game") end
      if rd(P2Active) ~= 1 then return fail("pad 2 B changed P2Active") end
      return nextStep("pad 2 B did not pause")
    end
  end,
  -- 5: second pad 2 Start -> P2Active 0.
  function()
    if since() == 1 then hitsAtStart = mode8Hits end
    if since() < 3 then pad2 = {start = true} end
    if since() >= 40 then
      if rd(P2Active) ~= 0 then return fail("P2Active not 0 after leave") end
      if mode8Hits - hitsAtStart < 20 then return fail("game loop stalled on leave") end
      return nextStep("pad 2 Start left")
    end
  end,
  -- 6: pad 1 Select+B switches sword.  Give wind + fire, equip wind.
  function()
    if since() == 1 then
      wr(0x6430, 0x00); wr(0x6431, 0x01); wr(0x6432, 0xff); wr(0x6433, 0xff)
      wr(0x0711, 0x01); wr(0x6428, 0x00)
    end
    if since() >= 2 and since() < 14 then pad1 = {select = true} end
    if since() >= 8 and since() < 11 then pad1 = {select = true, b = true} end
    if since() >= 60 then
      if rd(0x0711) ~= 2 then return fail(string.format("sword = %d after Select+B, want 2", rd(0x0711))) end
      if not inGame() then return fail("Select+B left normal play") end
      return nextStep("Select+B switched sword 1 -> 2")
    end
  end,
  -- 7: pad 1 Start+A+B wild warp.  Hold A+B, then tap Start.
  function()
    if since() == 1 then saved.loc = rd(CurLoc); saved.warp = false end
    if since() >= 2 and since() < 14 then pad1 = {a = true, b = true} end
    if since() >= 8 and since() < 11 then pad1 = {a = true, b = true, start = true} end
    if rd(GameMode) == 1 or rd(CurLoc) ~= saved.loc then saved.warp = true end
    if since() >= 120 then
      if not saved.warp then return fail("Start+A+B did not wild warp") end
      return nextStep(string.format("wild warp: location %02x -> %02x", saved.loc, rd(CurLoc)))
    end
  end,
  -- 8: set P2Active = 1, then reset.  It must read 0 on the title screen.
  function()
    if since() == 1 then wr(P2Active, 1); wr(P2Held, 0x55) end
    if since() == 2 then
      if rd(P2Active) ~= 1 then return fail("could not set P2Active before reset") end
      emu.reset()
    end
    if since() >= 90 then
      if inGame() then return fail("still in game after reset?") end
      if rd(P2Active) ~= 0 or rd(P2Held) ~= 0 then
        return fail(string.format("after reset P2Active=%d P2Held=%02x", rd(P2Active), rd(P2Held)))
      end
      return nextStep("reset cleared co-op RAM")
    end
  end,
  -- 9: all done.
  function() finish(0, "ALL PASS") end,
}

emu.addEventCallback(function()
  if done then return end
  if pad1 then emu.setInput(0, pad1) end
  if pad2 then emu.setInput(1, pad2) end
end, emu.eventType.inputPolled)

emu.addEventCallback(function()
  if done then return end
  frame = frame + 1
  pad1, pad2 = {}, {}
  table.insert(hist, mode8Hits > lastHits and 1 or 0); lastHits = mode8Hits
  if #hist > 30 then table.remove(hist, 1) end
  steps[step]()
  if not done and since() > 4000 then finish(100 + step, "TIMEOUT") end
end, emu.eventType.startFrame)

log("m1 test started")
