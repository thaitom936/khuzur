package.path='./lualib/?.lua;'..package.path
local engine=require 'rules.durak';local deal=engine.deal
local st,dispatch,result;local messages,results={},0
engine.deal=function(args) st=deal(args);return st end
package.preload['skynet.queue']=function() return function() return function(fn,...) return fn(...) end end end
package.preload['skynet']=function() return {
 start=function(fn) fn() end,dispatch=function(_,fn) dispatch=fn end,
 retpack=function(...) result=table.pack(...) end,getenv=function() return nil end,
 send=function(_,_,cmd,fd,msg) if cmd=='push' then messages[#messages+1]={fd=fd,msg=msg} end end,
 call=function(_,_,cmd) if cmd=='game_result' then results=results+1 end; return true end,
 self=function() return 99 end,now=function() return 0 end,timeout=function() end,exit=function() end,
} end
local function call(cmd,...) dispatch(0,0,cmd,...);return table.unpack(result,1,result.n) end
local function last(fd,kind) for i=#messages,1,-1 do local e=messages[i];if e.fd==fd and e.msg.push==kind then return e.msg end end end
dofile('service/room.lua')
assert(call('init',{mode='friend',game_type='durak',game_options={deckSize=36,transfer=true,allowDraw=true},code='662244',size=6,locked=true,
 players={{uid=1,name='A',agent=11,fd=11}}}))
assert(not call('start',1))
assert(call('join',{uid=2,name='B',agent=12,fd=12}))
assert(call('join',{uid=3,name='C',agent=13,fd=13}))
assert(not call('info').started,'must wait for host')
assert(not call('start',2),'host only')
assert(call('watch',{uid=4,agent=14,fd=14}))
assert(call('start',1))
assert(st.numPlayers==3 and st.config.transfer and #st.stock==18)
assert(#last(11,'durak_state').hand==6 and not last(14,'durak_state').hand)
assert(call('rejoin',1,21,21));assert(last(21,'snapshot').durak and #last(21,'snapshot').hand==6)
assert(not call('action',4,{cmd='durak_action',action='attack',cards={'6C'}}))
local moves=0
while st.phase=='playing' do
 moves=moves+1;assert(moves<2500)
 local a=engine.hint(st,st.turn)
 assert(call('action',st.turn,{cmd='durak_action',action=a.action,cards=a.cards,target=a.target and a.target-1}))
 assert(not last(14,'durak_state').hand)
end
assert(last(21,'game_end') and last(14,'game_end'))
assert(call('info').started,'room remains for rematch')
local count=results
assert(not call('start',2),'guest cannot start rematch')
assert(call('start',1));assert(st.phase=='playing' and st.bout==1)
assert(#last(21,'durak_state').hand==6)
assert(results==count,'rematch must not double-count result')
print('Durak room: host-only start/rematch, spectator privacy, reconnection, full game passed')
