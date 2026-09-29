--- Online registry + room manager.
--- Tracks who is online (for duplicate-login kicks), which room every uid
--- is in (for routing and reconnects), and friend-room codes.
local skynet = require "skynet"
require "skynet.manager" -- for skynet.register

local online = {}   -- uid -> {agent, fd}
local uid_room = {} -- uid -> room service addr
local rooms = {}    -- room addr -> {mode, code}
local codes = {}    -- code -> room addr

local CMD = {}

---------------------------------------------------------------- presence

--- Registers a connection; kicks any previous connection of the same uid.
function CMD.register(uid, agent, fd)
  local old = online[uid]
  online[uid] = { agent = agent, fd = fd }
  if old and (old.agent ~= agent or old.fd ~= fd) then
    skynet.send(old.agent, "lua", "kick", old.fd)
  end
  return uid_room[uid] ~= nil
end

function CMD.offline(uid, agent, fd)
  local cur = online[uid]
  if cur and cur.agent == agent and cur.fd == fd then
    online[uid] = nil
  end
  skynet.send(".match", "lua", "remove", uid)
  local room = uid_room[uid]
  if room then
    skynet.send(room, "lua", "offline", uid)
  end
end

---------------------------------------------------------------- rooms

function CMD.room_of(uid)
  return uid_room[uid]
end

function CMD.is_online(uid)
  return online[uid] ~= nil
end

--- Pushes a message to a user's live connection, if any.
function CMD.push_to(uid, msg)
  local c = online[uid]
  if not c then return false end
  skynet.send(c.agent, "lua", "push", c.fd, msg)
  return true
end

--- Live info about a room by code (stake escrow, lobby list).
function CMD.room_info(code)
  local room = codes[code]
  if not room then return nil, "room_not_found" end
  local ok, info = pcall(skynet.call, room, "lua", "info")
  if not ok then return nil, "room_not_found" end
  return info
end

function CMD.room_addr(code)
  return codes[code]
end

--- All rooms for the lobby list.
function CMD.room_list()
  local out = {}
  for room in pairs(rooms) do
    local ok, info = pcall(skynet.call, room, "lua", "info")
    if ok and info then out[#out + 1] = info end
  end
  table.sort(out, function(a, b) return a.code < b.code end)
  return out
end

local function newCode()
  for _ = 1, 100 do
    local code = ("%06d"):format(math.random(0, 999999))
    if not codes[code] then return code end
  end
  error "no free room code"
end

--- Creates a room. players: list of {uid, name, agent, fd} (quick match
--- passes the full table incl. bots; friend rooms start with the creator).
function CMD.create_room(mode, size, players, stake)
  local room = skynet.newservice("room")
  -- Every room gets a code so the lobby list can address it.
  local code = newCode()
  codes[code] = room
  rooms[room] = { mode = mode, code = code, stake = stake or 0, size = size }
  for _, p in ipairs(players) do
    if p.uid then uid_room[p.uid] = room end
  end
  skynet.call(room, "lua", "init", {
    mode = mode,
    size = size,
    code = code,
    stake = stake or 0,
    players = players,
  })
  return room, code
end

function CMD.join_room(code, player)
  local room = codes[code]
  if not room then return nil, "room_not_found" end
  local ok, err = skynet.call(room, "lua", "join", player)
  if not ok then return nil, err end
  uid_room[player.uid] = room
  return room
end

--- Called by a room when a uid leaves before the game starts.
function CMD.left_room(uid)
  uid_room[uid] = nil
  return true
end

--- Called by a room when the game is over (or the room is abandoned).
function CMD.room_closed(room, uids)
  for _, uid in ipairs(uids or {}) do
    if uid_room[uid] == room then uid_room[uid] = nil end
  end
  local info = rooms[room]
  if info then
    if info.code then codes[info.code] = nil end
    rooms[room] = nil
  end
  return true
end

skynet.start(function()
  math.randomseed()
  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
  skynet.register ".hub"
end)
