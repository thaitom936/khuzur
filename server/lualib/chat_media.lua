local httpc=require 'http.httpc'
local json=require 'json'
local M={}
function M.call(action,data)
  local secret=os.getenv('CHAT_MEDIA_SECRET')
  if not secret then return nil,'media_unavailable' end
  local port=tonumber(os.getenv('CHAT_MEDIA_PORT')) or 9761
  httpc.timeout=3500
  local ok,status,body=pcall(httpc.request,'POST','127.0.0.1:'..port,'/'..action,nil,
    {['Content-Type']='application/json',Authorization='Bearer '..secret},json.encode(data))
  if not ok then return nil,'media_unavailable' end
  local parsed,result=pcall(json.decode,body)
  if not parsed or type(result)~='table' then return nil,'media_unavailable' end
  if status~=200 then return nil,result.err or 'media_unavailable' end
  return result
end
return M
