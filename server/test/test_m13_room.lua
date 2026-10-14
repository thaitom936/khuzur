package.path='./lualib/?.lua;'..package.path
local engine=require 'rules.mongol13'
local deal=engine.deal
local st,dispatch,result
engine.deal=function(args) st=deal(args); return st end
local messages={}
package.preload['skynet.queue']=function() return function() return function(fn,...) return fn(...) end end end
package.preload['skynet']=function() return {
 start=function(fn) fn() end,dispatch=function(_,fn) dispatch=fn end,
 retpack=function(...) result=table.pack(...) end,getenv=function() return nil end,
 send=function(_,_,cmd,fd,msg) if cmd=='push' then messages[#messages+1]={fd=fd,msg=msg} end end,
 call=function() return true end,self=function() return 99 end,now=function() return 0 end,
 timeout=function() end,exit=function() end,
} end
local function call(cmd,...) dispatch(0,0,cmd,...);return table.unpack(result,1,result.n) end
local function last(fd,kind)
 for i=#messages,1,-1 do local e=messages[i];if e.fd==fd and e.msg.push==kind then return e.msg end end
end
dofile('service/room.lua')
call('init',{mode='friend',game_type='mongol13',code='131313',size=4,locked=true,
 players={{uid=1,name='A',agent=11,fd=11}}})
assert(call('info').game_type=='mongol13' and not call('info').started)
local ok,err=call('start',1);assert(not ok and err=='m13_need_players')
assert(call('join',{uid=2,name='B',agent=12,fd=12}))
assert(not call('info').started,'friend room must wait for host')
ok,err=call('start',2);assert(not ok and err=='not_host')
assert(call('watch',{uid=3,agent=13,fd=13}))
assert(call('start',1));assert(st.numPlayers==2 and call('info').size==2)
assert(#last(11,'m13_state').hand==13 and not last(13,'m13_state').hand)
assert(last(13,'m13_state').you==-1)
assert(last(11,'game_start').game_type=='mongol13')
ok,err=call('action',3,{cmd='play_card',cards={'3D'}});assert(not ok and err=='not_in_room')
ok,err=call('action',st.turn,{cmd='decide',play=false});assert(not ok and err=='m13_cannot_pass')
assert(call('rejoin',1,21,21))
assert(#last(21,'snapshot').hand==13 and last(21,'snapshot').m13.opening)
local count=0
while st.phase=='playing' do
 count=count+1;assert(count<150)
 local seat=st.turn;local cards=engine.hint(st,seat)
 assert(call('action',seat,#cards>0 and {cmd='play_card',cards=cards} or {cmd='decide',play=false}))
 assert(not last(13,'m13_state').hand,'spectator private hand leak')
end
assert(last(21,'game_end').winners[1]==st.winners[1]-1)
assert(last(13,'game_end'),'spectator must see the result')
print('M13 room: host-only start, no filler bots, spectator privacy, reconnect, full game passed')
