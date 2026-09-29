--- Server-side bot, a port of the Dart NormalBot (app/lib/bot/bot.dart).
-- Used for filling tables and for auto-play (timeouts / disconnects).

local engine = require "rules.engine"

local M = {}

local function suitOf(c) return c // 16 end
local function rankOf(c) return c % 16 end

--- Phase deciding: true to play, false to (try to) pass.
function M.decidePlay(state, seat)
  local strength = 0
  for _, c in ipairs(state.players[seat].hand) do
    if suitOf(c) == state.trumpSuit then strength = strength + 2 end
    if rankOf(c) >= 13 then strength = strength + 1 end -- K, A of any suit
  end
  return strength >= 3
end

--- Dealer's trade for the face-up trump: the card to give up, or nil.
--- Taking a trump for our weakest off-trump card is always good.
function M.chooseTrumpTake(state, seat)
  local worst
  for _, c in ipairs(state.players[seat].hand) do
    if suitOf(c) ~= state.trumpSuit then
      if not worst or rankOf(c) < rankOf(worst) then worst = c end
    end
  end
  if worst then return engine.cardString(worst) end
  -- All trumps: only upgrade the lowest one.
  local low
  for _, c in ipairs(state.players[seat].hand) do
    if not low or rankOf(c) < rankOf(low) then low = c end
  end
  if low and rankOf(state.trumpCard) > rankOf(low) then
    return engine.cardString(low)
  end
  return nil
end

--- Phase exchanging: list of card strings to discard.
function M.chooseExchange(state, seat)
  -- Discard weak off-trump cards (below queen), lowest first.
  local weak = {}
  for _, c in ipairs(state.players[seat].hand) do
    if suitOf(c) ~= state.trumpSuit and rankOf(c) < 12 then
      weak[#weak + 1] = c
    end
  end
  table.sort(weak, function(a, b) return rankOf(a) < rankOf(b) end)
  local limit = math.min(state.config.maxExchange, #state.stock, #weak)
  local out = {}
  for i = 1, limit do out[i] = engine.cardString(weak[i]) end
  return out
end

-- Whether playing `card` now would beat everything in the current trick.
local function wouldWin(state, card)
  local trumpSuit = state.trumpSuit
  local lead = suitOf(state.trick[1].card)
  local topTrump, topLead = nil, 0
  for _, t in ipairs(state.trick) do
    if suitOf(t.card) == trumpSuit then
      if not topTrump or rankOf(t.card) > topTrump then
        topTrump = rankOf(t.card)
      end
    elseif suitOf(t.card) == lead and rankOf(t.card) > topLead then
      topLead = rankOf(t.card)
    end
  end
  if suitOf(card) == trumpSuit then
    return not topTrump or rankOf(card) > topTrump
  end
  return not topTrump and suitOf(card) == lead and rankOf(card) > topLead
end

--- Phase playing: one card string out of legalCards.
function M.choosePlay(state, seat)
  local legalStrs = engine.legalCards(state, seat)
  local legal = {}
  for i, s in ipairs(legalStrs) do legal[i] = engine.parseCard(s) end
  local trumpSuit = state.trumpSuit

  -- Cheapest card first: low ranks before high, non-trumps before trumps.
  local function cost(c)
    return (suitOf(c) == trumpSuit and 100 or 0) + rankOf(c)
  end

  if #state.trick == 0 then
    -- Lead an ace if we have one, otherwise our cheapest card.
    local best
    for _, c in ipairs(legal) do
      if rankOf(c) == 14 then return engine.cardString(c) end
      if not best or cost(c) < cost(best) then best = c end
    end
    return engine.cardString(best)
  end

  -- Take the trick with the cheapest winning card, else dump the cheapest.
  local bestWin, bestAny
  for _, c in ipairs(legal) do
    if wouldWin(state, c) and (not bestWin or cost(c) < cost(bestWin)) then
      bestWin = c
    end
    if not bestAny or cost(c) < cost(bestAny) then bestAny = c end
  end
  return engine.cardString(bestWin or bestAny)
end

return M
