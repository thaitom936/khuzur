--- Verifies the showcase bot rooms: always present in the lobby list,
--- watchable, sittable mid-game, and respawned after a game ends.
-- Run from server/: ./skynet/skynet etc/config.botrooms
local skynet = require "skynet"
local websocket = require "http.websocket"
local json = require "json"

local URL = "ws://127.0.0.1:" .. (tonumber(skynet.getenv "ws_port") or 9621) .. "/ws"

-- skynet.error is async and would be lost to os.exit; write directly.
local function say(msg)
  io.stderr:write(msg .. "\n")
  io.stderr:flush()
end

local function check(cond, what)
  if not cond then
    say("BOTROOMS FAIL: " .. what)
    os.exit(1)
  end
end

local seq = 0
local pending = {} -- pushes that arrived while waiting for a response

local function call(id, t)
  seq = seq + 1
  t.seq = seq
  websocket.write(id, json.encode(t))
  while true do
    local raw = websocket.read(id)
    check(raw, "connection closed waiting for " .. t.cmd)
    local msg = json.decode(raw)
    if msg.seq == seq then return msg end
    pending[#pending + 1] = msg
  end
end

local function nextMsg(id)
  if #pending > 0 then return table.remove(pending, 1) end
  local raw = websocket.read(id)
  check(raw, "connection closed")
  return json.decode(raw)
end

local function waitPush(id, name)
  while true do
    local msg = nextMsg(id)
    if msg.push == name then return msg end
  end
end

local function botRooms(id)
  local r = call(id, { cmd = "room_list" })
  check(not r.err, "room_list failed")
  local out = {}
  for _, room in ipairs(r.rooms) do
    if room.mode == "bot" then out[#out + 1] = room end
  end
  return out
end

skynet.start(function()
  skynet.uniqueservice("db")
  skynet.uniqueservice("hub")
  skynet.uniqueservice("match")
  skynet.uniqueservice("wsgate")
  skynet.sleep(50)

  skynet.fork(function()
    skynet.sleep(12000)
    say("BOTROOMS FAIL: watchdog timeout")
    os.exit(1)
  end)

  local a = websocket.connect(URL)
  local r = call(a, { cmd = "login", device = "botrooms-device-a", name = "Ba" })
  check(not r.err, "login failed")

  -- Two bot rooms are up, playing, five bots each. (A room may just be
  -- respawning when we look, so poll briefly.)
  local rooms
  for _ = 1, 20 do
    rooms = botRooms(a)
    if #rooms == 2 then break end
    skynet.sleep(50)
  end
  check(#rooms == 2, "expected 2 bot rooms, got " .. #rooms)
  check(rooms[1].started and rooms[1].bots == 5 and rooms[1].size == 5,
    "bot room not running with 5 bots")

  -- Coin tables are rejected while stakes are disabled.
  r = call(a, { cmd = "create_room", size = 2, stake = 100 })
  check(r.err == "bad_stake", "stake should be rejected, got " .. tostring(r.err))

  -- Watching works.
  r = call(a, { cmd = "watch", code = rooms[1].code })
  check(not r.err, "watch: " .. tostring(r.err))
  local snap = waitPush(a, "snapshot")
  check(snap.you == -1, "bad watcher snapshot")
  call(a, { cmd = "unwatch" })

  -- Games are closed once started: no sitting down mid-game.
  local fresh = botRooms(a)
  check(#fresh > 0, "no bot room to test against")
  r = call(a, { cmd = "join_room", code = fresh[1].code })
  check(r.err == "already_started", "mid-game sit should be rejected, got "
    .. tostring(r.err))

  -- Watch one room until its game ends naturally; the keeper then
  -- replaces it.
  local endCode = fresh[1].code
  r = call(a, { cmd = "watch", code = endCode })
  check(not r.err, "watch: " .. tostring(r.err))
  waitPush(a, "snapshot")
  waitPush(a, "game_end")
  call(a, { cmd = "unwatch" })

  local after
  for _ = 1, 20 do
    skynet.sleep(50)
    after = botRooms(a)
    if #after == 2 then break end
  end
  check(#after == 2, "keeper did not respawn, got " .. #after)
  for _, room in ipairs(after) do
    check(room.code ~= endCode, "finished bot room still listed")
  end

  say("BOTROOMS PASS")
  os.exit(0)
end)
