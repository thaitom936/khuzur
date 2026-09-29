--- Minimal JSON decoder, just enough for the rule test cases
--- (objects, arrays, plain strings, numbers, true/false/null).

local M = {}

local function skipWs(s, i)
  local _, j = s:find("^[ \t\r\n]*", i)
  return j + 1
end

local decodeValue

local function decodeString(s, i)
  assert(s:sub(i, i) == '"', "expected string at " .. i)
  local j = s:find('"', i + 1, true)
  assert(j, "unterminated string at " .. i)
  local str = s:sub(i + 1, j - 1)
  assert(not str:find("\\", 1, true), "escapes not supported")
  return str, j + 1
end

local function decodeArray(s, i)
  local arr = {}
  i = skipWs(s, i + 1)
  if s:sub(i, i) == "]" then return arr, i + 1 end
  while true do
    local v
    v, i = decodeValue(s, i)
    arr[#arr + 1] = v
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == "]" then return arr, i + 1 end
    assert(c == ",", "expected , or ] at " .. i)
    i = skipWs(s, i + 1)
  end
end

local function decodeObject(s, i)
  local obj = {}
  i = skipWs(s, i + 1)
  if s:sub(i, i) == "}" then return obj, i + 1 end
  while true do
    local k, v
    k, i = decodeString(s, i)
    i = skipWs(s, i)
    assert(s:sub(i, i) == ":", "expected : at " .. i)
    v, i = decodeValue(s, skipWs(s, i + 1))
    obj[k] = v
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == "}" then return obj, i + 1 end
    assert(c == ",", "expected , or } at " .. i)
    i = skipWs(s, i + 1)
  end
end

decodeValue = function(s, i)
  local c = s:sub(i, i)
  if c == '"' then return decodeString(s, i) end
  if c == "{" then return decodeObject(s, i) end
  if c == "[" then return decodeArray(s, i) end
  if s:sub(i, i + 3) == "true" then return true, i + 4 end
  if s:sub(i, i + 4) == "false" then return false, i + 5 end
  if s:sub(i, i + 3) == "null" then return nil, i + 4 end
  local num = s:match("^-?%d+%.?%d*", i)
  assert(num, "unexpected token at " .. i .. ": " .. s:sub(i, i + 10))
  return tonumber(num), i + #num
end

function M.decode(s)
  local v, i = decodeValue(s, skipWs(s, 1))
  assert(skipWs(s, i) > #s, "trailing garbage")
  return v
end

return M
