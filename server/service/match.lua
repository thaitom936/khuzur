--- Quick-match queues. One queue per table size; when a queue has enough
--- players a room starts, and anyone waiting longer than match_fill_after
--- gets a table filled up with bots.
local skynet = require "skynet"
require "skynet.manager" -- for skynet.register

local queues = {} -- size -> list of {uid, name, agent, fd, since}
local queued = {} -- uid -> size

local CMD = {}

local fill_after
local default_size

local function startRoom(size, players)
  for _, p in ipairs(players) do
    queued[p.uid] = nil
  end
  local bots = size - #players
  for i = 1, bots do
    players[#players + 1] = { bot = true, name = "Bot " .. i }
  end
  local room = skynet.call(".hub", "lua", "create_room", "quick", size, players)
  for _, p in ipairs(players) do
    if p.agent then
      skynet.send(p.agent, "lua", "push", p.fd,
        { push = "match_found", room = skynet.address(room) })
    end
  end
end

function CMD.enqueue(player, size)
  size = size or default_size
  if size < 2 or size > 5 then return nil, "bad_size" end
  if queued[player.uid] then return nil, "already_queued" end
  local q = queues[size]
  if not q then
    q = {}
    queues[size] = q
  end
  player.since = skynet.now()
  q[#q + 1] = player
  queued[player.uid] = size
  if #q >= size then
    local players = {}
    for i = 1, size do players[i] = table.remove(q, 1) end
    startRoom(size, players)
  end
  return true
end

function CMD.remove(uid)
  local size = queued[uid]
  if not size then return true end
  queued[uid] = nil
  local q = queues[size]
  for i, p in ipairs(q) do
    if p.uid == uid then
      table.remove(q, i)
      break
    end
  end
  return true
end

local function tick()
  while true do
    skynet.sleep(100)
    for size, q in pairs(queues) do
      if #q > 0 and skynet.now() - q[1].since >= fill_after then
        local players = {}
        while #q > 0 and #players < size do
          players[#players + 1] = table.remove(q, 1)
        end
        startRoom(size, players)
      end
    end
  end
end

skynet.start(function()
  fill_after = tonumber(skynet.getenv "match_fill_after") or 500
  default_size = tonumber(skynet.getenv "quick_size") or 4
  skynet.fork(tick)
  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
  skynet.register ".match"
end)
