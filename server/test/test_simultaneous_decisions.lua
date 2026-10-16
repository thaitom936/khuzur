package.path = './lualib/?.lua;' .. package.path
local engine = require 'rules.engine'
local st, dispatch, result, now
local messages, timers = {}, {}
now = 0
local originalDeal = engine.deal
engine.deal = function(args)
  args.config.exchangePhase = false
  args.config.dealerTakesTrump = false
  st = originalDeal(args)
  return st
end
package.preload['skynet.queue'] = function()
  return function() return function(fn, ...) return fn(...) end end
end
package.preload['skynet'] = function() return {
  start=function(fn) fn() end, dispatch=function(_,fn) dispatch=fn end,
  retpack=function(...) result=table.pack(...) end,
  getenv=function(k) if k=='bot_delay' or k=='bot_delay_max' then return '300' end return nil end,
  now=function() return now end, self=function() return 99 end, exit=function() end,
  send=function(_,_,cmd,fd,msg)
    if cmd=='push' then messages[#messages+1]={fd=fd,msg=msg} end
  end,
  call=function() return true end,
  timeout=function(delay,fn) timers[#timers+1]={at=now+delay,fn=fn} end,
} end
local function call(cmd,...)
  dispatch(0,0,cmd,...); return table.unpack(result,1,result.n)
end
local function latest(kind,fd)
  for i=#messages,1,-1 do
    local m=messages[i]
    if m.msg.push==kind and (not fd or m.fd==fd) then return m.msg end
  end
end
local function due(time)
  now=time
  local pending=timers; timers={}
  for _,t in ipairs(pending) do
    if t.at<=now then t.fn() else timers[#timers+1]=t end
  end
end
dofile('service/room.lua')
assert(call('init',{mode='friend',code='simultaneous-test',size=4,players={
  {uid=1,name='A',agent=11,fd=11,online=true},
  {uid=2,name='B',agent=12,fd=12,online=true},
  {bot=true,name='C'},{bot=true,name='D'},
}}))
assert(latest('turn',11).deadline==1500 and latest('turn',12).deadline==1500)
-- Choose a human independently of the engine's compatibility turn cursor.
local human = st.turn==1 and 2 or 1
local other = human==1 and 2 or 1
now=200
assert(call('action',human,{cmd='decide',play=false}))
assert(st.players[human].decision=='pass')
assert(latest('turn',other==1 and 11 or 12).deadline==1300,'partial decisions must not restart CD')
local ok,err=call('action',human,{cmd='decide',play=true})
assert(not ok and err=='already_decided')
assert(st.players[human].passStreak==1,'duplicate must not change streak')
assert(call('rejoin',other,22,22))
assert(latest('snapshot',22).deadline==1300)
assert(latest('snapshot',22).config.simultaneousDecisions)
assert(call('offline',other))
assert(call('rejoin',other,22,22))
due(500)
assert(st.players[3].decision~='none' and st.players[4].decision~='none','bots decide independently')
assert(st.players[other].decision=='none','rejoining cancels the offline bot timer')
assert(st.phase=='deciding')
assert(latest('turn',22).deadline==1000)
-- Only the remaining human times out at the original common deadline.
due(1500)
assert(st.players[other].decision~='none' and st.phase=='playing')
local playingTurn=st.turn
due(1500)
assert(st.turn==playingTurn and #st.trick==0,'obsolete decision timers cannot play cards')
print('Simultaneous decisions PASS: independent inputs/bots, common CD, reconnect, duplicate and stale timer guards')
