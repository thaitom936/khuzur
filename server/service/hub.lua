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

local function newCode()
  for _ = 1, 100 do
    local code = ("%06d"):format(math.random(0, 999999))
    if not codes[code] then return code end
  end
  error "no free room code"
end

--- Creates a room. players: list of {uid, name, agent, fd} (quick match
--- passes the full table incl. bots; friend rooms start with the creator).
function CMD.create_room(mode, size, players)
  local room = skynet.newservice("room")
  local code
  if mode == "friend" then
    code = newCode()
    codes[code] = room
  end
  rooms[room] = { mode = mode, code = code }
  for _, p in ipairs(players) do
    if p.uid then uid_room[p.uid] = room end
  end
  skynet.call(room, "lua", "init", {
    mode = mode,
    size = size,
    code = code,
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
