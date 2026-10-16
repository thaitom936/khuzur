"""Private diagnostic accounts; never uses a real R2 bucket or publishes media."""
import sys,time
sys.path.insert(0,'/opt/khuzur/server/test')
from rtc_billing_e2e import Client

def reject(c,cmd,err,**args):
    try:c.call(cmd,**args)
    except AssertionError as e:assert err in str(e),str(e)
    else:raise AssertionError('expected '+err)
def latest(c,kind):return next((m for m in reversed(c.pushes)if m.get('push')==kind),None)
stamp=str(time.time_ns());names=['chat-a-','chat-b-','chat-c-']
clients=[Client(name+stamp)for name in names];a,b,c=clients
club=None
def flush():
    for p in clients:p.call('ping',t=1)
try:
    scope='lobby:en';assert a.call('chat_open',channel=scope)['capabilities']['media'];b.call('chat_open',channel=scope)
    sent=a.call('chat_send',channel=scope,nonce='hello-'+stamp,body='Hello 😀 Монгол 中文 Русский')
    flush();assert latest(b,'chat_message')['message']['id']==sent['message']['id']
    duplicate=a.call('chat_send',channel=scope,nonce='hello-'+stamp,body='Hello 😀 Монгол 中文 Русский');assert duplicate['duplicate']
    reject(a,'chat_send','chat_nonce_conflict',channel=scope,nonce='hello-'+stamp,body='different')
    for mime in ('image/jpeg','audio/mp4','video/mp4'):
        try:
            grant=a.call('chat_media_prepare',channel=scope,mime=mime,size=100)
            assert grant['key'].startswith('chat/') and grant['mime']==mime
        except AssertionError as error:
            assert 'media_unavailable' in str(error),str(error)
    a.call('chat_delete',channel=scope,id=sent['message']['id']);flush();assert latest(b,'chat_deleted')['id']==sent['message']['id']
    created=a.call('club_create',name='Diagnostic '+stamp,description='Chat integration test')
    club=created['club']['id'];scope='club:'+str(club)
    reject(b,'club_join','club_invite_required',id=club)
    assert not b.call('club_list',search='Diagnostic')['clubs']
    reject(b,'club_info','club_not_member',id=club)
    token=a.call('club_invite_create',id=club)['token']
    assert b.call('club_invite_info',token=token)['club']['id']==club
    b.call('club_join',token=token)
    b.call('club_join',token=token)  # retry is idempotent
    reject(b,'club_invite_create','chat_forbidden',id=club)
    reject(b,'club_create','club_already_joined',name='Duplicate club')
    reject(c,'chat_open','club_not_member',channel=scope)
    reject(c,'chat_history','club_not_member',channel=scope)
    assert a.call('chat_open',channel=scope)['capabilities']['moderator']
    b.call('chat_open',channel=scope)
    sent=a.call('chat_send',channel=scope,nonce='club-'+stamp,body='Members only')
    flush();assert latest(b,'chat_message')['channel']==scope
    b.call('chat_report',channel=scope,id=sent['message']['id'],reason='Test report')
    reject(b,'chat_delete','chat_forbidden',channel=scope,id=sent['message']['id'])
    a.call('chat_mute',channel=scope,target=b.user['uid'],seconds=60)
    reject(b,'chat_send','chat_muted',channel=scope,nonce='muted-'+stamp,body='must fail')
    a.call('chat_mute',channel=scope,target=b.user['uid'],seconds=0)
    b.call('chat_block',channel=scope,target=a.user['uid'],on=True)
    assert not b.call('chat_history',channel=scope)['messages']
    b.call('chat_block',channel=scope,target=a.user['uid'],on=False)
    reject(b,'club_leave','club_transfer_first') if False else None
    reject(a,'club_leave','club_transfer_first')
    a.call('club_manage',id=club,action='transfer',target=b.user['uid'])
    a.call('club_leave');reject(a,'chat_history','club_not_member',channel=scope)
    reject(a,'club_join','club_invite_expired',token=token)  # former owner cannot invite
    token=b.call('club_invite_create',id=club)['token']
    a.call('club_join',token=token)
    clients[0].s.close();clients[0]=Client(names[0]+stamp);a=clients[0]
    assert a.call('chat_open',channel=scope,after=sent['message']['id']-1)['messages']
    b.call('club_manage',id=club,action='kick',target=a.user['uid'])
    reject(a,'chat_history','club_not_member',channel=scope)
    code=b.call('create_room',size=3,game_type='thousand',locked=True)['code']
    a.call('join_room',code=code);c.call('watch',code=code);flush()
    scope=latest(b,'room_update')['chat_channel']
    assert b.call('chat_open',channel=scope)['capabilities']['write']
    try:
        grant=b.call('chat_media_prepare',channel=scope,mime='image/jpeg',size=100)
        assert grant['key'].startswith('chat/') and len(grant['key'].split('/')[1])==8
    except AssertionError as error:
        assert 'media_unavailable' in str(error),str(error)
    assert not c.call('chat_open',channel=scope)['capabilities']['write']
    reject(c,'chat_send','chat_read_only',channel=scope,nonce='spectator-'+stamp,body='must fail')
    reject(c,'chat_media_prepare','chat_read_only',channel=scope,mime='image/jpeg',size=100)
    sent=b.call('chat_send',channel=scope,nonce='table-'+stamp,body='At this table')
    flush();assert latest(c,'chat_message')['message']['id']==sent['message']['id']
    a.call('leave_room');b.call('leave_room');flush()
    reject(b,'chat_history','chat_forbidden',channel=scope)
    assert latest(c,'chat_closed')
    print('Chat WSS PASS: multilingual persistence, nonce deduplication, club membership/transfer/kick, report/delete/mute/block, reconnect, table spectators and channel closure')
finally:
    for p in clients:
        try:p.call('leave_room')
        except Exception:pass
        try:p.call('club_leave')
        except Exception:pass
        p.s.close()
