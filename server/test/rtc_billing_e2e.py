"""Opt-in WSS smoke test. Creates two diagnostic accounts and a private room.
Consumes a few test-account coins; does not publish real Agora media.
"""
import base64,json,os,socket,ssl,struct,time
class Client:
 def __init__(self,device):
  host='kzur.sdg8888.com'
  self.s=ssl.create_default_context().wrap_socket(socket.create_connection((host,443),timeout=8),server_hostname=host)
  self.s.settimeout(8); self.seq=0; self.pushes=[]
  key=base64.b64encode(os.urandom(16)).decode()
  self.s.sendall(('GET /ws HTTP/1.1\r\nHost: '+host+'\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: '+key+'\r\n\r\n').encode())
  header=b''
  while not header.endswith(b'\r\n\r\n'):header+=self.exact(1)
  assert b' 101 ' in header
  self.user=self.call('login',device=device,name='RTC billing test',lang='en')
 def exact(self,n):
  out=b''
  while len(out)<n:
   chunk=self.s.recv(n-len(out))
   if not chunk:raise RuntimeError('socket closed')
   out+=chunk
  return out
 def call(self,cmd,**args):
  self.seq+=1; data=json.dumps(dict(seq=self.seq,cmd=cmd,**args)).encode(); mask=os.urandom(4)
  self.s.sendall((bytes([129,128|len(data)]) if len(data)<126 else bytes([129,254])+struct.pack('!H',len(data)))+mask+bytes(v^mask[i%4] for i,v in enumerate(data)))
  while True:
   a,b=self.exact(2); n=b&127
   if n==126:n=struct.unpack('!H',self.exact(2))[0]
   elif n==127:n=struct.unpack('!Q',self.exact(8))[0]
   body=self.exact(n); assert a&15==1
   msg=json.loads(body)
   if msg.get('seq')==self.seq:
    assert not msg.get('err'), (cmd,msg.get('err'))
    return msg
   self.pushes.append(msg)
 def rtc(self,action,**args):return self.call('rtc_control',code=code,action=action,**args).get('rtc')
 def state(self,camera=False,epoch=0):return self.rtc('state',joined=True,microphone=False,camera=camera,video_epoch=epoch)
if __name__=='__main__':
 stamp=str(time.time_ns()); a=Client('rtc-bill-a-'+stamp); b=Client('rtc-bill-b-'+stamp)
 code=a.call('create_room',size=5,locked=True)['code']
 try:
  b.call('join_room',code=code)
  assert a.rtc('start')['enabled']
  b.call('ping',t=1)
  assert any(p.get('push')=='rtc_state' and p['rtc']['enabled'] for p in b.pushes)
  assert a.call('rtc_token',code=code)['token'].startswith('007')
  assert b.call('rtc_token',code=code)['token'].startswith('007')
  st=a.rtc('prepare',consent=True); epoch=st['video_epoch']; assert st['payer_uid']==a.user['uid']
  assert b.rtc('prepare',consent=True)['payer_uid']==a.user['uid']
  a.state(True,epoch); b.state(False,epoch)
  time.sleep(7.2)
  a.state(False,epoch)
  first=a.call('daily')['coins']; assert first==a.user['coins']-1
  assert b.call('daily')['coins']==b.user['coins']
  time.sleep(7.2)
  assert a.call('daily')['coins']==first,'paused billing charged'
  a.state(True,epoch); b.state(True,epoch)
  time.sleep(7.2)
  a.state(False,epoch); b.state(False,epoch)
  assert a.call('daily')['coins']==first-1,'multiple cameras charged twice'
  a.call('leave_room')
  b.call('ping',t=1)
  latest=[p['rtc'] for p in b.pushes if 'rtc' in p][-1]
  assert latest['payer_uid']==0 and latest['video_epoch']>epoch
  print('WSS_E2E_PASS: activation broadcast, tokens, single-payer debit, pause, multiple cameras, payer exit')
 finally:
  for c in (a,b):
   try:c.call('leave_room')
   except Exception:pass
   c.s.close()
