"""Uses fake credentials and a local object store, never accesses a real R2 account."""
import datetime, hashlib, importlib.util, io, json, os, subprocess, tempfile, threading, time
import unittest, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch
from pathlib import Path

spec=importlib.util.spec_from_file_location('r2_server',Path(__file__).resolve().parents[1]/'media/r2_server.py')
media=importlib.util.module_from_spec(spec);spec.loader.exec_module(media)
ENV={'R2_ACCOUNT_ID':'a'*32,'R2_BUCKET':'test-media','R2_ACCESS_KEY_ID':'example','R2_SECRET_ACCESS_KEY':'secret'}
class Store(BaseHTTPRequestHandler):
    objects={}; config=None
    def log_message(self,*_):pass
    def do_PUT(self):
        body=self.rfile.read(int(self.headers.get('Content-Length','0')))
        source=self.headers.get('x-amz-copy-source')
        if source:
            body=Store.objects.get(source)
            if body is None or self.headers.get('x-amz-copy-source-if-match')!='"'+hashlib.md5(body).hexdigest()+'"':
                self.send_response(412);self.send_header('Content-Length','0');self.end_headers();return
        if 'lifecycle=' in self.path:Store.config=body
        else:Store.objects[urllib.parse.urlsplit(self.path).path]=body
        self.send_response(200);self.send_header('Content-Length','0');self.end_headers()
    def do_GET(self):
        if 'lifecycle=' in self.path:body=Store.config
        else:body=Store.objects.get(urllib.parse.urlsplit(self.path).path)
        self.send_response(200 if body is not None else 404);self.send_header('Content-Length',str(len(body or b'')))
        if body is not None:self.send_header('ETag','"'+hashlib.md5(body).hexdigest()+'"')
        self.end_headers()
        if body is not None:self.wfile.write(body)
    def do_HEAD(self):
        body=Store.objects.get(urllib.parse.urlsplit(self.path).path)
        self.send_response(200 if body is not None else 404);self.send_header('Content-Length',str(len(body or b'')));self.end_headers()
    def do_DELETE(self):
        Store.objects.pop(urllib.parse.urlsplit(self.path).path,None)
        self.send_response(204);self.send_header('Content-Length','0');self.end_headers()

class Tests(unittest.TestCase):
    def test_signature_matches_aws_sdk(self):
        import boto3
        from botocore.config import Config
        r2=media.R2(ENV)
        now=datetime.datetime(2026,10,14,12,0,0)
        client=boto3.client('s3',endpoint_url=r2.endpoint,region_name='auto',aws_access_key_id=r2.access,aws_secret_access_key=r2.secret,config=Config(signature_version='s3v4',s3={'addressing_style':'path'}))
        for method,operation in [('PUT','put_object'),('GET','get_object'),('HEAD','head_object')]:
            headers={'Content-Type':'image/jpeg','Content-Length':'10'} if method=='PUT' else {}
            params={'Bucket':r2.bucket,'Key':'chat/20261014/'+'f'*32+'.jpg'}
            if method=='PUT':params.update(ContentType='image/jpeg',ContentLength=10)
            sdk=client.generate_presigned_url(operation,Params=params,ExpiresIn=300)
            stamp=dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(sdk).query))['X-Amz-Date']
            now=datetime.datetime.strptime(stamp,'%Y%m%dT%H%M%SZ')
            ours=r2.sign(method,params['Key'],headers=headers,now=now)
            self.assertEqual(dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(sdk).query)),dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(ours).query)))

    def test_date_key_limits_and_expiry(self):
        r2=media.R2(ENV);stamp=1791972000
        f=media.prepare(r2,{'mime':'audio/mp4','size':200},now=stamp)
        day=datetime.datetime.fromtimestamp(stamp,datetime.timezone.utc).strftime('%Y%m%d')
        self.assertRegex(f['key'],r'^chat/'+day+r'/[a-f0-9]{32}\.m4a$');self.assertEqual(f['expires_at']-f['created_at'],604800)
        for mime,size in [('text/html',100),('image/jpeg',5*1024*1024+1),('audio/mp4',2*1024*1024+1),('video/mp4',20*1024*1024+1)]:
            with self.assertRaises(media.MediaError):media.prepare(r2,{'mime':mime,'size':size})
        with self.assertRaises(media.MediaError):media.download(r2,{'key':f['key'],'expires_at':1})
        with self.assertRaises(media.MediaError):media.download(r2,{'key':'../../secret','expires_at':int(time.time())+100})
        result=media.download(r2,{'key':f['key'],'expires_at':int(time.time())+25})
        self.assertLessEqual(int(dict(urllib.parse.parse_qsl(urllib.parse.urlsplit(result['url']).query))['X-Amz-Expires']),25)

    def test_validation_image_voice_video_and_duration(self):
        from PIL import Image
        image=io.BytesIO();Image.new('RGB',(128,64)).save(image,'JPEG')
        details,thumbnail=media.inspect_media(image.getvalue(),'image');self.assertEqual(details['width'],128);self.assertTrue(thumbnail)
        with self.assertRaises(media.MediaError):media.inspect_media(b'<html>fake image</html>','image')
        with tempfile.TemporaryDirectory() as directory:
            voice=Path(directory)/'voice.m4a';video=Path(directory)/'video.mp4';long=Path(directory)/'long.m4a'
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','sine=frequency=440:duration=1','-c:a','aac',str(voice)],check=True)
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','color=c=blue:s=128x96:d=1','-c:v','libx264','-pix_fmt','yuv420p',str(video)],check=True)
            subprocess.run(['ffmpeg','-v','error','-f','lavfi','-i','sine=frequency=440:duration=61','-c:a','aac',str(long)],check=True)
            self.assertGreater(media.inspect_media(voice.read_bytes(),'audio')[0]['duration'],0)
            self.assertTrue(media.inspect_media(video.read_bytes(),'video')[1])
            with self.assertRaises(media.MediaError):media.inspect_media(long.read_bytes(),'audio')
            with self.assertRaises(media.MediaError):media.inspect_media(video.read_bytes(),'audio')

    def test_local_store_complete_and_lifecycle_merge(self):
        from PIL import Image
        server=ThreadingHTTPServer(('127.0.0.1',0),Store);threading.Thread(target=server.serve_forever,daemon=True).start()
        try:
            r2=media.R2(ENV);r2.endpoint='http://127.0.0.1:'+str(server.server_port)
            image=io.BytesIO();Image.new('RGB',(32,32)).save(image,'JPEG');blob=image.getvalue()
            grant=media.prepare(r2,{'mime':'image/jpeg','size':len(blob)})
            with urllib.request.urlopen(urllib.request.Request(grant['upload_url'],data=blob,method='PUT',headers=grant['headers'])):pass
            details=media.verify(r2,grant);self.assertTrue(details['thumb_key'].startswith('chat/'));self.assertTrue(details['thumb_key'].endswith('_thumb.jpg'))
            published=Store.objects['/'+r2.bucket+'/'+details['object_key']]
            with urllib.request.urlopen(urllib.request.Request(grant['upload_url'],data=b'X'*len(blob),method='PUT',headers=grant['headers'])):pass
            self.assertEqual(Store.objects['/'+r2.bucket+'/'+details['object_key']],published)
            with self.assertRaises(media.MediaError):media.verify(r2,{**grant,'size':len(blob)+1})
            Store.config=None;media.lifecycle(r2);self.assertIn(b'<Prefix>chat/</Prefix>',Store.config)
            Store.config=Store.config.replace(b'</LifecycleConfiguration>',b'<Rule><ID>keep-avatars</ID><Status>Enabled</Status><Filter><Prefix>avatars/</Prefix></Filter><Expiration><Days>365</Days></Expiration></Rule></LifecycleConfiguration>')
            media.lifecycle(r2);self.assertIn(b'keep-avatars',Store.config);self.assertEqual(Store.config.count(b'khuzur-chat-seven-days'),1)
        finally:server.shutdown();server.server_close()

if __name__=='__main__':unittest.main()
