-- Run from server/ with skynet/3rd/lua/lua test/test_room_rules_v2.lua.
package.path = './lualib/?.lua;' .. package.path
local engine = require 'rules.engine'
local st, deals, dispatch, result = nil, 0
local messages, timers = {}, {}
local origDefault = engine.defaultConfig
engine.defaultConfig = function()
  local c = origDefault(); c.startScore = 100; c.dealerTakesTrump = false; return c
end
engine.deal = function(args)
  deals = deals + 1
  if deals > 1 then assert(args.passStreaks[2] == deals - 1, 'streak lost between rounds') end
  st = engine.newRound {
    players=3, dealer=1, config=args.config, scores=args.scores, passStreaks=args.passStreaks,
    hands={{'AC','KC','QC','JC','TC'},{'9C','8C','7C','AD','KD'},{'QD','JD','TD','9D','8D'}},
    trump='7H', stock={},
  }
  return st
end
package.preload['skynet.queue'] = function() return function() return function(fn, ...) return fn(...) end end end
package.preload['skynet'] = function()
  return {
    start=function(fn) fn() end, dispatch=function(_, fn) dispatch=fn end,
    retpack=function(...) result=table.pack(...) end, getenv=function() return nil end,
    send=function(_, _, cmd, _, msg) if cmd=='push' then messages[#messages+1]=msg end end,
    call=function() return true end, self=function() return 99 end,
    now=function() return 0 end,
    timeout=function(_, fn) timers[#timers+1]=fn end, exit=function() end,
  }
end
local function call(cmd, ...)
  dispatch(0, 0, cmd, ...); return table.unpack(result, 1, result.n)
end
local function latest(kind)
  for i=#messages,1,-1 do if messages[i].push==kind then return messages[i] end end
end
dofile('service/room.lua')
call('init',{mode='friend',code='rules-test',size=3,players={
  {uid=1,name='A',agent=11,fd=11,online=true},
  {uid=2,name='B',agent=12,fd=12,online=true},
  {uid=3,name='C',agent=13,fd=13,online=true}}})
for round=1,3 do
  assert(call('action',2,{cmd='decide',play=false}))
  assert(latest('turn').can_pass==false, 'false must survive the wire')
  assert(call('action',3,{cmd='decide',play=true}))
  assert(call('action',1,{cmd='decide',play=true}))
  local count=0
  while st.phase=='playing' do
    count=count+1; assert(count<=10)
    assert(call('action',st.turn,{cmd='play_card',card=engine.legalCards(st,st.turn)[1]}))
  end
  assert(st.phase=='round_end')
  -- Run queued callbacks; turn guards make previous-round callbacks no-ops.
  local pending=timers; timers={}
  for _,fn in ipairs(pending) do if deals==round then fn() end end
  assert(deals==round+1)
end
assert(latest('turn').can_pass==false, 'fourth-round pass must be disabled')
call('rejoin',2,22,22)
assert(latest('snapshot').can_pass==false, 'reconnect must retain forced participation')
local ok,err=call('action',2,{cmd='decide',play=false})
assert(not ok and err=='must_play_pass_streak')
assert(call('action',2,{cmd='decide',play=true}))
assert(st.players[2].passStreak==0)
print('Room v2: cross-round streaks, forced-pass wire state and reconnect passed')
