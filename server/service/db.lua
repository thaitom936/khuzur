--- Persistence: users and stats in MySQL, sessions and leaderboard in Redis.
--- If MySQL is unreachable at startup the service falls back to an
--- in-memory user store (dev mode; a warning is logged).
local skynet = require "skynet"
require "skynet.manager" -- for skynet.register
local crypt = require "skynet.crypt"

local mysql -- nil in memory mode
local red

-- memory-mode fallback stores
local mem = { users = {}, by_device = {}, next_uid = 1 }

local CMD = {}

local function quote(s)
  return "'" .. tostring(s):gsub("[\\']", "\\%0") .. "'"
end

local SCHEMA = {
  [[CREATE TABLE IF NOT EXISTS user (
      uid INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
      name VARCHAR(32) NOT NULL,
      lang VARCHAR(8) NOT NULL DEFAULT 'en',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
    "SELECT u.uid, u.name, u.lang, s.games, s.wins FROM user_auth a" ..
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
  return { uid = uid, name = name, lang = lang or "en", games = 0, wins = 0 }
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
    ("SELECT u.uid, u.name, u.lang, s.games, s.wins FROM user u" ..
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

--- results: list of {uid, win (bool), score}, humans only.
function CMD.game_result(mode, results)
  for _, r in ipairs(results) do
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
