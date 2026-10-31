-- Co-op v0.2 test: leaving and joining again doesn't revive player 2.
--  1. Boot, wild warp to location $03, player 2 joins.
--  2. Player 2 at 20 HP leaves and rejoins: still 20 HP.
--  3. Player 2 is knocked down 64 px from player 1, leaves and rejoins:
--     still down, 0 HP, back where they fell, and not revived after 3 s.
--  4. Player 1 stands next to them: revived with a quarter of max HP.
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 100 + n stuck at step
-- n, 200 + n check failed at step n.  Details go to v02_rejoin.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v02_rejoin.log", "w") end)
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

local steps = {
  -- 1: boot, warp to $03, join.
  function()
    if not s.booted then
      if inGame() then s.booted = true; s.wf = 0 end
      if (rd(MainLoopMode) ~= 1 or rd(0x41) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
      return
    end
    if not s.warped then
      s.wf = s.wf + 1
      if s.wf < 12 then pad1 = {a = true, b = true} end
      if s.wf >= 6 and s.wf < 9 then pad1 = {a = true, b = true, start = true} end
      if s.wf > 90 and inGame() then
        s.warps = s.warps + 1
        if rd(CurLoc) == 0x03 then s.warped = true; s.jf = frame
        elseif s.warps >= 16 then return fail("never reached location 03")
        else s.wf = 0 end
      end
      return
    end
    local t = frame - s.jf
    if t < 3 then pad2 = {start = true} end
    if t == 40 then
      if rd(P2Active) ~= 1 or rd(P2Slot) == 0 then return fail("player 2 did not join") end
      return nextStep(string.format("joined with %d HP", rd(P2HP)))
    end
  end,
  -- 2: at 20 HP, leave and rejoin: still 20 HP.
  function()
    if since() == 1 then wr(P2HP, 20) end
    leaveAndRejoin(since())
    if since() == 15 and rd(P2Active) ~= 0 then return fail("player 2 did not leave") end
    if since() == 70 then
      if rd(P2Active) ~= 1 or rd(P2Slot) == 0 then return fail("player 2 did not come back") end
      if rd(P2HP) ~= 20 then return fail(string.format("HP %d after rejoining, want 20", rd(P2HP))) end
      return nextStep("left and rejoined with the same 20 HP")
    end
  end,
  -- 3: down 64 px from player 1, then leave and rejoin: still down, at
  --    the same spot, and not revived.
  function()
    if since() == 1 then
      atSafePoint = function()
        if not s.downed then
          local x = rd(0x90) * 256 + rd(0x70) + 64
          wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
          wr(P2HP, 0); wr(P2Down, 1); wr(P2DownTimer, 0)
          s.downed = true
        end
      end
    end
    if since() == 20 then
      if rd(P2Down) == 0 then return fail("player 2 not down") end
      s.x, s.y = p2pos()
    end
    if since() >= 30 then leaveAndRejoin(since() - 30) end
    if since() == 45 and rd(P2Active) ~= 0 then return fail("player 2 did not leave") end
    if since() == 100 then
      if rd(P2Active) ~= 1 then return fail("player 2 did not rejoin") end
      if rd(P2Down) == 0 then return fail(string.format("rejoining revived player 2 (HP %d)", rd(P2HP))) end
      if rd(P2HP) ~= 0 then return fail("down with HP " .. rd(P2HP)) end
      local x, y = p2pos()
      if x ~= s.x or y ~= s.y then return fail(string.format("moved from (%d,%d) to (%d,%d)", s.x, s.y, x, y)) end
    end
    if since() == 280 then
      if rd(P2Down) == 0 then return fail("revived without player 1 nearby") end
      return nextStep(string.format("rejoined still down at (%d,%d), not revived after 3 s", s.x, s.y))
    end
  end,
  -- 4: player 1 next to player 2: revived with a quarter of max HP.
  function()
    if since() == 1 then
      atSafePoint = function()
        local x = rd(P2Ground + 1) * 256 + rd(P2Ground) - 16
        for _, sl in ipairs({0, 1}) do
          wr(0x70 + sl, x % 256); wr(0x90 + sl, math.floor(x / 256))
          wr(0xb0 + sl, rd(P2Ground + 2)); wr(0xd0 + sl, rd(P2Ground + 3))
        end
      end
    end
    if rd(P2Down) == 0 then
      local want = math.max(1, math.floor(rd(P2MaxHP) / 4))
      if rd(P2HP) ~= want then return fail(string.format("revived with %d HP, want %d", rd(P2HP), want)) end
      return nextStep(string.format("player 1 revived player 2 after %d frames with %d HP", since(), rd(P2HP)))
    end
    if since() > 400 then return fail("player 1 never revived player 2") end
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

log("v02 rejoin test started")
