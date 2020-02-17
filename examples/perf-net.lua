local net = require('net')
local timer = require('timer')

local _isent = 0
local _irecv = 0
local _1M = 1024*1024
local LEN = 1024*8
local msg = string.rep('-', LEN)


p(process.argv)
local mode = process.argv[2]

if mode==nil or mode:match('s') then
  local dat = ''
  local interval = timer.setInterval(1000, function ()
    print(string.format("Sent:%02f Recv:%02f", _isent/_1M, _irecv/_1M))
    _irecv = 0
    _isent = 0
  end)

  local server = net.createServer(function(client)
    print("Client connected")
    client:nodelay(true)

    -- Add some listenners for incoming connection
    client:on("error",function(err)
      print("Client read error: " .. err)
      client:close()
    end)

    client:on("data",function(data)
      _irecv = _irecv + #data
      dat = dat .. data
      if (#dat == LEN) then
        client:write(data)
        _isent = _isent + #data
        dat = ''
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

  server:listen(1234, '127.0.0.1') -- or "server:listen(1234)"
end
if mode==nil or mode:match('c') then
  local client
  client = net.createConnection(1234, '127.0.0.1', function (err)
    if err then error(err) end

    print("Connected...")
    client:nodelay(true)

    client:on("data",function(data)
      client:write(data)
    end)

    client:write(msg)
  end)
end

