-- Real Skynet room actor -> authenticated loopback HTTP -> Agora 007 signer.
-- No game listener, Redis or MySQL is started by this integration test.
local skynet = require "skynet"
local token = require "rtc_token"

skynet.start(function()
  skynet.dispatch("lua", function() end) -- consume room pushes
  local ok, err = pcall(function()
    local room = skynet.newservice("room")
    assert(skynet.call(room, "lua", "init", {
      mode = "friend", code = "123456", size = 5,
      players = { { uid = 42, name = "Test", agent = skynet.self(), fd = 1 } },
    }))
    local grant = assert(skynet.call(room, "lua", "rtc_grant", 42, skynet.self(), 1))
    local response, issueErr = token.issue(grant.channel, grant.uid)
    assert(response, issueErr)
    assert(response.uid == 42 and response.channel == grant.channel)
    assert(response.token:sub(1, 3) == "007" and response.renew_after == 240)
    assert(not skynet.call(room, "lua", "rtc_grant", 43, skynet.self(), 1))
    assert(not skynet.call(room, "lua", "rtc_grant", 42, skynet.self(), 2))
    local second = assert(token.issue(grant.channel, grant.uid))
    assert(second.token ~= response.token, "renewal needs a fresh salt")
  end)
  io.stderr:write(ok and "RTC Skynet integration passed\n" or ("RTC FAIL: " .. tostring(err) .. "\n"))
  io.stderr:flush()
  os.exit(ok and 0 or 1)
end)
