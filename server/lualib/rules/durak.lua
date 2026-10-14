-- Durak friend rooms: serial attack/defend/add phases, server authoritative.
local cards=require 'rules.mongol13'
local M={parseCard=cards.parseCard,cardString=cards.cardString}
local function rank(c) return c%16 end
local function suit(c) return c//16 end
function M.beats(attack,cover,trump)
  return suit(cover)==suit(attack) and rank(cover)>rank(attack)
    or suit(cover)==trump and suit(attack)~=trump
end
function M.defaultConfig() return {rulesVersion=1,startScore=0,maxExchange=0,deckSize=36,transfer=false,allowDraw=true} end
local function nextLive(st,seat)
  for _=1,st.numPlayers do seat=seat%st.numPlayers+1; if not st.players[seat].finished then return seat end end
end
local function remove(hand,used)
  local out={};for _,c in ipairs(hand) do if not used[c] then out[#out+1]=c end end;return out
end
local function own(st,seat,strings)
  if type(strings)~='table' or #strings<1 or #strings>6 then return nil,'durak_bad_cards' end
  local available,seen,out={},{},{}
  for _,c in ipairs(st.players[seat].hand) do available[c]=true end
  for _,s in ipairs(strings) do
    local c=M.parseCard(s)
    if not c or seen[c] then return nil,'durak_bad_cards' end
    if not available[c] then return nil,'card_not_in_hand' end
    seen[c]=true;out[#out+1]=c
  end
  return out,seen
end
local function openCount(st)
  local n=0;for _,p in ipairs(st.pairs) do if not p.cover then n=n+1 end end;return n
end
local function adders(st)
  local out={};local s=st.attacker
  for _=1,st.numPlayers do
    if s~=st.defender and not st.players[s].finished and #st.players[s].hand>0 then out[#out+1]=s end
    s=s%st.numPlayers+1
  end
  return out
end
local beginBout,finishBout,beginAdd
local function finishGame(st,loser,draw)
  st.phase='game_end';st.loser=loser;st.draw=draw or false;st.winners={}
  for i,p in ipairs(st.players) do
    p.score=draw and 0 or (i==loser and -1 or 1)
    if i~=loser and not draw then st.winners[#st.winners+1]=i end
  end
end
beginBout=function(st,attacker)
  st.bout=st.bout+1;st.attacker=attacker;st.defender=nextLive(st,attacker)
  st.stage='attack';st.turn=attacker;st.pairs={};st.taking=false;st.addPassed={}
  st.limit=math.min(st.beaten and 6 or 5,#st.players[st.defender].hand)
end
finishBout=function(st)
  local previousDefender=st.defender
  for _,pair in ipairs(st.pairs) do
    for _,c in ipairs({pair.attack,pair.cover}) do
      if st.taking then st.players[st.defender].hand[#st.players[st.defender].hand+1]=c
      else st.discard[#st.discard+1]=c end
    end
  end
  if not st.taking then st.beaten=true end
  -- Draw clockwise from the current attacker, with current defender last.
  for offset=0,st.numPlayers do
    local s=offset==st.numPlayers and st.defender or (st.attacker-1+offset)%st.numPlayers+1
    if (offset==st.numPlayers or s~=st.defender) and not st.players[s].finished then
      local hand=st.players[s].hand
      while #hand<6 and #st.stock>0 do hand[#hand+1]=table.remove(st.stock,1) end
    end
  end
  local alive={}
  for i,p in ipairs(st.players) do
    if not p.finished and #p.hand==0 and #st.stock==0 then
      p.finished=true;st.finishOrder[#st.finishOrder+1]=i
    end
    if not p.finished then alive[#alive+1]=i end
  end
  if #alive==0 then
    finishGame(st,st.config.allowDraw and nil or previousDefender,st.config.allowDraw)
    return
  elseif #alive==1 then finishGame(st,alive[1]);return end
  local attacker
  if not st.taking and not st.players[previousDefender].finished then attacker=previousDefender
  else attacker=nextLive(st,previousDefender) end
  beginBout(st,attacker)
end
beginAdd=function(st)
  st.stage='add';st.addPassed={}
  local list=adders(st)
  if #st.pairs>=st.limit or #list==0 then finishBout(st) else st.turn=list[1] end
end
function M.newRound(args)
  local cfg=M.defaultConfig();for k,v in pairs(args.config or {}) do cfg[k]=v end
  local n=#args.hands;assert(n>=2 and n<=6)
  local st={config=cfg,numPlayers=n,players={},stock={},trick={},trickNo=1,phase='playing',
    trumpCard=assert(M.parseCard(args.trump)),dealer=args.dealer or 1,discard={},finishOrder={},beaten=false,bout=0}
  st.trumpSuit=suit(st.trumpCard)
  local seen={}
  for i,strings in ipairs(args.hands) do
    local p={hand={},score=0,tricks=0,decision='play',passStreak=0,finished=false}
    assert(#strings>0)
    for _,s in ipairs(strings) do local c=assert(M.parseCard(s));assert(not seen[c]);seen[c]=true;p.hand[#p.hand+1]=c end
    st.players[i]=p
  end
  for _,s in ipairs(args.stock or {}) do local c=assert(M.parseCard(s));assert(not seen[c]);seen[c]=true;st.stock[#st.stock+1]=c end
  local first=(st.dealer%n)+1;local low
  for i,p in ipairs(st.players) do for _,c in ipairs(p.hand) do
    if suit(c)==st.trumpSuit and (not low or rank(c)<rank(low)) then first=i;low=c end
  end end
  beginBout(st,first)
  return st
end
function M.deal(args)
  local cfg=args.config or M.defaultConfig();local minRank=cfg.deckSize==24 and 9 or cfg.deckSize==52 and 2 or 6
  assert(args.players*6<=cfg.deckSize)
  local deck={};for s=0,3 do for r=minRank,14 do deck[#deck+1]=s*16+r end end
  for i=#deck,2,-1 do local j=math.random(i);deck[i],deck[j]=deck[j],deck[i] end
  local trump=M.cardString(deck[#deck]);local hands={}
  for i=1,args.players do hands[i]={};for _=1,6 do hands[i][#hands[i]+1]=M.cardString(table.remove(deck,1)) end end
  local stock={};for _,c in ipairs(deck) do stock[#stock+1]=M.cardString(c) end
  return M.newRound{hands=hands,trump=trump,stock=stock,config=cfg,dealer=args.dealer}
end
function M.action(st,seat,action,strings,target)
  if st.phase~='playing' then return nil,'wrong_phase' end
  if st.turn~=seat then return nil,'not_your_turn' end
  if action=='take' then
    if st.stage~='defend' then return nil,'wrong_phase' end
    st.taking=true;beginAdd(st);return true
  elseif action=='finish' then
    if st.stage~='add' then return nil,'durak_cannot_finish' end
    st.addPassed[seat]=true
    for _,s in ipairs(adders(st)) do if not st.addPassed[s] then st.turn=s;return true end end
    finishBout(st);return true
  end
  local picked,used=own(st,seat,strings);if not picked then return nil,used end
  if action=='attack' then
    if st.stage~='attack' and st.stage~='add' then return nil,'wrong_phase' end
    if #st.pairs+#picked>st.limit then return nil,'durak_attack_limit' end
    local ranks={};for _,p in ipairs(st.pairs) do ranks[rank(p.attack)]=true;if p.cover then ranks[rank(p.cover)]=true end end
    for _,c in ipairs(picked) do
      if #st.pairs==0 then if rank(c)~=rank(picked[1]) then return nil,'durak_rank' end
      elseif not ranks[rank(c)] then return nil,'durak_rank' end
    end
    st.players[seat].hand=remove(st.players[seat].hand,used)
    for _,c in ipairs(picked) do st.pairs[#st.pairs+1]={attack=c,attackSeat=seat} end
    if st.taking then
      if #st.pairs==st.limit then finishBout(st) end
    else st.stage='defend';st.turn=st.defender end
    return true
  elseif action=='defend' then
    if st.stage~='defend' then return nil,'wrong_phase' end
    if #picked~=1 or type(target)~='number' or target%1~=0 or not st.pairs[target] or st.pairs[target].cover then return nil,'durak_target' end
    local pair=st.pairs[target]
    if not M.beats(pair.attack,picked[1],st.trumpSuit) then return nil,'durak_cannot_beat' end
    st.players[seat].hand=remove(st.players[seat].hand,used);pair.cover=picked[1];pair.coverSeat=seat
    if openCount(st)==0 then beginAdd(st) end
    return true
  elseif action=='transfer' then
    if st.stage~='defend' or not st.config.transfer then return nil,'durak_transfer' end
    if #picked~=1 then return nil,'durak_transfer' end
    for _,p in ipairs(st.pairs) do if p.cover or rank(p.attack)~=rank(picked[1]) then return nil,'durak_transfer' end end
    local nextDef=nextLive(st,st.defender)
    local limit=math.min(st.beaten and 6 or 5,#st.players[nextDef].hand)
    if #st.pairs+1>limit then return nil,'durak_transfer_limit' end
    st.players[seat].hand=remove(st.players[seat].hand,used)
    st.pairs[#st.pairs+1]={attack=picked[1],attackSeat=seat}
    st.attacker=st.defender;st.defender=nextDef;st.limit=limit;st.turn=nextDef;return true
  end
  return nil,'bad_cmd'
end
function M.hint(st,seat)
  local hand={table.unpack(st.players[seat].hand)}
  table.sort(hand,function(a,b) local va=rank(a)+(suit(a)==st.trumpSuit and 100 or 0);local vb=rank(b)+(suit(b)==st.trumpSuit and 100 or 0);return va==vb and a<b or va<vb end)
  if st.stage=='attack' then return {action='attack',cards={M.cardString(hand[1])}} end
  if st.stage=='add' then
    local ranks={};for _,p in ipairs(st.pairs) do ranks[rank(p.attack)]=true;if p.cover then ranks[rank(p.cover)]=true end end
    if #st.pairs<st.limit then for _,c in ipairs(hand) do if ranks[rank(c)] then return {action='attack',cards={M.cardString(c)}} end end end
    return {action='finish'}
  end
  for i,p in ipairs(st.pairs) do if not p.cover then
    for _,c in ipairs(hand) do if M.beats(p.attack,c,st.trumpSuit) then return {action='defend',cards={M.cardString(c)},target=i} end end
    break
  end end
  if st.config.transfer then
    local nxt=nextLive(st,st.defender);local can=#st.pairs+1<=math.min(st.beaten and 6 or 5,#st.players[nxt].hand)
    for _,p in ipairs(st.pairs) do if p.cover or rank(p.attack)~=rank(st.pairs[1].attack) then can=false end end
    if can then for _,c in ipairs(hand) do if rank(c)==rank(st.pairs[1].attack) then return {action='transfer',cards={M.cardString(c)}} end end end
  end
  return {action='take'}
end
function M.legalCards(st,seat) return M.hint(st,seat).cards or {} end
function M.view(st)
  local pairs={};for _,p in ipairs(st.pairs) do pairs[#pairs+1]={attack=M.cardString(p.attack),attack_seat=p.attackSeat-1,cover=p.cover and M.cardString(p.cover),cover_seat=p.coverSeat and p.coverSeat-1} end
  return {stage=st.stage,attacker=st.attacker-1,defender=st.defender-1,pairs=pairs,limit=st.limit,
    taking=st.taking,max_attacks=st.beaten and 6 or 5,transfer=st.config.transfer,allow_draw=st.config.allowDraw,bout=st.bout,
    draw=st.draw or false,loser=st.loser and st.loser-1,discard=#st.discard}
end
return M
