-- Per-table RTC activation and server-clock video billing. Time is centiseconds.
-- All public operations run under the room RTC queue, including the timer.
local M = {}
function M.new(opts)
  local self = { enabled=false, members={}, payer=nil, epoch=0, elapsed=0,
    sequence=0, charged=0, last=opts.now(), blocked=nil, closed=false }
  local function receiving(m) return m and m.joined and opts.now()-m.seen <= 1500 end
  local function charging()
    if self.closed or not self.payer or not receiving(self.members[self.payer]) then return false end
    local people, videos = 0, 0
    for _, m in pairs(self.members) do
      if receiving(m) then
        people=people+1
        if m.camera then videos=videos+1 end
      end
    end
    return people>=2 and videos>0
  end
  function self:state()
    return { enabled=self.enabled, payer_uid=self.payer or 0,
      video_epoch=self.epoch, blocked=self.blocked or '', charging=charging(),
      charged_coins=self.charged, coins_per_minute=10 }
  end
  local function emit() opts.emit(self:state()) end
  local function stopVideo(reason)
    for _, m in pairs(self.members) do m.camera=false end
    self.epoch=self.epoch+1
    self.blocked=reason
    self.elapsed=0
  end
  function self:tick()
    local now=opts.now()
    -- Accrue only the part of the interval covered by valid heartbeats.
    local untilAt=now
    local live={}
    local videoUntil=0
    for _,m in pairs(self.members) do
      if m.joined then
        live[#live+1]=m.seen+1500
        if m.camera then videoUntil=math.max(videoUntil,m.seen+1500) end
      end
    end
    table.sort(live,function(a,b) return a>b end)
    local payer=self.payer and self.members[self.payer]
    if not self.closed and payer and payer.joined and #live>=2 and videoUntil>0 then
      untilAt=math.min(now,live[2],payer.seen+1500,videoUntil)
      self.elapsed=self.elapsed+math.max(0,untilAt-self.last)
    end
    self.last=now
    while self.elapsed>=600 do
      self.sequence=self.sequence+1
      local balance,err=opts.charge(self.payer, opts.channel..':'..self.sequence)
      if balance==nil then
        stopVideo(err=='insufficient' and 'rtc_insufficient' or 'rtc_billing_failed')
        emit(); return
      end
      self.elapsed=self.elapsed-600
      self.charged=self.charged+1
      opts.balance(self.payer,balance)
      -- Do not give a zero-balance payer another unpaid billing interval.
      if balance==0 then stopVideo('rtc_insufficient'); emit(); return end
    end
    for uid,m in pairs(self.members) do
      if m.joined and now-m.seen>1500 then
        m.joined=false; m.camera=false; m.mic=false
        if uid==self.payer then stopVideo('rtc_payer_offline') end
        emit()
      end
    end
  end
  function self:start()
    if self.closed then return nil,'rtc_not_seated' end
    self.enabled=true; emit(); return self:state()
  end
  function self:prepare(uid, consent)
    self:tick()
    if self.closed then return nil,'rtc_not_seated' end
    if not self.payer then
      if not consent then return nil,'rtc_payment_required' end
      local balance=opts.getBalance(uid)
      if balance==nil then return nil,'rtc_billing_failed' end
      if balance<1 then return nil,'rtc_insufficient' end
      self.payer=uid; self.elapsed=0; self.charged=0
    end
    local balance=opts.getBalance(self.payer)
    if balance==nil then return nil,'rtc_billing_failed' end
    if balance<1 then return nil,'rtc_insufficient' end
    self.blocked=nil; emit(); return self:state()
  end
  function self:update(uid, joined, mic, camera, epoch)
    self:tick()
    if self.closed then return nil,'rtc_not_seated' end
    if camera and (not self.payer or self.blocked or epoch~=self.epoch) then
      return nil,self.blocked or 'rtc_payment_required'
    end
    self.members[uid]={joined=joined,mic=joined and mic,camera=joined and camera,seen=opts.now()}
    if not joined and uid==self.payer then stopVideo('rtc_payer_offline') end
    emit(); return self:state()
  end
  function self:remove(uid)
    self:tick()
    self.members[uid]=nil
    if uid==self.payer then
      stopVideo('rtc_payer_left'); self.payer=nil; self.charged=0
    end
    emit()
  end
  function self:close()
    self:tick(); self.closed=true; self.enabled=false
    stopVideo('rtc_closed'); self.payer=nil; emit()
  end
  return self
end
return M
