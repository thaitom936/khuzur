--- Runs the shared rule test cases in testdata/rules/ against the Lua engine.
-- Usage: lua server/test/run_rules.lua  (from the repo root)
--
-- Case file format (seats are 0-based in JSON, 1-based in the engine):
-- {
--   "name": "...", "players": N, "dealer": 0,
--   "config": {...overrides...}, "scores": [..]?,
--   "hands": [["7C",...], ...], "trump": "AS", "stock": ["7D", ...],
--   "steps": [
--     {"decide":   {"seat":1, "play":true},        "error": "..."?},
--     {"exchange": {"seat":1, "cards":["7C"]},     "error": "..."?},
--     {"play":     {"seat":1, "card":"7C"},        "error": "..."?},
--     {"legal":    {"seat":2, "cards":["QC","KC"]}},
--     {"expect":   {"phase":"playing", "turn":2, "trickNo":1,
--                   "tricks":[...], "scores":[...], "winners":[...],
--                   "hand":{"seat":0, "cards":[...]}}}
--   ]
-- }
-- Action steps with "error" must fail with exactly that error id.

package.path = package.path .. ";server/test/?.lua;server/lualib/?.lua"
local json = require "json"
local engine = require "rules.engine"

local failures = 0
local cases = 0

local function fail(name, stepNo, msg)
  failures = failures + 1
  io.write(("FAIL %s step %d: %s\n"):format(name, stepNo, msg))
end

local function listEq(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do
    if a[i] ~= b[i] then return false end
  end
  return true
end

-- Sorts card strings by card value, matching the engine's output order.
local function sorted(list)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  table.sort(out, function(a, b) return engine.parseCard(a) < engine.parseCard(b) end)
  return out
end

local function show(list)
  return "[" .. table.concat(list, ",") .. "]"
end

local function handStrings(state, seat)
  local out = {}
  local cards = {}
  for i, c in ipairs(state.players[seat].hand) do cards[i] = c end
  table.sort(cards)
  for i, c in ipairs(cards) do out[i] = engine.cardString(c) end
  return out
end

local function checkExpect(state, exp, name, stepNo)
  if exp.phase and state.phase ~= exp.phase then
    fail(name, stepNo, "phase " .. state.phase .. " ~= " .. exp.phase)
  end
  if exp.turn and state.turn ~= exp.turn + 1 then
    fail(name, stepNo, "turn " .. state.turn - 1 .. " ~= " .. exp.turn)
  end
  if exp.trickNo and state.trickNo ~= exp.trickNo then
    fail(name, stepNo, "trickNo " .. state.trickNo .. " ~= " .. exp.trickNo)
  end
  if exp.trump then
    local got = engine.cardString(state.trumpCard)
    if got ~= exp.trump then
      fail(name, stepNo, "trump " .. got .. " ~= " .. exp.trump)
    end
  end
  if exp.tricks then
    for seat, want in ipairs(exp.tricks) do
      local got = state.players[seat].tricks
      if got ~= want then
        fail(name, stepNo, ("tricks[%d] %d ~= %d"):format(seat - 1, got, want))
      end
    end
  end
  if exp.scores then
    for seat, want in ipairs(exp.scores) do
      local got = state.players[seat].score
      if got ~= want then
        fail(name, stepNo, ("scores[%d] %d ~= %d"):format(seat - 1, got, want))
      end
    end
  end
  if exp.winners then
    local got = {}
    for i, s in ipairs(state.winners or {}) do got[i] = s - 1 end
    if not listEq(got, exp.winners) then
      fail(name, stepNo, "winners " .. show(got) .. " ~= " .. show(exp.winners))
    end
  end
  if exp.hand then
    local got = handStrings(state, exp.hand.seat + 1)
    local want = sorted(exp.hand.cards)
    if not listEq(got, want) then
      fail(name, stepNo, "hand " .. show(got) .. " ~= " .. show(want))
    end
  end
end

local function runCase(case)
  cases = cases + 1
  local name = case.name
  local state = engine.newRound {
    players = case.players,
    dealer = case.dealer + 1,
    hands = case.hands,
    trump = case.trump,
    stock = case.stock,
    config = case.config,
    scores = case.scores,
  }

  for stepNo, step in ipairs(case.steps) do
    if step.expect then
      checkExpect(state, step.expect, name, stepNo)
    elseif step.legal then
      local got = engine.legalCards(state, step.legal.seat + 1)
      local want = sorted(step.legal.cards)
      if not listEq(got, want) then
        fail(name, stepNo, "legal " .. show(got) .. " ~= " .. show(want))
      end
    else
      local ok, err
      if step.decide then
        ok, err = engine.decide(state, step.decide.seat + 1, step.decide.play)
      elseif step.take then
        ok, err = engine.takeTrump(state, step.take.seat + 1, step.take.card)
      elseif step.skip then
        ok, err = engine.skipNavsh(state, step.skip.seat + 1)
      elseif step.exchange then
        ok, err = engine.exchange(state, step.exchange.seat + 1, step.exchange.cards)
      elseif step.play then
        ok, err = engine.play(state, step.play.seat + 1, step.play.card)
      else
        fail(name, stepNo, "unknown step")
      end
      if step.error then
        if ok then
          fail(name, stepNo, "expected error " .. step.error .. ", got success")
        elseif err ~= step.error then
          fail(name, stepNo, "error " .. tostring(err) .. " ~= " .. step.error)
        end
      elseif not ok then
        fail(name, stepNo, "unexpected error: " .. tostring(err))
      end
    end
  end
end

local dir = "testdata/rules"
local files = {}
local p = io.popen('ls "' .. dir .. '"/*.json 2>/dev/null')
for line in p:lines() do files[#files + 1] = line end
p:close()
assert(#files > 0, "no case files found in " .. dir .. " (run from the repo root)")
table.sort(files)

for _, path in ipairs(files) do
  local f = assert(io.open(path))
  local case = json.decode(f:read("a"))
  f:close()
  case.name = case.name or path
  runCase(case)
end

io.write(("%d cases, %d failures\n"):format(cases, failures))
os.exit(failures == 0 and 0 or 1)
