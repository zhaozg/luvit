local p = p
local uv = require('uv')
local table = require('table')

local _isent = 0
local _irecv = 0
local _csent = 0
local _crecv = 0

local _1M = 1024*1024
local LEN = 1024*64

local msg = string.rep('-', LEN)

local mode = process.argv[2]

local function set_interval(interval, callback)
  local timer = uv.new_timer()
  local function ontimeout()
    callback(timer)
  end
  uv.timer_start(timer, interval, interval, ontimeout)
  return timer
end

local iTimer = set_interval(1000, function()
  print(string.format(">Sent:%04.02f MB /%06d <Recv:%04.02f MB /%06d", _isent/_1M, _csent, _irecv/_1M, _crecv))
  _irecv = 0
  _isent = 0
  _crecv = 0
  _csent = 0
end)

local function create_server(host, port, on_connection)

  local server = uv.new_tcp()
  uv.tcp_nodelay(server, true)
  uv.tcp_bind(server, host, port)

  uv.listen(server, 128, function(err)
    assert(not err, err)
    local client = uv.new_tcp()
    uv.tcp_nodelay(server, true)
    uv.accept(server, client)
    on_connection(client)
  end)

  return server
end

if mode==nil or mode:match('^s') then

local cache = {}
local server = create_server("0.0.0.0", 1234, function (client)
  -- uv.tcp_nodelay(client, true)
  p("new client", client, uv.tcp_getsockname(client), uv.tcp_getpeername(client))
  if not cache[client] then
    cache[client] = {len=0}
  end
  local data = cache[client]

  uv.read_start(client, function (err, chunk)
    assert(not err, err)
    _irecv = _irecv + #chunk
    _crecv = _crecv + 1

    data.len = data.len + #chunk
    data[#data+1] = chunk
    -- Echo anything heard
    if data.len>=LEN then
      uv.write(client, table.concat(data), function()
        _isent = _isent + LEN
        _csent = _csent + 1
      end)
      data = {len=0}
    end
    --]]
  end)
end)

end

if mode==nil or mode:match('^c') then

local client = uv.new_tcp()
uv.tcp_nodelay(client, true)
local write_cb
write_cb = function(_)
  uv.write(client, msg, write_cb)
end
uv.tcp_connect(client, "127.0.0.1", 1234, function (err)
  assert(not err, err)
  uv.read_start(client, function (err, chunk)
    assert(not err, err)
    if chunk then
      uv.write(client, msg)
    else
      uv.close(client)
    end
  end)
  uv.write(client, msg)
end)

end

-- Start the main event loop
uv.run()
-- Close any stray handles when done
uv.walk(uv.close)
uv.run()
