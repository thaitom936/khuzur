-- Thousand: three-player Russian friend-room rules, no paid stakes.
local cards=require 'rules.mongol13'
local M={parseCard=cards.parseCard,cardString=cards.cardString}
local points={[9]=0,[10]=10,[11]=2,[12]=3,[13]=4,[14]=11}
local strength={[9]=0,[11]=1,[12]=2,[13]=3,[10]=4,[14]=5}
local marriage={[0]=60,[1]=80,[2]=100,[3]=40}
local function suit(c) return c//16 end
function M.defaultConfig() return {rulesVersion=1,startScore=0,maxExchange=2,targetScore=1000} end
function M.points(c) return points[c%16] end
function M.marriages(hand)
  local found,out={},{};for _,c in ipairs(hand) do found[c]=true end
  for s=0,3 do if found[s*16+12] and found[s*16+13] then out[#out+1]=s end end
  return out
end
function M.bidCap(hand)
  local cap=120;for _,s in ipairs(M.marriages(hand)) do cap=cap+marriage[s] end;return cap
end
function M.beats(a,b,trump,lead)
  local sa,sb=suit(a),suit(b)
  if sa==sb then return strength[a%16]>strength[b%16] end
  if sa==trump then return true end
  if sb==trump then return false end
  return sa==lead and sb~=lead
end
function M.legalCards(st,seat)
  local hand=st.players[seat].hand
  if #st.trick==0 then return {table.unpack(hand)} end
  local lead=suit(st.trick[1].card);local same,trumps={},{}
  for _,c in ipairs(hand) do
    if suit(c)==lead then same[#same+1]=c end
    if suit(c)==st.trumpSuit then trumps[#trumps+1]=c end
  end
  return #same>0 and same or #trumps>0 and trumps or {table.unpack(hand)}
end
local function strings(list) local out={};for _,c in ipairs(list) do out[#out+1]=M.cardString(c) end;return out end
local function remove(hand,c) for i,v in ipairs(hand) do if v==c then table.remove(hand,i);return true end end end
function M.newRound(args)
  assert(#args.hands==3 and #args.stock==3)
  local st={numPlayers=3,config=args.config or M.defaultConfig(),dealer=args.dealer or 1,
    players={},stock={},trick={},trickNo=1,phase='deciding',stage='bid',trumpSuit=-1,
    kitty={},passed={},announced={},discard={},bid=100,contract=100,bidder=0}
  local seen={}
  for i,h in ipairs(args.hands) do
    assert(#h==7);local old=args.carry and args.carry.players[i]
    local p={hand={},score=args.scores and args.scores[i] or 0,tricks=0,decision='play',passStreak=0,
      points=0,bonus=0,barrel=old and old.barrel or false,attempts=old and old.attempts or 0}
    for _,s in ipairs(h) do local c=assert(M.parseCard(s));assert(points[c%16] and not seen[c]);seen[c]=true;p.hand[#p.hand+1]=c end
    st.players[i]=p
  end
  for _,s in ipairs(args.stock) do local c=assert(M.parseCard(s));assert(points[c%16] and not seen[c]);seen[c]=true;st.stock[#st.stock+1]=c end
  st.bidder=st.dealer%3+1;st.turn=st.bidder%3+1
  return st
end
function M.deal(args)
  assert(args.players==3);local deck={}
  for s=0,3 do for r=9,14 do deck[#deck+1]=s*16+r end end
  for i=#deck,2,-1 do local j=math.random(i);deck[i],deck[j]=deck[j],deck[i] end
  local hands={{},{},{}};for _=1,7 do for i=1,3 do hands[i][#hands[i]+1]=M.cardString(table.remove(deck,1)) end end
  return M.newRound{hands=hands,stock=strings(deck),scores=args.scores,carry=args.carry,dealer=args.dealer,config=args.config}
end
local function finishAuction(st)
  st.phase='exchanging';st.stage='give';st.turn=st.bidder;st.contract=st.bid
  st.kitty={table.unpack(st.stock)}
  for _,c in ipairs(st.stock) do st.players[st.bidder].hand[#st.players[st.bidder].hand+1]=c end
  st.stock={}
end
local function settle(st)
  st.results={}
  for i,p in ipairs(st.players) do
    local total=p.points+p.bonus;local delta
    if i==st.bidder then delta=total>=st.contract and st.contract or -st.contract
    else delta=math.floor((total+2)/5)*5 end
    if p.barrel then
      p.attempts=p.attempts+1
      if i==st.bidder and total>=st.contract and total>=120 then
        p.score=1000;p.barrel=false
      elseif i==st.bidder and total<st.contract then
        p.score=p.score-st.contract;p.barrel=false;p.attempts=0
      elseif p.attempts>=3 then p.score=760;p.barrel=false;p.attempts=0
      end
    else
      p.score=p.score+delta
      if p.score>=880 and p.score<1000 then p.score=880;p.barrel=true;p.attempts=0 end
    end
    st.results[i]={points=total,delta=p.score-(st.startScores[i] or 0),score=p.score}
  end
  st.phase='round_end';st.stage='result';st.winners={}
  local high=-math.huge
  for _,p in ipairs(st.players) do if p.score>=1000 then high=math.max(high,p.score) end end
  if high>=1000 then
    st.phase='game_end'
    -- A fulfilled declarer's contract takes priority when several reach the target.
    if st.players[st.bidder].score>=1000 then st.winners={st.bidder}
    else for i,p in ipairs(st.players) do if p.score==high then st.winners[#st.winners+1]=i end end end
  end
end
function M.action(st,seat,action,value,announce)
  if st.phase=='round_end' or st.phase=='game_end' then return nil,'wrong_phase' end
  if seat~=st.turn then return nil,'not_your_turn' end
  if st.stage=='bid' then
    if action=='pass' then st.passed[seat]=true
    elseif action=='bid' then
      if type(value)~='number' or value%5~=0 or value<st.bid+5 or value>M.bidCap(st.players[seat].hand) then return nil,'thousand_bad_bid' end
      st.bid=value;st.bidder=seat
    else return nil,'bad_cmd' end
    local active=0;for i=1,3 do if not st.passed[i] then active=active+1 end end
    if active==1 then finishAuction(st)
    else repeat st.turn=st.turn%3+1 until not st.passed[st.turn] end
    return true
  elseif st.stage=='give' then
    if action~='give' or type(value)~='table' or #value~=2 then return nil,'thousand_give_two' end
    local a,b=M.parseCard(value[1]),M.parseCard(value[2]);local hand=st.players[seat].hand
    local found={};for _,c in ipairs(hand) do found[c]=true end
    if not a or not b or a==b or not found[a] or not found[b] then return nil,'card_not_in_hand' end
    remove(hand,a);remove(hand,b)
    st.players[seat%3+1].hand[#st.players[seat%3+1].hand+1]=a
    st.players[(seat+1)%3+1].hand[#st.players[(seat+1)%3+1].hand+1]=b
    st.stage='contract';return true
  elseif st.stage=='contract' then
    if action~='contract' or type(value)~='number' or value%5~=0 or value<st.bid or value>math.max(st.bid,M.bidCap(st.players[seat].hand)) then return nil,'thousand_bad_bid' end
    st.contract=value;st.phase='playing';st.stage='play';st.startScores={}
    for i,p in ipairs(st.players) do st.startScores[i]=p.score end
    return true
  elseif st.stage~='play' or action~='play' then return nil,'bad_cmd' end
  local c=M.parseCard(value);local hand=st.players[seat].hand;local legal=false
  for _,v in ipairs(M.legalCards(st,seat)) do if c==v then legal=true end end
  if not legal then return nil,'thousand_follow_suit' end
  if announce~=nil and type(announce)~='boolean' then return nil,'bad_request' end
  if announce then
    local s=suit(c);local can=false
    for _,v in ipairs(M.marriages(hand)) do if v==s then can=true end end
    if #st.trick>0 or st.players[seat].tricks==0 or (c%16~=12 and c%16~=13) or not can or st.announced[s] then return nil,'thousand_bad_marriage' end
    st.trumpSuit=s;st.trumpCard=c;st.announced[s]=true;st.players[seat].bonus=st.players[seat].bonus+marriage[s]
  end
  remove(hand,c);st.trick[#st.trick+1]={seat=seat,card=c};st.turn=seat%3+1;st.completed=nil
  if #st.trick==3 then
    local win=st.trick[1];local total=0;local lead=suit(win.card)
    for _,t in ipairs(st.trick) do
      total=total+M.points(t.card);st.discard[#st.discard+1]=t.card
      if M.beats(t.card,win.card,st.trumpSuit,lead) then win=t end
    end
    st.players[win.seat].points=st.players[win.seat].points+total
    st.players[win.seat].tricks=st.players[win.seat].tricks+1
    st.completed={cards=st.trick,winner=win.seat,winningCard=win.card,points=total}
    st.trick={};st.turn=win.seat;st.trickNo=st.trickNo+1
    if st.trickNo==9 then settle(st) end
  end
  return true
end
function M.hint(st,seat)
  if st.stage=='bid' then return {action='pass'} end
  local hand=st.players[seat].hand
  if st.stage=='give' then
    local h={table.unpack(hand)};table.sort(h,function(a,b) return M.points(a)==M.points(b) and a<b or M.points(a)<M.points(b) end)
    return {action='give',value={M.cardString(h[1]),M.cardString(h[2])}}
  elseif st.stage=='contract' then return {action='contract',value=st.bid} end
  local legal=M.legalCards(st,seat);table.sort(legal,function(a,b) return strength[a%16]==strength[b%16] and a<b or strength[a%16]<strength[b%16] end)
  if #st.trick==0 and st.players[seat].tricks>0 then
    for _,s in ipairs(M.marriages(hand)) do if not st.announced[s] then return {action='play',value=M.cardString(s*16+13),announce=true} end end
  end
  return {action='play',value=M.cardString(legal[1])}
end
function M.view(st)
  local details={};for i,p in ipairs(st.players) do details[i]={points=p.points,bonus=p.bonus,barrel=p.barrel,attempts=p.attempts} end
  return {stage=st.stage,bid=st.bid,contract=st.contract,bidder=st.bidder-1,kitty=strings(st.kitty),
    passed={st.passed[1] or false,st.passed[2] or false,st.passed[3] or false},details=details,results=st.results,
    trump_suit=st.trumpSuit,target=1000}
end
return M
