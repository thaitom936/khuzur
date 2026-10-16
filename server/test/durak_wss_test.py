"""Private Durak diagnostic game; no entry fee and no real media publication."""
import sys,time
sys.path.insert(0,'/opt/khuzur/server/test')
from rtc_billing_e2e import Client
def rank(c):return '23456789TJQKA'.index(c[0])
def beats(a,c,t):return (a[1]==c[1] and rank(c)>rank(a)) or c[1]==t and a[1]!=t
def choose(st,hand,seats):
 d=st['durak'];p=d['pairs'];stage=d['stage'];trump=st['trump'][1]
 hand=sorted(hand,key=lambda c:(c[1]==trump,rank(c),c[1]))
 if stage=='attack':return dict(action='attack',cards=[hand[0]])
 if stage=='add':
  allowed={rank(a['attack']) for a in p}|{rank(a['cover']) for a in p if a.get('cover')}
  if len(p)<d['limit']:
   for c in hand:
    if rank(c) in allowed:return dict(action='attack',cards=[c])
  return dict(action='finish')
 for i,a in enumerate(p):
  if not a.get('cover'):
   for c in hand:
    if beats(a['attack'],c,trump):return dict(action='defend',cards=[c],target=i)
   break
 if d['transfer'] and all(not a.get('cover') and rank(a['attack'])==rank(p[0]['attack']) for a in p):
  nxt=(d['defender']+1)%len(seats)
  while seats[nxt].get('finished'):nxt=(nxt+1)%len(seats)
  if len(p)<min(d['max_attacks'],seats[nxt]['hand']):
   for c in hand:
    if rank(c)==rank(p[0]['attack']):return dict(action='transfer',cards=[c])
 return dict(action='take')
def latest(c,kind):return next((p for p in reversed(c.pushes) if p.get('push')==kind),None)
def reject(c,cmd,err,**args):
 try:c.call(cmd,**args)
 except AssertionError as e:assert err in str(e),str(e)
 else:raise AssertionError('expected '+err)
stamp=str(time.time_ns());players=[Client('durak-'+str(i)+'-'+stamp) for i in range(3)]
watcher=Client('durak-watch-'+stamp);clients=players+[watcher]
def flush():
 for c in clients:c.call('ping',t=1)
try:
 a=players[0]
 reject(a,'create_room','bad_size',size=6,game_type='durak',deck_size=24)
 reject(a,'create_room','durak_bad_deck',size=2,game_type='durak',deck_size=32)
 reject(a,'create_room','bad_stake',size=2,game_type='durak',stake=100)
 code=a.call('create_room',size=6,game_type='durak',deck_size=36,transfer=True,allow_draw=True,locked=True)['code']
 assert all(r['code']!=code for r in a.call('room_list')['rooms'])
 reject(a,'start_room','m13_need_players')
 for c in players[1:]:c.call('join_room',code=code)
 reject(players[1],'start_room','not_host');watcher.call('watch',code=code)
 a.call('start_room');flush()
 initial=latest(a,'durak_state');assert len(initial['hand'])==6 and initial['size']==3 and initial['stock']==18
 assert initial['durak']['transfer'] and not latest(watcher,'durak_state').get('hand')
 reject(watcher,'durak_action','not_in_room',action='attack',cards=['6C'])
 # Same account reconnects; variant, role, trump, stock and own hand survive.
 players[1].s.close();players[1]=Client('durak-1-'+stamp);clients[1]=players[1];flush()
 snap=latest(players[1],'snapshot');assert snap['durak'] and len(snap['hand'])==6
 a.call('rtc_control',code=code,action='start')
 assert a.call('rtc_token',code=code)['token'].startswith('007')
 for step in range(2000):
  flush();st=latest(a,'durak_state')
  if st['phase']=='game_end':break
  current=players[st['turn']]
  if current is players[1] and not latest(current,'durak_state'):own=latest(current,'snapshot')
  else:own=latest(current,'durak_state')
  current.call('durak_action',**choose(st,own['hand'],st['seats']))
 else:raise AssertionError('no game progress')
 flush();end=latest(a,'game_end');assert end and latest(watcher,'game_end')
 assert end['draw'] or len(end['winners'])==2
 assert all(not p.get('hand') for p in watcher.pushes if p.get('push') in ('snapshot','durak_state'))
 for c in players:assert c.call('daily')['coins']==c.user['coins']
 reject(players[1],'start_room','not_host')
 a.call('start_room');flush()
 assert latest(a,'durak_state')['phase']=='playing' and len(latest(a,'durak_state')['hand'])==6
 print('Durak WSS PASS: private configuration, host start/rematch, reconnection, privacy, full game, Agora grant, no coin entry fee')
finally:
 for c in clients:
  try:c.call('leave_room')
  except Exception:pass
  c.s.close()
