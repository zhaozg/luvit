--[[

Copyright 2014 The Luvit Authors. All Rights Reserved.

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
local uv = require('uv')
local decoder = require('http-decoder')
local deepEqual = require('deep-equal')

local function testDecoder(decoder, inputs, type)
  local outputs, body = {}, {}
  local decode = decoder:new(type)
  decode:on(type, function(head)
    outputs[#outputs+1] = head
    outputs[#outputs+1] = ''
  end)
  decode:on('data', function(data)
    body[#body+1] = data
  end)
  decode:on('end', function()
    outputs[#outputs] = outputs[#outputs] .. table.concat(body, '')
    body = {}
  end)
  decode:on('error', function(name, desc)
    p('XXXX', name, desc)
  end)

  local chunk = table.remove(inputs, 1)
  while chunk do
    decode:execute(chunk)
    chunk = table.remove(inputs, 1)
  end
  uv.run()
  return outputs
end

require('tap')(function (test)

  test("http server parser", function ()
    local output = testDecoder(decoder, {
      "GET /path HTTP/1.1\r\n",
      "User-Agent: Luvit-Test\r\n\r\n"
    }, 'request')
    assert(deepEqual({
      { method = "GET", path = "/path", version = 1.1, keepAlive = true,
        {"User-Agent", "Luvit-Test"}
      },
      ""
    }, output))
  end)

  test("http client parser", function ()
    local output = testDecoder(decoder, {
      "HTTP/1.0 200 OK\r\n",
      "User-Agent: Luvit-Test\r\n\r\n"
    }, 'response')
    assert(deepEqual({
      { code = 200, reason = "OK", version = 1.0, keepAlive = false,
        {"User-Agent", "Luvit-Test"}
      },
      ""
    }, output))
  end)

  test("http client parser with an empty value", function ()
    local output = testDecoder(decoder, {
      "HTTP/1.0 200 OK\r\n",
      "X-Empty-Value:\r\n",
      "User-Agent: Luvit-Test\r\n\r\n"
    }, 'response')
    assert(deepEqual({
      { code = 200, reason = "OK", version = 1.0, keepAlive = false,
        {"X-Empty-Value", ""},
        {"User-Agent", "Luvit-Test"}
      },
      ""
    }, output))
  end)


  test("http 1.0 Keep-Alive", function ()
    local output = testDecoder(decoder, {
      "GET / HTTP/1.0\r\n",
      "Connection: Keep-Alive\r\n\r\n",
      "DELETE /bad-resource HTTP/1.0\r\n",
      "Connection: Keep-Alive\r\n\r\n",
    }, 'request')
    assert(deepEqual({
      { method = "GET", path = "/", version = 1.0, keepAlive = true,
        {"Connection", "Keep-Alive"},
      },
      "",
      { method = "DELETE", path = "/bad-resource", version = 1.0, keepAlive = true,
        {"Connection", "Keep-Alive"},
      },
      "",
    }, output))
  end)

  test("http 1.0 Raw body", function ()
    local output = testDecoder(decoder, {
      "POST / HTTP/1.0\r\n",
      "Content-Length: 57\r\n",
      "User-Agent: Test\r\n\r\n",
      "DELETE /bad-resource HTTP/1.0\r\n",
      "Connection: Keep-Alive\r\n\r\n",
    }, 'request')
    assert(deepEqual({
      { method = "POST", path = "/", version = 1.0, keepAlive = false,
        {"Content-Length", "57"},
        {"User-Agent", "Test"},
      },
      "DELETE /bad-resource HTTP/1.0\r\nConnection: Keep-Alive\r\n\r\n"
    }, output))
  end)

  test("http 1.1 Keep-Alive", function ()
    local output = testDecoder(decoder, {
      "HEAD / HTTP/1.1\r\n\r\n",
      "DELETE /bad-resource HTTP/1.1\r\n\r\n",
    }, 'request')
    assert(deepEqual({
      { method = "HEAD", path = "/", version = 1.1, keepAlive = true },
      "",
      { method = "DELETE", path = "/bad-resource", version = 1.1, keepAlive = true },
      "",
    }, output))
  end)
--]]

  test("http 1.1 Keep-Alive with bodies", function ()
    local output = testDecoder(decoder, {
      "POST /upload HTTP/1.1\r\n",
      "Content-Length: 12\r\n",
      "\r\nHello World\nDELETE ",
      "/ HTTP/1.1\r\n\r\n",
    }, 'request')
    assert(deepEqual({
      { method = "POST", path = "/upload", version = 1.1, keepAlive = true,
        {"Content-Length", "12"},
      },
      "Hello World\n",
      { method = "DELETE", path = "/", version = 1.1, keepAlive = true },
      ""
    }, output))
  end)

  test("http 1.1 Raw body", function ()
    local output = testDecoder(decoder, {
      "POST / HTTP/1.1\r\n",
      "Content-Length: 51\r\n",
      "Connection: Close\r\n\r\n",
      "User-Agent: Test\r\n\r\n",
      "DELETE /bad-resource HTTP/1.0\r\n",
    }, 'request')
    assert(deepEqual({
      { method = "POST", path = "/", version = 1.1, keepAlive = false,
        {"Content-Length", "51"},
        {"Connection", "Close"},
      },
      "User-Agent: Test\r\n\r\nDELETE /bad-resource HTTP/1.0\r\n"
    }, output))
  end)

  test("chunked encoding parser", function ()
    local output = testDecoder(decoder, {
      "PUT /my-file.txt HTTP/1.1\r\n",
      "Transfer-Encoding: chunked\r\n\r\n",
      "4\r\n",
      "Wiki\r\n",
      "5\r\n",
      "pedia\r\n",
      "e\r\n",
      " in\r\n\r\nchunks.\r\n",
      "0\r\n",
      "\r\n",
    }, 'request')
    assert(deepEqual({
      { method = "PUT", path = "/my-file.txt", version = 1.1, keepAlive = true,
        {"Transfer-Encoding", "chunked"},
      },
      "Wikipedia in\r\n\r\nchunks."
    }, output))
  end)

  test("chunked encoding parser (oneline)", function ()
    local output = testDecoder(decoder, {
      "PUT /my-file.txt HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n4\r\nWiki\r\n5\r\npedia\r\ne\r\n in\r\n\r\nchunks.\r\n0\r\n\r\n"
    }, 'request')
    assert(deepEqual({
      { method = "PUT", path = "/my-file.txt", version = 1.1, keepAlive = true,
        {"Transfer-Encoding", "chunked"},
      },
      "Wikipedia in\r\n\r\nchunks."
    }, output))
  end)

  test("chunked encoding parser (broken)", function ()
    local output = testDecoder(decoder, {
      "PUT /my-file.txt HTTP/1.1\r",
      "\nTransfer-Encoding: chunke",
      "d\r\n\r\n4\r\nWiki\r\n5\r\n",
      "pedia\r\n12\r",
      "\n in broken ch",
      "unks.\r\n0\r\n\r\n"
    }, 'request')
    assert(deepEqual({
      { method = "PUT", path = "/my-file.txt", version = 1.1, keepAlive = true,
        {"Transfer-Encoding", "chunked"},
      },
      "Wikipedia in broken chunks."
    }, output))
  end)

end)
