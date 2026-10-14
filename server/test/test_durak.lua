package.path='server/lualib/?.lua;'..package.path
local M=require 'rules.durak'
local json=require 'json'
local function round(hands,trump,stock,cfg)
 return M.newRound{hands=hands,trump=trump,stock=stock,config=cfg,dealer=2}
end
local function act(st,seat,a,c,t) assert(M.action(st,seat,a,c,t)) end
local function reject(st,seat,a,c,t,expected)
 local before=json.encode(st);local ok,err=M.action(st,seat,a,c,t)
 assert(not ok and err==expected,tostring(err));assert(json.encode(st)==before,'invalid action mutated state')
end
assert(M.beats(M.parseCard('9C'),M.parseCard('JC'),2))
assert(M.beats(M.parseCard('AC'),M.parseCard('6H'),2))
assert(not M.beats(M.parseCard('9H'),M.parseCard('AC'),2))
assert(not M.beats(M.parseCard('9H'),M.parseCard('8H'),2))
-- Six-card attack is forbidden until a successful defence; cap counts attacks only.
local st=round({{'6C','6D','7C','7D','8C','8D'},{'6H','7H','8H','9H','TH','JH'}},'AH',{}, {})
st.turn=1;st.attacker=1;st.defender=2
reject(st,1,'attack',{'6C','7C'},nil,'durak_rank')
act(st,1,'attack',{'6C','6D'})
reject(st,1,'take',nil,nil,'not_your_turn')
act(st,2,'defend',{'6H'},1)
reject(st,2,'defend',{'7H'},1,'durak_target')
act(st,2,'defend',{'7H'},2)
assert(st.stage=='add' and st.turn==1)
act(st,1,'attack',{'7C','7D'})
act(st,2,'take')
assert(st.taking and st.stage=='add')
reject(st,1,'attack',{'8C'},nil,'durak_rank')
act(st,1,'finish')
assert(st.turn==1 and #st.players[2].hand==10 and #st.discard==0 and not st.beaten)
-- Successful defence discards, defender leads, attackers refill before defender.
st=round({{'6H','6C'},{'7C','8D'}},'AH',{'9C','TC','JC','QC','KC','AC','9D','TD','JD','QD','KD','AD'}, {})
act(st,1,'attack',{'6C'});act(st,2,'defend',{'7C'},1);act(st,1,'finish')
assert(st.beaten and st.attacker==2 and st.limit==6 and #st.discard==2)
assert(#st.players[1].hand==6 and #st.players[2].hand==6 and #st.stock==2)
assert(M.cardString(st.players[1].hand[2])=='9C' and M.cardString(st.players[2].hand[2])=='AC')
-- Transfer only before covering; it moves BOTH attacking cards and may chain.
st=round({{'6H','6C','9C'},{'6D','7C','TC'},{'6S','7D','TD'}},'AH',{}, {transfer=true})
act(st,1,'attack',{'6C'});act(st,2,'transfer',{'6D'})
assert(st.defender==3 and st.turn==3 and #st.pairs==2)
reject(st,3,'transfer',{'6S'},nil,'durak_transfer_limit')
act(st,3,'defend',{'7D'},2)
reject(st,3,'transfer',{'6S'},nil,'durak_transfer')

-- Simultaneous empty hands: configurable draw or defender loses.
for _,allow in ipairs({true,false}) do
 st=round({{'6H','6C'},{'7C','8D'}},'AH',{}, {allowDraw=allow})
 act(st,1,'attack',{'6C'});act(st,2,'defend',{'7C'},1);act(st,1,'finish')
 -- Second bout defender from previous bout attacks 8D, old attacker covers with 6H.
 act(st,2,'attack',{'8D'});act(st,1,'defend',{'6H'},1)
 assert(st.phase=='game_end' and st.draw==allow)
 if allow then assert(#st.winners==0) else assert(st.loser==1 and st.winners[1]==2) end
end
-- Empty hand while deck remains must refill, not be counted as a win.
st=round({{'6H','6C'},{'7C'}},'AH',{'8D','9D','TD','JD','QD','KD','AD','9C','TC','JC','QC','KC'}, {})
act(st,1,'attack',{'6C'});act(st,2,'defend',{'7C'},1)
assert(not st.players[2].finished and #st.players[2].hand==6)
-- Full games across all supported deck sizes and player counts.
math.randomseed(729131)
local games=0
for _,deck in ipairs({24,36,52}) do for n=2,math.min(6,deck//6) do for _,transfer in ipairs({false,true}) do for trial=1,8 do
 local cfg=M.defaultConfig();cfg.deckSize=deck;cfg.transfer=transfer
 local game=M.deal{players=n,dealer=1,config=cfg};local moves=0
 assert(#game.stock==deck-6*n)
 if #game.stock>0 then assert(game.stock[#game.stock]==game.trumpCard) end
 while game.phase=='playing' do
  moves=moves+1;assert(moves<2500,'game failed to progress')
  local before=game.bout
  local a=M.hint(game,game.turn);assert(M.action(game,game.turn,a.action,a.cards,a.target))
  local seen,count={},0
  local function add(c) assert(not seen[c],'duplicate ownership');seen[c]=true;count=count+1 end
  for _,p in ipairs(game.players) do for _,c in ipairs(p.hand) do add(c) end end
  for _,c in ipairs(game.stock) do add(c) end
  for _,c in ipairs(game.discard) do add(c) end
  if game.phase=='playing' then for _,pair in ipairs(game.pairs) do add(pair.attack);if pair.cover then add(pair.cover) end end end
  assert(count==deck,'cards lost')
  assert(game.limit<=6 and #game.pairs<=game.limit)
 end
 assert(game.draw or game.loser and #game.winners==n-1)
 games=games+1
end end end end
print('Durak: legality, picking up, refill order, transfer bounds, draw, conservation and '..games..' complete games passed')
