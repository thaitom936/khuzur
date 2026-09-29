local skynet = require "skynet"

skynet.start(function()
  skynet.error("[main] khuzur server starting")

  local debug_port = tonumber(skynet.getenv "debug_port")
  if debug_port then
    skynet.newservice("debug_console", debug_port) -- binds 127.0.0.1 only
  end

  skynet.uniqueservice("db")
  skynet.uniqueservice("hub")
  skynet.uniqueservice("match")
  skynet.uniqueservice("wsgate")

  skynet.error("[main] khuzur server started")
  skynet.exit()
end)
