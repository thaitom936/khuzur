package.path='./lualib/?.lua;'..package.path
local dispatch,answer;local sent={};local stored={};local nextId=0
local memberships={[1]={club_id=1,role='owner'},[2]={club_id=1,role='member'}}
local blocked,mutes={},{};local current={[1]=true,[2]=true,[3]=true,[4]=true}
package.preload['skynet.manager']=function()return {}end
package.preload['skynet.queue']=function()return function()return function(fn,...)return fn(...)end end end
package.preload['chat_media']=function()return {call=function()return nil,'media_unavailable'end}end
package.preload['skynet']=function()return {
 start=function(fn)fn()end,register=function()end,dispatch=function(_,fn)dispatch=fn end,
 retpack=function(...)answer=table.pack(...)end,
 send=function(_,_,cmd,uid,msg)if cmd=='push_to' then sent[#sent+1]={uid=uid,msg=msg}end end,
 call=function(service,_,cmd,...)
  local a=table.pack(...)
  if service=='.hub' then
   if cmd=='chat_current' then return current[a[1]] and a[2]==11 and a[3]==a[1] end
   if cmd=='chat_table' then return a[4]=='table:test' and {write=a[1]==1,moderator=a[1]==1} or nil end
  end
  if cmd=='chat_member' then local m=memberships[a[1]];return m and m.club_id==a[2] and m or nil end
  if cmd=='chat_muted' then return mutes[a[2]..a[1]]==true end
  if cmd=='chat_blocked' then return blocked[a[1]..':'..a[2]]==true end
  if cmd=='chat_block' then blocked[a[1]..':'..a[2]]=a[3];return {ok=true} end
  if cmd=='chat_mute' then mutes[a[2]..a[3]]=true;return {ok=true} end
  if cmd=='chat_history' then return {messages={},has_more=false} end
  if cmd=='chat_send' then
   local old=stored[a[4]];if old then return {message=old,duplicate=true}end
   nextId=nextId+1;local row={id=nextId,uid=a[1],channel=a[3],nonce=a[4],body=a[5]};stored[a[4]]=row
   return {message=row}
  end
  if cmd=='chat_get' then for _,row in pairs(stored)do if row.id==a[1] then return row end end end
  if cmd=='chat_delete' then
   local row;for _,v in pairs(stored)do if v.id==a[2]then row=v end end
   if row.uid~=a[1] and not a[3]then return nil,'chat_forbidden'end
   return {id=a[2]}
  end
  if cmd=='club_leave' then local m=memberships[a[1]];memberships[a[1]]=nil;return {club_id=m.club_id}end
  if cmd=='chat_media_quota' then return true end
  error('unexpected '..cmd)
 end,
}end
dofile('service/chat.lua')
local function call(uid,cmd,args)
 local msg=args or {};msg.cmd=cmd;dispatch(0,0,cmd:match('^chat_media_') and 'media' or 'request',uid,'Test',11,uid,msg)
 return table.unpack(answer,1,answer.n)
end
local function reject(uid,cmd,args,err)local r,e=call(uid,cmd,args);assert(not r and e==err,tostring(e))end
local r=call(1,'chat_open',{channel='club:1'});assert(r.capabilities.moderator and r.capabilities.write)
assert(call(2,'chat_open',{channel='club:1'}))
reject(3,'chat_open',{channel='club:1'},'club_not_member')
reject(1,'chat_open',{channel='club:01'},'chat_bad_channel')
reject(1,'chat_open',{channel='club:1e0'},'chat_bad_channel')
local before=#sent
local sentMsg=call(1,'chat_send',{channel='club:1',nonce='abcdefgh',body='Hello'});assert(sentMsg.message.id==1 and #sent==before+2)
assert(call(1,'chat_send',{channel='club:1',nonce='abcdefgh',body='Hello'}).duplicate);assert(#sent==before+2)
assert(call(2,'chat_block',{target=1,on=true}));before=#sent
assert(call(1,'chat_send',{channel='club:1',nonce='abcdefgi',body='blocked'}));assert(#sent==before+1)
reject(2,'chat_delete',{channel='club:1',id=1},'chat_forbidden')
reject(1,'chat_delete',{channel='lobby:en',id=1},'chat_not_found')
assert(call(1,'chat_mute',{channel='club:1',target=2,seconds=3600}))
reject(2,'chat_send',{channel='club:1',nonce='abcdefgj',body='muted'},'chat_muted')
assert(call(2,'club_leave',{}))
reject(2,'chat_history',{channel='club:1'},'club_not_member')
assert(call(1,'chat_open',{channel='table:test'}).capabilities.write)
assert(call(2,'chat_open',{channel='table:test'}).capabilities.write==false)
reject(2,'chat_send',{channel='table:test',nonce='abcdefgk',body='spectator'},'chat_read_only')
for uid,lang in ipairs({'en','mn','zh','ru'}) do
 local scope='lobby:'..lang
 local lobby=call(uid,'chat_open',{channel=scope});assert(lobby.capabilities.media and lobby.capabilities.write)
 for _,mime in ipairs({'image/jpeg','audio/mp4','video/mp4'}) do
  reject(uid,'chat_media_prepare',{channel=scope,mime=mime,size=100},'media_unavailable')
 end
end
reject(3,'chat_open',{channel='lobby:invalid'},'chat_bad_channel')
reject(2,'chat_media_prepare',{channel='table:test',mime='image/jpeg',size=100},'chat_read_only')
reject(1,'chat_mute',{channel='lobby:en',target=3,seconds=3600},'chat_forbidden')
mutes['lobby:en'..3]=true
reject(3,'chat_media_prepare',{channel='lobby:en',mime='image/jpeg',size=100},'chat_muted')
reject(1,'chat_media_prepare',{channel='club:1',mime='image/jpeg',size=100},'media_unavailable')
current[1]=false
reject(1,'chat_send',{channel='club:1',nonce='abcdefgl',body='stale session'},'chat_forbidden')
print('Chat actor PASS: membership, canonical channel IDs, spectators, moderation, blocked delivery, deduplication, leave and session binding')
