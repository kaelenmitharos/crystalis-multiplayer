-- Co-op v0.2 test: player 2 is hidden in shops and inns.  The testers saw
-- player 2 crouching in the doorway while shopping: the shop modes ($20
-- armor .. $24 empty) animate the hero walking in and redraw every object
-- sprite on the way out, which drew player 2's stale sprite.
--  1. Boot, wild warp to location $03, player 2 joins.
--  2. Teleport to Leaf; game mode $21 (tool shop): player 2's sprite
--     slot is cleared.
--  3. Leave the shop (B): back in normal play, player 2 is back.
-- (The shop is entered by setting the game mode, so its contents and the
-- location after it are not meaningful; only player 2's sprite is.)
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 100 + n stuck at step
-- n, 200 + n check failed at step n.  Details go to v02_shop.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v02_shop.log", "w") end)
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
      if rd(P2Active) ~= 1 or rd(P2Slot) == 0 or rd(0x04a0 + rd(P2Slot)) ~= 0x09 then return fail("player 2 did not join") end
      return nextStep("joined")
    end
  end,
  -- 2: teleport to Leaf ($02), then the tool shop: player 2's sprite is
  --    gone.
  function()
    if since() == 1 then wr(CurLoc, 0x02); wr(0x6d, 0); wr(0x41, 1) end
    if not s.shopAt and since() > 30 and inGame() and rd(CurLoc) == 0x02 and since() > 150 then
      s.shopAt = since(); s.slot = rd(P2Slot)
      if s.slot == 0 or rd(0x04a0 + s.slot) ~= 0x09 then return fail("player 2 not back after the teleport") end
      wr(0x41, 0x21)
    end
    if since() > 1500 and not s.shopAt then return fail("teleport to Leaf failed") end
    if s.shopAt and since() == s.shopAt + 60 then
      if rd(0x41) ~= 0x21 then return fail(string.format("not in the shop (mode %02x)", rd(0x41))) end
      if rd(0x04a0 + s.slot) == 0x09 then return fail("player 2's sprite is still there") end
      return nextStep("in the shop, player 2's sprite is gone")
    end
  end,
  -- 3: leave the shop: player 2 comes back.
  function()
    if rd(0x41) ~= 8 and since() % 20 < 2 then pad1 = {b = true} end
    if rd(0x41) == 8 and inGame() and not s.back then s.back = since() end
    if s.back and since() == s.back + 60 then
      local sl = rd(P2Slot)
      if rd(P2Active) ~= 1 or sl == 0 or rd(0x04a0 + sl) ~= 0x09 then return fail("player 2 did not come back") end
      return nextStep("out of the shop, player 2 is back")
    end
    if since() > 3000 then return fail("never left the shop") end
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

log("v02 shop test started")
