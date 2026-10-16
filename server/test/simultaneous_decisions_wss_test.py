"""Private, zero-stake WSS diagnostic for simultaneous Muushig choices."""
import sys
import time

sys.path.insert(0, '/opt/khuzur/server/test')
from rtc_billing_e2e import Client


def latest(client, kind):
    return next(p for p in reversed(client.pushes) if p.get('push') == kind)


clients = []
try:
    stamp = str(time.time_ns())
    devices = ['simultaneous-' + stamp + '-' + str(i) for i in range(3)]
    clients = [Client(device) for device in devices]
    code = clients[0].call('create_room', size=3, game_type='muushig', locked=True)['code']
    for client in clients[1:]:
        client.call('join_room', code=code)
    for client in clients:
        client.call('ping', t=1)
        assert latest(client, 'game_start')['config']['simultaneousDecisions']
        assert latest(client, 'turn')['deadline'] == 1500
    cursor = latest(clients[0], 'turn')['seat']
    actor = (cursor + 1) % 3
    clients[actor].call('decide', play=True)
    try:
        clients[actor].call('decide', play=False)
    except AssertionError as error:
        assert 'already_decided' in str(error)
    else:
        raise AssertionError('Accepted a duplicate choice')
    time.sleep(.25)
    clients[actor].s.close()
    clients[actor] = Client(devices[actor])
    clients[actor].call('ping', t=1)
    snap = latest(clients[actor], 'snapshot')
    assert snap['phase'] == 'deciding'
    assert snap['seats'][actor]['decision'] == 'play'
    assert 0 < snap['deadline'] < 1500 and snap['turn_duration'] == 1500
    for seat in reversed(range(3)):
        if seat != actor:
            clients[seat].call('decide', play=True)
    for client in clients:
        client.call('ping', t=1)
    assert latest(clients[0], 'turn')['phase'] == 'exchanging'
    print('Simultaneous decisions WSS PASS: off-cursor choices, duplicate rejection, common 15s CD, reconnect, exchange transition')
finally:
    for client in clients:
        try:
            client.call('leave_room')
        except Exception:
            pass
        client.s.close()
