"""Diagnostic friend match; only test accounts, no media publication or entry fee."""
import sys, time
sys.path.insert(0, '/opt/khuzur/server/test')
from rtc_billing_e2e import Client

def latest(c, *kinds):
    return next((p for p in reversed(c.pushes) if p.get('push') in kinds), None)

def reject(c, cmd, err, **args):
    try: c.call(cmd, **args)
    except AssertionError as e: assert err in str(e), str(e)
    else: raise AssertionError('expected ' + err)

stamp = str(time.time_ns())
players = [Client('thousand-' + str(i) + '-' + stamp) for i in range(3)]
watcher = Client('thousand-watch-' + stamp)
clients = players + [watcher]

def flush():
    for c in clients: c.call('ping', t=1)

def own(c): return latest(c, 'thousand_state', 'snapshot')

def choose(state, hand):
    t = state['thousand']; stage = t['stage']
    if stage == 'bid': return dict(action='pass')
    if stage == 'give': return dict(action='give', value=hand[:2])
    if stage == 'contract': return dict(action='contract', value=t['bid'])
    trick = state.get('trick', [])
    if trick:
        same = [c for c in hand if c[1] == trick[0]['card'][1]]
        trump = 'CDHS'[state['trump_suit']] if state['trump_suit'] >= 0 else ''
        trumps = [c for c in hand if c[1] == trump]
        return dict(action='play', value=(same or trumps or hand)[0])
    if state['seats'][state['turn']]['tricks']:
        for s in 'CDHS':
            if 'K'+s in hand and 'Q'+s in hand:
                return dict(action='play', value='K'+s, announce=True)
    return dict(action='play', value=hand[0])

try:
    a = players[0]
    reject(a, 'create_room', 'thousand_need_players', size=2, game_type='thousand')
    reject(a, 'create_room', 'bad_stake', size=3, game_type='thousand', stake=100)
    code = a.call('create_room', size=3, game_type='thousand', locked=False)['code']
    assert all(r['code'] != code for r in a.call('room_list')['rooms'])
    reject(a, 'start_room', 'thousand_need_players')
    for c in players[1:]: c.call('join_room', code=code)
    reject(players[1], 'start_room', 'not_host')
    watcher.call('watch', code=code)
    a.call('start_room'); flush()
    state = own(a)
    assert state['size'] == 3 and len(state['hand']) == 7 and state['stock'] == 3
    assert state['trump_suit'] == -1 and not state.get('trump')
    reject(watcher, 'thousand_action', 'not_in_room', action='pass')
    reject(watcher, 'join_room', 'already_started', code=code)
    first = players[state['turn']]
    reject(first, 'thousand_action', 'thousand_bad_bid', action='bid', value=102)
    first.call('thousand_action', action='bid', value=105); flush()
    while own(a)['thousand']['stage'] == 'bid':
        state = own(a); players[state['turn']].call('thousand_action', action='pass'); flush()
    state = own(a); assert state['thousand']['bid'] == 105
    bidder = state['thousand']['bidder']
    assert len(own(players[bidder])['hand']) == 10 and len(own(watcher)['thousand']['kitty']) == 3
    # Duplicate account connection restores private hand and current auction state.
    players[1].s.close(); players[1] = Client('thousand-1-' + stamp); clients[1] = players[1]; flush()
    snap = latest(players[1], 'snapshot'); assert snap['thousand']['stage'] == 'give'
    assert len(snap['hand']) == (10 if bidder == 1 else 7)
    hand = own(players[bidder])['hand']; gifts = hand[:2]
    reject(players[bidder], 'thousand_action', 'thousand_give_two', action='give', value=gifts[:1])
    players[bidder].call('thousand_action', action='give', value=gifts); flush()
    assert gifts[0] in own(players[(bidder+1)%3])['hand']
    assert gifts[1] in own(players[(bidder+2)%3])['hand']
    assert all(len(own(c)['hand']) == 8 for c in players)
    players[bidder].call('thousand_action', action='contract', value=105); flush()
    players[bidder].call('rtc_control', code=code, action='start')
    assert players[bidder].call('rtc_token', code=code)['token'].startswith('007')
    for step in range(30):
        flush(); state = own(a)
        if state['phase'] in ('round_end','game_end'): break
        current = players[state['turn']]
        current.call('thousand_action', **choose(state, own(current)['hand']))
    else: raise AssertionError('hand did not finish')
    flush(); end = latest(a, 'round_end'); assert end and latest(watcher, 'round_end')
    assert sum(r['tricks'] for r in end['results']) == 8
    before = [r['score'] for r in end['results']]
    assert all(not p.get('hand') for p in watcher.pushes if p.get('push') in ('snapshot','thousand_state','round_start'))
    time.sleep(5.3); flush(); state = own(a)
    assert state['round'] == 2 and state['thousand']['stage'] == 'bid'
    assert [s['score'] for s in state['seats']] == before
    assert all(c.call('daily')['coins'] == c.user['coins'] for c in players)
    print('Thousand WSS PASS: three-player private room, auction, ordered gifts, reconnect, hand privacy, full hand, automatic next deal, Agora grant, no game coin fee')
finally:
    for c in clients:
        try: c.call('leave_room')
        except Exception: pass
        c.s.close()
