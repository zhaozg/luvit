local tls = require('tls')
local openssl = require('openssl')

local options = {
  port = '12456',
  host = '127.0.0.1',
  rejectUnauthorized=false
}
options.secureContext = tls.createCredentials(options)

local function Active(callback)
  local client = tls.connect(options)
  client:on('secureConnection', function()
    p('client connected')
  end)

  client:on('error', function(err)
    p(err)
    client:destroy()
  end)
  client:on('data', function(...)
    p(...)
    --
    local session = client.ssl:session()
    print('Reuseable:', session:is_resumable())
    print('has_ticket:', session:has_ticket())

    print('SessReuse:', client.ssl:session_reused())
    print('SessionID:', openssl.hex(session:id()))

    options.secureContext.session = session
    if callback then callback() end
  end)
  client:on('end', function()
    p('client end')
  end)
end

Active(Active)
