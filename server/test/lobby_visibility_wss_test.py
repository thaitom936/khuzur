"""Diagnostic zero-stake rooms; validates visibility and spectator-first entry."""
import sys
import time

sys.path.insert(0, '/opt/khuzur/server/test')
from rtc_billing_e2e import Client

stamp = str(time.time_ns())
host = Client('lobby-visibility-host-' + stamp)
watcher = Client('lobby-visibility-watcher-' + stamp)
try:
    for game in ('muushig', 'mongol13', 'durak', 'thousand'):
        for private in (True, False):
            size = 3 if game == 'thousand' else 2
            code = host.call('create_room', game_type=game, size=size, locked=private)['code']
            rooms = watcher.call('room_list')['rooms']
            assert any(r['code'] == code for r in rooms) == (not private), (game, private)
            watcher.call('watch', code=code)
            snapshot = next(p for p in reversed(watcher.pushes) if p.get('push') == 'snapshot')
            assert snapshot['you'] == -1, 'Watching must not occupy a seat'
            assert snapshot['game_type'] == game
            watcher.call('unwatch')
            host.call('leave_room')
    print('Lobby WSS PASS: four games, public/private listing and spectator-first entry')
finally:
    for client in (watcher, host):
        try:
            client.call('unwatch')
        except Exception:
            pass
        try:
            client.call('leave_room')
        except Exception:
            pass
        client.s.close()
