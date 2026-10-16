"""Private diagnostic friend game over production WSS; no wagering/media publication."""
import sys,time
sys.path.insert(0,'/opt/khuzur/server/test')
from rtc_billing_e2e import Client
stamp=str(time.time_ns())
a=Client('m13-a-'+stamp); b=Client('m13-b-'+stamp); w=Client('m13-w-'+stamp)
clients=[a,b,w]
def reject(c,cmd,expected,**args):
 try:c.call(cmd,**args)
 except AssertionError as e: assert expected in str(e),str(e)
 else:raise AssertionError('expected '+expected)
def latest(c,kind):return next((p for p in reversed(c.pushes) if p.get('push')==kind),None)
def flush():
 for c in clients:c.call('ping',t=1)
def value(s):return '3456789TJQKA2'.index(s[0])*4+'DCHS'.index(s[1])
try:
 reject(a,'create_room','bad_size',size=5,game_type='mongol13')
 reject(a,'create_room','bad_stake',size=2,game_type='mongol13',stake=100)
 code=a.call('create_room',size=4,game_type='mongol13',locked=True)['code']
 assert all(r['code']!=code for r in a.call('room_list')['rooms']),'must be private'
 reject(a,'start_room','m13_need_players')
 b.call('join_room',code=code)
 reject(b,'start_room','not_host')
 w.call('watch',code=code)
 a.call('start_room');flush()
 assert latest(a,'game_start')['game_type']=='mongol13'
 assert latest(a,'game_start')['size']==2
 assert len(latest(a,'m13_state')['hand'])==13
 assert not latest(w,'m13_state').get('hand')
 reject(w,'play_card','not_in_room',cards=['3D'])
 # Reconnect the same diagnostic account; the private hand and variant survive.
 b.s.close();b=Client('m13-b-'+stamp);clients[1]=b;flush()
 snap=latest(b,'snapshot');assert snap and snap['game_type']=='mongol13' and len(snap['hand'])==13
 a.call('rtc_control',code=code,action='start')
 assert a.call('rtc_token',code=code)['token'].startswith('007')
 assert b.call('rtc_token',code=code)['token'].startswith('007')
 state=latest(a,'m13_state')
 if state['phase']=='playing':
  turn=clients[state['turn']]
  reject(turn,'play_card','m13_bad_combo',cards=['XX'])
 for step in range(160):
  flush();state=latest(a,'m13_state')
  if state['phase']=='game_end':break
  turn=clients[state['turn']]
  own=latest(turn,'m13_state') or latest(turn,'snapshot')
  hand=own['hand'];last=state['m13']['last'];opening=state['m13'].get('opening')
  legal=[s for s in hand if (not last or value(s)>value(last[0])) and (not opening or s==opening)]
  if legal:turn.call('play_card',cards=[min(legal,key=value)])
  else:turn.call('decide',play=False)
 else:raise AssertionError('game did not finish')
 flush()
 end=latest(a,'game_end');assert end and latest(w,'game_end')
 result=latest(a,'round_end')['results'];assert sum(p['score'] for p in result)==0
 assert all(not p.get('hand') for p in w.pushes if p.get('push') in ('snapshot','m13_state'))
 assert a.call('daily')['coins']==a.user['coins'] and b.call('daily')['coins']==b.user['coins']
 print('M13 WSS PASS: validation, private room, host start, reconnect, spectator privacy, Agora grants, full game, zero coin debit')
finally:
 for c in clients:
  try:c.call('leave_room')
  except Exception:pass
  c.s.close()
