-- Mongol 13 friend rooms. Card encoding matches the existing client atlas.
local M = {}
local ranks = {['2']=2,['3']=3,['4']=4,['5']=5,['6']=6,['7']=7,['8']=8,['9']=9,T=10,J=11,Q=12,K=13,A=14}
local suits = {C=0,D=1,H=2,S=3}
local chars = '23456789TJQKA'
function M.parseCard(s)
  if type(s)~='string' or #s~=2 or not ranks[s:sub(1,1)] or not suits[s:sub(2,2)] then return nil end
  return suits[s:sub(2,2)]*16+ranks[s:sub(1,1)]
end
function M.cardString(c) return chars:sub(c%16-1,c%16-1)..({'C','D','H','S'})[c//16+1] end
local function rank(c) return c%16==2 and 15 or c%16 end
local function suit(c) return ({[0]=1,[1]=0,[2]=2,[3]=3})[c//16] end
function M.value(c) return rank(c)*4+suit(c) end
function M.combo(cards)
  local n=#cards
  if n<1 or n>5 then return nil end
  local groups,seen,sorted,natural = {},{},{},{}
  for _,c in ipairs(cards) do
    if type(c)~='number' or c%1~=0 or c%16<2 or c%16>14 or c//16<0 or c//16>3 or seen[c] then return nil end
    seen[c]=true; groups[rank(c)]=(groups[rank(c)] or 0)+1
    sorted[#sorted+1]=c; natural[#natural+1]=c%16
  end
  table.sort(sorted,function(a,b) return M.value(a)>M.value(b) end)
  table.sort(natural)
  local distinct,three,four=0,nil,nil
  for r,count in pairs(groups) do distinct=distinct+1; if count==3 then three=r end; if count==4 then four=r end end
  if n<=4 then
    if distinct~=1 then return nil end
    return {kind=({'single','pair','triple','four'})[n], count=n, strength={M.value(sorted[1])}}
  end
  local straight=0
  if distinct==5 then
    if table.concat(natural,',')=='2,3,4,5,14' then straight=5
    elseif natural[5]-natural[1]==4 then straight=natural[5] end
  end
  local flush=true
  for _,c in ipairs(cards) do if c//16~=cards[1]//16 then flush=false end end
  local kind,strength
  if straight>0 and flush then kind='straightFlush'; strength={4,straight,suit(cards[1]),0,0,0,0}
  elseif four then kind='fourOne'; strength={3,four,0,0,0,0,0}
  elseif three and distinct==2 then kind='fullHouse'; strength={2,three,0,0,0,0,0}
  elseif flush then kind='flush'; strength={1}; for _,c in ipairs(sorted) do strength[#strength+1]=rank(c) end; strength[7]=suit(sorted[1])
  elseif straight>0 then
    local high; for _,c in ipairs(cards) do if c%16==straight then high=c end end
    kind='straight'; strength={0,straight,suit(high),0,0,0,0}
  else return nil end
  return {kind=kind,count=5,strength=strength}
end
function M.beats(a,b)
  if not a or not b or a.count~=b.count then return false end
  for i,v in ipairs(a.strength) do
    if v~=b.strength[i] then return v>b.strength[i] end
  end
  return false
end
function M.defaultConfig() return {rulesVersion=1,startScore=0,maxExchange=0} end
local function settle(st,winner,dragon)
  local gain=0
  for s,p in ipairs(st.players) do
    p.score=0
    if s~=winner then
      local n=#p.hand
      local loss=n*(n==13 and 3 or n>=10 and 2 or 1)
      p.score=-loss; gain=gain+loss
    end
  end
  st.players[winner].score=gain; st.phase='game_end'; st.winners={winner}; st.dragon=dragon or false
end
function M.newRound(args)
  local n=#args.hands
  assert(n>=2 and n<=4)
  local st={numPlayers=n,dealer=1,players={},phase='playing',turn=1,last={},lastSeat=nil,passes=0,
    opening=nil,trick={},trickNo=1,trumpCard=7,trumpSuit=0,stock={},config=M.defaultConfig()}
  local seen,dragons={},{}
  for s,hand in ipairs(args.hands) do
    assert(#hand==13)
    local p={hand={},score=0,tricks=0,decision='play',passStreak=0}
    local unique={}
    for _,str in ipairs(hand) do
      local c=assert(M.parseCard(str)); assert(not seen[c]); seen[c]=true
      p.hand[#p.hand+1]=c; unique[c%16]=true
      if not st.opening or M.value(c)<M.value(st.opening) then st.opening=c; st.turn=s end
    end
    st.players[s]=p
    local count=0; for _ in pairs(unique) do count=count+1 end
    if count==13 then dragons[#dragons+1]=s end
  end
  if #dragons>0 then
    local winner,best=dragons[1],-1
    for _,s in ipairs(dragons) do for _,c in ipairs(st.players[s].hand) do
      if c%16==2 and M.value(c)>best then winner=s; best=M.value(c) end
    end end
    settle(st,winner,true)
  end
  return st
end
function M.deal(args)
  local deck={}; for s=0,3 do for r=2,14 do deck[#deck+1]=M.cardString(s*16+r) end end
  for i=#deck,2,-1 do local j=math.random(i); deck[i],deck[j]=deck[j],deck[i] end
  local hands={}; for s=1,args.players do hands[s]={}; for _=1,13 do hands[s][#hands[s]+1]=table.remove(deck) end end
  return M.newRound{hands=hands}
end
function M.canPlay(st,seat,cards)
  if st.phase~='playing' then return nil,'wrong_phase' end
  if st.turn~=seat then return nil,'not_your_turn' end
  local own={}; for _,c in ipairs(st.players[seat].hand) do own[c]=true end
  for _,c in ipairs(cards) do if not own[c] then return nil,'card_not_in_hand' end end
  local combo=M.combo(cards); if not combo then return nil,'m13_bad_combo' end
  if st.opening then local has=false; for _,c in ipairs(cards) do if c==st.opening then has=true end end
    if not has then return nil,'m13_opening' end
  end
  if #st.last>0 and not M.beats(combo,M.combo(st.last)) then return nil,'m13_too_small' end
  return true
end
function M.play(st,seat,strings)
  if type(strings)~='table' or #strings<1 or #strings>5 then return nil,'m13_bad_combo' end
  local cards={}; for _,s in ipairs(strings) do local c=M.parseCard(s); if not c then return nil,'m13_bad_combo' end; cards[#cards+1]=c end
  local ok,err=M.canPlay(st,seat,cards); if not ok then return nil,err end
  local used={}; for _,c in ipairs(cards) do used[c]=true end
  local hand={}; for _,c in ipairs(st.players[seat].hand) do if not used[c] then hand[#hand+1]=c end end
  st.players[seat].hand=hand; st.last=cards; st.lastSeat=seat; st.passes=0; st.opening=nil
  st.turn=seat%st.numPlayers+1
  if #hand==0 then settle(st,seat) end
  return true
end
function M.pass(st,seat)
  if st.phase~='playing' then return nil,'wrong_phase' end
  if st.turn~=seat then return nil,'not_your_turn' end
  if #st.last==0 then return nil,'m13_cannot_pass' end
  st.passes=st.passes+1; st.turn=seat%st.numPlayers+1
  if st.passes==st.numPlayers-1 then st.turn=st.lastSeat; st.last={}; st.lastSeat=nil; st.passes=0 end
  return true
end
function M.hint(st,seat)
  local hand={table.unpack(st.players[seat].hand)}
  table.sort(hand,function(a,b) return M.value(a)<M.value(b) end)
  for _,n in ipairs(#st.last>0 and {#st.last} or {5,4,3,2,1}) do
    local found
    local function visit(start,picked)
      if found then return end
      if #picked==n then if M.canPlay(st,seat,picked) then found={table.unpack(picked)} end; return end
      for i=start,#hand-(n-#picked)+1 do picked[#picked+1]=hand[i]; visit(i+1,picked); picked[#picked]=nil; if found then return end end
    end
    visit(1,{})
    if found then local out={}; for _,c in ipairs(found) do out[#out+1]=M.cardString(c) end; return out end
  end
  return {}
end
function M.legalCards(st,seat) return M.hint(st,seat) end
return M
