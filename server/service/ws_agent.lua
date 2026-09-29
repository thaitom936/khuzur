--- WebSocket session agent. Each instance serves many connections.
--- Wire protocol: JSON text frames.
---   request:  {seq, cmd, ...args}
---   response: {seq, cmd, err?, ...data}
---   push:     {push = "<name>", ...data}
local skynet = require "skynet"
local websocket = require "http.websocket"
local json = require "json"

local conns = {} -- fd -> {uid, name}

local handle = {}
local HANDLERS = {}

local function send(fd, msg)
  local ok = pcall(websocket.write, fd, json.encode(msg))
  if not ok then
    skynet.error("[agent] write failed fd=" .. fd)
  end
end

local function roomOf(uid)
  return skynet.call(".hub", "lua", "room_of", uid)
end

---------------------------------------------------------------- handlers
-- Each handler returns (data | nil, err). `c` is the connection state.

function HANDLERS.ping(fd, c, msg)
  return { t = msg.t }
end

function HANDLERS.login(fd, c, msg)
  if type(msg.device) ~= "string" or #msg.device < 8 or #msg.device > 128 then
    return nil, "bad_device"
  end
  local user, token = skynet.call(".db", "lua", "login_guest",
    msg.device, msg.name, msg.lang)
  c.uid = user.uid
  c.name = user.name
  local inRoom = skynet.call(".hub", "lua", "register", c.uid, skynet.self(), fd)
  local resp = {
    uid = user.uid, name = user.name, lang = user.lang,
    games = user.games, wins = user.wins, token = token,
    in_room = inRoom,
  }
  if inRoom then
    local room = roomOf(c.uid)
    if room then skynet.call(room, "lua", "rejoin", c.uid, skynet.self(), fd) end
  end
  return resp
end

function HANDLERS.resume(fd, c, msg)
  local uid = skynet.call(".db", "lua", "auth_token", msg.token or "")
  if not uid then return nil, "bad_token" end
  local user = skynet.call(".db", "lua", "get_user", uid)
  if not user then return nil, "bad_token" end
  c.uid = uid
  c.name = user.name
  local inRoom = skynet.call(".hub", "lua", "register", uid, skynet.self(), fd)
  if inRoom then
    local room = roomOf(uid)
    if room then skynet.call(room, "lua", "rejoin", uid, skynet.self(), fd) end
  end
  return {
    uid = user.uid, name = user.name, lang = user.lang,
    games = user.games, wins = user.wins, in_room = inRoom,
  }
end

local function authed(fn)
  return function(fd, c, msg)
    if not c.uid then return nil, "not_logged_in" end
    return fn(fd, c, msg)
  end
end

HANDLERS.set_name = authed(function(fd, c, msg)
  local name = tostring(msg.name or "")
  if #name < 1 or #name > 24 then return nil, "bad_name" end
  skynet.call(".db", "lua", "set_name", c.uid, name)
  c.name = name
  return { name = name }
end)

HANDLERS.set_lang = authed(function(fd, c, msg)
  skynet.call(".db", "lua", "set_lang", c.uid, tostring(msg.lang or "en"))
  return {}
end)

HANDLERS.rank = authed(function(fd, c, msg)
  return skynet.call(".db", "lua", "rank_top", c.uid, msg.count)
end)

local function playerEntry(fd, c)
  return { uid = c.uid, name = c.name, agent = skynet.self(), fd = fd }
end

HANDLERS.quick_match = authed(function(fd, c, msg)
  if roomOf(c.uid) then return nil, "already_in_room" end
  local ok, err = skynet.call(".match", "lua", "enqueue",
    playerEntry(fd, c), msg.size)
  if not ok then return nil, err end
  return {}
end)

HANDLERS.cancel_match = authed(function(fd, c, msg)
  skynet.call(".match", "lua", "remove", c.uid)
  return {}
end)

HANDLERS.create_room = authed(function(fd, c, msg)
  if roomOf(c.uid) then return nil, "already_in_room" end
  local size = tonumber(msg.size) or 4
  if size < 2 or size > 5 then return nil, "bad_size" end
  local _, roomCode = skynet.call(".hub", "lua", "create_room", "friend",
    size, { playerEntry(fd, c) })
  return { code = roomCode }
end)

HANDLERS.join_room = authed(function(fd, c, msg)
  if roomOf(c.uid) then return nil, "already_in_room" end
  local room, err = skynet.call(".hub", "lua", "join_room",
    tostring(msg.code or ""), playerEntry(fd, c))
  if not room then return nil, err end
  return {}
end)

HANDLERS.leave_room = authed(function(fd, c, msg)
  local room = roomOf(c.uid)
  if not room then return nil, "not_in_room" end
  local ok, err = skynet.call(room, "lua", "leave", c.uid)
  if not ok then return nil, err end
  return {}
end)

HANDLERS.start_room = authed(function(fd, c, msg)
  local room = roomOf(c.uid)
  if not room then return nil, "not_in_room" end
  local ok, err = skynet.call(room, "lua", "start", c.uid)
  if not ok then return nil, err end
  return {}
end)

local ROOM_CMDS = {
  decide = true, exchange = true, play_card = true, auto = true, chat = true,
}

local function roomAction(fd, c, msg)
  local room = roomOf(c.uid)
  if not room then return nil, "not_in_room" end
  local ok, err = skynet.call(room, "lua", "action", c.uid, msg)
  if not ok then return nil, err end
  return {}
end

---------------------------------------------------------------- websocket

function handle.connect(fd) end

function handle.handshake(fd, header, url)
  conns[fd] = {}
end

function handle.message(fd, raw, msg_type)
  local c = conns[fd]
  if not c then return end
  local msg = json.decode(raw)
  if type(msg) ~= "table" or type(msg.cmd) ~= "string" then
    send(fd, { err = "bad_request" })
    return
  end
  local handler = HANDLERS[msg.cmd]
      or (ROOM_CMDS[msg.cmd] and c.uid and roomAction)
      or (ROOM_CMDS[msg.cmd] and function() return nil, "not_logged_in" end)
  if not handler then
    send(fd, { seq = msg.seq, cmd = msg.cmd, err = "unknown_cmd" })
    return
  end
  local ok, data, err = pcall(handler, fd, c, msg)
  if not ok then
    skynet.error("[agent] " .. msg.cmd .. " error: " .. tostring(data))
    send(fd, { seq = msg.seq, cmd = msg.cmd, err = "internal" })
    return
  end
  local resp = { seq = msg.seq, cmd = msg.cmd, err = err }
  if type(data) == "table" then
    for k, v in pairs(data) do resp[k] = v end
  end
  send(fd, resp)
end

function handle.close(fd, code, reason)
  local c = conns[fd]
  conns[fd] = nil
  if c and c.uid then
    skynet.send(".hub", "lua", "offline", c.uid, skynet.self(), fd)
  end
end

function handle.error(fd)
  handle.close(fd)
end

---------------------------------------------------------------- dispatch

local CMD = {}

function CMD.accept(fd, addr)
  local ok, err = websocket.accept(fd, handle, "ws", addr)
  if not ok then
    skynet.error("[agent] accept failed: " .. tostring(err))
  end
end

function CMD.push(fd, msg)
  if conns[fd] then
    send(fd, msg)
  end
end

function CMD.kick(fd)
  if conns[fd] then
    send(fd, { push = "kick" })
    pcall(websocket.close, fd)
  end
end

skynet.start(function()
  skynet.dispatch("lua", function(_, _, cmd, ...)
    CMD[cmd](...)
  end)
end)
