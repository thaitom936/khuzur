--- End-to-end test: boots the whole server, then drives real WebSocket
--- clients through login, matchmaking (with bot fill), a full game to
--- game_end, reconnect-free flows, friend rooms and the leaderboard.
-- Run from server/: ./skynet/skynet etc/config.test
local skynet = require "skynet"
local websocket = require "http.websocket"
local json = require "json"

local URL = "ws://127.0.0.1:" .. (tonumber(skynet.getenv "ws_port") or 9611) .. "/ws"

local failed = false

local function check(cond, what)
  if not cond then
    failed = true
    skynet.error("E2E FAIL: " .. what)
    error("E2E FAIL: " .. what)
  end
end

---------------------------------------------------------------- client sim

local Client = {}
Client.__index = Client

local function connect(name)
  local self = setmetatable({}, Client)
  self.id = websocket.connect(URL)
  self.name = name
  self.seq = 0
  self.hand = {}
  self.you = nil
  self.log = {}
  return self
end

function Client:send(t)
  self.seq = self.seq + 1
  t.seq = self.seq
  websocket.write(self.id, json.encode(t))
end

function Client:read()
  local raw = websocket.read(self.id)
  if not raw then return nil end
  local msg = json.decode(raw)
  self.log[#self.log + 1] = msg
  return msg
end

--- Sends a request and reads until its response arrives; pushes seen on
--- the way are handled (game state bookkeeping) and queued for the outer
--- read loop, which must not miss e.g. a game_end that raced the response.
function Client:call(t)
  self:send(t)
  local want = self.seq
  while true do
    local msg = self:read()
    check(msg, self.name .. " connection closed waiting for " .. t.cmd)
    if msg.seq == want then return msg end
    self:handlePush(msg)
    self.pending = self.pending or {}
    self.pending[#self.pending + 1] = msg
  end
end

--- Next push: queued ones first, then fresh reads.
function Client:next()
  if self.pending and #self.pending > 0 then
    return table.remove(self.pending, 1), true
  end
  return self:read(), false
end

function Client:handlePush(msg)
  if msg.push == "game_start" or msg.push == "snapshot" then
    self.you = msg.you
    if msg.hand then self.hand = msg.hand end
  elseif msg.push == "round_start" or msg.push == "exchange_result" then
    self.hand = msg.hand
  elseif msg.push == "played" and msg.seat == self.you then
    for i, c in ipairs(self.hand) do
      if c == msg.card then
        table.remove(self.hand, i)
        break
      end
    end
  end
end

--- On our turn, act; playing tries hand cards until the engine accepts one.
function Client:act(phase)
  if phase == "deciding" then
    local r = self:call { cmd = "decide", play = true }
    check(not r.err, self.name .. " decide: " .. tostring(r.err))
  elseif phase == "swapping" then
    local r = self:call { cmd = "swap_trump" }
    if r.err then
      r = self:call { cmd = "skip_swap" }
      check(not r.err, self.name .. " skip_swap: " .. tostring(r.err))
    end
  elseif phase == "exchanging" then
    local r = self:call { cmd = "exchange", cards = json.empty_array }
    check(not r.err, self.name .. " exchange: " .. tostring(r.err))
  elseif phase == "playing" then
    for _, card in ipairs({ table.unpack(self.hand) }) do
      local r = self:call { cmd = "play_card", card = card }
      if not r.err then return end
      check(r.err == "illegal_card",
        self.name .. " unexpected play error: " .. tostring(r.err))
    end
    check(false, self.name .. " no playable card")
  end
end

--- Reads pushes until game_end; acts whenever it is our turn.
function Client:playUntilGameEnd()
  while true do
    local msg, queued = self:next()
    check(msg, self.name .. " connection closed mid-game")
    if not queued then self:handlePush(msg) end
    if msg.push == "turn" and msg.seat == self.you then
      self:act(msg.phase)
    elseif msg.push == "game_end" then
      return msg
    end
  end
end

function Client:waitPush(name)
  while true do
    local msg, queued = self:next()
    check(msg, self.name .. " connection closed waiting push " .. name)
    if not queued then self:handlePush(msg) end
    if msg.push == name then return msg end
  end
end

---------------------------------------------------------------- scenarios

local function scenario_quick_match_with_bots()
  local a = connect("A")
  local r = a:call { cmd = "login", device = "e2e-device-aaaa", name = "Alice" }
  check(not r.err and r.uid and r.token, "login failed: " .. tostring(r.err))
  check(r.name == "Alice", "bad name")

  r = a:call { cmd = "quick_match", size = 3 }
  check(not r.err, "quick_match: " .. tostring(r.err))

  -- Alone in the queue: bots fill the table after match_fill_after.
  a:waitPush("game_start")
  local ge = a:playUntilGameEnd()
  check(type(ge.winners) == "table" and #ge.winners >= 1, "no winners")
  check(type(ge.scores) == "table" and #ge.scores == 3, "bad scores")
  skynet.error("E2E quick_match_with_bots OK, scores: " .. json.encode(ge.scores))

  r = a:call { cmd = "rank" }
  check(not r.err and type(r.top) == "table", "rank failed")
  websocket.close(a.id)
end

local function scenario_friend_room_two_humans()
  local a = connect("A2")
  local b = connect("B2")
  local ra = a:call { cmd = "login", device = "e2e-device-aaaa" }
  check(not ra.err, "A relogin failed")
  local rb = b:call { cmd = "login", device = "e2e-device-bbbb", name = "Bob" }
  check(not rb.err, "B login failed")

  local cr = a:call { cmd = "create_room", size = 2 }
  check(not cr.err and cr.code, "create_room: " .. tostring(cr.err))

  local jr = b:call { cmd = "join_room", code = cr.code }
  check(not jr.err, "join_room: " .. tostring(jr.err))

  -- Room is full (size 2): game starts for both.
  a:waitPush("game_start")
  b:waitPush("game_start")

  -- Drive both clients concurrently until game_end.
  local done = 0
  local function drive(c)
    skynet.fork(function()
      local ok, err = pcall(function() c:playUntilGameEnd() end)
      check(ok, "drive: " .. tostring(err))
      done = done + 1
    end)
  end
  drive(a)
  drive(b)
  local waited = 0
  while done < 2 do
    skynet.sleep(10)
    waited = waited + 10
    check(waited < 6000, "friend room game did not finish in 60s")
  end
  skynet.error("E2E friend_room_two_humans OK")
  websocket.close(a.id)
  websocket.close(b.id)
end

local function scenario_join_bad_room()
  local c = connect("C")
  local r = c:call { cmd = "login", device = "e2e-device-cccc" }
  check(not r.err, "C login failed")
  r = c:call { cmd = "join_room", code = "000000" }
  check(r.err == "room_not_found", "expected room_not_found, got " .. tostring(r.err))
  r = c:call { cmd = "decide", play = true }
  check(r.err == "not_in_room", "expected not_in_room, got " .. tostring(r.err))
  websocket.close(c.id)
end

local function scenario_resume_token()
  local a = connect("A3")
  local r = a:call { cmd = "login", device = "e2e-device-dddd", name = "Dana" }
  check(not r.err, "login failed")
  local token = r.token
  websocket.close(a.id)

  local b = connect("A3b")
  r = b:call { cmd = "resume", token = token }
  check(not r.err and r.name == "Dana", "resume failed: " .. tostring(r.err))
  r = b:call { cmd = "resume", token = "bogus" }
  check(r.err == "bad_token", "expected bad_token")
  websocket.close(b.id)
end

local function scenario_friends_and_invite()
  local a = connect("FA")
  local b = connect("FB")
  local ra = a:call { cmd = "login", device = "e2e-device-f-aa", name = "Fa" }
  local rb = b:call { cmd = "login", device = "e2e-device-f-bb", name = "Fb" }
  check(not ra.err and not rb.err, "friend logins failed")

  -- Request + accept via name lookup.
  local r = a:call { cmd = "friend_add", q = "Fb" }
  check(r.status == "requested" and r.uid == rb.uid,
    "friend_add: " .. tostring(r.err or r.status))
  r = a:call { cmd = "friend_add", q = "Fb" }
  check(r.err == "already_requested", "expected already_requested")

  b:waitPush("friend_update")
  r = b:call { cmd = "friends" }
  check(#r.requests == 1 and r.requests[1].uid == ra.uid, "request not listed")
  r = b:call { cmd = "friend_respond", uid = ra.uid, accept = true }
  check(not r.err, "friend_respond: " .. tostring(r.err))

  r = a:call { cmd = "friends" }
  check(#r.friends == 1 and r.friends[1].uid == rb.uid and r.friends[1].online,
    "friend not listed online")

  -- Invite from a friend room.
  r = a:call { cmd = "create_room", size = 2 }
  check(not r.err, "create_room: " .. tostring(r.err))
  r = a:call { cmd = "invite", uid = rb.uid }
  check(not r.err, "invite: " .. tostring(r.err))
  local inv = b:waitPush("invite")
  check(inv.from == "Fa" and inv.code, "bad invite push")
  r = b:call { cmd = "join_room", code = inv.code }
  check(not r.err, "join via invite: " .. tostring(r.err))
  a:waitPush("game_start")
  b:waitPush("game_start")
  local done = 0
  local function drive(cl)
    skynet.fork(function()
      cl:playUntilGameEnd()
      done = done + 1
    end)
  end
  drive(a)
  drive(b)
  while done < 2 do skynet.sleep(10) end
  skynet.error("E2E friends_and_invite OK")
  websocket.close(a.id)
  websocket.close(b.id)
end

local function scenario_coins_and_daily()
  local a = connect("CA")
  local b = connect("CB")
  local ra = a:call { cmd = "login", device = "e2e-device-c-aa", name = "Ca" }
  local rb = b:call { cmd = "login", device = "e2e-device-c-bb", name = "Cb" }
  check(ra.coins == 1000 and rb.coins == 1000, "starting coins not 1000")

  -- Daily bonus: claim once, second claim fails.
  local r = a:call { cmd = "daily" }
  check(not r.err and r.bonus_claimed == false and #r.tasks == 3, "daily state")
  r = a:call { cmd = "daily_claim" }
  check(r.coins == 1200, "bonus claim: got " .. tostring(r.coins))
  r = a:call { cmd = "daily_claim" }
  check(r.err == "already_claimed", "expected already_claimed")

  -- Bad stake / insufficient balance are rejected.
  r = a:call { cmd = "quick_match", stake = 123 }
  check(r.err == "bad_stake", "expected bad_stake")

  -- Coin table for two: stakes escrowed, winner takes the pot.
  r = a:call { cmd = "quick_match", size = 2, stake = 100 }
  check(not r.err, "A coin match: " .. tostring(r.err))
  r = b:call { cmd = "quick_match", size = 2, stake = 100 }
  check(not r.err, "B coin match: " .. tostring(r.err))
  a:waitPush("game_start")
  b:waitPush("game_start")
  local ends = {}
  local function drive(cl, key)
    skynet.fork(function()
      ends[key] = cl:playUntilGameEnd()
    end)
  end
  drive(a, "a")
  drive(b, "b")
  while not (ends.a and ends.b) do skynet.sleep(10) end
  check(#ends.a.winnings >= 1, "no winnings reported")

  -- Balances: winner got the 200 pot, loser lost the 100 stake.
  local da = a:call { cmd = "daily" }
  local db_ = b:call { cmd = "daily" }
  local total = da.coins + db_.coins
  check(total == 1200 + 1000, "pot not conserved: " .. total)

  -- Task progress advanced (played a game; one of them won it).
  check(da.tasks[1].progress == 1, "play3 progress")
  skynet.error("E2E coins_and_daily OK")
  websocket.close(a.id)
  websocket.close(b.id)
end

local function scenario_spectate_and_replay()
  local a = connect("SA")
  local b = connect("SB")
  local w = connect("SW")
  local ra = a:call { cmd = "login", device = "e2e-device-s-aa", name = "Sa" }
  local rb = b:call { cmd = "login", device = "e2e-device-s-bb", name = "Sb" }
  local rw = w:call { cmd = "login", device = "e2e-device-s-ww", name = "Sw" }
  check(not (ra.err or rb.err or rw.err), "spectate logins failed")

  local r = a:call { cmd = "quick_match", size = 2 }
  check(not r.err, "A match: " .. tostring(r.err))
  r = b:call { cmd = "quick_match", size = 2 }
  check(not r.err, "B match: " .. tostring(r.err))
  a:waitPush("game_start")
  b:waitPush("game_start")

  -- W watches A's game: snapshot without a hand, then live pushes.
  r = w:call { cmd = "watch", uid = ra.uid }
  check(not r.err, "watch: " .. tostring(r.err))
  local snap = w:waitPush("snapshot")
  check(snap.you == -1 and snap.hand == nil and #snap.seats == 2,
    "bad spectator snapshot")

  local done = 0
  local function drive(cl)
    skynet.fork(function()
      cl:playUntilGameEnd()
      done = done + 1
    end)
  end
  drive(a)
  drive(b)
  -- The watcher also sees the game end, without ever acting.
  local wEnd = w:waitPush("game_end")
  check(type(wEnd.winners) == "table", "watcher missed game_end")
  while done < 2 do skynet.sleep(10) end

  -- Replay: listed for both players, loadable, and structurally sound.
  skynet.sleep(20) -- allow the async save to land
  r = a:call { cmd = "replays" }
  check(not r.err and #r.list >= 1, "replay list empty")
  local meta = r.list[1]
  check(meta.size == 2 and type(meta.names) == "table", "bad replay meta")
  r = a:call { cmd = "replay", id = meta.id }
  check(not r.err and type(r.replay) == "string", "replay fetch failed")
  local rec = json.decode(r.replay)
  check(#rec.rounds >= 1 and #rec.rounds[1].hands == 2
    and #rec.rounds[1].hands[1] == 5 and #rec.rounds[1].actions > 0,
    "bad replay record")

  -- Replay the whole record through the engine (what the client's replay
  -- viewer does): every recorded action must be accepted.
  local engine = require "rules.engine"
  local steps = 0
  for ri, round in ipairs(rec.rounds) do
    local rst = engine.newRound {
      players = rec.size,
      dealer = round.dealer + 1,
      hands = round.hands,
      trump = round.trump,
      stock = round.stock,
      config = rec.config,
      scores = round.scores,
    }
    for ai, act in ipairs(round.actions) do
      local ok2, aerr
      if act.c == "d" then
        ok2, aerr = engine.decide(rst, act.s + 1, act.v and true or false)
      elseif act.c == "t" then
        ok2, aerr = engine.swapTrump(rst, act.s + 1)
      elseif act.c == "s" then
        ok2, aerr = engine.skipSwap(rst, act.s + 1)
      elseif act.c == "e" then
        ok2, aerr = engine.exchange(rst, act.s + 1, act.v or {})
      else
        ok2, aerr = engine.play(rst, act.s + 1, act.v)
      end
      check(ok2, ("replay desync r%d a%d: %s"):format(ri, ai, tostring(aerr)))
      steps = steps + 1
    end
    check(rst.phase == "round_end" or rst.phase == "game_end",
      "round " .. ri .. " incomplete after replay")
  end
  skynet.error("E2E spectate_and_replay OK (" .. #rec.rounds .. " rounds, "
    .. steps .. " steps re-verified)")
  websocket.close(a.id)
  websocket.close(b.id)
  websocket.close(w.id)
end

local function scenario_room_list_and_sit()
  local a = connect("LA")
  local b = connect("LB")
  local w2 = connect("LW")
  local ra = a:call { cmd = "login", device = "e2e-device-l-aa", name = "La" }
  local rb = b:call { cmd = "login", device = "e2e-device-l-bb", name = "Lb" }
  local rw = w2:call { cmd = "login", device = "e2e-device-l-ww", name = "Lw" }
  check(not (ra.err or rb.err or rw.err), "list logins failed")

  -- A creates a 3-seat free room; it shows up in the list.
  local cr = a:call { cmd = "create_room", size = 3 }
  check(not cr.err, "create: " .. tostring(cr.err))
  local r = b:call { cmd = "room_list" }
  check(not r.err, "room_list: " .. tostring(r.err))
  local entry
  for _, room in ipairs(r.rooms) do
    if room.code == cr.code then entry = room end
  end
  check(entry and entry.seated == 1 and entry.size == 3
    and entry.started == false, "room missing from list")

  -- Entering a waiting room is spectator-only and must not occupy a seat.
  r = b:call { cmd = "watch", code = cr.code }
  check(not r.err, "watch waiting room: " .. tostring(r.err))
  local waiting = b:waitPush("snapshot")
  check(waiting.you == -1 and waiting.started == false and not waiting.hand,
    "waiting watcher received player state")
  r = b:call { cmd = "room_list" }
  for _, room in ipairs(r.rooms) do
    if room.code == cr.code then
      check(room.seated == 1 and room.watchers == 1, "watcher occupied a seat")
    end
  end

  -- A starts early: two bot seats. The list now shows a running room.
  r = a:call { cmd = "start_room" }
  check(not r.err, "start_room: " .. tostring(r.err))
  a:waitPush("game_start")
  local watching = b:waitPush("snapshot")
  check(watching.you == -1 and watching.started == true and not watching.hand,
    "waiting watcher did not transition to the started game")
  local publicRound = b:waitPush("round_start")
  check(not publicRound.hand, "private cards leaked to spectator")
  r = b:call { cmd = "room_list" }
  local running
  for _, room in ipairs(r.rooms) do
    if room.code == cr.code then running = room end
  end
  check(running and running.started == true and running.bots == 2,
    "running room not listed with bots")

  -- B sits down mid-game on a bot seat and gets a proper snapshot.
  r = b:call { cmd = "join_room", code = cr.code }
  check(not r.err, "sit: " .. tostring(r.err))
  local snap = b:waitPush("snapshot")
  check(snap.you >= 0 and snap.hand and #snap.seats == 3, "bad sit snapshot")
  r = b:call { cmd = "room_list" }
  for _, room in ipairs(r.rooms) do
    if room.code == cr.code then
      check(room.watchers == 0 and room.bots == 1,
        "new player retained spectator membership")
    end
  end
  check(b.you >= 0, "spectator snapshot overwrote the seated player")

  -- W watches by room code.
  r = w2:call { cmd = "watch", code = cr.code }
  check(not r.err, "watch by code: " .. tostring(r.err))
  local wsnap = w2:waitPush("snapshot")
  check(wsnap.you == -1, "bad watcher snapshot")

  -- Play it out: both seated humans drive to the end.
  local done = 0
  local function drive(cl)
    skynet.fork(function()
      cl:playUntilGameEnd()
      done = done + 1
    end)
  end
  drive(a)
  drive(b)
  while done < 2 do skynet.sleep(10) end

  -- The finished room disappears from the list.
  skynet.sleep(30)
  r = b:call { cmd = "room_list" }
  for _, room in ipairs(r.rooms) do
    check(room.code ~= cr.code, "closed room still listed")
  end
  skynet.error("E2E room_list_and_sit OK")
  websocket.close(a.id)
  websocket.close(b.id)
  websocket.close(w2.id)
end

local function scenario_locked_room()
  local a = connect("KA")
  local b = connect("KB")
  local ra = a:call { cmd = "login", device = "e2e-device-k-aa", name = "Ka" }
  local rb = b:call { cmd = "login", device = "e2e-device-k-bb", name = "Kb" }
  check(not (ra.err or rb.err), "locked logins failed")

  local cr = a:call { cmd = "create_room", size = 2, locked = true }
  check(not cr.err and cr.code, "create locked: " .. tostring(cr.err))

  -- Locked rooms are invisible in the lobby list...
  local r = b:call { cmd = "room_list" }
  for _, room in ipairs(r.rooms) do
    check(room.code ~= cr.code, "locked room leaked into the list")
  end

  -- ...but joinable by code (e.g. via an invite).
  r = b:call { cmd = "join_room", code = cr.code }
  check(not r.err, "join locked by code: " .. tostring(r.err))
  a:waitPush("game_start")
  b:waitPush("game_start")
  local done = 0
  local function drive(cl)
    skynet.fork(function()
      cl:playUntilGameEnd()
      done = done + 1
    end)
  end
  drive(a)
  drive(b)
  while done < 2 do skynet.sleep(10) end
  skynet.error("E2E locked_room OK")
  websocket.close(a.id)
  websocket.close(b.id)
end

---------------------------------------------------------------- boot & run

local function scenario_sit_while_waiting()
  local a, b = connect("waiting-host"), connect("waiting-viewer")
  check(not a:call { cmd = "login", device = "waiting-host-device" }.err, "host login")
  check(not b:call { cmd = "login", device = "waiting-viewer-device" }.err, "viewer login")
  local cr = a:call { cmd = "create_room", size = 3 }
  check(not cr.err, "create waiting room")
  check(not b:call { cmd = "watch", code = cr.code }.err, "watch waiting room")
  local snap = b:waitPush("snapshot")
  check(snap.you == -1 and snap.started == false, "waiting spectator identity")
  check(not b:call { cmd = "join_room", code = cr.code }.err, "sit while waiting")
  snap = b:waitPush("snapshot")
  check(snap.you == 1 and snap.started == false and #snap.seats == 2,
    "waiting spectator did not become a seated player")
  local list = b:call { cmd = "room_list" }
  for _, room in ipairs(list.rooms) do
    if room.code == cr.code then
      check(room.watchers == 0 and room.seated == 2, "waiting seat count")
    end
  end
  check(not b:call { cmd = "leave_room" }.err, "viewer leaves waiting room")
  check(not a:call { cmd = "leave_room" }.err, "host leaves waiting room")
  websocket.close(a.id)
  websocket.close(b.id)
  skynet.error("E2E sit_while_waiting OK")
end

skynet.start(function()
  skynet.uniqueservice("db")
  skynet.uniqueservice("hub")
  skynet.uniqueservice("match")
  skynet.uniqueservice("wsgate")
  skynet.sleep(20)

  -- Watchdog: the whole suite must finish in 120s.
  skynet.fork(function()
    skynet.sleep(12000)
    skynet.error("E2E FAIL: watchdog timeout")
    os.exit(1)
  end)

  local ok, err = pcall(function()
    scenario_sit_while_waiting()
    scenario_join_bad_room()
    scenario_resume_token()
    scenario_quick_match_with_bots()
    scenario_friend_room_two_humans()
    scenario_friends_and_invite()
    scenario_coins_and_daily()
    scenario_spectate_and_replay()
    scenario_room_list_and_sit()
    scenario_locked_room()
  end)
  if ok and not failed then
    skynet.error("E2E PASS")
    os.exit(0)
  else
    skynet.error("E2E FAIL: " .. tostring(err))
    os.exit(1)
  end
end)
