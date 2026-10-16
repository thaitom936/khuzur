package.path='./lualib/?.lua;'..package.path
local engine=require 'rules.engine'
local dispatch,result,now= nil,nil,0
local messages,timers={},{}
engine.deal=function()
  return engine.newRound{players=2,dealer=1,
    hands={{'7C','8C','9C','TC','JC'},{'7D','8D','9D','TD','JD'}},trump='AS',stock={},
    config={decidePhase=false,exchangePhase=false,dealerTakesTrump=false}}
end
package.preload['skynet.queue']=function()return function()return function(fn,...)return fn(...)end end end
package.preload['skynet']=function()return {
 start=function(fn)fn()end,dispatch=function(_,fn)dispatch=fn end,
 retpack=function(...)result=table.pack(...)end,
 getenv=function(key)if key=='bot_delay' or key=='bot_delay_max' then return '300' end return nil end,
 now=function()return now end,self=function()return 99 end,exit=function()end,
 send=function(_,_,cmd,_,msg)if cmd=='push' then messages[#messages+1]=msg end end,
 call=function()return true end,
 timeout=function(delay,fn)timers[#timers+1]={delay=delay,fn=fn}end,
}end
local function call(cmd,...)dispatch(0,0,cmd,...);return table.unpack(result,1,result.n)end
local function latest(kind)
  for i=#messages,1,-1 do if messages[i].push==kind then return messages[i]end end
end
dofile('service/room.lua')
call('init',{mode='friend',code='cd-test',size=2,players={
 {uid=1,name='Human',agent=11,fd=11},{bot=true,name='Bot'},
}})
assert(latest('turn').seat==1)
assert(latest('turn').deadline==1500 and latest('turn').turn_duration==1500,'bot CD must start at 15s')
local botTimer=timers[#timers]
assert(botTimer.delay==300,'bot may play before the CD expires')
now=300;botTimer.fn()
assert(latest('turn').seat==0)
assert(latest('turn').deadline==1500 and latest('turn').turn_duration==1500,'human CD must start at 15s')
assert(timers[#timers].delay==1500,'human gets the full 15s')
now=500
call('watch',{uid=3,agent=13,fd=13})
assert(latest('snapshot').deadline==1300 and latest('snapshot').turn_duration==1500,'late entry must preserve remaining/full times separately')
print('Turn CD PASS: bot and human get 15-second display budget, bots act early, snapshot preserves full duration')
