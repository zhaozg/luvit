--[[

Copyright 2015 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

--[[lit-meta
  name = "luvit/http"
  version = "2.1.4"
  dependencies = {
    "luvit/net@2.0.0",
    "luvit/url@2.0.0",
    "luvit/http-codec@2.0.0",
    "luvit/stream@2.0.0",
    "luvit/utils@2.0.0",
    "luvit/http-header@1.0.0",
  }
  license = "Apache 2"
  homepage = "https://github.com/luvit/luvit/blob/master/deps/http.lua"
  description = "Node-style http client and server module for luvit"
  tags = {"luvit", "http", "stream"}
]]

local net = require('net')
local url = require('url')
local Emitter = require('core').Emitter
local codec = require('http-codec')
local Writable = require('stream').Writable
local date = require('os').date
local luvi = require('luvi')
local utils = require('utils')
local httpHeader = require('http-header')
local HttpDecoder = require('http-decoder')

local IncomingMessage = Emitter:extend()

function IncomingMessage:initialize(head, socket)
  self.httpVersion = tostring(head.version)
  self.headers = httpHeader.getHeaders(head)
  self.socket = socket
  if head.method then
    -- server specific
    self.method = head.method
    self.url = head.path
    self.upgrade = head.upgrade
  else
    -- client specific
    self.statusCode = head.code
    self.statusMessage = head.reason
  end
end
function IncomingMessage:write(data, cb)
  return self.socket:write(data, cb)
end
function IncomingMessage:done()
  return self.socket:done()
end

local ServerResponse = Writable:extend()

function ServerResponse:initialize(socket)
  Writable.initialize(self)
  local encode = codec.encoder()
  self.socket = socket
  self.encode = encode
  self.statusCode = 200
  self.headersSent = false
  self.headers = httpHeader.newHeaders()

  self._extra_key = {'close', 'drain', 'end'}
  --keep clean handlers when http connection keepAlive
  if not socket._extra_http then
    socket._extra_http = {}
  end
  local extra = socket._extra_http
  for _, evt in pairs(self._extra_key) do
    if extra[evt] then
      self.socket:removeListener(evt,extra[evt])
    end
    extra[evt] = utils.bind(self.emit, self, evt)
    self.socket:on(evt, extra[evt])
  end
end

-- Override this in the instance to not send the date
ServerResponse.sendDate = true

function ServerResponse:setHeader(name, value)
  assert(not self.headersSent, "headers already sent")
  self.headers[name] = value
end

function ServerResponse:getHeader(name)
  assert(not self.headersSent, "headers already sent")
  return self.headers[name]
end

function ServerResponse:removeHeader(name)
  assert(not self.headersSent, "headers already sent")
  self.headers[name] = nil
end

function ServerResponse:flushHeaders()
  if self.headersSent then return end
  self.headersSent = true
  local headers = self.headers
  local statusCode = self.statusCode

  local head = {}
  local sent_date, sent_connection, sent_transfer_encoding, sent_content_length
  for i = 1, #headers do
    local key, value = unpack(headers[i])
    local klower = key:lower()
    head[#head + 1] = {tostring(key), tostring(value)}
    if klower == "connection" then
      self.keepAlive = value:lower() ~= "close"
      sent_connection = true
    elseif klower == "transfer-encoding" then
      sent_transfer_encoding = true
    elseif klower == "content-length" then
      sent_content_length = true
    elseif klower == "date" then
      sent_date = true
    end
    head[i] = headers[i]
  end

  if not sent_date and self.sendDate then
    head[#head + 1] = {"Date", date("!%a, %d %b %Y %H:%M:%S GMT")}
  end
  if self.hasBody and not sent_transfer_encoding and not sent_content_length then
    sent_transfer_encoding = true
    head[#head + 1] = {"Transfer-Encoding", "chunked"}
  end
  if not sent_connection then
    if self.keepAlive then
      if self.hasBody then
        if sent_transfer_encoding or sent_content_length then
          head[#head + 1] = {"Connection", "keep-alive"}
        else
          -- body has no length so close to indicate end
          self.keepAlive = false
          head[#head + 1] = {"Connection", "close"}
        end
      elseif statusCode >= 300 then
        self.keepAlive = false
        head[#head + 1] = {"Connection", "close"}
      else
        head[#head + 1] = {"Connection", "keep-alive"}
      end
    else
      self.keepAlive = false
      head[#head + 1] = {"Connection", "close"}
    end
  end
  head.code = statusCode
  local h = self.encode(head)
  print('hhh', h)
  self.socket:write(h)
end

function ServerResponse:write(chunk, callback)
  if chunk and #chunk > 0 then
    self.hasBody = true
  end
  self:flushHeaders()
  return self.socket:write(self.encode(chunk), callback)
end

function ServerResponse:_end()
  self:finish()
end

function ServerResponse:finish(chunk)
  if chunk and #chunk > 0 then
    self.hasBody = true
  end
  self:flushHeaders()
  local last = ""
  if chunk then
    last = last .. self.encode(chunk)
  end
  last = last .. (self.encode("") or "")
  local function maybeClose()
    self:emit('finish')
    if not self.keepAlive then
      self.socket:_end()
    end
  end
  if #last > 0 then
    self.socket:write(last, function()
      maybeClose()
    end)
  else
    maybeClose()
  end
end

function ServerResponse:writeHead(newStatusCode, newHeaders)
  assert(not self.headersSent, "headers already sent")
  self.statusCode = newStatusCode
  self.headers = httpHeader.toHeaders(newHeaders)
end

local function handleConnection(socket, onRequest)

  -- Initialize the two halves of the stateful decoder and encoder for HTTP.
  local decode = HttpDecoder:new('request')

  local req, res

  local function flush()
    req = nil
  end

  local function onTimeout()
    socket:_end()
  end

  local function onEnd()
    -- Just in case the stream ended and we still had an open request,
    -- end it.
    if req then flush() end
  end

  decode:on('error', function(name, desc)
    if req then
      req:emit('error', desc)
      flush()
    end
    socket:_end()
  end)

  decode:on('data', function(data)
    req:emit('data', data)
  end)

  decode:on('end', function()
    req:emit('end')
  end)

  local function onData(chunk)
    decode:execute(chunk)
  end

  decode:on('request', function(head)
    -- If there was an old request that never closed, end it.
    if req then flush() end

    -- Create a new request object
    req = IncomingMessage:new(head)
    -- Create a new response object
    res = ServerResponse:new(socket)
    res.keepAlive = head.keepAlive

    if req.method == 'CONNECT' or req.upgrade then
      local evt = req.method == 'CONNECT' and 'connect' or 'upgrade'
      if req:listenerCount(evt) > 0 then
        socket:removeListener('data', onData)
        socket:removeListener('end', flush)
        socket:read(0)
        return req:emit(evt, res, socket, evt)
      elseif req.method == 'CONNECT' or res.statusCode == 101 then
        onRequest(req, res)
        return
      end
    end

    res.send = function(self, data, callback)
      data = self.encode and self.encode(data) or data
      return self.socket:write(data, callback or function() end)
    end

    -- Call the user callback to handle the request
    onRequest(req, res)
  end)

  socket:once('timeout', onTimeout)
  -- set socket timeout
  socket:setTimeout(120000)
  socket:on('data', onData)
  socket:on('end', onEnd)
end

local function createServer(onRequest)
  return net.createServer(function (socket)
    return handleConnection(socket, onRequest)
  end)
end

local ClientRequest = Writable:extend()

function ClientRequest.getDefaultUserAgent()
  if ClientRequest._defaultUserAgent == nil then
    ClientRequest._defaultUserAgent = 'luvit/http luvi/' .. luvi.version
  end
  return ClientRequest._defaultUserAgent
end

function ClientRequest:initialize(options, callback)
  Writable.initialize(self)
  self:cork()
  local headers = httpHeader.toHeaders(options.headers)

  local host_found, connection_found, user_agent
  for i = 1, #headers do
    self[#self + 1] = headers[i]
    local key, value = unpack(headers[i])
    local klower = key:lower()
    if klower == 'host' then host_found = value end
    if klower == 'connection' then connection_found = value end
    if klower == 'user-agent' then user_agent = value end
  end

  if not user_agent then
    user_agent = self.getDefaultUserAgent()

    if user_agent ~= '' then
      table.insert(self, 1, { 'User-Agent', user_agent })
    end
  end

  options.host = host_found or options.hostname or options.host

  if not host_found and options.host then
    table.insert(self, 1, { 'Host', options.host })
  end

  self.host = options.host
  self.method = (options.method or 'GET'):upper()
  self.path = options.path or '/'
  self.port = options.port or 80
  self.self_sent = false
  self.connection = connection_found

  self.encode = codec.encoder()
  self.decode = HttpDecoder:new('response')

  if callback then
    self:once('response', callback)
  end

  local res, keepAlive

  local function flush()
    if res then
      res = nil
    end
  end

  local socket = options.socket or net.createConnection({
      nodelay = true,
      port = self.port,
      host = self.host
  })
  local connect_emitter = options.connect_emitter or 'connect'

  self.socket = socket

  local function onError(...) self:emit('error',...) end
  local function onConnect()
    self.connected = true
    self:emit('socket', socket)

    local function onEnd()
      -- Just in case the stream ended and we still had an open response,
      -- end it.
      if res then flush() end
    end

    self.decode:on('data', function(data)
      res:emit('data', data)
    end)
    self.decode:on('end', function()
      res:emit('end')
    end)
    self.decode:on('error', function(name, desc)
      self:emit('error', desc)
      if res then
        res:emit('error', desc)
      end
      socket:_end()
    end)

    local function onData(chunk)
      self.decode:execute(chunk)
    end
    socket:on('data', onData)
    socket:on('end', flush)

    self.decode:on('response', function(head)
      if res then flush() end
      -- Create a new response object
      res = IncomingMessage:new(head)
      if self.method == 'CONNECT' or res.headers.upgrade then
        local evt = self.method == 'CONNECT' and 'connect' or 'upgrade'
        if self:listenerCount(evt) > 0 then
          socket:removeListener("data", onData)
          socket:removeListener("end", onEnd)
          socket:read(0)

          return self:emit(evt, res, socket, evt)
        elseif self.method == 'CONNECT' or res.statusCode == 101 then
          return self:destroy()
        end
      end
      -- Whether the server supports keepAlive connection
      keepAlive = res.headers['Connection']
      if keepAlive then
        keepAlive = keepAlive:lower() == 'keep-alive'
      end
      -- Call the user callback to handle the response
      self:emit('response', res, self)
    end)

    self.reset = function()
      if keepAlive then
        socket:removeAllListeners('data', true)
        socket:removeAllListeners('end', true)
        socket:removeAllListeners('error', true)
        socket:removeAllListeners(connect_emitter, true)
        return socket
      end
    end

    if self.ended then
      return self:_done(self.ended.data, self.ended.cb)
    end
  end

  socket:on('error', onError)
  if socket._connecting then
    socket:on(connect_emitter, onConnect)
  else
    onConnect()
  end
end

function ClientRequest:flushHeaders()
  if not self.headers_sent then
    self.headers_sent = true
    -- set connection
    self:_setConnection()
    Writable.write(self, self.encode(self))
  end
end

function ClientRequest:write(data, cb)
  self:flushHeaders()
  local encoded = self.encode(data)

  -- Don't write empty strings to the socket, it breaks HTTPS.
  if encoded and #encoded > 0 then
    Writable.write(self, encoded, cb)
  else
    if cb then
      cb()
    end
  end
end

function ClientRequest:_write(data, cb)
  self.socket:write(data, cb)
end

function ClientRequest:_done(data, cb)
  self:_end(data, function()
    if cb then
      cb()
    end
  end)
end

function ClientRequest:_setConnection()
  if not self.connection then
    table.insert(self, { 'connection', 'close' })
  end
end

function ClientRequest:done(data, cb)
  -- Optionally send one more chunk
  if data then self:write(data) end

  self:flushHeaders()

  local ended =
    {
      cb = cb or function() end,
      data = ''
    }
  if self.connected then
    self:_done(ended.data, ended.cb)
  else
    self.ended = ended
  end
end

function ClientRequest:setTimeout(msecs, callback)
  if self.socket then
    self.socket:setTimeout(msecs,callback)
  end
end

function ClientRequest:destroy()
  if self.socket then
    self.socket:destroy()
  end
end

local function parseUrl(options)
  if type(options) == 'string' then
    options = url.parse(options)
  end
  return options
end

local function request(options, onResponse)
  return ClientRequest:new(parseUrl(options), onResponse)
end

local function get(options, onResponse)
  options = parseUrl(options)
  options.method = 'GET'
  local req = request(options, onResponse)
  req:done()
  return req
end

return {
  headerMeta = httpHeader.headerMeta, -- for backwards compatibility
  IncomingMessage = IncomingMessage,
  ServerResponse = ServerResponse,
  handleConnection = handleConnection,
  createServer = createServer,
  ClientRequest = ClientRequest,
  parseUrl = parseUrl,
  request = request,
  get = get,
}
