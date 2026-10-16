"""Loopback-only R2 signing/validation helper. No public upload proxy or credential logging."""
import base64, datetime, hashlib, hmac, io, json, os, re, secrets, subprocess
import tempfile, time, urllib.parse, urllib.request, urllib.error, uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TTL = 7 * 86400
LIMITS = {'image': 5 * 1024 * 1024, 'audio': 2 * 1024 * 1024, 'video': 20 * 1024 * 1024}
MIMES = {'image/jpeg': ('image', '.jpg'), 'image/png': ('image', '.png'),
         'image/webp': ('image', '.webp'), 'audio/mp4': ('audio', '.m4a'),
         'video/mp4': ('video', '.mp4'), 'video/quicktime': ('video', '.mov')}

class MediaError(Exception):
    pass

class R2:
    def __init__(self, env=None):
        env = env or os.environ
        self.account = env.get('R2_ACCOUNT_ID', '')
        self.bucket = env.get('R2_BUCKET', '')
        self.access = env.get('R2_ACCESS_KEY_ID', '')
        self.secret = env.get('R2_SECRET_ACCESS_KEY', '')
        self.endpoint = 'https://' + self.account + '.r2.cloudflarestorage.com'

    @property
    def enabled(self):
        return bool(re.fullmatch(r'[a-fA-F0-9]{32}', self.account) and
                    re.fullmatch(r'[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]', self.bucket) and self.access and self.secret)

    def sign(self, method, key='', ttl=300, headers=None, query=None, now=None):
        if not self.enabled:
            raise MediaError('media_unavailable')
        now = now or datetime.datetime.now(datetime.timezone.utc)
        date, stamp = now.strftime('%Y%m%d'), now.strftime('%Y%m%dT%H%M%SZ')
        scope = date + '/auto/s3/aws4_request'
        uri = '/' + self.bucket + '/' + urllib.parse.quote(key, safe='/~') if key else '/' + self.bucket
        headers = {k.lower(): str(v).strip() for k, v in (headers or {}).items()}
        headers['host'] = urllib.parse.urlsplit(self.endpoint).netloc
        signed = ';'.join(sorted(headers))
        params = dict(query or {})
        params.update({'X-Amz-Algorithm': 'AWS4-HMAC-SHA256',
                       'X-Amz-Credential': self.access + '/' + scope,
                       'X-Amz-Date': stamp, 'X-Amz-Expires': str(max(1, min(int(ttl), 604800))),
                       'X-Amz-SignedHeaders': signed})
        q = '&'.join(urllib.parse.quote(k, safe='~') + '=' + urllib.parse.quote(str(v), safe='~')
                     for k, v in sorted(params.items()))
        canonical = '\n'.join([method, uri, q, ''.join(k + ':' + headers[k] + '\n' for k in sorted(headers)),
                               signed, 'UNSIGNED-PAYLOAD'])
        to_sign = '\n'.join(['AWS4-HMAC-SHA256', stamp, scope, hashlib.sha256(canonical.encode()).hexdigest()])
        signing = ('AWS4' + self.secret).encode()
        for part in [date, 'auto', 's3', 'aws4_request']:
            signing = hmac.new(signing, part.encode(), hashlib.sha256).digest()
        signature = hmac.new(signing, to_sign.encode(), hashlib.sha256).hexdigest()
        return self.endpoint + uri + '?' + q + '&X-Amz-Signature=' + signature

    def request(self, method, key='', body=None, headers=None, query=None):
        url = self.sign(method, key, headers=headers, query=query)
        try:
            return urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers or {}, method=method), timeout=15)
        except (urllib.error.URLError, TimeoutError) as exc:
            error=MediaError('media_storage_failed');error.status=getattr(exc,'code',None)
            if isinstance(exc,urllib.error.HTTPError): exc.close()
            raise error from exc

def valid_key(key):
    return isinstance(key, str) and re.fullmatch(r'chat/\d{8}/[a-f0-9]{32}(?:_thumb)?\.(jpg|png|webp|m4a|mp4|mov)', key)

def prepare(r2, data, now=None):
    if not r2.enabled:
        raise MediaError('media_unavailable')
    mime, size = data.get('mime'), data.get('size')
    if mime not in MIMES or type(size) is not int or size <= 0:
        raise MediaError('media_bad_file')
    kind, ext = MIMES[mime]
    if size > LIMITS[kind]:
        raise MediaError('media_too_large')
    now = int(now or time.time())
    media_id = uuid.uuid4().hex
    day = datetime.datetime.fromtimestamp(now, datetime.timezone.utc).strftime('%Y%m%d')
    key = 'chat/' + day + '/' + media_id + ext
    headers = {'Content-Type': mime, 'Content-Length': str(size)}
    return {'id': media_id, 'key': key, 'kind': kind, 'mime': mime, 'size': size,
            'created_at': now, 'expires_at': now + TTL,
            'upload_url': r2.sign('PUT', key, headers=headers), 'headers': headers}

def inspect_media(blob, kind):
    thumb, duration, width, height = None, 0, 0, 0
    if kind == 'image':
        from PIL import Image, UnidentifiedImageError
        Image.MAX_IMAGE_PIXELS = 20_000_000
        try:
            with Image.open(io.BytesIO(blob)) as image:
                if image.format not in ('JPEG', 'PNG', 'WEBP') or image.width * image.height > 20_000_000:
                    raise MediaError('media_bad_file')
                image.verify()
            with Image.open(io.BytesIO(blob)) as image:
                width, height = image.size
                image.thumbnail((640, 640)); out = io.BytesIO()
                image.convert('RGB').save(out, 'JPEG', quality=80); thumb = out.getvalue()
        except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
            raise MediaError('media_bad_file') from exc
    else:
        with tempfile.TemporaryDirectory(prefix='khuzur-media-') as directory:
            path = os.path.join(directory, 'media.bin')
            with open(path, 'wb') as f: f.write(blob)
            proc = subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
                                   'format=duration,format_name:stream=codec_type,codec_name,width,height,duration',
                                   '-of', 'json', path], capture_output=True, timeout=10)
            if proc.returncode:
                raise MediaError('media_bad_file')
            info = json.loads(proc.stdout); streams = info.get('streams', [])
            try: duration = float(info['format']['duration'])
            except (KeyError, TypeError, ValueError): raise MediaError('media_bad_file')
            if not 0 < duration <= 60.1:
                raise MediaError('media_bad_duration')
            videos = [s for s in streams if s.get('codec_type') == 'video']
            audio = [s for s in streams if s.get('codec_type') == 'audio']
            if kind == 'audio' and (videos or not audio or any(s.get('codec_name') != 'aac' for s in audio)):
                raise MediaError('media_bad_file')
            if kind == 'video':
                if len(videos) != 1 or videos[0].get('codec_name') not in ('h264', 'hevc'):
                    raise MediaError('media_bad_file')
                width, height = videos[0].get('width', 0), videos[0].get('height', 0)
                if not 0 < width * height <= 8_500_000:
                    raise MediaError('media_bad_file')
                proc = subprocess.run(['ffmpeg', '-v', 'error', '-i', path, '-frames:v', '1',
                                       '-vf', 'scale=640:640:force_original_aspect_ratio=decrease',
                                       '-f', 'image2pipe', '-vcodec', 'mjpeg', 'pipe:1'], capture_output=True, timeout=10)
                if proc.returncode or not proc.stdout:
                    raise MediaError('media_bad_file')
                thumb = proc.stdout
    return {'duration': round(duration, 3), 'width': width, 'height': height}, thumb

def verify(r2, data):
    key, size, kind = data.get('key'), data.get('size'), data.get('kind')
    if not valid_key(key) or kind not in LIMITS or type(size) is not int or not 0 < size <= LIMITS[kind]:
        raise MediaError('media_bad_file')
    if int(data.get('expires_at', 0)) <= time.time(): raise MediaError('media_expired')
    with r2.request('HEAD', key) as response:
        if int(response.headers.get('Content-Length', -1)) != size:
            raise MediaError('media_bad_file')
    with r2.request('GET', key) as response:
        etag=response.headers.get('ETag')
        blob = response.read(size + 1)
    if len(blob) != size: raise MediaError('media_bad_file')
    result, thumbnail = inspect_media(blob, kind)
    if not etag: raise MediaError('media_storage_failed')
    # Publish an immutable object so a reused upload URL cannot replace a sent file.
    final_key=key.rsplit('/',1)[0]+'/'+uuid.uuid4().hex+'.'+key.rsplit('.',1)[1]
    with r2.request('PUT',final_key,body=b'',headers={
        'x-amz-copy-source':'/'+r2.bucket+'/'+key,
        'x-amz-copy-source-if-match':etag,
    }) as response:
        if b'<Error' in response.read(65536): raise MediaError('media_storage_failed')
    result['object_key']=final_key
    if thumbnail:
        thumb_key = final_key.rsplit('.', 1)[0] + '_thumb.jpg'
        with r2.request('PUT', thumb_key, thumbnail, {'Content-Type': 'image/jpeg', 'Content-Length': str(len(thumbnail))}): pass
        result['thumb_key'] = thumb_key
    try:
        with r2.request('DELETE',key): pass
    except MediaError: pass
    return result

def download(r2, data):
    key, expires = data.get('key'), int(data.get('expires_at', 0))
    if not valid_key(key): raise MediaError('media_bad_file')
    remaining = int(expires - time.time())
    if remaining <= 0: raise MediaError('media_expired')
    return {'url': r2.sign('GET', key, ttl=min(60, remaining)), 'url_expires_at': int(time.time()) + min(60, remaining)}

def lifecycle(r2):
    import xml.etree.ElementTree as ET
    ns = 'http://s3.amazonaws.com/doc/2006-03-01/'
    ET.register_namespace('', ns)
    try:
        with r2.request('GET', query={'lifecycle': ''}) as response: root = ET.fromstring(response.read())
    except MediaError as error:
        # Do not replace unknown configurations after network/auth errors.
        if getattr(error,'status',None)==404:
            root=ET.Element('{'+ns+'}LifecycleConfiguration')
        else: raise MediaError('lifecycle_read_failed')
    for rule in list(root):
        if rule.findtext('{'+ns+'}ID') == 'khuzur-chat-seven-days': root.remove(rule)
    rule = ET.SubElement(root, '{'+ns+'}Rule')
    ET.SubElement(rule, '{'+ns+'}ID').text = 'khuzur-chat-seven-days'
    ET.SubElement(rule, '{'+ns+'}Status').text = 'Enabled'
    prefix = ET.SubElement(rule, '{'+ns+'}Filter')
    ET.SubElement(prefix, '{'+ns+'}Prefix').text = 'chat/'
    expiry = ET.SubElement(rule, '{'+ns+'}Expiration')
    ET.SubElement(expiry, '{'+ns+'}Days').text = '7'
    body = ET.tostring(root, encoding='utf-8')
    headers = {'Content-Type': 'application/xml', 'Content-MD5': base64.b64encode(hashlib.md5(body).digest()).decode()}
    with r2.request('PUT', body=body, headers=headers, query={'lifecycle': ''}): pass

class Handler(BaseHTTPRequestHandler):
    r2 = R2()
    def log_message(self, *_): pass
    def do_POST(self):
        status, result = 200, {}
        try:
            secret = os.environ.get('CHAT_MEDIA_SECRET', '')
            if not secret or not secrets.compare_digest(self.headers.get('Authorization', ''), 'Bearer '+secret):
                status = 403; raise MediaError('forbidden')
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 4096: raise MediaError('bad_request')
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict): raise MediaError('bad_request')
            action = {'/prepare': prepare, '/verify': verify, '/url': download}.get(self.path)
            if not action: status = 404; raise MediaError('bad_request')
            result = action(self.r2, data)
        except MediaError as exc:
            if status == 200: status = 400
            result = {'err': str(exc)}
        except (ImportError, FileNotFoundError): status, result = 503, {'err': 'media_processing_unavailable'}
        except Exception: status, result = 400, {'err': 'media_bad_file'}
        body = json.dumps(result).encode(); self.send_response(status)
        self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)

if __name__ == '__main__':
    import sys
    if '--configure-lifecycle' in sys.argv:
        lifecycle(R2()); print('R2 chat/ lifecycle set to 7 days; other rules preserved.')
    else:
        ThreadingHTTPServer(('127.0.0.1', int(os.environ.get('CHAT_MEDIA_PORT', '9761'))), Handler).serve_forever()
