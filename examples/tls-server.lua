
local fixture = require('../tests/fixture-tls')
local tls = require('tls')
local options = {
  cert = fixture.certPem,
  key = fixture.keyPem
}

local serverConnected = 0

local server = tls.createServer(options, function(conn)
  serverConnected = serverConnected + 1
  p('server accepted',serverConnected)
  conn:write('done\n')
  conn:destroy()
end)

server:listen(fixture.commonPort, function()
  p('server listening at:',fixture.commonPort)
end)

