
package.path='./lualib/?.lua;'..package.path
local engine=require 'rules.thousand';local deal=engine.deal
local st,dispatch,result;local messages,results,timers={},0,{}
engine.deal=function(args) st=deal(args);return st end
package.preload['skynet.queue']=function() return function() return function(fn,...) return fn(...) end end end
package.preload['skynet']=function() return {
 start=function(fn) fn() end,dispatch=function(_,fn) dispatch=fn end,
 retpack=function(...) result=table.pack(...) end,getenv=function() return nil end,
 send=function(_,_,cmd,fd,msg) if cmd=='push' then messages[#messages+1]={fd=fd,msg=msg} end end,
 call=function(_,_,cmd) if cmd=='game_result' then results=results+1 end;return true end,
 self=function() return 99 end,now=function() return 0 end,timeout=function(t,f) timers[#timers+1]={t=t,f=f} end,exit=function() end,
} end
local function call(cmd,...) dispatch(0,0,cmd,...);return table.unpack(result,1,result.n) end
local function last(fd,kind) for i=#messages,1,-1 do local e=messages[i];if e.fd==fd and e.msg.push==kind then return e.msg end end end
dofile('service/room.lua')
assert(call('init',{mode='friend',game_type='thousand',code='661000',size=3,locked=true,
 players={{uid=1,name='A',agent=11,fd=11}}}))
local ok,err=call('start',1);assert(not ok and err=='thousand_need_players')
assert(call('join',{uid=2,name='B',agent=12,fd=12}))
assert(not call('start',1));assert(call('join',{uid=3,name='C',agent=13,fd=13}))
assert(not call('info').started);assert(not call('start',2))
assert(call('watch',{uid=4,agent=14,fd=14}));assert(call('start',1))
assert(st.numPlayers==3 and #st.stock==3)
assert(#last(11,'thousand_state').hand==7 and not last(14,'thousand_state').hand)
assert(last(14,'thousand_state').trump==nil and last(14,'thousand_state').trump_suit==-1)
assert(call('rejoin',1,21,21));assert(last(21,'snapshot').thousand and #last(21,'snapshot').hand==7)
assert(not call('action',4,{cmd='thousand_action',action='pass'}))
for round=1,200 do
 while st.phase~='round_end' and st.phase~='game_end' do
  local a=engine.hint(st,st.turn)
  assert(call('action',st.turn,{cmd='thousand_action',action=a.action,value=a.value,announce=a.announce}))
  assert(not last(14,'thousand_state').hand)
 end
 assert(last(21,'round_end') and last(14,'round_end'))
 if st.phase=='game_end' then break end
 local previous=st;local scores={};for i,p in ipairs(st.players) do scores[i]=p.score end
 local timer;for i=#timers,1,-1 do if timers[i].t==500 then timer=timers[i];break end end
 assert(timer);timer.f()
 assert(st~=previous and st.stage=='bid')
 for i,p in ipairs(st.players) do assert(p.score==scores[i] and p.barrel==previous.players[i].barrel and p.attempts==previous.players[i].attempts) end
end
assert(st.phase=='game_end' and last(21,'game_end') and last(14,'game_end'))
assert(call('info').started);local count=results
assert(not call('start',2));assert(call('start',1));assert(st.stage=='bid' and st.players[1].score==0)
assert(results==count);assert(#last(21,'thousand_state').hand==7)
print('Thousand room PASS: 3 humans, host control, privacy, reconnect, round carry, whole match and rematch')
