
package.path='./lualib/?.lua;'..package.path
local M=require 'rules.thousand';local json=require 'json'
local function encode(v)
 if type(v)~='table' then return type(v)..':'..tostring(v) end
 local out={};for k,x in pairs(v) do out[#out+1]=encode(k)..'='..encode(x) end
 table.sort(out);return '{'..table.concat(out,',')..'}'
end
local function act(st,seat,a,v,d) local ok,err=M.action(st,seat,a,v,d);assert(ok,err) end
local function bad(st,seat,a,v,d,e)
 local before=encode(st);local ok,err=M.action(st,seat,a,v,d)
 assert(not ok and err==e,tostring(err));assert(encode(st)==before,'rejected action mutated state')
end
local function conservation(st)
 local seen,n={},0
 local function check(c) assert(not seen[c],'duplicate card');seen[c]=true;n=n+1 end
 for _,p in ipairs(st.players) do for _,c in ipairs(p.hand) do check(c) end end
 for _,c in ipairs(st.stock) do check(c) end
 for _,c in ipairs(st.discard) do check(c) end
 for _,t in ipairs(st.trick) do check(t.card) end
 assert(n==24,'cards lost: '..n)
end
local c=M.parseCard
assert(M.points(c('AH'))==11 and M.points(c('9C'))==0)
assert(M.beats(c('TC'),c('KC'),-1,0));assert(not M.beats(c('KC'),c('TC'),-1,0))
assert(M.beats(c('9H'),c('AC'),2,0));assert(not M.beats(c('AS'),c('9C'),-1,0))
assert(M.bidCap({c('KH'),c('QH'),c('KC'),c('QC')})==280)
local st=M.deal{players=3,dealer=3}
bad(st,1,'bid',105,nil,'not_your_turn')
bad(st,2,'bid',102,nil,'thousand_bad_bid')
bad(st,2,'bid',1000,nil,'thousand_bad_bid')
act(st,2,'pass');act(st,3,'pass')
assert(st.stage=='give' and st.turn==1 and #st.players[1].hand==10 and #st.kitty==3)
bad(st,1,'give',{'9C'},nil,'thousand_give_two')
local give={M.cardString(st.players[1].hand[1]),M.cardString(st.players[1].hand[2])}
bad(st,1,'give',{give[1],give[1]},nil,'card_not_in_hand')
act(st,1,'give',give);assert(st.stage=='contract')
for _,p in ipairs(st.players) do assert(#p.hand==8) end
bad(st,1,'contract',95,nil,'thousand_bad_bid');act(st,1,'contract',100)
assert(st.trumpSuit==-1 and st.stage=='play')
-- Full match simulation validates carry, barrel progression, all 24 cards and 120 points.
local games,rounds=0,0
math.randomseed(73194)
for seed=1,80 do
 local carry,scores=nil,nil
 for round=1,200 do
  rounds=rounds+1
  st=M.deal{players=3,dealer=round%3+1,scores=scores,carry=carry}
  conservation(st)
  local moves=0
  while st.phase~='round_end' and st.phase~='game_end' do
   moves=moves+1;assert(moves<50)
   local a=M.hint(st,st.turn);act(st,st.turn,a.action,a.value,a.announce);conservation(st)
  end
  assert(st.players[1].points+st.players[2].points+st.players[3].points==120)
  assert(st.players[1].tricks+st.players[2].tricks+st.players[3].tricks==8)
  for _,p in ipairs(st.players) do assert(#p.hand==0) end
  assert(#st.discard==24 and #st.trick==0 and st.results)
  if st.phase=='game_end' then assert(#st.winners>=1);games=games+1;break end
  carry=st;scores={st.players[1].score,st.players[2].score,st.players[3].score}
 end
end
assert(games==80)
-- Focused rule edges: follow suit before trumps, no compulsory overtake; declarations change trumps.
st=M.deal{players=3,dealer=3};st.stage='play';st.phase='playing';st.turn=1;st.stock={};st.startScores={0,0,0}
st.players[1].hand={c('KH'),c('QH'),c('9C')};st.players[1].tricks=1
st.players[2].hand={c('KS'),c('QS'),c('JC')};st.players[2].tricks=1
st.players[3].hand={c('AH'),c('TC')}
st.trick={{seat=3,card=c('AC')}}
local legal=M.legalCards(st,1);assert(#legal==1 and legal[1]==c('9C'))
bad(st,1,'play','KH',false,'thousand_follow_suit')
st.trick={};st.players[1].tricks=0
bad(st,1,'play','KH',true,'thousand_bad_marriage')
st.players[1].tricks=1;act(st,1,'play','KH',true)
assert(st.trumpSuit==2 and st.players[1].bonus==100)
bad(st,2,'play','KS',true,'thousand_bad_marriage')
act(st,2,'play','JC',false);act(st,3,'play','AH',false)
assert(st.completed.winner==3 and st.players[3].points==17)
st.turn=2;act(st,2,'play','KS',true)
assert(st.trumpSuit==3 and st.players[2].bonus==40)
-- Scoring cases at the eighth trick, including contract failure and barrel attempts.
local function scoring(scores,barrels,attempts,total,contract)
 local q=M.deal{players=3,dealer=3};q.phase='playing';q.stage='play';q.turn=1;q.trickNo=8
 q.bidder=1;q.contract=contract or 100;q.startScores=scores
 q.stock={};q.players[1].hand={c('9C')};q.players[2].hand={c('JC')};q.players[3].hand={c('AC')}
 for i,p in ipairs(q.players) do p.score=scores[i];p.barrel=barrels and barrels[i] or false;p.attempts=attempts and attempts[i] or 0 end
 q.players[1].points=total or 100;q.players[2].points=12
 act(q,1,'play','9C');act(q,2,'play','JC');act(q,3,'play','AC');return q
end
st=scoring({0,0,0},nil,nil,99,100);assert(st.players[1].score==-100 and st.players[2].score==10 and st.players[3].score==15)
st=scoring({800,0,0},nil,nil,100,100);assert(st.players[1].score==880 and st.players[1].barrel and st.players[1].attempts==0)
st=scoring({880,880,0},{true,true,false},{0,1,0},120,120)
assert(st.phase=='game_end' and st.winners[1]==1 and st.players[2].score==880 and st.players[2].attempts==2)
st=scoring({0,880,0},{false,true,false},{0,2,0},100,100);assert(st.players[2].score==760 and not st.players[2].barrel)
st=scoring({880,0,0},{true,false,false},{0,0,0},100,100);assert(st.players[1].score==880 and st.players[1].attempts==1)
st=scoring({880,0,0},{true,false,false},nil,99,100);assert(st.players[1].score==780 and not st.players[1].barrel)
st=scoring({850,0,0},nil,nil,150,150);assert(st.phase=='game_end' and st.players[1].score==1000)
print('Thousand rules PASS: '..games..' whole matches / '..rounds..' deals, conservation, rejection, trump changes, scoring and barrel')
