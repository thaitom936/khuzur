--- Online registry + room manager.
--- Tracks who is online (for duplicate-login kicks), which room every uid
--- is in (for routing and reconnects), and friend-room codes.
local skynet = require "skynet"
require "skynet.manager" -- for skynet.register

local online = {}   -- uid -> {agent, fd}
local uid_room = {} -- uid -> room service addr
local rooms = {}    -- room addr -> {mode, code, stake, size, locked}
local codes = {}    -- code -> room addr

local CMD = {}

-- Showcase rooms: bot_rooms tables full of bots play round the clock so
-- the lobby always has something to watch or sit down into.
local BOT_NAMES = {
  "Bataa", "Bold", "Saruul", "Tuya", "Nomin",
  "Oyunaa", "Temuulen", "Anar", "Zolboo", "Khulan",
}
local botRoomTarget = 0

local function countBotRooms()
  local n = 0
  for _, meta in pairs(rooms) do
    if meta.mode == "bot" then n = n + 1 end
  end
  return n
end

local function spawnBotRoom()
  local players, used = {}, {}
  for i = 1, 5 do
    local name
    repeat
      name = BOT_NAMES[math.random(#BOT_NAMES)]
    until not used[name]
    used[name] = true
    players[i] = name
  end
  CMD.create_room("bot", 5, {}, 0, false, players)
end

local spawning = 0 -- spawns in flight (spawnBotRoom yields internally)

local function ensureBotRooms()
  while countBotRooms() + spawning < botRoomTarget do
    spawning = spawning + 1
    local ok, err = pcall(spawnBotRoom)
    spawning = spawning - 1
    if not ok then
      skynet.error("[hub] bot room spawn failed: " .. tostring(err))
      break
    end
  end
end

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

--- Public rooms for the lobby list (locked ones are code/invite only).
function CMD.room_list()
  local out = {}
  for room, meta in pairs(rooms) do
    if not meta.locked then
      local ok, info = pcall(skynet.call, room, "lua", "info")
      if ok and info then out[#out + 1] = info end
    end
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
function CMD.create_room(mode, size, players, stake, locked, botNames)
  local room = skynet.newservice("room")
  -- Every room gets a code so the lobby list can address it.
  local code = newCode()
  codes[code] = room
  rooms[room] = {
    mode = mode, code = code, stake = stake or 0, size = size,
    locked = locked or false,
  }
  for _, p in ipairs(players) do
    if p.uid then uid_room[p.uid] = room end
  end
  skynet.call(room, "lua", "init", {
    mode = mode,
    size = size,
    code = code,
    stake = stake or 0,
    locked = locked or false,
    players = players,
    bot_names = botNames,
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
    if info.mode == "bot" then
      ensureBotRooms() -- keep the showcase tables running
    end
  end
  return true
end

skynet.start(function()
  math.randomseed()
  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
  skynet.register ".hub"
  botRoomTarget = tonumber(skynet.getenv "bot_rooms") or 0
  if botRoomTarget > 0 then
    skynet.fork(function()
      skynet.sleep(10)
      ensureBotRooms()
    end)
  end
end)
