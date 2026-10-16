-- Durable chat and minimal club membership. Called under the existing DB queue.
local json=require 'json'
local M={}
M.schema={
 [[CREATE TABLE IF NOT EXISTS chat_clubs (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,name VARCHAR(40) NOT NULL,owner_id INT UNSIGNED NOT NULL,description VARCHAR(300) NOT NULL DEFAULT '',status VARCHAR(12) NOT NULL DEFAULT 'active',created_at BIGINT NOT NULL) CHARSET=utf8mb4]],
 [[CREATE TABLE IF NOT EXISTS chat_members (uid INT UNSIGNED PRIMARY KEY,club_id BIGINT UNSIGNED NOT NULL,role VARCHAR(12) NOT NULL DEFAULT 'member',joined_at BIGINT NOT NULL,INDEX(club_id)) CHARSET=utf8mb4]],
 [[CREATE TABLE IF NOT EXISTS chat_member_events (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,uid INT UNSIGNED NOT NULL,club_id BIGINT UNSIGNED NOT NULL,action VARCHAR(16) NOT NULL,created_at BIGINT NOT NULL,INDEX(uid,created_at)) CHARSET=utf8mb4]],
 [[CREATE TABLE IF NOT EXISTS chat_club_invites (token CHAR(32) CHARACTER SET ascii PRIMARY KEY,club_id BIGINT UNSIGNED NOT NULL,inviter_uid INT UNSIGNED NOT NULL,expires_at BIGINT NOT NULL,INDEX(club_id),INDEX(expires_at))]],
 [[CREATE TABLE IF NOT EXISTS chat_messages (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,channel VARCHAR(100) CHARACTER SET ascii NOT NULL,uid INT UNSIGNED NOT NULL,name VARCHAR(32) NOT NULL,nonce VARCHAR(64) CHARACTER SET ascii NOT NULL,body VARCHAR(2000) NOT NULL,media_id CHAR(32) CHARACTER SET ascii,created_at BIGINT NOT NULL,deleted_at BIGINT,UNIQUE(channel,uid,nonce),INDEX(channel,id)) CHARSET=utf8mb4]],
 [[CREATE TABLE IF NOT EXISTS chat_media (id CHAR(32) CHARACTER SET ascii PRIMARY KEY,uid INT UNSIGNED NOT NULL,channel VARCHAR(100) CHARACTER SET ascii NOT NULL,object_key VARCHAR(100) CHARACTER SET ascii NOT NULL,kind VARCHAR(8) NOT NULL,mime VARCHAR(40) NOT NULL,size INT NOT NULL,created_at BIGINT NOT NULL,expires_at BIGINT NOT NULL,status VARCHAR(12) NOT NULL DEFAULT 'pending',metadata TEXT,INDEX(uid,created_at)) CHARSET=utf8mb4]],
 [[CREATE TABLE IF NOT EXISTS chat_blocks (uid INT UNSIGNED NOT NULL,target_uid INT UNSIGNED NOT NULL,PRIMARY KEY(uid,target_uid))]],
 [[CREATE TABLE IF NOT EXISTS chat_mutes (channel VARCHAR(100) CHARACTER SET ascii NOT NULL,uid INT UNSIGNED NOT NULL,until_at BIGINT NOT NULL,PRIMARY KEY(channel,uid))]],
 [[CREATE TABLE IF NOT EXISTS chat_reports (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,message_id BIGINT UNSIGNED NOT NULL,uid INT UNSIGNED NOT NULL,reason VARCHAR(300) NOT NULL,created_at BIGINT NOT NULL,status VARCHAR(12) NOT NULL DEFAULT 'pending',UNIQUE(message_id,uid)) CHARSET=utf8mb4]],
 [[CREATE TABLE IF NOT EXISTS chat_moderation (id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,channel VARCHAR(100) CHARACTER SET ascii NOT NULL,actor_uid INT UNSIGNED NOT NULL,target_id BIGINT UNSIGNED NOT NULL,action VARCHAR(16) NOT NULL,created_at BIGINT NOT NULL) CHARSET=utf8mb4]],
}
function M.new(getmysql,quote)
 local S={}
 local function q(sql)
  local db=getmysql();if not db then error('chat_unavailable') end
  local r=db:query(sql);if r.err then error('chat_database_failed') end;return r
 end
 local function text(s,max)
  return type(s)=='string' and #s<=max*4 and utf8.len(s) and utf8.len(s)<=max
 end
 local function integer(v) return type(v)=='number' and v%1==0 and v>=1 and v<=9007199254740991 end
 local function member(uid) return q(('SELECT * FROM chat_members WHERE uid=%d'):format(uid))[1] end
 function S.club_list(uid,search)
  local m=member(uid)
  local clubs=m and q(("SELECT c.*, (SELECT COUNT(*) FROM chat_members m WHERE m.club_id=c.id) AS members FROM chat_clubs c WHERE c.status='active' AND c.id=%d"):format(m.club_id)) or {}
  return {clubs=clubs,member=m}
 end
 function S.club_info(uid,id)
  if not integer(id) then return nil,'club_not_found' end
  local c=q(('SELECT * FROM chat_clubs WHERE id=%d AND status=\'active\''):format(id))[1]
  if not c then return nil,'club_not_found' end
  local m=member(uid);if not m or m.club_id~=id then return nil,'club_not_member' end
  local members=q(('SELECT m.uid,m.role,m.joined_at,u.name FROM chat_members m JOIN user u ON u.uid=m.uid WHERE club_id=%d ORDER BY m.joined_at,m.uid LIMIT 200'):format(id))
  return {club=c,members=members,member=member(uid)}
 end
 function S.club_create(uid,name,description)
  if not text(name,40) or name:match('^%s*$') or not text(description or '',300) then return nil,'club_bad_name' end
  if member(uid) then return nil,'club_already_joined' end
  q('START TRANSACTION')
  local ok,id=pcall(function()
   local r=q(('INSERT INTO chat_clubs(name,owner_id,description,created_at) VALUES(%s,%d,%s,%d)'):format(quote(name),uid,quote(description or ''),os.time()))
   q(('INSERT INTO chat_members(uid,club_id,role,joined_at) VALUES(%d,%d,\'owner\',%d)'):format(uid,r.insert_id,os.time()))
   q(('INSERT INTO chat_member_events(uid,club_id,action,created_at) VALUES(%d,%d,\'create\',%d)'):format(uid,r.insert_id,os.time()))
   return r.insert_id
  end)
  if not ok then q('ROLLBACK');return nil,'chat_database_failed' end
  q('COMMIT');return S.club_info(uid,id)
 end
 function S.club_invite_create(uid,id,token)
  local m=member(uid)
  if not integer(id) or not m or m.club_id~=id or m.role~='owner' then return nil,'chat_forbidden' end
  local expires=os.time()+7*86400
  q(('DELETE FROM chat_club_invites WHERE expires_at<=%d'):format(os.time()))
  q(('INSERT INTO chat_club_invites(token,club_id,inviter_uid,expires_at) VALUES(%s,%d,%d,%d)'):format(quote(token),id,uid,expires))
  return {token=token,expires_at=expires}
 end
 function S.club_invite_info(uid,token)
  if type(token)~='string' or #token~=32 or not token:match('^[a-f0-9]+$') then return nil,'club_invite_required' end
  local r=q(('SELECT i.club_id,i.inviter_uid,i.expires_at,c.name,c.description,u.name AS inviter FROM chat_club_invites i JOIN chat_clubs c ON c.id=i.club_id JOIN chat_members m ON m.uid=i.inviter_uid AND m.club_id=c.id AND m.role=\'owner\' JOIN user u ON u.uid=i.inviter_uid WHERE i.token=%s AND i.expires_at>%d AND c.status=\'active\''):format(quote(token),os.time()))[1]
  if not r then return nil,'club_invite_expired' end
  return {club={id=r.club_id,name=r.name,description=r.description},inviter=r.inviter,expires_at=r.expires_at}
 end
 function S.club_join(uid,token)
  local info,err=S.club_invite_info(uid,token);if not info then return nil,err end
  local id=info.club.id;local m=member(uid)
  if m then if m.club_id==id then return S.club_info(uid,id) end;return nil,'club_already_joined' end
  local count=q(('SELECT COUNT(*) AS n FROM chat_members WHERE club_id=%d'):format(id))[1].n
  if count>=200 then return nil,'club_full' end
  q('START TRANSACTION')
  q(('INSERT INTO chat_members(uid,club_id,joined_at) VALUES(%d,%d,%d)'):format(uid,id,os.time()))
  q(('INSERT INTO chat_member_events(uid,club_id,action,created_at) VALUES(%d,%d,\'join\',%d)'):format(uid,id,os.time()))
  q('COMMIT');return S.club_info(uid,id)
 end
 function S.club_leave(uid)
  local m=member(uid);if not m then return nil,'club_not_member' end
  local count=q(('SELECT COUNT(*) AS n FROM chat_members WHERE club_id=%d'):format(m.club_id))[1].n
  if m.role=='owner' and count>1 then return nil,'club_transfer_first' end
  q('START TRANSACTION');q(('DELETE FROM chat_members WHERE uid=%d'):format(uid))
  if m.role=='owner' then q(('UPDATE chat_clubs SET status=\'closed\' WHERE id=%d'):format(m.club_id)) end
  q(('INSERT INTO chat_member_events(uid,club_id,action,created_at) VALUES(%d,%d,\'leave\',%d)'):format(uid,m.club_id,os.time()))
  q('COMMIT');return {club_id=m.club_id}
 end
 function S.club_manage(uid,id,action,target,value)
  local m=member(uid);if not m or m.club_id~=id or m.role~='owner' then return nil,'chat_forbidden' end
  if action=='description' then
   if not text(value,300) then return nil,'bad_request' end
   q(('UPDATE chat_clubs SET description=%s WHERE id=%d'):format(quote(value),id))
  elseif action=='kick' or action=='transfer' then
   if not integer(target) or target==uid then return nil,'bad_request' end
   local t=member(target);if not t or t.club_id~=id then return nil,'club_not_member' end
   q('START TRANSACTION')
   if action=='kick' then q(('DELETE FROM chat_members WHERE uid=%d'):format(target))
   else
    q(('UPDATE chat_members SET role=\'member\' WHERE uid=%d'):format(uid))
    q(('UPDATE chat_members SET role=\'owner\' WHERE uid=%d'):format(target))
    q(('UPDATE chat_clubs SET owner_id=%d WHERE id=%d'):format(target,id))
   end
   q(('INSERT INTO chat_member_events(uid,club_id,action,created_at) VALUES(%d,%d,%s,%d)'):format(target,id,quote(action),os.time()))
   q('COMMIT')
  else return nil,'bad_request' end
  return S.club_info(uid,id)
 end
 function S.chat_member(uid,id) local m=member(uid);return m and m.club_id==id and m or nil end
 function S.chat_blocked(uid,target) return #q(('SELECT uid FROM chat_blocks WHERE uid=%d AND target_uid=%d'):format(uid,target))>0 end
 function S.chat_block(uid,target,on)
  if not integer(target) or target==uid or type(on)~='boolean' then return nil,'bad_request' end
  if on then q(('INSERT IGNORE INTO chat_blocks VALUES(%d,%d)'):format(uid,target))
  else q(('DELETE FROM chat_blocks WHERE uid=%d AND target_uid=%d'):format(uid,target)) end
  return {ok=true}
 end
 function S.chat_muted(uid,channel)
  return #q(('SELECT uid FROM chat_mutes WHERE uid=%d AND channel=%s AND until_at>%d'):format(uid,quote(channel),os.time()))>0
 end
 function S.chat_mute(actor,channel,target,seconds)
  if not integer(target) or target==actor or type(seconds)~='number' or seconds%1~=0 or seconds<0 or seconds>86400 then return nil,'bad_request' end
  q(('REPLACE INTO chat_mutes VALUES(%s,%d,%d)'):format(quote(channel),target,os.time()+seconds))
  q(('INSERT INTO chat_moderation(channel,actor_uid,target_id,action,created_at) VALUES(%s,%d,%d,\'mute\',%d)'):format(quote(channel),actor,target,os.time()))
  return {ok=true}
 end
 local function media(id)
  if type(id)~='string' or not id:match('^%x+$') or #id~=32 then return nil end
  local row=q('SELECT * FROM chat_media WHERE id='..quote(id))[1]
  if row and row.metadata then row.details=json.decode(row.metadata);row.metadata=nil end
  return row
 end
 local function wire(row)
  row.deleted=row.deleted_at~=nil
  if row.deleted then row.body='';row.media_id=nil
  elseif row.media_id then
   local f=media(row.media_id)
   if f then
    row.media={id=f.id,kind=f.kind,mime=f.mime,size=f.size,expires_at=f.expires_at,
     expired=f.expires_at<=os.time() or f.status=='deleted',duration=f.details and f.details.duration,width=f.details and f.details.width,height=f.details and f.details.height,
     thumbnail=f.details and f.details.thumb_key~=nil}
   end
  end
  return row
 end
 function S.chat_get(id) if not integer(id) then return nil end;return q(('SELECT * FROM chat_messages WHERE id=%d'):format(id))[1] end
 function S.chat_history(uid,channel,before,after)
  if before~=nil and not integer(before) or after~=nil and (type(after)~='number' or after%1~=0 or after<0) then return nil,'bad_request' end
  local range=before and (' AND m.id<'..before) or after and (' AND m.id>'..after) or ''
  local rows=q(('SELECT m.* FROM chat_messages m WHERE m.channel=%s%s AND NOT EXISTS(SELECT 1 FROM chat_blocks b WHERE b.uid=%d AND b.target_uid=m.uid) ORDER BY m.id %s LIMIT 50'):format(quote(channel),range,uid,after and 'ASC' or 'DESC'))
  for _,row in ipairs(rows) do wire(row) end
  if not after then local out={};for i=#rows,1,-1 do out[#out+1]=rows[i] end;rows=out end
  return {messages=rows,has_more=#rows==50}
 end
 function S.chat_send(uid,name,channel,nonce,body,mediaId)
  if type(nonce)~='string' or #nonce<8 or #nonce>64 or not nonce:match('^[%w%-]+$') or not text(body,500) then return nil,'chat_bad_message' end
  local old=q(('SELECT * FROM chat_messages WHERE channel=%s AND uid=%d AND nonce=%s'):format(quote(channel),uid,quote(nonce)))[1]
  if old then
   if old.body~=body or old.media_id~=mediaId then return nil,'chat_nonce_conflict' end
   return {message=wire(old),duplicate=true}
  end
  if S.chat_muted(uid,channel) then return nil,'chat_muted' end
  if mediaId then
   local f=media(mediaId)
   if not f or f.uid~=uid or f.channel~=channel or f.status~='ready' or f.expires_at<=os.time() then return nil,'media_not_ready' end
  elseif body:match('^%s*$') then return nil,'chat_bad_message' end
  q('START TRANSACTION')
  local r=q(('INSERT INTO chat_messages(channel,uid,name,nonce,body,media_id,created_at) VALUES(%s,%d,%s,%s,%s,%s,%d)'):format(quote(channel),uid,quote(name),quote(nonce),quote(body),mediaId and quote(mediaId) or 'NULL',os.time()))
  if mediaId then q('UPDATE chat_media SET status=\'attached\' WHERE id='..quote(mediaId)) end
  q('COMMIT')
  return {message=wire(S.chat_get(r.insert_id))}
 end
 function S.chat_delete(actor,id,moderator)
  local row=S.chat_get(id);if not row then return nil,'chat_not_found' end
  if row.uid~=actor and not moderator then return nil,'chat_forbidden' end
  q(('UPDATE chat_messages SET deleted_at=%d WHERE id=%d'):format(os.time(),id))
  if row.media_id then q('UPDATE chat_media SET status=\'deleted\' WHERE id='..quote(row.media_id)) end
  q(('INSERT INTO chat_moderation(channel,actor_uid,target_id,action,created_at) VALUES(%s,%d,%d,\'delete\',%d)'):format(quote(row.channel),actor,id,os.time()))
  return {id=id,channel=row.channel}
 end
 function S.chat_report(uid,id,reason)
  if not S.chat_get(id) or not text(reason or '',300) then return nil,'bad_request' end
  q(('INSERT IGNORE INTO chat_reports(message_id,uid,reason,created_at) VALUES(%d,%d,%s,%d)'):format(id,uid,quote(reason or ''),os.time()))
  return {ok=true}
 end
 function S.chat_reports(uid)
  return {reports=q('SELECT r.*,m.channel,m.body,m.uid AS sender_uid FROM chat_reports r JOIN chat_messages m ON m.id=r.message_id WHERE r.status=\'pending\' ORDER BY r.id LIMIT 100')}
 end
 function S.chat_report_resolve(uid,id)
  if not integer(id) then return nil,'bad_request' end
  q(('UPDATE chat_reports SET status=\'resolved\' WHERE id=%d'):format(id));return {ok=true}
 end
 function S.chat_media_get(id) return media(id) end
 function S.chat_media_quota(uid)
  local row=q(('SELECT COUNT(*) AS count,COALESCE(SUM(size),0) AS bytes FROM chat_media WHERE uid=%d AND created_at>%d'):format(uid,os.time()-86400))[1]
  return row.count<100 and row.bytes<200*1024*1024
 end
 function S.chat_media_save(uid,channel,f)
  local used=q(('SELECT COUNT(*) AS count,COALESCE(SUM(size),0) AS bytes FROM chat_media WHERE uid=%d AND created_at>%d'):format(uid,os.time()-86400))[1]
  if used.count>=100 or used.bytes+f.size>200*1024*1024 then return nil,'chat_rate_limit' end
  q(('INSERT INTO chat_media(id,uid,channel,object_key,kind,mime,size,created_at,expires_at) VALUES(%s,%d,%s,%s,%s,%s,%d,%d,%d)'):format(quote(f.id),uid,quote(channel),quote(f.key),quote(f.kind),quote(f.mime),f.size,f.created_at,f.expires_at))
  return true
 end
 function S.chat_media_ready(id,details)
  q(('UPDATE chat_media SET status=\'ready\',object_key=%s,metadata=%s WHERE id=%s AND status=\'verifying\' AND expires_at>%d'):format(quote(details.object_key),quote(json.encode(details)),quote(id),os.time()))
  return media(id)
 end
 function S.chat_media_claim(id)
  return q(('UPDATE chat_media SET status=\'verifying\' WHERE id=%s AND status=\'pending\' AND expires_at>%d'):format(quote(id),os.time())).affected_rows==1
 end
 function S.chat_media_release(id)
  q('UPDATE chat_media SET status=\'pending\' WHERE id='..quote(id)..' AND status=\'verifying\'');return true
 end
 return S
end
return M
