"""Opt-in production WSS check using private, zero-stake diagnostic rooms."""
import sys
import time

sys.path.insert(0, '/opt/khuzur/server/test')
from rtc_billing_e2e import Client


def reject(client, command, expected, **args):
    try:
        client.call(command, **args)
    except AssertionError as error:
        assert expected in str(error), error
    else:
        raise AssertionError('Expected ' + expected)


clients = []
try:
    stamp = str(time.time_ns())
    clients = [Client('room-exit-' + stamp + '-' + str(i)) for i in range(3)]
    host, guest, spectator = clients
    for game, size in [('muushig', 5), ('mongol13', 4), ('durak', 4), ('thousand', 3)]:
        code = host.call('create_room', size=size, game_type=game, locked=True)['code']
        guest.call('join_room', code=code)
        spectator.call('watch', code=code)
        reject(guest, 'dissolve_room', 'not_host', code=code)
        reject(host, 'dissolve_room', 'not_in_room', code='wrong')
        host.call('dissolve_room', code=code)
        for client in clients:
            client.call('ping', t=1)
            assert any(p.get('push') == 'room_dissolved' and p.get('code') == code for p in client.pushes)
        reject(spectator, 'watch', 'not_in_room', code=code)
        reject(host, 'dissolve_room', 'not_in_room', code=code)
        # Both seated users must immediately be free to create another room.
        guest.call('create_room', size=4, game_type='durak', locked=True)
        guest.call('leave_room')
    code = host.call('create_room', size=5, game_type='muushig', locked=True)['code']
    guest.call('join_room', code=code)
    host.call('start_room')
    reject(host, 'dissolve_room', 'already_started', code=code)
    print('Room exit WSS PASS: four games, host-only pre-game dissolution, seated/spectator notifications, membership cleanup')
finally:
    for client in clients:
        for command in ('unwatch', 'leave_room'):
            try:
                client.call(command)
            except Exception:
                pass
        client.s.close()
