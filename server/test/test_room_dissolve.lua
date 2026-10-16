package.path = './lualib/?.lua;' .. package.path
local dispatch, result
local pushes, refunds, closed = {}, {}, {}
package.preload['skynet.queue'] = function()
  return function() return function(fn, ...) return fn(...) end end
end
package.preload['skynet'] = function() return {
  start=function(fn) fn() end, dispatch=function(_, fn) dispatch=fn end,
  retpack=function(...) result=table.pack(...) end, getenv=function() return nil end,
  now=function() return 0 end, self=function() return 99 end,
  timeout=function() end, exit=function() end,
  send=function(service, _, cmd, uid, msg)
    if cmd=='push' then pushes[#pushes+1]={fd=uid,msg=msg} end
    if service=='.db' and cmd=='coins_add' then refunds[#refunds+1]={uid,msg} end
  end,
  call=function(service, _, cmd, room, uids)
    if service=='.hub' and cmd=='room_closed' then closed[#closed+1]=uids end
    return true
  end,
} end
local function call(cmd, ...)
  dispatch(0,0,cmd,...); return table.unpack(result,1,result.n)
end
local function init()
  dofile('service/room.lua')
  call('init',{mode='friend',code='dissolve-test',size=3,stake=10,players={
    {uid=1,name='Host',agent=11,fd=11}, {uid=2,name='Guest',agent=12,fd=12},
  }})
end
init()
assert(call('watch',{uid=3,agent=13,fd=13}))
local ok,err=call('dissolve',2); assert(not ok and err=='not_host')
assert(call('dissolve',1))
assert(#closed==1 and #closed[1]==2)
assert(#refunds==2 and refunds[1][2]==10 and refunds[2][2]==10)
for _,fd in ipairs({11,12,13}) do
  local found=false
  for _,p in ipairs(pushes) do
    if p.fd==fd and p.msg.push=='room_dissolved' and p.msg.code=='dissolve-test' then found=true end
  end
  assert(found,'missing notification')
end
ok,err=call('dissolve',1); assert(not ok and err=='not_in_room')
assert(#refunds==2 and #closed==1,'duplicate dissolution must not refund twice')
assert(not call('join',{uid=4,name='Late'}))
assert(not call('start',1))
init()
assert(call('start',1))
ok,err=call('dissolve',1); assert(not ok and err=='already_started')
print('Room dissolution PASS: host-only, pre-game only, notifications, refunds, idempotency')
