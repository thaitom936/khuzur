"""Zero-stake diagnostic: the original exposed card survives trade/reconnect/watch."""
import sys
import time

sys.path.insert(0, '/opt/khuzur/server/test')
from rtc_billing_e2e import Client


def latest(client, kind):
    return next(p for p in reversed(client.pushes) if p.get('push') == kind)


clients = []
try:
    stamp = str(time.time_ns())
    devices = ['trump-indicator-' + stamp + '-' + str(i) for i in range(3)]
    clients = [Client(device) for device in devices]
    code = clients[0].call('create_room', size=3, game_type='muushig', locked=True)['code']
    for client in clients[1:]:
        client.call('join_room', code=code)
    for _ in range(16):
        for client in clients:
            client.call('ping', t=1)
        turn = latest(clients[0], 'turn')
        actor = clients[turn['seat']]
        if turn['phase'] == 'deciding':
            actor.call('decide', play=True)
        elif turn['phase'] == 'exchanging':
            actor.call('exchange', cards=[])
        elif turn['phase'] == 'navsh':
            original = latest(actor, 'round_start')['trump']
            discard = latest(actor, 'round_start')['hand'][0]
            actor.call('take_trump', card=discard)
            break
        else:
            raise AssertionError(turn)
    else:
        raise AssertionError('No dealer exchange phase')
    for client in clients:
        client.call('ping', t=1)
        event = latest(client, 'trump_taken')
        assert event['trump_indicator'] == original and event['trump'] == discard, event
    spectator = Client('trump-watch-' + stamp)
    clients.append(spectator)
    spectator.call('watch', code=code)
    snap = latest(spectator, 'snapshot')
    assert snap['trump_taken'] and snap['trump_indicator'] == original and snap['trump'] == discard
    clients[0].s.close()
    clients[0] = Client(devices[0])
    clients[0].call('ping', t=1)
    snap = latest(clients[0], 'snapshot')
    assert snap['trump_indicator'] == original and snap['trump'] == discard
    print('Trump indicator WSS PASS: original face-up card retained through trade, spectator entry and reconnection')
finally:
    for client in clients:
        for command in ('unwatch', 'leave_room'):
            try:
                client.call(command)
            except Exception:
                pass
        client.s.close()
