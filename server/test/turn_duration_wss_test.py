"""Opt-in zero-stake private-room check of human/bot CD budgets over real WSS."""
import sys
import time

sys.path.insert(0, '/opt/khuzur/server/test')
from rtc_billing_e2e import Client


def latest(client, kind):
    return next(p for p in reversed(client.pushes) if p.get('push') == kind)


clients = []
try:
    stamp = str(time.time_ns())
    host = Client('cd15-host-' + stamp)
    watcher = Client('cd15-watch-' + stamp)
    clients = [host, watcher]
    code = host.call('create_room', size=2, game_type='muushig', locked=True)['code']
    host.call('start_room')
    host.call('ping', t=1)
    turn = latest(host, 'turn')
    assert turn['deadline'] == turn['turn_duration'] == 1500
    if turn['seat'] == 0:
        host.call('decide', play=True)
        host.call('ping', t=1)
        turn = latest(host, 'turn')
    assert turn['seat'] == 1
    assert turn['deadline'] == turn['turn_duration'] == 1500, turn
    watcher.call('watch', code=code)
    snapshot = latest(watcher, 'snapshot')
    assert snapshot['turn_duration'] == 1500 and 0 < snapshot['deadline'] <= 1500
    count = sum(p.get('push') == 'turn' for p in host.pushes)
    start = time.monotonic()
    for _ in range(20):
        host.call('ping', t=1)
        if sum(p.get('push') == 'turn' for p in host.pushes) > count:
            turn = latest(host, 'turn')
            assert turn['deadline'] == turn['turn_duration'] == 1500
            print('CD WSS PASS: bot CD starts at 15s; next turn starts at 15s; bot acted after %.2fs; snapshot retains full 15s budget' % (time.monotonic() - start))
            break
        time.sleep(.5)
    else:
        raise AssertionError('Bot did not act within expected thinking time')
finally:
    for client in clients:
        for command in ('unwatch', 'leave_room'):
            try:
                client.call(command)
            except Exception:
                pass
        client.s.close()
