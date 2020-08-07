local net = require('net')
local timer = require('timer')

local _isent = 0
local _irecv = 0
local _csent = 0
local _crecv = 0
local _1M = 1024*1024
local LEN = 1024*8*8
local msg = string.rep('-', LEN)

local mode = process.argv[2]

if mode==nil or mode:match('s') then
  local dat = ''
  local interval = timer.setInterval(1000, function ()
    print(string.format(">Sent:%04.02f MB /%06d <Recv:%04.02f MB /%06d", _isent/_1M, _csent, _irecv/_1M, _crecv))
    _irecv, _isent, _crecv, _csent = 0, 0, 0, 0
  end)

  local server = net.createServer(function(client)
    print("Client connected")
    client:nodelay(true)

    -- Add some listenners for incoming connection
    client:on("error",function(err)
      print("Client read error: " .. err)
      client:destroy()
    end)

    client:on("data",function(data)
      _irecv = _irecv + #data
      _crecv = _crecv + 1
      dat = dat .. data
      if (#dat >= LEN) then
        client:write(dat:sub(1, LEN))
        _isent = _isent + LEN
        dat = dat:sub(LEN+1)
        _csent = _csent + 1
      end
    end)

    client:on("end",function()
      interval:destroy()
      print("Client disconnected")
    end)
  end)

  -- Add error listenner for server
  server:on('error',function(err)
    if err then error(err) end
  end)

  server:listen(1234) -- or "server:listen(1234)"
end

if mode==nil or mode:match('c') then
  local client
  client = net.createConnection({port=1234, host='127.0.0.1', nodelay=true}, function (err)
    if err then error(err) end

    print("Connected...")
    client:on("data",function(data)
      client:write(data)
    end)

    client:write(msg)
  end)
end

