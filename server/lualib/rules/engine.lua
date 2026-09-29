--- Muushig rules engine (pure Lua, no skynet dependency).
--
-- Cards are encoded as integers: suit * 16 + rank,
-- suit: 0=clubs(C) 1=diamonds(D) 2=hearts(H) 3=spades(S),
-- rank: 7..14 (11=J 12=Q 13=K 14=A).
-- String form is "<rank><suit>", e.g. "7C", "TD", "AH".
--
-- Seats are 1-based inside the engine.
-- All mutating calls return `true` on success or `nil, err` with the state
-- unchanged, where err is a stable error id used by the shared test cases.

local M = {}

local RANK_CHARS = { [7]="7", [8]="8", [9]="9", [10]="T", [11]="J", [12]="Q", [13]="K", [14]="A" }
local CHAR_RANKS = {}
for r, c in pairs(RANK_CHARS) do CHAR_RANKS[c] = r end
local SUIT_CHARS = { [0]="C", [1]="D", [2]="H", [3]="S" }
local CHAR_SUITS = { C=0, D=1, H=2, S=3 }

function M.parseCard(s)
  local rank = CHAR_RANKS[s:sub(1, 1)]
  local suit = CHAR_SUITS[s:sub(2, 2)]
  assert(rank and suit, "bad card string: " .. tostring(s))
  return suit * 16 + rank
end

function M.cardString(c)
  return RANK_CHARS[c % 16] .. SUIT_CHARS[c // 16]
end

local function suitOf(c) return c // 16 end
local function rankOf(c) return c % 16 end

function M.defaultConfig()
  return {
    startScore = 15,
    noTrickPenalty = 5,
    decidePhase = true,    -- deal, then each player opts in or passes
    exchangePhase = true,
    mustFollowSuit = true,
    mustBeat = false,      -- follow suit, no need to beat
    mustTrump = true,
    mustOvertrump = false, -- any trump will do when void
    mustPlayAtScore = 1,
    minPlayers = 2,
    dealerTakesTrump = true, -- the dealer may trade a card for the face-up trump
    maxExchange = 5,
  }
end

--- Creates the state for one round.
-- args: { players, dealer, hands = {{cardstr,...},...}, trump = cardstr,
--         stock = {cardstr,...}, config?, scores? }
function M.newRound(args)
  local config = M.defaultConfig()
  for k, v in pairs(args.config or {}) do config[k] = v end
  local n = args.players
  assert(n and n >= 2 and n <= 5, "players must be 2..5")
  assert(#args.hands == n, "hands must match player count")

  local state = {
    config = config,
    numPlayers = n,
    dealer = args.dealer,
    phase = "deciding",
    trumpCard = M.parseCard(args.trump),
    stock = {},
    players = {},
    trick = {},
    trickNo = 0,
    turn = args.dealer % n + 1,
    winners = nil,
  }
  state.trumpSuit = suitOf(state.trumpCard)

  local seen = { [state.trumpCard] = "trump" }
  for seat = 1, n do
    local hand = {}
    for _, s in ipairs(args.hands[seat]) do
      local c = M.parseCard(s)
      assert(not seen[c], "duplicate card: " .. s)
      seen[c] = true
      hand[#hand + 1] = c
    end
    assert(#hand == 5, "each hand must have 5 cards")
    state.players[seat] = {
      hand = hand,
      score = args.scores and args.scores[seat] or config.startScore,
      decision = "none",
      tricks = 0,
      exchanged = false,
    }
  end
  for _, s in ipairs(args.stock or {}) do
    local c = M.parseCard(s)
    assert(not seen[c], "duplicate card: " .. s)
    seen[c] = true
    state.stock[#state.stock + 1] = c
  end

  if not config.decidePhase then
    -- Everyone plays; skip straight to exchanging (or playing).
    for _, p in ipairs(state.players) do
      p.decision = "play"
    end
    if config.exchangePhase then
      state.phase = "exchanging"
      -- turn is already the seat left of the dealer.
    else
      M.startPlaying(state)
    end
  end
  return state
end

function M.startPlaying(state)
  state.phase = "playing"
  state.trickNo = 1
  state.trick = {}
  local s = state.dealer % state.numPlayers + 1
  for _ = 1, state.numPlayers do
    if state.players[s].decision == "play" then break end
    s = s % state.numPlayers + 1
  end
  state.turn = s
end

--- Shuffles the 32-card deck and creates a round: 5 cards each, one
--- face-up trump, the rest is stock.
-- args: { players, dealer, scores?, config?, random? (fn like math.random) }
function M.deal(args)
  local rnd = args.random or math.random
  local deck = {}
  for suit = 0, 3 do
    for rank = 7, 14 do deck[#deck + 1] = suit * 16 + rank end
  end
  for i = #deck, 2, -1 do
    local j = rnd(i)
    deck[i], deck[j] = deck[j], deck[i]
  end

  local i = 0
  local function draw()
    i = i + 1
    return M.cardString(deck[i])
  end
  local hands = {}
  for seat = 1, args.players do
    local hand = {}
    for _ = 1, 5 do hand[#hand + 1] = draw() end
    hands[seat] = hand
  end
  local trump = draw()
  local stock = {}
  while i < #deck do stock[#stock + 1] = draw() end

  return M.newRound {
    players = args.players,
    dealer = args.dealer,
    hands = hands,
    trump = trump,
    stock = stock,
    config = args.config,
    scores = args.scores,
  }
end

local function nextSeat(state, seat) return seat % state.numPlayers + 1 end

-- First seat matching pred, scanning clockwise from `start` inclusive.
local function findSeat(state, start, pred)
  local s = start
  for _ = 1, state.numPlayers do
    if pred(state.players[s]) then return s end
    s = nextSeat(state, s)
  end
  return nil
end

local function playCount(state)
  local n = 0
  for _, p in ipairs(state.players) do
    if p.decision == "play" then n = n + 1 end
  end
  return n
end

local function checkTurn(state, phase, seat)
  if state.phase ~= phase then return nil, "wrong_phase" end
  if state.turn ~= seat then return nil, "not_your_turn" end
  return true
end

--- Phase "deciding": choose to play (true) or pass (false).
function M.decide(state, seat, play)
  local ok, err = checkTurn(state, "deciding", seat)
  if not ok then return nil, err end
  local p = state.players[seat]

  if not play then
    if p.score <= state.config.mustPlayAtScore then
      return nil, "must_play_low_score"
    end
    local undecidedAfter = -1 -- exclude current player
    for _, q in ipairs(state.players) do
      if q.decision == "none" then undecidedAfter = undecidedAfter + 1 end
    end
    if playCount(state) + undecidedAfter < state.config.minPlayers then
      return nil, "must_play_min_players"
    end
  end
  p.decision = play and "play" or "pass"

  local nxt = findSeat(state, nextSeat(state, seat), function(q) return q.decision == "none" end)
  if nxt then
    state.turn = nxt
  elseif playCount(state) == 0 then
    state.phase = "round_end" -- everyone passed (only possible when minPlayers == 0)
  else
    state.phase = "exchanging"
    state.turn = findSeat(state, state.dealer % state.numPlayers + 1,
      function(q) return q.decision == "play" end)
  end
  return true
end

--- Dealer privilege (庄可以换翻的主牌): on the dealer's exchange turn,
--- trade any one hand card for the face-up trump card. The trump SUIT
--- stays what was flipped at the deal. Once per round, before the
--- dealer's stock exchange.
function M.takeTrump(state, seat, cardStr)
  local ok, err = checkTurn(state, "exchanging", seat)
  if not ok then return nil, err end
  if not state.config.dealerTakesTrump then return nil, "not_allowed" end
  if seat ~= state.dealer then return nil, "not_dealer" end
  if state.trumpTaken then return nil, "already_taken" end
  local card = M.parseCard(cardStr)
  local p = state.players[seat]
  for i, c in ipairs(p.hand) do
    if c == card then
      p.hand[i] = state.trumpCard
      state.trumpCard = card
      state.trumpTaken = true
      return true
    end
  end
  return nil, "card_not_in_hand"
end

--- Phase "exchanging": discard `cards` (list of card strings, may be empty)
--- and draw the same number from the stock.
function M.exchange(state, seat, cards)
  local ok, err = checkTurn(state, "exchanging", seat)
  if not ok then return nil, err end
  local p = state.players[seat]

  if #cards > state.config.maxExchange or #cards > #state.stock then
    return nil, "exchange_too_many"
  end
  -- Validate before mutating (duplicates in the request also fail here).
  local picked = {}
  for _, s in ipairs(cards) do
    local c = M.parseCard(s)
    if picked[c] then return nil, "card_not_in_hand" end
    local found = false
    for _, h in ipairs(p.hand) do
      if h == c then found = true break end
    end
    if not found then return nil, "card_not_in_hand" end
    picked[c] = true
  end
  local newHand = {}
  for _, h in ipairs(p.hand) do
    if not picked[h] then newHand[#newHand + 1] = h end
  end
  for _ = 1, #cards do
    newHand[#newHand + 1] = table.remove(state.stock, 1)
  end
  p.hand = newHand
  p.exchanged = true

  local nxt = findSeat(state, nextSeat(state, seat),
    function(q) return q.decision == "play" and not q.exchanged end)
  if nxt then
    state.turn = nxt
  else
    M.startPlaying(state)
  end
  return true
end

-- Highest trump in the current trick, or nil.
local function trickTrump(state)
  local best = nil
  for _, t in ipairs(state.trick) do
    if suitOf(t.card) == state.trumpSuit then
      if not best or rankOf(t.card) > rankOf(best) then best = t.card end
    end
  end
  return best
end

--- Legal cards for `seat` in phase "playing", sorted, as card strings.
function M.legalCards(state, seat)
  local cfg = state.config
  local hand = state.players[seat].hand
  local result

  if #state.trick == 0 then
    result = hand
  else
    local lead = suitOf(state.trick[1].card)
    local topTrump = trickTrump(state)
    local followers, trumps = {}, {}
    for _, c in ipairs(hand) do
      if suitOf(c) == lead then followers[#followers + 1] = c end
      if suitOf(c) == state.trumpSuit then trumps[#trumps + 1] = c end
    end

    if cfg.mustFollowSuit and #followers > 0 then
      result = followers
      if cfg.mustBeat then
        -- The card to beat within the lead suit: irrelevant if the trick has
        -- already been trumped by another suit (a lead-suit card can't win).
        local toBeat
        if lead == state.trumpSuit then
          toBeat = topTrump
        elseif not topTrump then
          for _, t in ipairs(state.trick) do
            if suitOf(t.card) == lead and (not toBeat or rankOf(t.card) > rankOf(toBeat)) then
              toBeat = t.card
            end
          end
        end
        if toBeat then
          local beaters = {}
          for _, c in ipairs(followers) do
            if rankOf(c) > rankOf(toBeat) then beaters[#beaters + 1] = c end
          end
          if #beaters > 0 then result = beaters end
        end
      end
    elseif cfg.mustTrump and #trumps > 0 then
      result = trumps
      if cfg.mustOvertrump and topTrump then
        local over = {}
        for _, c in ipairs(trumps) do
          if rankOf(c) > rankOf(topTrump) then over[#over + 1] = c end
        end
        if #over > 0 then result = over end
      end
    else
      result = hand
    end
  end

  local out = {}
  for _, c in ipairs(result) do out[#out + 1] = c end
  table.sort(out)
  local strs = {}
  for i, c in ipairs(out) do strs[i] = M.cardString(c) end
  return strs
end

local function trickWinner(state)
  local lead = suitOf(state.trick[1].card)
  local ref = state.trumpSuit
  local topTrump = trickTrump(state)
  if not topTrump then ref = lead end
  local bestSeat, bestRank
  for _, t in ipairs(state.trick) do
    if suitOf(t.card) == ref and (not bestRank or rankOf(t.card) > bestRank) then
      bestSeat, bestRank = t.seat, rankOf(t.card)
    end
  end
  return bestSeat
end

local function settle(state)
  local cfg = state.config
  for _, p in ipairs(state.players) do
    if p.decision == "play" then
      if p.tricks > 0 then
        p.score = p.score - p.tricks
      else
        p.score = p.score + cfg.noTrickPenalty
      end
    end
  end
  state.phase = "round_end"
  local minScore
  for _, p in ipairs(state.players) do
    if p.score <= 0 then state.phase = "game_end" end
    if not minScore or p.score < minScore then minScore = p.score end
  end
  if state.phase == "game_end" then
    state.winners = {}
    for seat, p in ipairs(state.players) do
      if p.score == minScore then state.winners[#state.winners + 1] = seat end
    end
  end
end

--- Phase "playing": play one card (card string).
function M.play(state, seat, cardStr)
  local ok, err = checkTurn(state, "playing", seat)
  if not ok then return nil, err end
  local p = state.players[seat]
  local card = M.parseCard(cardStr)

  local inHand = false
  for _, c in ipairs(p.hand) do
    if c == card then inHand = true break end
  end
  if not inHand then return nil, "card_not_in_hand" end
  local legal = false
  for _, s in ipairs(M.legalCards(state, seat)) do
    if s == cardStr then legal = true break end
  end
  if not legal then return nil, "illegal_card" end

  for i, c in ipairs(p.hand) do
    if c == card then table.remove(p.hand, i) break end
  end
  state.trick[#state.trick + 1] = { seat = seat, card = card }

  if #state.trick == playCount(state) then
    local winner = trickWinner(state)
    state.players[winner].tricks = state.players[winner].tricks + 1
    if state.trickNo == 5 then
      settle(state)
    else
      state.trickNo = state.trickNo + 1
      state.trick = {}
      state.turn = winner
    end
  else
    state.turn = findSeat(state, nextSeat(state, seat),
      function(q) return q.decision == "play" end)
  end
  return true
end

return M
