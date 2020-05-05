local lhp = require'lhttp.parser'
local concat = table.concat
local Emitter = require'core'.Emitter

local Decoder = Emitter:extend()

function Decoder:initialize(ptype)
  assert(ptype=='request' or ptype=='response')
  local header, ctx = nil, nil

  local cb = {}
  function cb.onMessageBegin()
    header = {}                         -- wait for header
    ctx = {}
  end

  function cb.onUrl(value)
    ctx[#ctx+1] = value
    header.path = value
  end

  function cb.onStatus(code, reason)
    header.code = code
    header.reason = reason
  end

  function cb.onHeaderField(field)
    if ptype=='request' and #ctx>0 then
      header.path = concat(ctx, '')
      ctx = {}
    end
    ctx[#ctx+1] = field
  end

  function cb.onHeaderValue(value)
    if #ctx>0 then
      local field = concat(ctx, '')
      ctx = {}
      header[#header+1] = {field, value}
    else
      local v = header[#header]
      v[2] = v[2]..value
    end
  end

  function cb.onHeadersComplete(info)
    header.code = info.status_code
    header.keepAlive = info.should_keep_alive
    header.method = info.method
    header.version = info.version_major+info.version_minor/10
    header.upgrade = info.upgrade or nil
    self:emit(ptype, header)
    header = {}
  end

  function cb.onBody(value)
    self:emit('data', value)
  end

  function cb.onMessageComplete()
    self:emit('end')
  end

  self.parser = lhp.new(ptype, cb)
end

function Decoder:execute(buffer)
  local parser = self.parser
  if buffer then
    parser:execute(buffer)
  else
    parser:finish()
  end
  local errno, name, desc = parser:http_errno()
  if errno~=0 then
    self:emit('error', name, desc)
  end
end

return Decoder

