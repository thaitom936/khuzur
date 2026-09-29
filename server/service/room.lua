--- One table (room) per service. Runs the rules engine, drives bots,
--- enforces per-turn timers with auto-play on timeout, and handles
--- disconnects/reconnects. All wire messages use 0-based seats and card
--- strings; the engine is 1-based internally.
local skynet = require "skynet"
local engine = require "rules.engine"
local bot = require "rules.bot"

local mode, size, code
local stake = 0 -- per-player entry fee, escrowed by the agents
local locked = false -- kept off the lobby list; join by code/invite only
local cfg = engine.defaultConfig()
local players = {}   -- seat(1-based) -> {uid,name,agent,fd,bot,online,auto,misses}
local started = false
local st                -- engine state
local roundNo = 0
local dealerSeat = 1
local turnId = 0
local deadline = 0      -- absolute, in centiseconds (skynet.now())
local totalTricks = {}  -- seat -> tricks across the whole game
local watchers = {}     -- uid -> {uid, agent, fd}

-- Full game record for replays: every deal and every action.
local record = { rounds = {} }
local curRound

local T = {}            -- timeouts, filled in skynet.start

local CMD = {}

---------------------------------------------------------------- push helpers

local function push(p, msg)
  if p.agent then
    skynet.send(p.agent, "lua", "push", p.fd, msg)
  end
end

local function broadcast(msg)
  for _, p in ipairs(players) do
    push(p, msg)
  end
  for _, w in pairs(watchers) do
    push(w, msg)
  end
end

local function seatInfos()
  local seats = {}
  for i, p in ipairs(players) do
    local e = st and st.players[i]
    seats[#seats + 1] = {
      name = p.name,
      bot = p.bot or false,
      online = p.online ~= false,
      auto = p.auto or false,
      score = e and e.score,
      tricks = e and e.tricks,
      decision = e and e.decision,
      hand = e and #e.hand,
    }
  end
  return seats
end

local function handStrings(seat)
  local out = {}
  for _, c in ipairs(st.players[seat].hand) do
    out[#out + 1] = engine.cardString(c)
  end
  return out
end

local function trickWire()
  local out = {}
  for _, t in ipairs(st.trick) do
    out[#out + 1] = { seat = t.seat - 1, card = engine.cardString(t.card) }
  end
  return out
end

local function scores()
  local out = {}
  for _, e in ipairs(st.players) do out[#out + 1] = e.score end
  return out
end

-- Table snapshot; seat = nil for a spectator view (no hand, you = -1).
local function snapshot(seat)
  return {
    push = "snapshot",
    you = seat and seat - 1 or -1,
    started = started,
    mode = mode,
    code = code,
    size = size,
    stake = stake,
    locked = locked,
    round = roundNo,
    phase = st and st.phase,
    turn = st and st.turn - 1,
    dealer = st and dealerSeat - 1,
    trump = st and engine.cardString(st.trumpCard),
    stock = st and #st.stock,
    trickNo = st and st.trickNo,
    trick = st and trickWire(),
    seats = seatInfos(),
    hand = (st and started and seat) and handStrings(seat) or nil,
    deadline = st and math.max(0, deadline - skynet.now()) or nil,
    config = cfg,
  }
end

-- Whether the seat whose turn it is may pass (mirrors engine.decide).
local function canPass()
  local e = st.players[st.turn]
  if e.score <= cfg.mustPlayAtScore then return false end
  local playCount, undecided = 0, 0
  for _, q in ipairs(st.players) do
    if q.decision == "play" then playCount = playCount + 1 end
    if q.decision == "none" then undecided = undecided + 1 end
  end
  return playCount + undecided - 1 >= cfg.minPlayers
end

---------------------------------------------------------------- game flow

local announceTurn -- forward

local function phaseActive()
  return st and (st.phase == "deciding" or st.phase == "exchanging"
    or st.phase == "playing")
end

local function guard(id, fn)
  return function()
    if started and turnId == id and phaseActive() then fn() end
  end
end

local function startRound(prevScores)
  roundNo = roundNo + 1
  st = engine.deal {
    players = size,
    dealer = dealerSeat,
    scores = prevScores,
    config = cfg,
  }
  -- Record the full deal for the replay.
  local allHands, stockStrings = {}, {}
  for i = 1, size do allHands[i] = handStrings(i) end
  for _, c in ipairs(st.stock) do
    stockStrings[#stockStrings + 1] = engine.cardString(c)
  end
  curRound = {
    dealer = dealerSeat - 1,
    trump = engine.cardString(st.trumpCard),
    hands = allHands,
    stock = stockStrings,
    scores = scores(),
    actions = {},
  }
  record.rounds[#record.rounds + 1] = curRound

  for i, p in ipairs(players) do
    push(p, {
      push = "round_start",
      round = roundNo,
      dealer = dealerSeat - 1,
      trump = curRound.trump,
      stock = #st.stock,
      hand = allHands[i],
      scores = curRound.scores,
    })
  end
  for _, w in pairs(watchers) do
    push(w, {
      push = "round_start",
      round = roundNo,
      dealer = dealerSeat - 1,
      trump = curRound.trump,
      stock = #st.stock,
      scores = curRound.scores,
    })
  end
  announceTurn()
end

--- Appends one action to the current round's replay record.
local function recordAction(seat, cmd, value)
  curRound.actions[#curRound.actions + 1] =
    { s = seat - 1, c = cmd, v = value }
end

local function endRound()
  local results = {}
  for i, e in ipairs(st.players) do
    results[#results + 1] = {
      seat = i - 1,
      tricks = e.tricks,
      score = e.score,
      passed = e.decision == "pass",
    }
  end
  broadcast { push = "round_end", round = roundNo, results = results }

  if st.phase == "game_end" then
    local winners = {}
    local winnerSet = {}
    for _, s in ipairs(st.winners) do
      winners[#winners + 1] = s - 1
      winnerSet[s] = true
    end
    -- Coin pot: every human paid `stake`; human winners split the pot
    -- equally, a bot winner's share is burned.
    local humanCount = 0
    for _, p in ipairs(players) do
      if p.uid then humanCount = humanCount + 1 end
    end
    local pot = stake * humanCount
    local share = pot > 0 and pot // #st.winners or 0
    local winnings = {}
    for i, p in ipairs(players) do
      if p.uid and winnerSet[i] and share > 0 then
        winnings[#winnings + 1] = { seat = i - 1, coins = share }
        skynet.send(".db", "lua", "coins_add", p.uid, share)
      end
    end
    broadcast {
      push = "game_end",
      winners = winners,
      scores = scores(),
      winnings = winnings,
    }
    local humans = {}
    local uids = {}
    for i, p in ipairs(players) do
      if p.uid then
        humans[#humans + 1] = {
          uid = p.uid,
          win = winnerSet[i] or false,
          score = st.players[i].score,
          tricks = totalTricks[i] or 0,
        }
        uids[#uids + 1] = p.uid
      end
    end
    if #humans > 0 then
      skynet.call(".db", "lua", "game_result", mode, humans)
      -- Persist the replay for the human participants.
      record.mode = mode
      record.size = size
      record.stake = stake
      record.config = cfg
      local names = {}
      local seatUids = {}
      for i, p in ipairs(players) do
        names[i] = p.name
        seatUids[i] = p.uid or 0
      end
      record.names = names
      record.uids = uids
      record.seat_uids = seatUids
      record.winners = winners
      skynet.send(".db", "lua", "save_replay", uids, record)
    end
    skynet.send(".hub", "lua", "room_closed", skynet.self(), uids)
    skynet.timeout(200, function() skynet.exit() end)
  else
    local round = roundNo
    skynet.timeout(T.round_pause, function()
      if started and roundNo == round then
        dealerSeat = dealerSeat % size + 1
        startRound(scores())
      end
    end)
  end
end

local function postAction()
  if not phaseActive() then
    endRound()
  else
    announceTurn()
  end
end

local function doPlay(seat, cardStr)
  local playCount = 0
  for _, e in ipairs(st.players) do
    if e.decision == "play" then playCount = playCount + 1 end
  end
  local completing = #st.trick == playCount - 1
  local before = {}
  for i, e in ipairs(st.players) do before[i] = e.tricks end

  local ok, err = engine.play(st, seat, cardStr)
  if not ok then return err end
  recordAction(seat, "p", cardStr)
  broadcast { push = "played", seat = seat - 1, card = cardStr }
  if completing then
    local winner
    for i, e in ipairs(st.players) do
      if e.tricks > before[i] then winner = i end
    end
    totalTricks[winner] = (totalTricks[winner] or 0) + 1
    broadcast { push = "trick_end", winner = winner - 1 }
  end
  postAction()
  return nil
end

local function botAct()
  local seat = st.turn
  if st.phase == "deciding" then
    local play = bot.decidePlay(st, seat)
    if not engine.decide(st, seat, play) then
      play = true
      engine.decide(st, seat, true)
    end
    recordAction(seat, "d", play)
    broadcast { push = "decided", seat = seat - 1, play = play }
    postAction()
  elseif st.phase == "exchanging" then
    local cards = bot.chooseExchange(st, seat)
    if not engine.exchange(st, seat, cards) then
      cards = {}
      engine.exchange(st, seat, cards)
    end
    recordAction(seat, "e", cards)
    broadcast { push = "exchanged", seat = seat - 1, count = #cards }
    postAction()
  elseif st.phase == "playing" then
    doPlay(seat, bot.choosePlay(st, seat))
  end
end

local function onTimeout()
  local p = players[st.turn]
  p.misses = (p.misses or 0) + 1
  if p.misses >= 2 and not p.auto then
    p.auto = true
    broadcast { push = "seat_state", seat = st.turn - 1, online = p.online ~= false,
      auto = true }
  end
  botAct()
end

announceTurn = function()
  turnId = turnId + 1
  local id = turnId
  local timeout = st.phase == "deciding" and T.decide
    or st.phase == "exchanging" and T.exchange or T.play
  deadline = skynet.now() + timeout
  broadcast {
    push = "turn",
    seat = st.turn - 1,
    phase = st.phase,
    deadline = timeout,
    can_pass = st.phase == "deciding" and canPass() or nil,
  }
  local cur = players[st.turn]
  if cur.bot or cur.auto or cur.online == false then
    skynet.timeout(T.bot_delay, guard(id, botAct))
  else
    skynet.timeout(timeout, guard(id, onTimeout))
  end
end

local function startGame()
  started = true
  dealerSeat = math.random(size)
  for i, p in ipairs(players) do
    push(p, {
      push = "game_start",
      you = i - 1,
      size = size,
      code = code,
      stake = stake,
      seats = seatInfos(),
      config = cfg,
    })
  end
  startRound(nil)
end

---------------------------------------------------------------- commands

function CMD.info()
  local names = {}
  local bots = 0
  for i, p in ipairs(players) do
    names[i] = p.name
    if p.bot then bots = bots + 1 end
  end
  local watcherCount = 0
  for _ in pairs(watchers) do watcherCount = watcherCount + 1 end
  return {
    code = code,
    mode = mode,
    stake = stake,
    size = size,
    locked = locked,
    started = started,
    seated = #players,
    bots = bots,
    watchers = watcherCount,
    names = names,
    round = roundNo,
  }
end

--- Adds a spectator; they get every broadcast but never any hand.
function CMD.watch(p)
  watchers[p.uid] = { uid = p.uid, agent = p.agent, fd = p.fd }
  push(watchers[p.uid], snapshot(nil))
  return true
end

function CMD.unwatch(uid)
  watchers[uid] = nil
  return true
end

function CMD.init(opts)
  mode = opts.mode
  size = opts.size
  code = opts.code
  stake = opts.stake or 0
  locked = opts.locked or false
  for _, p in ipairs(opts.players) do
    players[#players + 1] = {
      uid = p.uid, name = p.name, agent = p.agent, fd = p.fd,
      bot = p.bot or false, online = not p.bot, misses = 0,
    }
  end
  if mode == "quick" or #players == size then
    startGame()
  else
    broadcast { push = "room_update", code = code, size = size, stake = stake, locked = locked, seats = seatInfos() }
  end
  return true
end

function CMD.join(p)
  if started then
    -- Sitting down mid-game: take over a bot seat (free tables only,
    -- so the pot stays consistent).
    if stake > 0 then return nil, "already_started" end
    local seat
    for i, q in ipairs(players) do
      if q.bot then seat = i break end
    end
    if not seat then return nil, "room_full" end
    players[seat] = {
      uid = p.uid, name = p.name, agent = p.agent, fd = p.fd,
      bot = false, online = true, misses = 0,
    }
    -- (hub.join_room registers uid -> room after this call returns.)
    -- Everyone sees the new seating; each viewer gets their own snapshot.
    for i, q in ipairs(players) do
      push(q, snapshot(i))
    end
    for _, w in pairs(watchers) do
      push(w, snapshot(nil))
    end
    if phaseActive() and st.turn == seat then
      announceTurn() -- restart this turn's timer as a human turn
    end
    return true
  end
  if #players >= size then return nil, "room_full" end
  players[#players + 1] = {
    uid = p.uid, name = p.name, agent = p.agent, fd = p.fd,
    bot = false, online = true, misses = 0,
  }
  broadcast { push = "room_update", code = code, size = size, stake = stake, locked = locked, seats = seatInfos() }
  if #players == size then startGame() end
  return true
end

function CMD.leave(uid)
  if started then return nil, "already_started" end
  for i, p in ipairs(players) do
    if p.uid == uid then
      table.remove(players, i)
      break
    end
  end
  skynet.send(".hub", "lua", "left_room", uid)
  if #players == 0 then
    skynet.send(".hub", "lua", "room_closed", skynet.self(), {})
    skynet.timeout(10, function() skynet.exit() end)
  else
    broadcast { push = "room_update", code = code, size = size, stake = stake, locked = locked, seats = seatInfos() }
  end
  return true
end

--- Host (first seat) starts a friend room early; empty seats become bots.
function CMD.start(uid)
  if started then return nil, "already_started" end
  if not players[1] or players[1].uid ~= uid then return nil, "not_host" end
  local n = 0
  while #players < size do
    n = n + 1
    players[#players + 1] = { bot = true, name = "Bot " .. n, misses = 0 }
  end
  startGame()
  return true
end

local function seatOf(uid)
  for i, p in ipairs(players) do
    if p.uid == uid then return i, p end
  end
end

function CMD.action(uid, msg)
  local seat, p = seatOf(uid)
  if not seat then return nil, "not_in_room" end

  if msg.cmd == "chat" then
    broadcast { push = "chat", seat = seat - 1, phrase = msg.phrase }
    return true
  end
  if msg.cmd == "auto" then
    p.auto = msg.on and true or false
    p.misses = 0
    broadcast { push = "seat_state", seat = seat - 1, online = p.online,
      auto = p.auto }
    return true
  end
  if not started then return nil, "not_started" end

  p.misses = 0
  local err
  if msg.cmd == "decide" then
    local ok, e = engine.decide(st, seat, msg.play and true or false)
    err = not ok and e or nil
    if not err then
      recordAction(seat, "d", msg.play and true or false)
      broadcast { push = "decided", seat = seat - 1, play = msg.play and true or false }
      postAction()
    end
  elseif msg.cmd == "exchange" then
    local cards = msg.cards or {}
    local ok, e = engine.exchange(st, seat, cards)
    err = not ok and e or nil
    if not err then
      recordAction(seat, "e", cards)
      broadcast { push = "exchanged", seat = seat - 1, count = #cards }
      push(p, { push = "exchange_result", hand = handStrings(seat) })
      postAction()
    end
  elseif msg.cmd == "play_card" then
    err = doPlay(seat, msg.card)
  else
    err = "bad_cmd"
  end
  if err then return nil, err end
  return true
end

function CMD.rejoin(uid, agent, fd)
  local seat, p = seatOf(uid)
  if not seat then return nil, "not_in_room" end
  p.agent, p.fd = agent, fd
  p.online = true
  p.auto = false
  p.misses = 0
  broadcast { push = "seat_state", seat = seat - 1, online = true, auto = false }
  push(p, snapshot(seat))
  if started and phaseActive() and st.turn == seat then
    announceTurn() -- restart this turn's timer as a human turn
  end
  return true
end

function CMD.offline(uid)
  local seat, p = seatOf(uid)
  if not seat then return true end
  if not started then return CMD.leave(uid) end
  p.online = false
  p.agent, p.fd = nil, nil
  broadcast { push = "seat_state", seat = seat - 1, online = false,
    auto = p.auto or false }
  if phaseActive() and st.turn == seat then
    announceTurn() -- hand the current turn to the bot
  end
  return true
end

skynet.start(function()
  math.randomseed()
  T.decide = tonumber(skynet.getenv "timeout_decide") or 1000
  T.exchange = tonumber(skynet.getenv "timeout_exchange") or 1500
  T.play = tonumber(skynet.getenv "timeout_play") or 1500
  T.bot_delay = tonumber(skynet.getenv "bot_delay") or 80
  T.round_pause = tonumber(skynet.getenv "round_pause") or 500
  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
end)
