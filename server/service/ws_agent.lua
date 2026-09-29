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
    coins = user.coins, games = user.games, wins = user.wins,
    token = token, in_room = inRoom,
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
    coins = user.coins, games = user.games, wins = user.wins,
    in_room = inRoom,
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

local STAKES = { [0] = true, [100] = true, [500] = true, [2000] = true }
local stakesEnabled -- coin tables switch, set from config in skynet.start

local function stakeAllowed(stake)
  if not STAKES[stake] then return false end
  return stake == 0 or stakesEnabled
end

-- Takes the entry fee before queueing/joining. Returns nil, err on failure.
local function escrow(uid, stakeAmount)
  if stakeAmount == 0 then return true end
  local bal, err = skynet.call(".db", "lua", "coins_add", uid, -stakeAmount)
  if not bal then return nil, err end
  return true
end

local function refund(uid, stakeAmount)
  if stakeAmount > 0 then
    skynet.send(".db", "lua", "coins_add", uid, stakeAmount)
  end
end

HANDLERS.quick_match = authed(function(fd, c, msg)
  if roomOf(c.uid) then return nil, "already_in_room" end
  local stake = tonumber(msg.stake) or 0
  if not stakeAllowed(stake) then return nil, "bad_stake" end
  local ok, err = escrow(c.uid, stake)
  if not ok then return nil, err end
  ok, err = skynet.call(".match", "lua", "enqueue",
    playerEntry(fd, c), msg.size, stake)
  if not ok then
    refund(c.uid, stake)
    return nil, err
  end
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
  local stake = tonumber(msg.stake) or 0
  if not stakeAllowed(stake) then return nil, "bad_stake" end
  local ok, err = escrow(c.uid, stake)
  if not ok then return nil, err end
  local _, roomCode = skynet.call(".hub", "lua", "create_room", "friend",
    size, { playerEntry(fd, c) }, stake, msg.locked and true or false)
  return { code = roomCode }
end)

HANDLERS.join_room = authed(function(fd, c, msg)
  if roomOf(c.uid) then return nil, "already_in_room" end
  local code = tostring(msg.code or "")
  local info, ierr = skynet.call(".hub", "lua", "room_info", code)
  if not info then return nil, ierr end
  -- Mid-game sits are free-table only; nothing to escrow then.
  local fee = info.started and 0 or info.stake
  local ok, err = escrow(c.uid, fee)
  if not ok then return nil, err end
  local room, jerr = skynet.call(".hub", "lua", "join_room",
    code, playerEntry(fd, c))
  if not room then
    refund(c.uid, fee)
    return nil, jerr
  end
  return {}
end)

HANDLERS.room_list = authed(function(fd, c, msg)
  return { rooms = skynet.call(".hub", "lua", "room_list") }
end)

HANDLERS.leave_room = authed(function(fd, c, msg)
  local room = roomOf(c.uid)
  if not room then return nil, "not_in_room" end
  local info = skynet.call(room, "lua", "info")
  local ok, err = skynet.call(room, "lua", "leave", c.uid)
  if not ok then return nil, err end
  refund(c.uid, info.stake) -- leaving is only possible before the start
  return {}
end)

HANDLERS.start_room = authed(function(fd, c, msg)
  local room = roomOf(c.uid)
  if not room then return nil, "not_in_room" end
  local ok, err = skynet.call(room, "lua", "start", c.uid)
  if not ok then return nil, err end
  return {}
end)

---------------------------------------------------------------- coins & daily

HANDLERS.daily = authed(function(fd, c, msg)
  return skynet.call(".db", "lua", "daily_state", c.uid)
end)

HANDLERS.daily_claim = authed(function(fd, c, msg)
  local coins, err
  if msg.task then
    coins, err = skynet.call(".db", "lua", "daily_claim_task", c.uid, msg.task)
  else
    coins, err = skynet.call(".db", "lua", "daily_claim_bonus", c.uid)
  end
  if not coins then return nil, err end
  return { coins = coins }
end)

---------------------------------------------------------------- friends

HANDLERS.friends = authed(function(fd, c, msg)
  local list = skynet.call(".db", "lua", "friend_list", c.uid)
  for _, f in ipairs(list.friends) do
    f.online = skynet.call(".hub", "lua", "is_online", f.uid)
    f.in_room = f.online
        and skynet.call(".hub", "lua", "room_of", f.uid) ~= nil or false
  end
  return list
end)

---------------------------------------------------------------- spectate

--- Watches an ongoing game, by friend uid or by room code.
HANDLERS.watch = authed(function(fd, c, msg)
  local room
  if msg.code then
    room = skynet.call(".hub", "lua", "room_addr", tostring(msg.code))
  else
    local fuid = tonumber(msg.uid)
    room = fuid and skynet.call(".hub", "lua", "room_of", fuid)
  end
  if not room then return nil, "not_in_room" end
  skynet.call(room, "lua", "watch",
    { uid = c.uid, agent = skynet.self(), fd = fd })
  c.watching = room
  return {}
end)

HANDLERS.unwatch = authed(function(fd, c, msg)
  if c.watching then
    skynet.send(c.watching, "lua", "unwatch", c.uid)
    c.watching = nil
  end
  return {}
end)

---------------------------------------------------------------- replays

HANDLERS.replays = authed(function(fd, c, msg)
  return { list = skynet.call(".db", "lua", "replay_list", c.uid) }
end)

--- The replay field is a JSON string (decode it client-side).
HANDLERS.replay = authed(function(fd, c, msg)
  local raw, err = skynet.call(".db", "lua", "replay_get",
    tonumber(msg.id) or 0)
  if not raw then return nil, err end
  return { replay = raw }
end)

HANDLERS.friend_add = authed(function(fd, c, msg)
  local target = skynet.call(".db", "lua", "find_user", tostring(msg.q or ""))
  if not target then return nil, "no_user" end
  local status, err = skynet.call(".db", "lua", "friend_add", c.uid, target.uid)
  if not status then return nil, err end
  skynet.call(".hub", "lua", "push_to", target.uid, {
    push = "friend_update",
  })
  return { status = status, uid = target.uid, name = target.name }
end)

HANDLERS.friend_respond = authed(function(fd, c, msg)
  local ok, err = skynet.call(".db", "lua", "friend_respond", c.uid,
    tonumber(msg.uid), msg.accept and true or false)
  if not ok then return nil, err end
  skynet.call(".hub", "lua", "push_to", tonumber(msg.uid),
    { push = "friend_update" })
  return {}
end)

HANDLERS.friend_remove = authed(function(fd, c, msg)
  skynet.call(".db", "lua", "friend_remove", c.uid, tonumber(msg.uid))
  return {}
end)

--- Invites a friend to the (unstarted) friend room the player is in.
HANDLERS.invite = authed(function(fd, c, msg)
  local room = roomOf(c.uid)
  if not room then return nil, "not_in_room" end
  local info = skynet.call(room, "lua", "info")
  if info.started or not info.code then return nil, "already_started" end
  local fuid = tonumber(msg.uid)
  local status = skynet.call(".db", "lua", "find_user", tostring(fuid))
  if not status then return nil, "no_user" end
  local delivered = skynet.call(".hub", "lua", "push_to", fuid, {
    push = "invite",
    from = c.name,
    code = info.code,
    stake = info.stake,
  })
  if not delivered then return nil, "friend_offline" end
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
  if c and c.watching then
    skynet.send(c.watching, "lua", "unwatch", c.uid)
  end
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
  stakesEnabled = skynet.getenv "stakes_enabled" == "true"
  skynet.dispatch("lua", function(_, _, cmd, ...)
    CMD[cmd](...)
  end)
end)
