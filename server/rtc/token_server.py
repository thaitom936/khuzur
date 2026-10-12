"""Private, loopback-only Agora signer. Authentication/seat checks live in Skynet.

No external Python dependencies. The certificate never crosses this boundary.
"""
import hmac
import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from vendor.RtcTokenBuilder2 import RtcTokenBuilder, Role_Publisher

TTL = 300


def issue(app_id, certificate, request):
    channel, uid = request.get("channel"), request.get("uid")
    if not isinstance(channel, str) or not re.fullmatch(r"kh_[0-9a-f]{32}", channel):
        raise ValueError("bad channel")
    if type(uid) is not int or not 1 <= uid <= 0xFFFFFFFF:
        raise ValueError("bad uid")
    token = RtcTokenBuilder.build_token_with_uid(
        app_id, certificate, channel, uid, Role_Publisher, TTL, TTL)
    if not token:
        raise ValueError("invalid configuration")
    return dict(app_id=app_id, channel=channel, uid=uid, token=token,
                expires_at=int(time.time()) + TTL, renew_after=TTL - 60)


def make_handler(app_id, certificate, secret):
    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.connection.settimeout(5)

        def log_message(self, *args):
            pass  # Neither credentials nor tokens belong in access logs.

        def reply(self, status, body):
            data = json.dumps(body).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            self.reply(200 if self.path == "/health" else 404, {"ok": self.path == "/health"})

        def do_POST(self):
            if self.path != "/token":
                return self.reply(404, {})
            supplied = self.headers.get("Authorization", "").encode()
            if not hmac.compare_digest(supplied, ("Bearer " + secret).encode()):
                return self.reply(403, {})
            try:
                length = int(self.headers.get("Content-Length", "0"))
                if not 0 < length <= 1024:
                    raise ValueError("bad length")
                request = json.loads(self.rfile.read(length))
                if not isinstance(request, dict):
                    raise ValueError("bad request")
                result = issue(app_id, certificate, request)
            except (ValueError, TypeError):
                return self.reply(400, {})
            self.reply(200, result)

    return Handler


if __name__ == "__main__":
    app_id = os.environ.get("AGORA_APP_ID", "")
    certificate = os.environ.get("AGORA_APP_CERTIFICATE", "")
    secret = os.environ.get("AGORA_TOKEN_SECRET", "")
    if not all(re.fullmatch(r"[0-9a-fA-F]{32}", value) for value in (app_id, certificate)) or len(secret) < 32:
        raise SystemExit("Agora signer: invalid or missing server credentials")
    server = ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("AGORA_TOKEN_PORT", "9760"))),
                                 make_handler(app_id, certificate, secret))
    server.daemon_threads = True
    server.serve_forever()
