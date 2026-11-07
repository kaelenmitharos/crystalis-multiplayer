-- Co-op v0.3 test: heals reach player 2.
--  1. Boot (Wind Sword), teleport to Sealed Cave 2 ($05, slimes), join.
--  2. Medical Herb with player 1 hurt: heals player 1 only (as vanilla).
--  3. Medical Herb with player 1 full: heals player 2 instead.
--  4. Player 2's B with a herb equipped doesn't use it (it used to: the
--     hero code that runs for player 2 checks the equipped item).
--  5. Refresh (player 1's spell): both heal by the same amount.
--  6. Refresh with player 2 down: player 2 stays down at 0 HP.
--  7. Level up: player 2's max HP and HP go up by player 1's increase.
--  8. Inn with player 2 down: player 1 healed to full during a map reload
--     (what an inn does): player 2 is revived and fully restored too.
-- (Items are used the game's way: equipped, then B in normal play.)
-- Build with --flags="Dn Ec Et Vemsw Cp"; run like m1_input.lua (see its
-- header for the MesenCE / Mesen 0.9.9 commands).
--
-- Result is the exit code: 0 pass, 99 Lua error, 100 + n stuck at step n,
-- 200 + n check failed at step n.  Details go to v03_heal.log.

local DIR = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])") or ""
local LOG = nil
pcall(function() LOG = io.open(DIR .. "v03_heal.log", "w") end)
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
local P2Down, P2DownTimer, P2Invuln = 0x62c4, 0x6287, 0x62c0
local HP, MaxHP, MP, GameMode, CurLoc = 0x03c1, 0x03c0, 0x0708, 0x41, 0x6c
local HERB = 0x1d

local frame, stepFrame, step, done = 0, 0, 1, false
local pad1, pad2 = {}, {}
local s = {}
local hits, last, hist = 0, 0, {}
emu.addMemoryCallback(function() hits = hits + 1 end, EXEC, 0xcb62, 0xcb62)
local atSafePoint = nil
emu.addMemoryCallback(function()
  wr(P2Invuln, 0x3c); wr(0x071a, 0x3c)   -- no damage from the slimes
  if atSafePoint then pcall(atSafePoint) end
end, EXEC, 0xcb6e, 0xcb6e)
local function inGame()
  local n = 0; for _, v in ipairs(hist) do n = n + v end
  return rd(0x40) == 1 and n >= 15
end
local function finish(code, msg)
  if done then return end
  done = true
  log(string.format("frame %d step %d: %s (exit %d)", frame, step, msg, code))
  log(string.format("  P1 %d/%d  P2 %d/%d down %d  MP %d  gm %02x", rd(HP), rd(MaxHP), rd(P2HP), rd(P2MaxHP), rd(P2Down), rd(MP), rd(GameMode)))
  if LOG then LOG:close() end
  emu.stop(code)
end
local function nextStep(msg)
  log(string.format("frame %d step %d ok: %s", frame, step, msg))
  step = step + 1; stepFrame = frame; atSafePoint = nil; s.t = nil
end
local function fail(msg) finish(200 + step, "FAIL " .. msg) end
local function since() return frame - stepFrame end
-- Put a herb in the first item slot and equip it through the menu (Select,
-- down 4 rows to the items, A, Select), then press B in normal play.
-- useItem(t, who) drives the pads for frame t of the step; true when done.
local function herb() wr(0x6440, HERB) end
-- Set player 1's HP without it counting as a heal for player 2: also set
-- CoopP1HPLast, which the co-op code compares against.
local function setHP(v) wr(HP, v); wr(0x62d2, v) end
local itemStart = nil
local function useItem(t, who)
  -- start once normal play has run for a while (the last step may still
  -- be showing a message)
  if t <= 1 then itemStart = nil end
  if not itemStart then
    if inGame() and rd(GameMode) == 8 then itemStart = t end
    return false
  end
  t = t - itemStart
  local seq = {{10, {select = true}}, {50, {down = true}}, {62, {down = true}}, {74, {down = true}},
               {86, {down = true}}, {100, {a = true}}, {150, {select = true}}}
  for _, e in ipairs(seq) do if t >= e[1] and t < e[1] + 3 then pad1 = e[2] end end
  if t >= 200 and t < 203 then if who == 2 then pad2 = {b = true} else pad1 = {b = true} end end
  -- the herb's message waits for a button without leaving mode 8
  if t > 205 and t % 20 < 2 and (rd(GameMode) ~= 8 or not inGame()) then pad1 = {a = true} end
  return t >= 400 and inGame()
end

local FRONT = {[0] = {0, -14}, [1] = {10, -10}, [2] = {14, 0}, [3] = {10, 10},
               [4] = {0, 14}, [5] = {-10, 10}, [6] = {-14, 0}, [7] = {-10, -10}}

local steps = {
  -- 1: boot, teleport to $05, join.
  function()
    if not s.booted then
      if inGame() then s.booted = true; s.b = frame; wr(0x6430, 0x00); wr(0x0711, 0x01) end
      if (rd(0x40) ~= 1 or rd(GameMode) == 0x13) and frame % 40 < 2 then pad1 = {start = true} end
      return
    end
    local t = frame - s.b
    if t == 5 then wr(CurLoc, 0x05); wr(0x6d, 0); wr(GameMode, 1) end
    if not s.jf and t > 150 and inGame() and rd(CurLoc) == 0x05 then s.jf = frame end
    if s.jf then
      local j = frame - s.jf
      if j < 3 then pad2 = {start = true} end
      if j == 40 then
        if rd(P2Active) ~= 1 or rd(P2Slot) == 0 then return fail("player 2 did not join") end
        return nextStep(string.format("joined; P1 %d/%d, P2 %d/%d", rd(HP), rd(MaxHP), rd(P2HP), rd(P2MaxHP)))
      end
    end
    if t > 2000 then return fail("teleport failed") end
  end,
  -- 2: herb with player 1 hurt: player 1 heals, player 2 doesn't.
  function()
    if since() == 1 then setHP(10); wr(P2HP, 20); herb() end
    if since() == 5 then s.p1, s.p2 = rd(HP), rd(P2HP) end
    if useItem(since(), 1) and not s.t then
      s.t = true
      local want = math.min(s.p1 + 0x50, rd(MaxHP))
      if rd(HP) ~= want then return fail(string.format("player 1 %d -> %d, want %d", s.p1, rd(HP), want)) end
      if rd(P2HP) ~= s.p2 then return fail(string.format("player 2 changed %d -> %d", s.p2, rd(P2HP))) end
      if rd(0x6440) == HERB then return fail("the herb was not used up") end
      return nextStep(string.format("herb: player 1 %d -> %d, player 2 stays %d", s.p1, rd(HP), rd(P2HP)))
    end
  end,
  -- 3: herb with player 1 full: player 2 heals instead.
  function()
    if since() == 1 then setHP(rd(MaxHP)); wr(P2HP, 10); herb() end
    if since() == 5 then s.p1, s.p2 = rd(HP), rd(P2HP) end
    if useItem(since(), 1) and not s.t then
      s.t = true
      local want = math.min(s.p2 + 0x50, rd(P2MaxHP))
      if rd(P2HP) ~= want then return fail(string.format("player 2 %d -> %d, want %d", s.p2, rd(P2HP), want)) end
      if rd(HP) ~= s.p1 then return fail(string.format("player 1 changed %d -> %d", s.p1, rd(HP))) end
      if rd(0x6440) == HERB then return fail("the herb was not used up") end
      return nextStep(string.format("herb with player 1 full: player 2 %d -> %d", s.p2, rd(P2HP)))
    end
  end,
  -- 4: player 2's B doesn't use player 1's herb.
  function()
    if since() == 1 then setHP(10); wr(P2HP, 10); herb() end
    if itemStart and since() - itemStart == 208 and rd(GameMode) ~= 8 then return fail(string.format("player 2's B started item use (mode %02x)", rd(GameMode))) end
    if useItem(since(), 2) and not s.t then
      s.t = true
      if rd(0x6440) ~= HERB then return fail("player 2's B used the herb") end
      if rd(HP) ~= 10 or rd(P2HP) ~= 10 then return fail(string.format("HP changed: P1 %d, P2 %d", rd(HP), rd(P2HP))) end
      wr(0x0715, 0); wr(0x6440, 0xff)
      return nextStep("player 2's B left player 1's equipped herb alone")
    end
  end,
  -- 5: Refresh: both heal by the same amount.
  function()
    if since() == 1 then
      wr(0x0712, 1); wr(MP, 34); wr(0x0709, 34)   -- Refresh equipped, MP
      setHP(10); wr(P2HP, 10)
    end
    if since() == 10 then s.p1, s.p2 = rd(HP), rd(P2HP) end
    if since() >= 12 and since() < 15 then pad1 = {a = true} end
    if since() > 15 and since() % 20 < 2 and rd(GameMode) ~= 8 then pad1 = {a = true} end
    if since() == 300 then
      local d1, d2 = rd(HP) - s.p1, rd(P2HP) - s.p2
      if d1 <= 0 then return fail("Refresh didn't heal player 1") end
      if d2 ~= d1 then return fail(string.format("Refresh healed player 1 by %d, player 2 by %d", d1, d2)) end
      return nextStep(string.format("Refresh healed both by %d (P1 %d, P2 %d)", d1, rd(HP), rd(P2HP)))
    end
  end,
  -- 6: Refresh with player 2 down: player 2 stays down.
  function()
    if since() == 1 then
      wr(MP, 34); setHP(10)
      atSafePoint = function() if not s.downed then wr(P2HP, 0); wr(P2Down, 1); wr(P2DownTimer, 0); s.downed = true end end
      -- keep player 1 away from player 2 so they don't revive them
    end
    if since() == 10 then
      s.p1 = rd(HP)
      atSafePoint = function()
        local x = rd(0x90) * 256 + rd(0x70) + 64
        wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256)); wr(P2DownTimer, 0)
      end
    end
    if since() >= 12 and since() < 15 then pad1 = {a = true} end
    if since() > 15 and since() % 20 < 2 and rd(GameMode) ~= 8 then pad1 = {a = true} end
    if since() == 300 then
      if rd(HP) <= s.p1 then return fail("Refresh didn't heal player 1") end
      if rd(P2Down) == 0 or rd(P2HP) ~= 0 then return fail(string.format("player 2 healed while down: %d HP, down %d", rd(P2HP), rd(P2Down))) end
      atSafePoint = function()  -- revive for the next steps
        wr(P2Down, 0); wr(P2HP, 20)
        local x = rd(0x90) * 256 + rd(0x70) - 16
        wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
      end
      s.revAt = since()
    end
    if s.revAt and since() == s.revAt + 5 then
      return nextStep(string.format("Refresh healed player 1 to %d; player 2 stayed down", rd(HP)))
    end
  end,
  -- 7: level up: player 2 gains player 1's increase.
  function()
    if since() == 1 then
      wr(0x0704, 1); wr(0x0705, 0)   -- 1 experience to the next level
      setHP(20); wr(P2HP, 20)
      s.max0, s.p20 = rd(MaxHP), 20
      for e = 0x0d, 0x1e do
        if e ~= rd(P2Slot) and rd(0x04a0 + e) ~= 0 and rd(0x03c0 + e) > 0 and rd(0x03c0 + e) ~= 0xff and rd(0x0540 + e) ~= 0xff then s.e = e; break end
      end
      if not s.e then return fail("no enemy") end
      atSafePoint = function()
        local e = s.e
        if rd(0x04a0 + e) ~= 0 and rd(0x03c0 + e) > 0 and rd(0x03c0 + e) ~= 0xff then
          wr(0x03c0 + e, 1)
          local f = FRONT[rd(0x0360) & 7]
          local x = rd(0x90) * 256 + rd(0x70) + f[1]
          wr(0x70 + e, x % 256); wr(0x90 + e, math.floor(x / 256))
          wr(0xb0 + e, (rd(0xb0) + f[2]) % 240); wr(0xd0 + e, rd(0xd0))
        end
      end
    end
    if rd(GameMode) == 8 and since() % 16 < 2 and not s.lvl then pad1 = {b = true} end
    if rd(GameMode) ~= 8 and since() % 20 < 2 then pad1 = {a = true} end
    if rd(MaxHP) > s.max0 and not s.lvl then s.lvl = since() end
    if s.lvl and since() == s.lvl + 120 then
      local d = rd(MaxHP) - s.max0
      if rd(P2MaxHP) ~= rd(MaxHP) then return fail(string.format("player 2's max HP %d, player 1's %d", rd(P2MaxHP), rd(MaxHP))) end
      if rd(P2HP) ~= math.min(s.p20 + d, rd(MaxHP)) then return fail(string.format("player 2 HP %d after a level up of +%d max HP (was %d)", rd(P2HP), d, s.p20)) end
      return nextStep(string.format("level up: max HP +%d; player 2 %d -> %d (player 1 %d)", d, s.p20, rd(P2HP), rd(HP)))
    end
    if since() > 2000 then return fail("no level up") end
  end,
  -- 8: inn with player 2 down: revived and fully restored.  An inn heals
  --    player 1 to full and reloads the map when you leave; the test does
  --    the same to RAM (forcing the inn's game mode skips the innkeeper's
  --    conversation, so the game's inn wouldn't heal anyone).
  function()
    if since() == 1 then
      setHP(10)
      atSafePoint = function()
        if not s.innDowned then
          local x = rd(0x90) * 256 + rd(0x70) + 64
          wr(P2Ground, x % 256); wr(P2Ground + 1, math.floor(x / 256))
          wr(P2HP, 0); wr(P2Down, 1); wr(P2DownTimer, 0)
          s.innDowned = true
        end
      end
    end
    if rd(GameMode) ~= 8 and since() % 20 < 2 and not s.downAt then pad1 = {a = true} end  -- level-up message
    if s.innDowned and not s.downAt then s.downAt = since() end
    if s.downAt and since() == s.downAt + 10 then
      if rd(P2Down) == 0 then return fail("player 2 not down") end
      atSafePoint = nil
      wr(CurLoc, 0x02); wr(0x6d, 0); wr(GameMode, 1)   -- leaving the inn: map reload
    end
    if s.downAt and since() == s.downAt + 12 then wr(HP, rd(MaxHP)) end  -- the inn's heal (not a co-op write)
    if s.downAt and since() > s.downAt + 40 and rd(GameMode) == 8 and inGame() and not s.back then s.back = since() end
    if s.back and since() == s.back + 30 then
      if rd(P2Down) ~= 0 then return fail("player 2 still down after the inn") end
      if rd(P2HP) ~= rd(P2MaxHP) then return fail(string.format("player 2 %d/%d after the inn", rd(P2HP), rd(P2MaxHP))) end
      return nextStep(string.format("inn: player 1 %d/%d, player 2 revived at %d/%d", rd(HP), rd(MaxHP), rd(P2HP), rd(P2MaxHP)))
    end
    if since() > 2000 then return fail("map reload never finished") end
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

log("v03 heal test started")
