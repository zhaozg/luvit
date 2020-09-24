local http = require('http')

local options = {
  host = "127.0.0.1",
  port = 10080,
  path = "/",
  headers = {Connection="Keep-Alive"}
}

local req
local function request(options, onEnd)
  req = http.request(options, function (res)
    res:on('data', function (chunk)
      p("ondata", {chunk=chunk})
    end)
    res:on('end', onEnd)
  end)
  p(req.socket._handle)
  req:done()
end
local i=0
local function onEnd()
  options.socket = req.reset()
  p(options.socket)
  i=i+1
  if (i<200) then
    request(options, onEnd)
  end
end

request(options, onEnd)
