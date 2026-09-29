--- Small JSON encoder/decoder for the wire protocol.
-- Encoding: Lua tables with consecutive integer keys from 1 become arrays,
-- other tables become objects. json.empty_array encodes as [].
-- Decoding: null becomes nil (absent keys).

local M = {}

M.empty_array = setmetatable({}, { __jsonarray = true })

---------------------------------------------------------------- encode

local escapes = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(s)
  return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
    return escapes[c] or ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function isArray(t)
  if getmetatable(t) and getmetatable(t).__jsonarray then return true end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" then return false end
    n = n + 1
  end
  return n == #t
end

local encodeValue

local function encodeTable(t, out)
  if isArray(t) then
    out[#out + 1] = "["
    for i, v in ipairs(t) do
      if i > 1 then out[#out + 1] = "," end
      encodeValue(v, out)
    end
    out[#out + 1] = "]"
  else
    out[#out + 1] = "{"
    local first = true
    for k, v in pairs(t) do
      assert(type(k) == "string", "object keys must be strings")
      if not first then out[#out + 1] = "," end
      first = false
      out[#out + 1] = encodeString(k)
      out[#out + 1] = ":"
      encodeValue(v, out)
    end
    out[#out + 1] = "}"
  end
end

encodeValue = function(v, out)
  local t = type(v)
  if t == "table" then
    encodeTable(v, out)
  elseif t == "string" then
    out[#out + 1] = encodeString(v)
  elseif t == "number" then
    out[#out + 1] = (v % 1 == 0) and ("%d"):format(v) or ("%.14g"):format(v)
  elseif t == "boolean" then
    out[#out + 1] = tostring(v)
  elseif t == "nil" then
    out[#out + 1] = "null"
  else
    error("cannot encode " .. t)
  end
end

function M.encode(v)
  local out = {}
  encodeValue(v, out)
  return table.concat(out)
end

---------------------------------------------------------------- decode

local function skipWs(s, i)
  local _, j = s:find("^[ \t\r\n]*", i)
  return j + 1
end

local decodeValue

local unescapes = {
  ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f",
  n = "\n", r = "\r", t = "\t",
}

local function decodeString(s, i)
  if s:sub(i, i) ~= '"' then error("expected string at " .. i) end
  local parts = {}
  i = i + 1
  while true do
    local j = s:find('["\\]', i)
    if not j then error("unterminated string") end
    parts[#parts + 1] = s:sub(i, j - 1)
    if s:sub(j, j) == '"' then
      return table.concat(parts), j + 1
    end
    local esc = s:sub(j + 1, j + 1)
    if esc == "u" then
      local code = tonumber(s:sub(j + 2, j + 5), 16)
      if not code then error("bad \\u escape at " .. j) end
      parts[#parts + 1] = utf8.char(code)
      i = j + 6
    else
      local ch = unescapes[esc]
      if not ch then error("bad escape \\" .. esc) end
      parts[#parts + 1] = ch
      i = j + 2
    end
  end
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
    if c ~= "," then error("expected , or ] at " .. i) end
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
    if s:sub(i, i) ~= ":" then error("expected : at " .. i) end
    v, i = decodeValue(s, skipWs(s, i + 1))
    obj[k] = v
    i = skipWs(s, i)
    local c = s:sub(i, i)
    if c == "}" then return obj, i + 1 end
    if c ~= "," then error("expected , or } at " .. i) end
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
  local num = s:match("^-?%d+%.?%d*[eE]?[+-]?%d*", i)
  if not num or #num == 0 then
    error("unexpected token at " .. i .. ": " .. s:sub(i, i + 10))
  end
  return tonumber(num), i + #num
end

function M.decode(s)
  local ok, v = pcall(function()
    local value, i = decodeValue(s, skipWs(s, 1))
    if skipWs(s, i) <= #s then error("trailing garbage") end
    return value
  end)
  if not ok then return nil, v end
  return v
end

return M
