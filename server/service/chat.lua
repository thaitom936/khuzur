local skynet=require 'skynet'
require 'skynet.manager'
local queue=require 'skynet.queue'()
local media=require 'chat_media'
local function newInviteToken()
 local source=io.open('/dev/urandom','rb');if not source then return nil end
 local bytes=source:read(16);source:close()
 if not bytes or #bytes~=16 then return nil end
 return (bytes:gsub('.',function(c)return ('%02x'):format(c:byte())end))
end
local CMD={};local subscriptions={};local rates={}
local function db(cmd,...) return skynet.call('.db','lua',cmd,...) end
local function admin(uid)
 for n in (os.getenv('CHAT_ADMIN_UIDS') or ''):gmatch('%d+') do if tonumber(n)==uid then return true end end
 return false
end
local function current(uid,agent,fd) return skynet.call('.hub','lua','chat_current',uid,agent,fd) end
local function authorize(uid,agent,fd,scope,posting)
 if not current(uid,agent,fd) then return nil,'chat_forbidden' end
 if type(scope)~='string' or #scope>100 then return nil,'chat_bad_channel' end
 local kind,id=scope:match('^(%a+):([%w_%-]+)$');local mod=admin(uid);local write=true
 if kind=='lobby' and (id=='en' or id=='mn' or id=='zh' or id=='ru') then
 elseif kind=='club' and id:match('^%d+$') and scope=='club:'..tonumber(id) then
  local m=db('chat_member',uid,tonumber(id));if not m and not mod then return nil,'club_not_member' end;mod=mod or m.role=='owner'
 elseif kind=='table' then
  local grant=skynet.call('.hub','lua','chat_table',uid,agent,fd,scope)
  if not grant and not mod then return nil,'chat_forbidden' end
  write=grant and grant.write or false
  if posting and not write then return nil,'chat_read_only' end
  mod=mod or (grant and grant.moderator)
 else return nil,'chat_bad_channel' end
 if posting and db('chat_muted',uid,scope) then return nil,'chat_muted' end
 return {channel=scope,moderator=mod,media=true,admin=admin(uid),write=write and not db('chat_muted',uid,scope)}
end
local function push(uid,msg) skynet.send('.hub','lua','push_to',uid,msg) end
local function broadcast(scope,msg)
 msg.channel=scope
 for uid,s in pairs(subscriptions[scope] or {}) do
  local grant=authorize(uid,s.agent,s.fd,scope,false)
  if not grant then subscriptions[scope][uid]=nil;push(uid,{push='chat_closed',channel=scope})
  elseif not msg.message or not db('chat_blocked',uid,msg.message.uid) then push(uid,msg) end
 end
end
local function limit(uid,kind,max,window)
 local key=uid..':'..kind;local r=rates[key];local now=os.time()
 if not r or now>=r.start+window then r={start=now,count=0};rates[key]=r end
 if r.count>=max then return false end;r.count=r.count+1;return true
end
function CMD.offline(uid,agent,fd)
 for _,members in pairs(subscriptions) do local s=members[uid];if s and s.agent==agent and s.fd==fd then members[uid]=nil end end
 return true
end
function CMD.close(scope) broadcast(scope,{push='chat_closed'});subscriptions[scope]=nil;return true end
function CMD.request(uid,name,agent,fd,msg)
 if not current(uid,agent,fd) then return nil,'chat_forbidden' end
 local cmd=msg.cmd
 if cmd=='club_list' then return db(cmd,uid)
 elseif cmd=='club_info' then return db(cmd,uid,msg.id)
 elseif cmd=='club_create' then
  if not limit(uid,'clubs',3,3600) then return nil,'chat_rate_limit' end
  return db(cmd,uid,msg.name,msg.description)
 elseif cmd=='club_invite_create' then
  if not limit(uid,'club_invites',20,3600) then return nil,'chat_rate_limit' end
  local token=newInviteToken();if not token then return nil,'chat_unavailable' end
  return db(cmd,uid,msg.id,token)
 elseif cmd=='club_invite_info' or cmd=='club_join' then
  if not limit(uid,'club_invite_checks',30,60) then return nil,'chat_rate_limit' end
  return db(cmd,uid,msg.token)
 elseif cmd=='club_leave' then
  local result,err=db(cmd,uid)
  if result then
   local scope='club:'..result.club_id;if subscriptions[scope] then subscriptions[scope][uid]=nil end
   push(uid,{push='chat_closed',channel=scope})
  end
  return result,err
 elseif cmd=='club_manage' then
  local result,err=db(cmd,uid,msg.id,msg.action,msg.target,msg.value)
  if result and msg.action=='kick' then
   local scope='club:'..msg.id;if subscriptions[scope] then subscriptions[scope][msg.target]=nil end
   push(msg.target,{push='chat_closed',channel=scope})
  end
  return result,err
 elseif cmd=='chat_block' then return db(cmd,uid,msg.target,msg.on)
 elseif cmd=='chat_reports' or cmd=='chat_report_resolve' then
  if not admin(uid) then return nil,'chat_forbidden' end
  return db(cmd,uid,msg.id)
 end
 local grant,err=authorize(uid,agent,fd,msg.channel,cmd=='chat_send' or cmd=='chat_media_prepare' or cmd=='chat_media_complete')
 if not grant then return nil,err end
 if cmd=='chat_open' or cmd=='chat_history' then
  local result,e=db('chat_history',uid,msg.channel,msg.before,msg.after)
  if not result then return nil,e end
  result.capabilities=grant
  if cmd=='chat_open' then
   subscriptions[msg.channel]=subscriptions[msg.channel] or {};subscriptions[msg.channel][uid]={agent=agent,fd=fd}
  end
  return result
 elseif cmd=='chat_close' then
  if subscriptions[msg.channel] then local s=subscriptions[msg.channel][uid];if s and s.agent==agent and s.fd==fd then subscriptions[msg.channel][uid]=nil end end
  return {ok=true}
 elseif cmd=='chat_send' then
  if msg.media_id and not grant.media then return nil,'chat_text_only' end
  if not limit(uid,'messages',5,5) then return nil,'chat_rate_limit' end
  local result,e=db('chat_send',uid,name,msg.channel,msg.nonce,msg.body or '',msg.media_id)
  if result and not result.duplicate then broadcast(msg.channel,{push='chat_message',message=result.message}) end
  return result,e
 elseif cmd=='chat_delete' or cmd=='chat_report' then
  local row=db('chat_get',msg.id);if not row or row.channel~=msg.channel then return nil,'chat_not_found' end
  if cmd=='chat_report' then return db(cmd,uid,msg.id,msg.reason) end
  local result,e=db(cmd,uid,msg.id,grant.moderator)
  if result then broadcast(msg.channel,{push='chat_deleted',id=msg.id}) end
  return result,e
 elseif cmd=='chat_mute' then
  if not grant.moderator then return nil,'chat_forbidden' end
  if msg.channel:match('^club:') and not db('chat_member',msg.target,tonumber(msg.channel:match('%d+$'))) then return nil,'club_not_member' end
  return db(cmd,uid,msg.channel,msg.target,msg.seconds or 3600)
 end
 return nil,'bad_cmd'
end
-- Network and media probing yield outside the chat mutation queue. Recheck access after yielding.
function CMD.media(uid,name,agent,fd,msg)
 local grant,err=authorize(uid,agent,fd,msg.channel,msg.cmd~='chat_media_url')
 if not grant then return nil,err end
 if not grant.media then return nil,'chat_text_only' end
 if msg.cmd=='chat_media_prepare' then
  if not limit(uid,'uploads',10,60) or not db('chat_media_quota',uid) then return nil,'chat_rate_limit' end
  local result,e=media.call('prepare',{mime=msg.mime,size=msg.size})
  if not result then return nil,e end
  local allowed,e2=authorize(uid,agent,fd,msg.channel,true);if not allowed then return nil,e2 end
  local saved,e3=db('chat_media_save',uid,msg.channel,result);if not saved then return nil,e3 end;return result
 end
 local f=db('chat_media_get',msg.id)
 if not f or f.channel~=msg.channel then return nil,'chat_not_found' end
 if f.expires_at<=os.time() or f.status=='deleted' then return nil,'media_expired' end
 local result,e
 if msg.cmd=='chat_media_complete' then
  if f.uid~=uid then return nil,'chat_forbidden' end
  if f.status=='ready' or f.status=='attached' then return {id=f.id,kind=f.kind,expires_at=f.expires_at} end
  if not db('chat_media_claim',f.id) then return nil,'media_not_ready' end
  result,e=media.call('verify',{key=f.object_key,size=f.size,kind=f.kind,expires_at=f.expires_at})
  if not result then db('chat_media_release',f.id);return nil,e end
  local allowed,e2=authorize(uid,agent,fd,msg.channel,true);if not allowed then db('chat_media_release',f.id);return nil,e2 end
  db('chat_media_ready',f.id,result);return {id=f.id,kind=f.kind,expires_at=f.expires_at}
 elseif msg.cmd=='chat_media_url' then
  if f.status~='attached' and f.uid~=uid then return nil,'chat_forbidden' end
  if f.status~='ready' and f.status~='attached' then return nil,'media_not_ready' end
  local key=msg.thumbnail and f.details and f.details.thumb_key or f.object_key
  result,e=media.call('url',{key=key,expires_at=f.expires_at})
  if not result then return nil,e end
  local allowed,e2=authorize(uid,agent,fd,msg.channel,false);if not allowed then return nil,e2 end
  local fresh=db('chat_media_get',f.id)
  if not fresh or fresh.status=='deleted' then return nil,'media_expired' end
  if db('chat_blocked',uid,f.uid) then return nil,'chat_forbidden' end
  return result
 end
 return nil,'bad_cmd'
end
skynet.start(function()
 skynet.dispatch('lua',function(_,_,cmd,...)
  if cmd=='media' then skynet.retpack(CMD.media(...)) else skynet.retpack(queue(CMD[cmd],...)) end
 end)
 skynet.register('.chat')
end)
