-- Co-op v0.2 test: player 2 picks up coins into the shared money.
--  1. Boot, wild warp to location $03, player 2 joins.
--  2. Player 2's sword kills enemies held in front of them until one
--     drops a coin; player 2 is 64 px from player 1.
--  3. The coin is put on player 2: the money goes up and the coin is
--     gone (v0.1 left coins for player 1).
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 100 + n stuck at step
-- n, 200 + n check failed at step n.  Details go to v02_coins.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v02_coins.log", "w") end)
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
local noInvuln = false
emu.addMemoryCallback(function()
  -- Keep enemies from deciding the test: player 2 can't be hit while
  -- the test holds them still, and player 1 stays at full HP.
  if not noInvuln then wr(0x62c0, 0x3c) end  -- P2Invuln (not while collecting)
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

local FRONT = {[0] = {0, -14}, [1] = {10, -10}, [2] = {14, 0}, [3] = {10, 10},
               [4] = {0, 14}, [5] = {-10, 10}, [6] = {-14, 0}, [7] = {-10, -10}}
local function putNearP2(e, dx, dy)
  local x = rd(P2Ground + 1) * 256 + rd(P2Ground) + dx
  local ylo, yhi = rd(P2Ground + 2) + dy, rd(P2Ground + 3)
  if ylo < 0 then ylo = ylo + 240; yhi = yhi - 1 elseif ylo >= 240 then ylo = ylo - 240; yhi = yhi + 1 end
  wr(0x70 + e, x % 256); wr(0x90 + e, math.floor(x / 256))
  wr(0xb0 + e, ylo); wr(0xd0 + e, yhi % 256)
end
local function findEnemy()
  local plane = rd(0x03a1) & 0xf0
  for e = 0x0d, 0x1e do
    if e ~= rd(P2Slot) and e ~= rd(0x62c1) then
      local act = rd(0x04a0 + e)
      if act ~= 0 and (act & 0x7f) ~= 0x7b and (act & 0x7f) ~= 0x7d and (act & 0x7f) ~= 0x10
         and (rd(0x03a0 + e) & plane) ~= 0 and rd(0x03c0 + e) > 0 and rd(0x03c0 + e) ~= 0xff and rd(0x0540 + e) ~= 0xff then
        return e
      end
    end
  end
  return nil
end
local function findCoin()
  for e = 0x0d, 0x1e do if (rd(0x04a0 + e) & 0x7f) == 0x7b then return e end end
  return nil
end
local function money() return rd(0x0702) + 256 * rd(0x0703) end

local steps = {
  -- 1: boot, warp to $03, join (with the Wind Sword).
  function()
    if not s.booted then
      if inGame() then s.booted = true; s.wf = 0; wr(0x6430, 0x00); wr(0x0711, 0x01) end
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
      return nextStep("joined")
    end
  end,
  -- 2: player 2 kills enemies until a coin drops (64 px from player 1).
  function()
    if since() == 1 then
      atSafePoint = function()
        if not s.moved then
          local x = rd(0x90) * 256 + rd(0x70) + 64
          wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
          wr(P2Ground + 2, rd(0xb0)); wr(P2Ground + 3, rd(0xd0))
          s.moved = true
        end
        if not (s.e and rd(0x04a0 + s.e) ~= 0 and (rd(0x04a0 + s.e) & 0x7f) ~= 0x7d and (rd(0x04a0 + s.e) & 0x7f) ~= 0x7b) then s.e = findEnemy() end
        if s.e then
          wr(0x03c0 + s.e, math.min(rd(0x03c0 + s.e), 1))
          local f = FRONT[rd(P2Ground + 6) & 7]
          putNearP2(s.e, f[1], f[2])
        end
      end
    end
    if since() % 12 < 2 then pad2 = {b = true} end
    local c = findCoin()
    if c then
      s.coin = c
      return nextStep(string.format("a coin dropped (slot %02x)", c))
    end
    if since() > 2500 then return fail("no coin dropped") end
  end,
  -- 3: the coin on player 2: money goes up, coin gone.
  function()
    if since() == 1 then
      s.m0 = money()
      noInvuln = true
      wr(0x62c0, 0)
      atSafePoint = function()
        if (rd(0x04a0 + s.coin) & 0x7f) == 0x7b then putNearP2(s.coin, 0, 0) end
      end
    end
    if (rd(0x04a0 + s.coin) & 0x7f) ~= 0x7b then
      if money() <= s.m0 then return fail(string.format("coin gone but money %d -> %d", s.m0, money())) end
      local d = math.abs(rd(0x90) * 256 + rd(0x70) - (rd(P2Ground + 1) * 256 + rd(P2Ground)))
      return nextStep(string.format("player 2 picked up the coin: money %d -> %d (player 1 %d px away)", s.m0, money(), d))
    end
    if since() > 300 then return fail(string.format("coin still there after 300 frames (money %d)", money())) end
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

log("v02 coins test started")
