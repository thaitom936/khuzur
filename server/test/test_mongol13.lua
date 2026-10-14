package.path='server/lualib/?.lua;'..package.path
local M=require 'rules.mongol13'
local json=require 'json'
local f=assert(io.open('testdata/mongol13/combinations.json'));local cases=json.decode(f:read('a'));f:close()
local function cards(a) local out={} for _,c in ipairs(a) do out[#out+1]=assert(M.parseCard(c)) end return out end
for i,c in ipairs(cases) do
  local combo=M.combo(cards(c.cards))
  assert((combo and combo.kind or nil)==(type(c.kind)=='string' and c.kind or nil),'combo '..i)
  if c.other then assert(M.beats(combo,M.combo(cards(c.other)))==c.beats,'comparison '..i) end
end
-- Complete randomized games with valid hints. No hidden-card leakage is needed by the rules.
math.randomseed(1313)
for n=2,4 do for trial=1,40 do
  local st=M.deal{players=n};local count=0
  local seen={};for _,p in ipairs(st.players) do assert(#p.hand==13);for _,c in ipairs(p.hand) do assert(not seen[c]);seen[c]=true end end
  if st.phase=='playing' then
    local before=#st.players[st.turn].hand
    assert(not M.pass(st,st.turn))
    assert(not M.play(st,st.turn,{'XX'}))
    assert(#st.players[st.turn].hand==before)
  end
  while st.phase=='playing' do
    count=count+1; assert(count<220,'no progress')
    local seat=st.turn;local hint=M.hint(st,seat)
    if #hint==0 then assert(M.pass(st,seat)) else assert(M.play(st,seat,hint)) end
  end
  local sum=0;for _,p in ipairs(st.players) do sum=sum+p.score end
  assert(sum==0 and #st.winners==1)
  assert(st.dragon or #st.players[st.winners[1]].hand==0)
end end
-- Dragon is checked at the deal; suits do not matter.
local dragon={'2D','3C','4H','5S','6D','7C','8H','9S','TD','JC','QH','KS','AD'}
local used={};for _,s in ipairs(dragon) do used[s]=true end
local second={};for suit=0,3 do for r=2,14 do local s=M.cardString(suit*16+r);if not used[s] and #second<13 then second[#second+1]=s end end end
local st=M.newRound{hands={dragon,second}}
assert(st.phase=='game_end' and st.dragon and st.winners[1]==1 and st.players[1].score==39)
print('Mongol 13: 21 shared combinations, 120 full games, validation, dragon and zero-sum scores passed')
