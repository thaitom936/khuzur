"""Run with Python 3 from server/. Uses dummy credentials, never Agora cloud."""
import os
import secrets
import subprocess
import threading
from http.server import ThreadingHTTPServer

from token_server import make_handler

secret = secrets.token_hex(32)
server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler('a' * 32, 'b' * 32, secret))
worker = threading.Thread(target=server.serve_forever, daemon=True)
worker.start()
try:
    env = dict(os.environ, AGORA_TOKEN_SECRET=secret, AGORA_TOKEN_PORT=str(server.server_port))
    result = subprocess.run(['./skynet/skynet', 'etc/config.rtc'], env=env, timeout=20)
finally:
    server.shutdown()
    server.server_close()
    worker.join()
raise SystemExit(result.returncode)
