--- Persistence: users and stats in MySQL, sessions and leaderboard in Redis.
--- If MySQL is unreachable at startup the service falls back to an
--- in-memory user store (dev mode; a warning is logged).
local skynet = require "skynet"
require "skynet.manager" -- for skynet.register
local crypt = require "skynet.crypt"

local mysql -- nil in memory mode
local red

-- memory-mode fallback stores
local mem = { users = {}, by_device = {}, friends = {}, next_uid = 1 }

local CMD = {}

local function quote(s)
  return "'" .. tostring(s):gsub("[\\']", "\\%0") .. "'"
end

local SCHEMA = {
  [[CREATE TABLE IF NOT EXISTS user (
      uid INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(32) NOT NULL,
      lang VARCHAR(8) NOT NULL DEFAULT 'en',
      coins INT NOT NULL DEFAULT 1000,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) CHARSET=utf8mb4]],
  [[CREATE TABLE IF NOT EXISTS friend (
      uid INT UNSIGNED NOT NULL,
      fuid INT UNSIGNED NOT NULL,
      status VARCHAR(8) NOT NULL, -- pending (uid asked fuid) | accepted
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (uid, fuid)
    ) CHARSET=utf8mb4]],
  [[CREATE TABLE IF NOT EXISTS user_auth (
      provider VARCHAR(16) NOT NULL,
      open_id VARCHAR(128) NOT NULL,
      uid INT UNSIGNED NOT NULL,
      PRIMARY KEY (provider, open_id)
    ) CHARSET=utf8mb4]],
  [[CREATE TABLE IF NOT EXISTS user_stat (
      uid INT UNSIGNED PRIMARY KEY,
      games INT NOT NULL DEFAULT 0,
      wins INT NOT NULL DEFAULT 0
    ) CHARSET=utf8mb4]],
  [[CREATE TABLE IF NOT EXISTS match_record (
      id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      mode VARCHAR(16) NOT NULL,
      players JSON NOT NULL,
      ended_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    ) CHARSET=utf8mb4]],
}

local function newToken()
  return crypt.hexencode(crypt.randomkey()) .. crypt.hexencode(crypt.randomkey())
end

local function defaultName(uid)
  return "Player" .. uid
end

-- Returns {uid, name, lang, games, wins} for a guest device, creating the
-- account on first login.
local function loginGuestSql(device, name, lang)
  local rows = mysql:query(
    "SELECT u.uid, u.name, u.lang, u.coins, s.games, s.wins FROM user_auth a" ..
    " JOIN user u ON u.uid = a.uid JOIN user_stat s ON s.uid = u.uid" ..
    " WHERE a.provider = 'guest' AND a.open_id = " .. quote(device))
  if rows.err then error(rows.err) end
  if rows[1] then return rows[1] end

  local r = mysql:query(("INSERT INTO user (name, lang) VALUES (%s, %s)")
    :format(quote(name or ""), quote(lang or "en")))
  if r.err then error(r.err) end
  local uid = r.insert_id
  if not name or name == "" then
    name = defaultName(uid)
    mysql:query(("UPDATE user SET name = %s WHERE uid = %d"):format(quote(name), uid))
  end
  mysql:query(("INSERT INTO user_auth (provider, open_id, uid) VALUES ('guest', %s, %d)")
    :format(quote(device), uid))
  mysql:query(("INSERT INTO user_stat (uid) VALUES (%d)"):format(uid))
  return { uid = uid, name = name, lang = lang or "en", coins = 1000, games = 0, wins = 0 }
end

local function loginGuestMem(device, name, lang)
  local uid = mem.by_device[device]
  if uid then return mem.users[uid] end
  uid = mem.next_uid
  mem.next_uid = uid + 1
  local u = {
    uid = uid,
    name = (name and name ~= "") and name or defaultName(uid),
    lang = lang or "en",
    coins = 1000,
    games = 0,
    wins = 0,
  }
  mem.users[uid] = u
  mem.by_device[device] = uid
  return u
end

function CMD.login_guest(device, name, lang)
  local user = mysql and loginGuestSql(device, name, lang)
      or loginGuestMem(device, name, lang)
  local token = newToken()
  red:setex("sess:" .. token, 30 * 86400, user.uid)
  red:set("sessname:" .. user.uid, user.name)
  return user, token
end

function CMD.auth_token(token)
  local uid = red:get("sess:" .. token)
  return uid and tonumber(uid) or nil
end

function CMD.get_user(uid)
  if not mysql then return mem.users[uid] end
  local rows = mysql:query(
    ("SELECT u.uid, u.name, u.lang, u.coins, s.games, s.wins FROM user u" ..
     " JOIN user_stat s ON s.uid = u.uid WHERE u.uid = %d"):format(uid))
  return rows[1]
end

function CMD.set_name(uid, name)
  red:set("sessname:" .. uid, name)
  if not mysql then
    if mem.users[uid] then mem.users[uid].name = name end
    return true
  end
  mysql:query(("UPDATE user SET name = %s WHERE uid = %d"):format(quote(name), uid))
  return true
end

function CMD.set_lang(uid, lang)
  if not mysql then
    if mem.users[uid] then mem.users[uid].lang = lang end
    return true
  end
  mysql:query(("UPDATE user SET lang = %s WHERE uid = %d"):format(quote(lang), uid))
  return true
end

local dailyProgress -- defined in the daily section below

--- results: list of {uid, win (bool), score, tricks}, humans only.
function CMD.game_result(mode, results)
  for _, r in ipairs(results) do
    dailyProgress(r.uid, r.win, r.tricks)
    if mysql then
      mysql:query(("UPDATE user_stat SET games = games + 1, wins = wins + %d" ..
        " WHERE uid = %d"):format(r.win and 1 or 0, r.uid))
    elseif mem.users[r.uid] then
      local u = mem.users[r.uid]
      u.games = u.games + 1
      u.wins = u.wins + (r.win and 1 or 0)
    end
    if r.win then
      red:zincrby("rank:wins", 1, r.uid)
    end
  end
  if mysql then
    local json = require "json"
    mysql:query(("INSERT INTO match_record (mode, players) VALUES (%s, %s)")
      :format(quote(mode), quote(json.encode(results))))
  end
  return true
end

function CMD.rank_top(uid, count)
  local raw = red:zrevrange("rank:wins", 0, (count or 50) - 1, "WITHSCORES")
  local top = {}
  for i = 1, #raw, 2 do
    local id = tonumber(raw[i])
    top[#top + 1] = {
      uid = id,
      wins = tonumber(raw[i + 1]),
      name = red:get("sessname:" .. id) or ("Player" .. id),
    }
  end
  local me
  if uid then
    local r = red:zrevrank("rank:wins", uid)
    if r then
      me = { rank = r + 1, wins = tonumber(red:zscore("rank:wins", uid)) }
    end
  end
  return { top = top, me = me }
end

---------------------------------------------------------------- coins

function CMD.coins_get(uid)
  if not mysql then return mem.users[uid] and mem.users[uid].coins or 0 end
  local rows = mysql:query(("SELECT coins FROM user WHERE uid = %d"):format(uid))
  return rows[1] and rows[1].coins or 0
end

--- Adds delta (may be negative). Fails with "insufficient" instead of
--- going below zero. Returns the new balance.
function CMD.coins_add(uid, delta)
  if not mysql then
    local u = mem.users[uid]
    if not u then return nil, "no_user" end
    if u.coins + delta < 0 then return nil, "insufficient" end
    u.coins = u.coins + delta
    return u.coins
  end
  local r = mysql:query(("UPDATE user SET coins = coins + %d" ..
    " WHERE uid = %d AND coins + %d >= 0"):format(delta, uid, delta))
  if (r.affected_rows or 0) == 0 then return nil, "insufficient" end
  return CMD.coins_get(uid)
end

---------------------------------------------------------------- friends

local function friendStatus(uid, fuid)
  if not mysql then
    return mem.friends[uid] and mem.friends[uid][fuid]
  end
  local rows = mysql:query(("SELECT status FROM friend" ..
    " WHERE uid = %d AND fuid = %d"):format(uid, fuid))
  return rows[1] and rows[1].status
end

local function friendSet(uid, fuid, status)
  if not mysql then
    mem.friends[uid] = mem.friends[uid] or {}
    mem.friends[uid][fuid] = status
    return
  end
  mysql:query(("REPLACE INTO friend (uid, fuid, status) VALUES (%d, %d, %s)")
    :format(uid, fuid, quote(status)))
end

local function friendDel(uid, fuid)
  if not mysql then
    if mem.friends[uid] then mem.friends[uid][fuid] = nil end
    return
  end
  mysql:query(("DELETE FROM friend WHERE uid = %d AND fuid = %d")
    :format(uid, fuid))
end

--- Finds a user by numeric uid or exact name.
function CMD.find_user(q)
  if not mysql then
    local n = tonumber(q)
    if n and mem.users[n] then
      return { uid = n, name = mem.users[n].name }
    end
    for uid, u in pairs(mem.users) do
      if u.name == q then return { uid = uid, name = u.name } end
    end
    return nil
  end
  local n = tonumber(q)
  local rows
  if n then
    rows = mysql:query(("SELECT uid, name FROM user WHERE uid = %d"):format(n))
  else
    rows = mysql:query("SELECT uid, name FROM user WHERE name = " .. quote(q)
      .. " LIMIT 1")
  end
  return rows[1]
end

--- Sends (or auto-accepts, when the reverse request exists) a request.
function CMD.friend_add(uid, fuid)
  if uid == fuid then return nil, "bad_target" end
  if not CMD.get_user(fuid) then return nil, "no_user" end
  local mine = friendStatus(uid, fuid)
  if mine == "accepted" then return nil, "already_friends" end
  if mine == "pending" then return nil, "already_requested" end
  if friendStatus(fuid, uid) == "pending" then
    friendSet(uid, fuid, "accepted")
    friendSet(fuid, uid, "accepted")
    return "accepted"
  end
  friendSet(uid, fuid, "pending")
  return "requested"
end

function CMD.friend_respond(uid, fuid, accept)
  if friendStatus(fuid, uid) ~= "pending" then return nil, "no_request" end
  friendDel(fuid, uid)
  if accept then
    friendSet(uid, fuid, "accepted")
    friendSet(fuid, uid, "accepted")
  end
  return true
end

function CMD.friend_remove(uid, fuid)
  friendDel(uid, fuid)
  friendDel(fuid, uid)
  return true
end

--- Returns { friends = {{uid, name}...}, requests = {{uid, name}...} }.
function CMD.friend_list(uid)
  local friends, requests = {}, {}
  local function nameOf(id)
    local u = CMD.get_user(id)
    return u and u.name or ("Player" .. id)
  end
  if not mysql then
    for fuid, status in pairs(mem.friends[uid] or {}) do
      if status == "accepted" then
        friends[#friends + 1] = { uid = fuid, name = nameOf(fuid) }
      end
    end
    for ouid, t in pairs(mem.friends) do
      if t[uid] == "pending" then
        requests[#requests + 1] = { uid = ouid, name = nameOf(ouid) }
      end
    end
  else
    local rows = mysql:query(("SELECT f.fuid AS uid, u.name FROM friend f" ..
      " JOIN user u ON u.uid = f.fuid" ..
      " WHERE f.uid = %d AND f.status = 'accepted'"):format(uid))
    for _, r in ipairs(rows) do friends[#friends + 1] = r end
    rows = mysql:query(("SELECT f.uid AS uid, u.name FROM friend f" ..
      " JOIN user u ON u.uid = f.uid" ..
      " WHERE f.fuid = %d AND f.status = 'pending'"):format(uid))
    for _, r in ipairs(rows) do requests[#requests + 1] = r end
  end
  return { friends = friends, requests = requests }
end

---------------------------------------------------------------- daily

local DAILY_BONUS = 200

-- Fixed daily tasks: field in the daily hash, goal, coin reward.
local TASKS = {
  { id = "play3", field = "games", goal = 3, reward = 100 },
  { id = "win1", field = "wins", goal = 1, reward = 150 },
  { id = "tricks10", field = "tricks", goal = 10, reward = 100 },
}

-- Day key in UTC+8 (Ulaanbaatar).
local function today()
  return os.date("!%Y%m%d", os.time() + 8 * 3600)
end

local function dailyKey(uid)
  return "daily:" .. uid .. ":" .. today()
end

local function dailyHash(uid)
  local key = dailyKey(uid)
  local raw = red:hgetall(key)
  local h = {}
  for i = 1, #raw, 2 do h[raw[i]] = tonumber(raw[i + 1]) or raw[i + 1] end
  return h, key
end

function CMD.daily_state(uid)
  local h = dailyHash(uid)
  local tasks = {}
  for _, t in ipairs(TASKS) do
    tasks[#tasks + 1] = {
      id = t.id,
      goal = t.goal,
      reward = t.reward,
      progress = math.min(h[t.field] or 0, t.goal),
      claimed = h["claimed:" .. t.id] == 1,
    }
  end
  return {
    coins = CMD.coins_get(uid),
    bonus = DAILY_BONUS,
    bonus_claimed = h.bonus == 1,
    tasks = tasks,
  }
end

function CMD.daily_claim_bonus(uid)
  local h, key = dailyHash(uid)
  if h.bonus == 1 then return nil, "already_claimed" end
  red:hset(key, "bonus", 1)
  red:expire(key, 3 * 86400)
  return CMD.coins_add(uid, DAILY_BONUS)
end

function CMD.daily_claim_task(uid, id)
  for _, t in ipairs(TASKS) do
    if t.id == id then
      local h, key = dailyHash(uid)
      if h["claimed:" .. id] == 1 then return nil, "already_claimed" end
      if (h[t.field] or 0) < t.goal then return nil, "not_done" end
      red:hset(key, "claimed:" .. id, 1)
      red:expire(key, 3 * 86400)
      return CMD.coins_add(uid, t.reward)
    end
  end
  return nil, "bad_task"
end

---------------------------------------------------------------- replays

local REPLAY_TTL = 30 * 86400
local REPLAYS_PER_USER = 10

--- Stores a finished game's record and indexes it for its players.
function CMD.save_replay(uids, record)
  local json = require "json"
  local id = red:incr("replay:seq")
  record.id = id
  record.ts = os.time()
  red:setex("replay:" .. id, REPLAY_TTL, json.encode(record))
  local meta = json.encode {
    id = id,
    ts = record.ts,
    mode = record.mode,
    size = record.size,
    stake = record.stake,
    names = record.names,
    winners = record.winners,
  }
  red:setex("replaymeta:" .. id, REPLAY_TTL, meta)
  for _, uid in ipairs(uids) do
    local key = "replays:" .. uid
    red:lpush(key, id)
    red:ltrim(key, 0, REPLAYS_PER_USER - 1)
    red:expire(key, REPLAY_TTL)
  end
  return id
end

function CMD.replay_list(uid)
  local json = require "json"
  local ids = red:lrange("replays:" .. uid, 0, REPLAYS_PER_USER - 1)
  local out = {}
  for _, id in ipairs(ids) do
    local meta = red:get("replaymeta:" .. id)
    if meta then out[#out + 1] = json.decode(meta) end
  end
  return out
end

function CMD.replay_get(id)
  local raw = red:get("replay:" .. tonumber(id))
  if not raw then return nil, "replay_not_found" end
  return raw -- already JSON; forwarded verbatim
end

--- Bumps the daily counters after a game (humans only).
function dailyProgress(uid, win, tricks)
  local key = dailyKey(uid)
  red:hincrby(key, "games", 1)
  if win then red:hincrby(key, "wins", 1) end
  red:hincrby(key, "tricks", tricks or 0)
  red:expire(key, 3 * 86400)
end

skynet.start(function()
  local redis = require "skynet.db.redis"
  red = redis.connect {
    host = skynet.getenv "redis_host" or "127.0.0.1",
    port = tonumber(skynet.getenv "redis_port") or 6379,
    db = tonumber(skynet.getenv "redis_db") or 0,
  }

  local ok, err = pcall(function()
    local driver = require "skynet.db.mysql"
    mysql = driver.connect {
      host = skynet.getenv "mysql_host" or "127.0.0.1",
      port = tonumber(skynet.getenv "mysql_port") or 3306,
      database = skynet.getenv "mysql_db" or "khuzur",
      user = skynet.getenv "mysql_user",
      password = skynet.getenv "mysql_password",
      max_packet_size = 1024 * 1024,
    }
    for _, sql in ipairs(SCHEMA) do
      local r = mysql:query(sql)
      if r.err then error(r.err) end
    end
    -- CREATE TABLE IF NOT EXISTS does not upgrade existing user tables.
    local columns = mysql:query("SHOW COLUMNS FROM user LIKE 'coins'")
    if columns.err then error(columns.err) end
    if not columns[1] then
      local r = mysql:query(
        "ALTER TABLE user ADD COLUMN coins INT NOT NULL DEFAULT 1000")
      if r.err then error(r.err) end
      skynet.error("[db] migrated user.coins")
    end
  end)
  if not ok then
    mysql = nil
    skynet.error("[db] MySQL unavailable, using in-memory store: " .. tostring(err))
  else
    skynet.error("[db] MySQL connected")
  end

  skynet.dispatch("lua", function(_, _, cmd, ...)
    skynet.retpack(CMD[cmd](...))
  end)
  skynet.register ".db"
end)
