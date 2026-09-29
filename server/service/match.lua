--- Quick-match queues. One queue per table size; when a queue has enough
--- players a room starts, and anyone waiting longer than match_fill_after
--- gets a table filled up with bots.
local skynet = require "skynet"
require "skynet.manager" -- for skynet.register

local queues = {} -- "<size>:<stake>" -> list of {uid, name, agent, fd, since}
local queued = {} -- uid -> queue key

local CMD = {}

local fill_after
local default_size
local min_humans -- humans required before a table may start (bots fill the rest)

local function startRoom(size, stake, players)
  for _, p in ipairs(players) do
    queued[p.uid] = nil
  end
  local bots = size - #players
  for i = 1, bots do
    players[#players + 1] = { bot = true, name = "Bot " .. i }
  end
  local room = skynet.call(".hub", "lua", "create_room", "quick", size,
    players, stake)
  for _, p in ipairs(players) do
    if p.agent then
      skynet.send(p.agent, "lua", "push", p.fd,
        { push = "match_found", room = skynet.address(room) })
    end
  end
end

-- Tells everyone in a queue how many players they are still waiting for.
local function notifyQueue(q)
  local need = math.min(q.size, min_humans)
  if q.stake > 0 and need < 2 then need = 2 end
  for _, p in ipairs(q) do
    skynet.send(p.agent, "lua", "push", p.fd,
      { push = "queue_update", waiting = #q, need = need })
  end
end

--- The stake was already escrowed by the agent before enqueueing.
function CMD.enqueue(player, size, stake)
  size = size or default_size
  stake = stake or 0
  if size < 2 or size > 5 then return nil, "bad_size" end
  if queued[player.uid] then return nil, "already_queued" end
  local key = size .. ":" .. stake
  local q = queues[key]
  if not q then
    q = { size = size, stake = stake }
    queues[key] = q
  end
  player.since = skynet.now()
  q[#q + 1] = player
  queued[player.uid] = key
  if #q >= size then
    local players = {}
    for i = 1, size do players[i] = table.remove(q, 1) end
    startRoom(size, stake, players)
  else
    notifyQueue(q)
  end
  return true
end

--- Removes a queued player and refunds their escrowed stake.
function CMD.remove(uid)
  local key = queued[uid]
  if not key then return true end
  queued[uid] = nil
  local q = queues[key]
  for i, p in ipairs(q) do
    if p.uid == uid then
      table.remove(q, i)
      if q.stake > 0 then
        skynet.send(".db", "lua", "coins_add", uid, q.stake)
      end
      notifyQueue(q)
      break
    end
  end
  return true
end

local function tick()
  while true do
    skynet.sleep(100)
    for _, q in pairs(queues) do
      -- A table starts once it has enough humans (min_humans, capped by
      -- the table size); coin tables additionally need two humans so the
      -- pot means something. Only then are the empty seats given to bots.
      local need = math.min(q.size, min_humans)
      if q.stake > 0 and need < 2 then need = 2 end
      if #q >= need and skynet.now() - q[1].since >= fill_after then
        local players = {}
        while #q > 0 and #players < q.size do
          players[#players + 1] = table.remove(q, 1)
        end
        startRoom(q.size, q.stake, players)
      end
    end
  end
end

skynet.start(function()
  fill_after = tonumber(skynet.getenv "match_fill_after") or 500
  default_size = tonumber(skynet.getenv "quick_size") or 5
  min_humans = tonumber(skynet.getenv "match_min_humans") or 5
  skynet.fork(tick)
  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
  skynet.register ".match"
end)
