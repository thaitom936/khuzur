--- One table (room) per service. Runs the rules engine, drives bots,
--- enforces per-turn timers with auto-play on timeout, and handles
--- disconnects/reconnects. All wire messages use 0-based seats and card
--- strings; the engine is 1-based internally.
local skynet = require "skynet"
local engine = require "rules.engine"
local bot = require "rules.bot"
local function newRtcChannel()
  -- skynet.crypt.randomkey uses libc random(), not secure entropy.
  local source = assert(io.open("/dev/urandom", "rb"))
  local bytes = source:read(16)
  source:close()
  assert(bytes and #bytes == 16, "RTC channel entropy unavailable")
  return "kh_" .. (bytes:gsub(".", function(c)
    return string.format("%02x", c:byte())
  end))
end
local rtcChannel = newRtcChannel()
local rtc
local rtcQueue = require "skynet.queue"()

local mode, size, code
local stake = 0 -- per-player entry fee, escrowed by the agents
local locked = false -- kept off the lobby list; join by code/invite only
local gameType = "muushig"
local cfg = engine.defaultConfig()
local players = {}   -- seat(1-based) -> {uid,name,agent,fd,bot,online,auto,misses}
local started = false
local dissolved = false
local st                -- engine state
local roundNo = 0
local dealerSeat = 1
local turnId = 0
local deadline = 0      -- absolute, in centiseconds (skynet.now())
local turnDuration = 0  -- full action budget, independent of bot thinking time
local decisionTurnId, decisionTimers
local totalTricks = {}  -- seat -> tricks across the whole game
local wonCards = {}     -- seat -> public winning cards in this round
local trumpIndicatorCard -- original public card, retained after dealer exchange
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
  msg.game_type = gameType
  msg.chat_channel = 'table:'..rtcChannel
  if rtc then msg.rtc = rtc:state() end
  for _, p in ipairs(players) do
    push(p, msg)
  end
  for _, w in pairs(watchers) do
    push(w, msg)
  end
end

rtc = require "rtc_table".new {
  channel = rtcChannel,
  now = skynet.now,
  charge = function(uid, key)
    local ok, balance, err = pcall(skynet.call, ".db", "lua", "rtc_charge", uid, key)
    if not ok then return nil, "rtc_billing_failed" end
    return balance, err
  end,
  getBalance = function(uid)
    local ok, balance = pcall(skynet.call, ".db", "lua", "coins_get", uid)
    return ok and balance or nil
  end,
  balance = function(uid, balance)
    for _, p in ipairs(players) do
      if p.uid == uid then push(p, { push="rtc_balance", coins=balance }) end
    end
  end,
  emit = function(state)
    broadcast { push="rtc_state", code=code, rtc=state }
  end,
}
local function rtcTick()
  rtcQueue(function() rtc:tick() end)
  if not rtc.closed then skynet.timeout(100, rtcTick) end
end

local function seatInfos()
  local seats = {}
  for i, p in ipairs(players) do
    local e = st and st.players[i]
    seats[#seats + 1] = {
      name = p.name,
      rtc_uid = not p.bot and p.uid or nil,
      bot = p.bot or false,
      online = p.online ~= false,
      auto = p.auto or false,
      score = e and e.score,
      tricks = e and e.tricks,
      won_cards = wonCards[i] or {},
      decision = e and e.decision,
      hand = e and #e.hand,
      finished = e and e.finished or false,
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

local canPass -- also used by reconnect snapshots

-- Table snapshot; seat = nil for a spectator view (no hand, you = -1).
local function snapshot(seat)
  return {
    push = "snapshot",
    chat_channel = 'table:'..rtcChannel,
    game_type = gameType,
    thousand = st and gameType == "thousand" and engine.view(st) or nil,
    durak = st and gameType == "durak" and engine.view(st) or nil,
    m13 = st and gameType == "mongol13" and {
      last = (function() local a={} for _,c in ipairs(st.last) do a[#a+1]=engine.cardString(c) end return a end)(),
      last_seat = st.lastSeat and st.lastSeat-1,
      opening = st.opening and engine.cardString(st.opening),
      dragon = st.dragon or false,
    } or nil,
    rtc = rtc:state(),
    you = seat and seat - 1 or -1,
    started = started,
    mode = mode,
    code = code,
    size = size,
    stake = stake,
    locked = locked,
    round = roundNo,
    phase = st and st.phase,
    draw = st and st.draw or false,
    winners = st and st.winners and (function() local out={} for _,seat in ipairs(st.winners) do out[#out+1]=seat-1 end return out end)(),
    turn = st and st.turn - 1,
    dealer = st and dealerSeat - 1,
    trump = st and st.trumpCard and engine.cardString(st.trumpCard),
    trump_suit = st and st.trumpSuit,
    trump_taken = st and st.trumpTaken or false,
    trump_indicator = st and gameType == "muushig" and engine.cardString(trumpIndicatorCard or st.trumpCard) or nil,
    stock = st and #st.stock,
    trickNo = st and st.trickNo,
    trick = st and trickWire(),
    seats = seatInfos(),
    hand = (st and started and seat) and handStrings(seat) or nil,
    deadline = st and math.max(0, deadline - skynet.now()) or nil,
    turn_duration = st and turnDuration or nil,
    config = cfg,
    can_pass = st and (st.phase == "deciding" or gameType ~= "muushig") and canPass(seat),
  }
end

-- Whether the seat whose turn it is may pass (mirrors engine.decide).
canPass = function(seat)
  if gameType == "thousand" then return st.stage == "bid" end
  if gameType == "durak" then return st.stage == "add" end
  if gameType == "mongol13" then return st.phase == "playing" and #st.last > 0 end
  local e = st.players[seat or st.turn]
  if not e or e.decision ~= "none" then return false end
  if cfg.rulesVersion < 2 and e.score <= cfg.mustPlayAtScore then return false end
  if cfg.rulesVersion >= 2 and e.passStreak >= 3 then return false end
  local playCount, undecided = 0, 0
  for _, q in ipairs(st.players) do
    if q.decision == "play" then playCount = playCount + 1 end
    if q.decision == "none" then undecided = undecided + 1 end
  end
  return playCount + undecided - 1 >= cfg.minPlayers
end

---------------------------------------------------------------- game flow

local announceTurn -- forward
local endRound
local function sendM13State(actionSeat, cards)
  for i,p in ipairs(players) do
    local msg = snapshot(i); msg.push = gameType == "thousand" and "thousand_state" or gameType == "durak" and "durak_state" or "m13_state"; msg.action_seat = actionSeat and actionSeat-1; msg.cards = cards
    push(p,msg)
  end
  for _,w in pairs(watchers) do
    local msg = snapshot(nil); msg.push = gameType == "thousand" and "thousand_state" or gameType == "durak" and "durak_state" or "m13_state"; msg.action_seat = actionSeat and actionSeat-1; msg.cards = cards
    push(w,msg)
  end
end

local function phaseActive()
  return st and (st.phase == "deciding" or st.phase == "exchanging"
    or st.phase == "navsh" or st.phase == "playing")
end

local function concurrentDecisions()
  return gameType == "muushig" and cfg.rulesVersion >= 2
    and cfg.simultaneousDecisions and st and st.phase == "deciding"
end

local function guard(id, fn)
  return function()
    if started and turnId == id and phaseActive() then fn() end
  end
end

local function startRound(prevScores)
  decisionTurnId, decisionTimers = nil, nil
  roundNo = roundNo + 1
  wonCards = {}
  local passStreaks = {}
  for i = 1, size do
    passStreaks[i] = prevScores and st and st.players[i].passStreak or 0
  end
  st = engine.deal {
    players = size,
    dealer = dealerSeat,
    scores = prevScores,
    passStreaks = passStreaks,
    carry = gameType == "thousand" and st or nil,
    config = cfg,
  }
  trumpIndicatorCard = st.trumpCard
  -- Record the full deal for the replay.
  local allHands, stockStrings = {}, {}
  for i = 1, size do allHands[i] = handStrings(i) end
  for _, c in ipairs(st.stock) do
    stockStrings[#stockStrings + 1] = engine.cardString(c)
  end
  curRound = {
    dealer = dealerSeat - 1,
    trump = st.trumpCard and engine.cardString(st.trumpCard),
    hands = allHands,
    stock = stockStrings,
    scores = scores(),
    actions = {},
    pass_streaks = passStreaks,
  }
  record.rounds[#record.rounds + 1] = curRound

  for i, p in ipairs(players) do
    push(p, {
      push = "round_start",
      round = roundNo,
      dealer = dealerSeat - 1,
      trump = curRound.trump,
      trump_suit = st.trumpSuit,
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
      trump_suit = st.trumpSuit,
      stock = #st.stock,
      scores = curRound.scores,
    })
  end
  if gameType ~= "muushig" then sendM13State() end
  if st.phase == "game_end" then endRound() else announceTurn() end
end

--- Appends one action to the current round's replay record.
local function recordAction(seat, cmd, value)
  curRound.actions[#curRound.actions + 1] =
    { s = seat - 1, c = cmd, v = value }
end

endRound = function()
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
    if gameType ~= "durak" and gameType ~= "thousand" then rtcQueue(function() rtc:close() end) end
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
      draw = st.draw or false,
      loser = st.loser and st.loser-1,
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
      if not st.draw then skynet.call(".db", "lua", "game_result", mode, humans) end
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
      if gameType == "muushig" then
        skynet.send(".db", "lua", "save_replay", uids, record)
      end
    end
    if (gameType == "durak" or gameType == "thousand") and #humans > 0 then return end
    if gameType == "durak" or gameType == "thousand" then rtcQueue(function() rtc:close() end) end
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
  local playedCards = { [seat] = cardStr }
  for _, t in ipairs(st.trick) do
    playedCards[t.seat] = engine.cardString(t.card)
  end

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
    wonCards[winner] = wonCards[winner] or {}
    table.insert(wonCards[winner], playedCards[winner])
    broadcast { push = "trick_end", winner = winner - 1,
      winning_card = playedCards[winner] }
  end
  postAction()
  return nil
end

local function doThousand(seat,action,value,announce)
  local ok,err=engine.action(st,seat,action,value,announce)
  if not ok then return nil,err end
  if action=='play' then
    broadcast {push='played',seat=seat-1,card=value}
    if st.completed then
      local w=st.completed.winner
      totalTricks[w]=(totalTricks[w] or 0)+1
      wonCards[w]=wonCards[w] or {};table.insert(wonCards[w],engine.cardString(st.completed.winningCard))
      broadcast {push='trick_end',winner=w-1,winning_card=engine.cardString(st.completed.winningCard)}
    end
  end
  sendM13State()
  postAction()
  return true
end

local function botAct(decisionSeat)
  local seat = decisionSeat or st.turn
  if gameType == "thousand" then
    local a=engine.hint(st,seat);assert(doThousand(seat,a.action,a.value,a.announce));return
  end
  if gameType == "durak" then
    local a = engine.hint(st,seat)
    assert(engine.action(st,seat,a.action,a.cards,a.target))
    sendM13State(seat,a.cards or {})
    postAction()
    return
  end
  if gameType == "mongol13" then
    local cards = engine.hint(st,seat)
    if #cards > 0 then assert(engine.play(st,seat,cards)) else assert(engine.pass(st,seat)) end
    sendM13State(seat,cards)
    postAction()
    return
  end
  if st.phase == "deciding" then
    local play = bot.decidePlay(st, seat)
    if not engine.decide(st, seat, play) then
      play = true
      engine.decide(st, seat, true)
    end
    recordAction(seat, "d", play)
    broadcast { push = "decided", seat = seat - 1, play = play }
    postAction()
  elseif st.phase == "navsh" then
    -- Trading a weak card for the face-up trump is usually worth it.
    local give = bot.chooseTrumpTake(st, seat)
    if give and engine.takeTrump(st, seat, give) then
      recordAction(seat, "k", give)
      broadcast { push = "trump_taken", seat = seat - 1,
        trump = engine.cardString(st.trumpCard), trump_indicator = engine.cardString(trumpIndicatorCard) }
    else
      engine.skipNavsh(st, seat)
      recordAction(seat, "n", true)
    end
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

--- Humanlike thinking time for a bot turn, in centiseconds: forced moves
--- come fast, open choices take longer, and sometimes a bot just thinks.
local function botThink()
  local lo, hi = T.bot_delay, T.bot_delay_max
  if hi <= lo then return lo end
  local span = hi - lo
  local d
  if st.phase == "playing" then
    local legal = engine.legalCards(st, st.turn)
    if #legal == 1 then
      return lo + math.random(0, span // 4) -- forced card, play it quickly
    end
    d = lo + math.random(0, span)
  else
    d = lo + math.random(span // 4, span) -- decisions take a beat longer
  end
  return d
end

local function onTimeout(decisionSeat)
  local seat = decisionSeat or st.turn
  local p = players[seat]
  p.misses = (p.misses or 0) + 1
  if p.misses >= 2 and not p.auto then
    p.auto = true
    broadcast { push = "seat_state", seat = seat - 1, online = p.online ~= false,
      auto = true }
  end
  botAct(decisionSeat)
end

announceTurn = function()
  if concurrentDecisions() then
    if not decisionTurnId then
      turnId = turnId + 1
      decisionTurnId, decisionTimers = turnId, {}
      turnDuration = T.decide
      deadline = skynet.now() + T.decide
    end
    local id = decisionTurnId
    local remaining = math.max(0, deadline - skynet.now())
    for seat, p in ipairs(players) do
      push(p, { push="turn", game_type=gameType, phase="deciding", seat=st.turn-1,
        deadline=remaining, turn_duration=turnDuration, can_pass=canPass(seat) })
      if st.players[seat].decision == "none" then
        local automated = p.bot or p.auto or p.online == false
        local previous = decisionTimers[seat]
        if not previous or previous.automated ~= automated then
          local token = { automated=automated }
          decisionTimers[seat] = token
          local delay = automated and math.min(remaining, botThink()) or remaining
          skynet.timeout(delay, guard(id, function()
            if concurrentDecisions() and decisionTimers[seat] == token
                and st.players[seat].decision == "none" then
              if automated then botAct(seat) else onTimeout(seat) end
            end
          end))
        end
      end
    end
    for _, w in pairs(watchers) do
      push(w, { push="turn", game_type=gameType, phase="deciding", seat=st.turn-1,
        deadline=remaining, turn_duration=turnDuration, can_pass=false })
    end
    return
  end
  decisionTurnId, decisionTimers = nil, nil
  turnId = turnId + 1
  local id = turnId
  local timeout = st.phase == "deciding" and T.decide
    or (st.phase == "exchanging" or st.phase == "navsh") and T.exchange
    or T.play
  local cur = players[st.turn]
  local automated = cur.bot or cur.auto or cur.online == false
  local actionDelay = automated and math.min(timeout, botThink()) or timeout
  turnDuration = timeout
  deadline = skynet.now() + timeout
  broadcast {
    push = "turn",
    seat = st.turn - 1,
    phase = st.phase,
    deadline = timeout,
    turn_duration = turnDuration,
    can_pass = (st.phase == "deciding" or gameType ~= "muushig") and canPass(),
  }
  if automated then
    skynet.timeout(actionDelay, guard(id, botAct))
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
      chat_channel = 'table:'..rtcChannel,
      game_type = gameType,
      you = i - 1,
      size = size,
      code = code,
      stake = stake,
      seats = seatInfos(),
      config = cfg,
    })
  end
  -- Waiting-room spectators must also learn that the game has started.
  for _, w in pairs(watchers) do push(w, snapshot(nil)) end
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
    chat_channel = 'table:'..rtcChannel,
    code = code,
    mode = mode,
    game_type = gameType,
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

function CMD.chat_access(uid,agent,fd)
  for i,p in ipairs(players) do
    if p.uid==uid and p.agent==agent and p.fd==fd and p.online~=false then return {write=true,moderator=i==1} end
  end
  local w=watchers[uid]
  if w and w.agent==agent and w.fd==fd then return {write=false,moderator=false} end
end

--- Adds a spectator; they get every broadcast but never any hand.
function CMD.watch(p)
  if dissolved then return nil, "not_in_room" end
  watchers[p.uid] = { uid = p.uid, agent = p.agent, fd = p.fd }
  push(watchers[p.uid], snapshot(nil))
  return true
end

function CMD.unwatch(uid)
  watchers[uid] = nil
  return true
end

function CMD.init(opts)
  skynet.timeout(100, rtcTick)
  gameType = opts.game_type or "muushig"
  if gameType == "thousand" then engine = require "rules.thousand"; cfg = engine.defaultConfig() end
  if gameType == "mongol13" then engine = require "rules.mongol13"; cfg = engine.defaultConfig() end
  if gameType == "durak" then
    engine = require "rules.durak"; cfg = engine.defaultConfig()
    for k,v in pairs(opts.game_options or {}) do cfg[k]=v end
  end
  mode = opts.mode
  size = opts.size
  code = opts.code
  skynet.send('.hub','lua','chat_register',skynet.self(),'table:'..rtcChannel)
  stake = opts.stake or 0
  locked = opts.locked or false
  for _, p in ipairs(opts.players) do
    players[#players + 1] = {
      uid = p.uid, name = p.name, agent = p.agent, fd = p.fd,
      bot = p.bot or false, online = not p.bot, misses = 0,
    }
  end
  if gameType == "muushig" and (mode == "quick" or #players == size) then
    startGame()
  else
    broadcast { push = "room_update", code = code, size = size, stake = stake, locked = locked, seats = seatInfos() }
    if mode == "bot" then
      local nextBot = 0
      local function fillNext()
        if started or #players >= size then return end
        nextBot = nextBot + 1
        players[#players + 1] = {
          bot = true, online = false, misses = 0,
          name = opts.bot_names[nextBot] or ("Bot " .. nextBot),
        }
        broadcast { push = "room_update", code = code, size = size,
          stake = stake, locked = locked, seats = seatInfos() }
        if #players == size then startGame()
        else skynet.timeout(T.bot_join_interval, fillNext) end
      end
      skynet.timeout(T.bot_join_grace, fillNext)
    end
  end
  return true
end

function CMD.join(p)
  if dissolved then return nil, "not_in_room" end
  -- One game is one sitting: once play starts, nobody new sits down.
  if started then return nil, "already_started" end
  if #players >= size then return nil, "room_full" end
  watchers[p.uid] = nil
  players[#players + 1] = {
    uid = p.uid, name = p.name, agent = p.agent, fd = p.fd,
    bot = false, online = true, misses = 0,
  }
  broadcast { push = "room_update", code = code, size = size, stake = stake, locked = locked, seats = seatInfos() }
  push(players[#players], snapshot(#players))
  if gameType == "muushig" and #players == size then startGame() end
  return true
end

function CMD.dissolve(uid)
  if dissolved then return nil, "not_in_room" end
  if started then return nil, "already_started" end
  if mode ~= "friend" or not players[1] or players[1].uid ~= uid then
    return nil, "not_host"
  end
  dissolved = true
  local uids = {}
  for _, p in ipairs(players) do
    if p.uid then
      uids[#uids + 1] = p.uid
      -- Entry fees are escrowed until play starts.
      if stake > 0 then skynet.send(".db", "lua", "coins_add", p.uid, stake) end
    end
  end
  broadcast { push = "room_dissolved", code = code }
  rtcQueue(function() rtc:close() end)
  skynet.call(".hub", "lua", "room_closed", skynet.self(), uids)
  skynet.timeout(10, function() skynet.exit() end)
  return true
end

function CMD.leave(uid)
  if dissolved then return nil, "not_in_room" end
  rtcQueue(function() rtc:remove(uid) end)
  if (gameType == "durak" or gameType == "thousand") and st and st.phase == "game_end" then started=false; st=nil end
  if started then
    -- Leaving mid-game forfeits: the seat is handed to a bot for good,
    -- the leaver takes a recorded loss, and is free to join a new game.
    local seat, p = nil, nil
    for i, q in ipairs(players) do
      if q.uid == uid then seat, p = i, q break end
    end
    if not seat then return nil, "not_in_room" end
    skynet.send(".db", "lua", "game_result", mode, {
      { uid = uid, win = gameType == "durak" and st.players[seat].finished or false, tricks = totalTricks[seat] or 0 },
    })
    players[seat] = { bot = true, name = p.name, misses = 0 }
    skynet.send(".hub", "lua", "left_room", uid)
    if gameType == "durak" or gameType == "thousand" then
      local hasHuman=false
      for _,q in ipairs(players) do if q.uid then hasHuman=true end end
      if not hasHuman then
        rtcQueue(function() rtc:close() end)
        skynet.send(".hub", "lua", "room_closed", skynet.self(), {})
        skynet.timeout(10,function() skynet.exit() end)
        return true
      end
    end
    -- Everyone sees the takeover; each viewer gets their own snapshot.
    for i, q in ipairs(players) do
      push(q, snapshot(i))
    end
    for _, w in pairs(watchers) do
      push(w, snapshot(nil))
    end
    if phaseActive() and (st.turn == seat or concurrentDecisions()) then
      announceTurn() -- the bot takes over this turn immediately
    end
    return true
  end
  for i, p in ipairs(players) do
    if p.uid == uid then
      table.remove(players, i)
      break
    end
  end
  skynet.send(".hub", "lua", "left_room", uid)
  if #players == 0 then
    rtcQueue(function() rtc:close() end)
    skynet.send(".hub", "lua", "room_closed", skynet.self(), {})
    skynet.timeout(10, function() skynet.exit() end)
  else
    broadcast { push = "room_update", code = code, size = size, stake = stake, locked = locked, seats = seatInfos() }
    for i,p in ipairs(players) do push(p,snapshot(i)) end
  end
  return true
end

--- Host (first seat) starts a friend room early; empty seats become bots.
function CMD.start(uid)
  if dissolved then return nil, "not_in_room" end
  if (gameType == "durak" or gameType == "thousand") and st and st.phase == "game_end" then
    if not players[1] or players[1].uid ~= uid then return nil,"not_host" end
    started=false; st=nil; roundNo=0; record={rounds={}}; totalTricks={}
  end
  if started then return nil, "already_started" end
  if not players[1] or players[1].uid ~= uid then return nil, "not_host" end
  if gameType ~= "muushig" then
    if gameType == "thousand" and #players ~= 3 then return nil,"thousand_need_players" end
    if #players < 2 then return nil, "m13_need_players" end
    size = #players
    startGame()
    return true
  end
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
    if concurrentDecisions() then announceTurn() end
    return true
  end
  if not started then return nil, "not_started" end

  p.misses = 0
  if gameType == "thousand" then
    if msg.cmd ~= "thousand_action" then return nil,"bad_cmd" end
    return doThousand(seat,msg.action,msg.value,msg.announce)
  end
  if gameType == "durak" then
    if msg.cmd ~= "durak_action" then return nil,"bad_cmd" end
    local target = type(msg.target) == "number" and msg.target+1 or nil
    local ok,err = engine.action(st,seat,msg.action,msg.cards,target)
    if not ok then return nil,err end
    sendM13State(seat,msg.cards or {})
    postAction()
    return true
  end
  if gameType == "mongol13" then
    local ok, err
    if msg.cmd == "play_card" then ok,err=engine.play(st,seat,msg.cards)
    elseif msg.cmd == "decide" and msg.play == false then ok,err=engine.pass(st,seat)
    else return nil,"bad_cmd" end
    if not ok then return nil,err end
    sendM13State(seat,msg.cards or {})
    postAction()
    return true
  end
  local err
  if msg.cmd == "decide" then
    local ok, e = engine.decide(st, seat, msg.play and true or false)
    err = not ok and e or nil
    if not err then
      recordAction(seat, "d", msg.play and true or false)
      broadcast { push = "decided", seat = seat - 1, play = msg.play and true or false }
      postAction()
    end
  elseif msg.cmd == "take_trump" then
    local ok, e = engine.takeTrump(st, seat, msg.card)
    err = not ok and e or nil
    if not err then
      recordAction(seat, "k", msg.card)
      broadcast { push = "trump_taken", seat = seat - 1,
        trump = engine.cardString(st.trumpCard), trump_indicator = engine.cardString(trumpIndicatorCard) }
      push(p, { push = "exchange_result", hand = handStrings(seat) })
      postAction()
    end
  elseif msg.cmd == "skip_navsh" then
    local ok, e = engine.skipNavsh(st, seat)
    err = not ok and e or nil
    if not err then
      recordAction(seat, "n", true)
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

-- Bind each grant to the current seat AND current socket, including renewals.
-- Spectators and superseded login sessions cannot obtain a grant.
function CMD.rtc_grant(uid, agent, fd)
  local _, p = seatOf(uid)
  if not p or p.bot or not p.online or p.agent ~= agent or p.fd ~= fd
      or (st and st.phase == "game_end") then
    return nil, "rtc_not_seated"
  end
  if type(uid) ~= "number" or uid < 1 or uid > 0xffffffff then
    return nil, "rtc_unavailable"
  end
  return { channel = rtcChannel, uid = uid, code = code }
end

-- Never accept client-selected payer, elapsed time, price or another room.
function CMD.rtc_control(uid, agent, fd, roomCode, action, msg)
  return rtcQueue(function()
    local grant, err = CMD.rtc_grant(uid, agent, fd)
    if not grant or roomCode ~= code then return nil, err or "rtc_not_seated" end
    if action == "start" then return rtc:start() end
    if action == "prepare" then return rtc:prepare(uid, msg.consent == true) end
    if action == "state" then
      if type(msg.joined) ~= "boolean" or type(msg.camera) ~= "boolean"
          or type(msg.microphone) ~= "boolean" then return nil, "bad_request" end
      if not rtc.enabled then return nil, "rtc_unavailable" end
      return rtc:update(uid, msg.joined, msg.microphone, msg.camera, msg.video_epoch)
    end
    return nil, "bad_cmd"
  end)
end

function CMD.rejoin(uid, agent, fd)
  local seat, p = seatOf(uid)
  if not seat then return nil, "not_in_room" end
  rtcQueue(function() rtc:remove(uid) end)
  p.agent, p.fd = agent, fd
  p.online = true
  p.auto = false
  p.misses = 0
  broadcast { push = "seat_state", seat = seat - 1, online = true, auto = false }
  push(p, snapshot(seat))
  if started and phaseActive() and (st.turn == seat or concurrentDecisions()) then
    announceTurn() -- restart this turn's timer as a human turn
  end
  return true
end

function CMD.offline(uid)
  local seat, p = seatOf(uid)
  if not seat then return true end
  if not started then return CMD.leave(uid) end
  rtcQueue(function() rtc:remove(uid) end)
  p.online = false
  p.agent, p.fd = nil, nil
  broadcast { push = "seat_state", seat = seat - 1, online = false,
    auto = p.auto or false }
  if phaseActive() and (st.turn == seat or concurrentDecisions()) then
    announceTurn() -- hand the current turn to the bot
  end
  return true
end

skynet.start(function()
  math.randomseed()
  T.decide = tonumber(skynet.getenv "timeout_decide") or 1500
  T.exchange = tonumber(skynet.getenv "timeout_exchange") or 1500
  T.play = tonumber(skynet.getenv "timeout_play") or 1500
  T.bot_delay = tonumber(skynet.getenv "bot_delay") or 300
  T.bot_delay_max = tonumber(skynet.getenv "bot_delay_max") or 600
  T.bot_join_grace = tonumber(skynet.getenv "bot_join_grace") or 3000
  T.bot_join_interval = tonumber(skynet.getenv "bot_join_interval") or 500
  T.round_pause = tonumber(skynet.getenv "round_pause") or 500
  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
end)
