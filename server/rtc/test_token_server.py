import base64
import hashlib
import hmac
import http.client
import json
import struct
import threading
import unittest
import zlib
from http.server import ThreadingHTTPServer

from token_server import TTL, issue, make_handler

APP = "a" * 32
CERT = "b" * 32
CHANNEL = "kh_" + "c" * 32


class Tokens(unittest.TestCase):
    def test_signature_identity_and_expiry(self):
        result = issue(APP, CERT, dict(channel=CHANNEL, uid=42))
        self.assertTrue(result['token'].startswith('007'))
        raw = zlib.decompress(base64.b64decode(result['token'][3:]))

        def string():
            nonlocal raw
            length = struct.unpack('<H', raw[:2])[0]
            value, raw = raw[2:2 + length], raw[2 + length:]
            return value

        signature = string()
        signed = raw
        self.assertEqual(string().decode(), APP)
        issued, expiry, salt, count = struct.unpack('<IIIH', raw[:14])
        raw = raw[14:]
        self.assertEqual(expiry, TTL)
        self.assertEqual(count, 1)
        # Independently verify the Agora 007 HMAC hierarchy.
        key = hmac.new(struct.pack('<I', issued), CERT.encode(), hashlib.sha256).digest()
        key = hmac.new(struct.pack('<I', salt), key, hashlib.sha256).digest()
        self.assertEqual(signature, hmac.new(key, signed, hashlib.sha256).digest())
        service, privileges = struct.unpack('<HH', raw[:4])
        raw = raw[4:]
        self.assertEqual(service, 1)
        self.assertEqual(privileges, 4)
        for expected in range(1, 5):
            privilege, lifetime = struct.unpack('<HI', raw[:6])
            raw = raw[6:]
            self.assertEqual((privilege, lifetime), (expected, TTL))
        self.assertEqual(string().decode(), CHANNEL)
        self.assertEqual(string(), b'42')
        self.assertEqual(raw, b'')

    def test_rejects_wildcard_and_invalid_identities(self):
        for uid in (0, -1, 2**32, True, '42', None):
            with self.subTest(uid=uid), self.assertRaises(ValueError):
                issue(APP, CERT, dict(channel=CHANNEL, uid=uid))
        for channel in ('123456', '', CHANNEL + '\n', '../test', None):
            with self.subTest(channel=channel), self.assertRaises(ValueError):
                issue(APP, CERT, dict(channel=channel, uid=42))

    def test_private_http_boundary(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), make_handler(APP, CERT, 'secret' * 8))
        worker = threading.Thread(target=server.serve_forever, daemon=True)
        worker.start()
        try:
            def post(body, auth=None):
                client = http.client.HTTPConnection(*server.server_address, timeout=3)
                headers = {} if auth is None else {'Authorization': auth}
                client.request('POST', '/token', json.dumps(body), headers)
                response = client.getresponse()
                status, data = response.status, response.read()
                client.close()
                return status, json.loads(data)

            body = dict(channel=CHANNEL, uid=42)
            self.assertEqual(post(body)[0], 403)
            self.assertEqual(post(body, 'Bearer wrong')[0], 403)
            self.assertEqual(post([], 'Bearer ' + 'secret' * 8)[0], 400)
            status, result = post(body, 'Bearer ' + 'secret' * 8)
            self.assertEqual(status, 200)
            self.assertEqual(result['uid'], 42)
            self.assertNotIn(CERT, json.dumps(result))
        finally:
            server.shutdown()
            server.server_close()
            worker.join()


if __name__ == '__main__':
    unittest.main()
