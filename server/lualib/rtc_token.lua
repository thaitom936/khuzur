-- Only trusted server code calls the loopback signer. Never accept a channel or
-- Agora uid from a client request. Keep HTTP timeouts out of the room actor.
local httpc = require "http.httpc"
local json = require "json"
local M = {}
httpc.timeout = 300

function M.issue(channel, uid)
  local secret = os.getenv("AGORA_TOKEN_SECRET")
  if not secret or secret == "" then return nil, "rtc_unavailable" end
  local port = tonumber(os.getenv("AGORA_TOKEN_PORT")) or 9760
  local ok, status, body = pcall(httpc.request, "POST", "127.0.0.1:" .. port,
    "/token", nil, { ["Content-Type"] = "application/json", Authorization = "Bearer " .. secret },
    json.encode { channel = channel, uid = uid })
  if not ok or status ~= 200 then return nil, "rtc_unavailable" end
  local parsed, data = pcall(json.decode, body)
  if not parsed or type(data) ~= "table" or type(data.token) ~= "string"
      or data.channel ~= channel or data.uid ~= uid then
    return nil, "rtc_unavailable"
  end
  return data
end

return M
