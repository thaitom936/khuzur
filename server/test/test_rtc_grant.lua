-- No network or database: run with skynet/3rd/lua/lua test/test_rtc_grant.lua.
package.path = './lualib/?.lua;' .. package.path
local dispatch, result
package.preload['skynet.queue'] = function() return function() return function(fn, ...) return fn(...) end end end
package.preload['skynet'] = function()
  local s = {}
  function s.start(fn) fn() end
  function s.dispatch(_, fn) dispatch = fn end
  function s.retpack(...) result = table.pack(...) end
  function s.getenv() return nil end
  function s.send() end
  function s.call() return true end
  function s.self() return 99 end
  function s.now() return 0 end
  function s.timeout() end
  return s
end
local function call(cmd, ...)
  dispatch(0, 0, cmd, ...)
  return table.unpack(result, 1, result.n)
end
dofile('service/room.lua')
call('init', { mode = 'friend', code = '123456', size = 5,
  players = { { uid = 42, name = 'A', agent = 100, fd = 10 } } })
local grant = assert(call('rtc_grant', 42, 100, 10))
assert(grant.uid == 42 and grant.code == '123456' and #grant.channel == 35)
assert(not call('rtc_grant', 43, 100, 10), 'spectator/stranger denied')
assert(not call('rtc_grant', 42, 101, 10), 'wrong agent denied')
assert(not call('rtc_grant', 42, 100, 11), 'wrong socket denied')
call('rejoin', 42, 101, 11)
assert(not call('rtc_grant', 42, 100, 10), 'superseded login denied')
assert(call('rtc_grant', 42, 101, 11).channel == grant.channel, 'renewal stable within room')
call('join', { uid = 43, name = 'B', agent = 102, fd = 12 })
assert(call('rtc_grant', 43, 102, 12).channel == grant.channel, 'same room shares channel')
call('leave', 42)
assert(not call('rtc_grant', 42, 101, 11), 'leaver denied renewal')
assert(call('rtc_grant', 43, 102, 12).uid == 43, 'uid stable after seat shift')
call('offline', 43)
assert(not call('rtc_grant', 43, 102, 12), 'offline player denied')
dofile('service/room.lua')
call('init', { mode = 'friend', code = '123456', size = 5,
  players = { { uid = 42, name = 'A', agent = 100, fd = 10 } } })
assert(call('rtc_grant', 42, 100, 10).channel ~= grant.channel, 'reused room code has fresh channel')
print('RTC grant: membership, session binding, renewal, seat shifts, channel isolation passed')
