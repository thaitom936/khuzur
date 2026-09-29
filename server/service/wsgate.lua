--- WebSocket gate: accepts connections and hands the fds to a pool of
--- ws_agent services, round robin.
local skynet = require "skynet"
local socket = require "skynet.socket"

skynet.start(function()
  local pool = tonumber(skynet.getenv "agent_pool") or 4
  local port = tonumber(skynet.getenv "ws_port") or 9601

  local agents = {}
  for i = 1, pool do
    agents[i] = skynet.newservice("ws_agent")
  end

  local balance = 1
  local id = socket.listen("0.0.0.0", port)
  socket.start(id, function(fd, addr)
    skynet.send(agents[balance], "lua", "accept", fd, addr)
    balance = balance % pool + 1
  end)
  skynet.error("[wsgate] listening on :" .. port)
end)
