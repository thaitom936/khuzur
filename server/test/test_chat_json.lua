package.path='./lualib/?.lua;'..package.path
local json=require 'json'
assert(json.decode('"\\ud83d\\ude00"')==utf8.char(0x1F600))
assert(json.decode('"\\u4e2d\\u6587"')=='中文')
assert(json.decode('"\\ud83d"')==nil)
assert(json.decode('"\\ude00"')==nil)
assert(json.decode('"\\ud83d\\u0041"')==nil)
print('Chat JSON PASS: escaped Emoji surrogate pairs and malformed Unicode')
