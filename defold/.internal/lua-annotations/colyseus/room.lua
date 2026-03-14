---@meta
local os = require('os')
local msgpack = require('colyseus.messagepack.MessagePack')

local Connection = require('colyseus.connection')
local protocol = require('colyseus.protocol')

local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils.utils')
local decode = require('colyseus.serializer.schema.encoding.decode')
local encode = require('colyseus.serializer.schema.encoding.encode')
local serialization = require('colyseus.serialization')

local function exponential_backoff(attempt, delay)
  return math.floor(math.pow(2, attempt) * delay)
end

---@class Room : EventEmitterInstance
---@field state table
---@field session_id string
---@field room_id string
---@field connection Connection
Room = {}
Room.__index = function (self, key)
  if key == "state" then
    -- state getter
    return self.serializer:get_state()
  else
    return Room[key]
  end
end

---@private
---@param name string
---@return Room
function Room.new(name)
  local room = EventEmitter:new({
    serializer_id = nil,
    reconnection_token = nil,
    previous_code = nil
  })
  setmetatable(room, Room)
  room:init(name)
  return room
end

---@private
---@param name string
function Room:init(name)
  self.name = name
  self.serializer = nil
  self.on_message_handlers = {}

  self.reconnection = {
    retry_count = 0,
    max_retries = 15,
    delay = 100,
    min_delay = 100,
    max_delay = 5000,
    min_uptime = 5000,
    backoff = exponential_backoff,
    max_enqueued_messages = 10,
    enqueued_messages = {},
    is_reconnecting = false
  }

  local room = self

  -- remove all listeners on leave
  self:on('leave', function()
    room:destroy()
    room:off()
  end)
end

---@private
---@param endpoint string
---@param options table
function Room:connect (endpoint, options)
  self.connection = Connection.new()

  local room = self

  self.connection:on("message", function(message)
    room:_on_message(message, { offset = 1 })
  end)

  self.connection:on("close", function(e)
    if (room._joined_at_time == nil) then
      print("Room connection closed before JOIN_ROOM")
      return
    end

    if (
      e.code == protocol.CLOSE_CODE.NO_STATUS_RECEIVED
      or e.code == protocol.CLOSE_CODE.ABNORMAL_CLOSURE
      or e.code == protocol.CLOSE_CODE.GOING_AWAY
      or e.code == protocol.CLOSE_CODE.MAY_TRY_RECONNECT
    ) then
      room:emit("drop", e)
      room:_handle_reconnection()

    else
      room:emit("leave", e)
    end
  end)

  room.connection:on("error", function(e)
    room:emit("error", e)
  end)

  -- TODO: support "?skipHandshake=1" option here!
  room.connection:open(endpoint)
end

---@param type string
---@param handler fun(message:table)
function Room:on_message(type, handler)
  local _self = self

  local message_type = self:get_message_handler_key(type)
  self.on_message_handlers[message_type] = handler

  return function()
    _self.on_message_handlers[message_type] = nil
  end
end

---@private
function Room:_on_batch_message(binary_string)
  local total_bytes = #binary_string
  local cursor = { offset = 1 }
  while cursor.offset <= total_bytes do
    self:_on_message(binary_string, cursor)
  end
end

---@private
function Room:_on_message (binary_string, it)
  local message = utils.string_to_byte_array(binary_string)

  local code = message[it.offset]
  it.offset = it.offset + 1

  if code == protocol.JOIN_ROOM then
    local reconnection_token = decode.string(message, it)
    self.serializer_id = decode.string(message, it)

    self.reconnection_token = {
      room_id = self.room_id,
      reconnection_token = reconnection_token,
    }

    -- Only create a new serializer on first join.
    -- When reconnecting with "skipHandshake=1", we reuse the existing serializer
    if self.serializer == nil then
      local serializer = serialization.get_serializer(self.serializer_id)
      if not serializer then error("missing serializer: " .. self.serializer_id); end
      self.serializer = serializer:new()
    end

    if #message > it.offset and self.serializer.handshake ~= nil then
      self.serializer:handshake(message, it)
    end

    -- emit join OR reconnect event
    if self._joined_at_time == nil then
      self._joined_at_time = os.time()
      self:emit("join")

    else
      self.reconnection.is_reconnecting = false
      self:emit("reconnect", self.reconnection.retry_count)
    end

    -- acknowledge JOIN_ROOM
    self.connection:send(utils.byte_array_to_string({ protocol.JOIN_ROOM, 0 })) -- 0 is necessary for HTML5 builds (null-terminated string)

    -- send enqueued messages
    if #self.reconnection.enqueued_messages > 0 then
      for _, msg in ipairs(self.reconnection.enqueued_messages) do
        self.connection:send(msg.data)
      end
      self.reconnection.enqueued_messages = {}
    end

  elseif code == protocol.ERROR then
    local code = decode.number(message, it)
    local error = decode.string(message, it)
    self:emit("error", { code = code, error = error })

  elseif code == protocol.LEAVE_ROOM then
    self:leave()

  elseif code == protocol.ROOM_STATE then
    self:set_state(message, it)

  elseif code == protocol.ROOM_STATE_PATCH then
    self:patch(message, it)

  elseif code == protocol.ROOM_DATA then
    local message_type

    if decode.string_check(message, it) then
      message_type = decode.string(message, it)
    else
      message_type = decode.number(message, it)
    end

    local payload = nil

    if #binary_string >= it.offset then
      local msgpack_cursor = {
          s = binary_string,
          i = it.offset,
          j = #binary_string,
          underflow = function() error "missing bytes" end,
      }
      payload = msgpack.unpack_cursor(msgpack_cursor)
      it.offset = msgpack_cursor.i
    end

    self:_dispatch_message(message_type, payload)

  elseif code == protocol.ROOM_DATA_BYTES then
    local message_type

    if decode.string_check(message, it) then
      message_type = decode.string(message, it)
    else
      message_type = decode.number(message, it)
    end

    local payload = {}
    for i = it.offset, #binary_string, 1 do
      payload[#payload+1] = message[i]
    end

    self:_dispatch_message(message_type, payload)

  elseif code == protocol.PING then
    if self.ping_callback then
      local now = os.time()
      self.ping_callback(math.floor((now - self.last_ping_time) + 0.5))
      self.ping_callback = nil
    end
  end
end

---@private
function Room:set_state (encoded_state, it)
  self.serializer:set_state(encoded_state, it)
  self:emit("statechange", self.serializer:get_state())
end

---@private
function Room:patch (binary_patch, it)
  self.serializer:patch(binary_patch, it)
  self:emit("statechange", self.serializer:get_state())
end

---@private
function Room:_handle_reconnection()
  if (os.time() - self._joined_at_time) < (self.reconnection.min_uptime / 1000) then
     print(string.format("[Colyseus reconnection]: ❌ Room has not been up for long enough for automatic reconnection. (min uptime: %dms)", self.reconnection.min_uptime))
     return
  end

  if not self.reconnection.is_reconnecting then
    self.reconnection.retry_count = 0
    self.reconnection.is_reconnecting = true
  end

  self:_retry_reconnection()
end

---@private
function Room:_retry_reconnection()
  self.reconnection.retry_count = self.reconnection.retry_count + 1

  local delay_ms = math.min(self.reconnection.max_delay, math.max(self.reconnection.min_delay, self.reconnection.backoff(self.reconnection.retry_count, self.reconnection.delay)))
  local delay_sec = delay_ms / 1000

  print(string.format("[Colyseus reconnection]: ⏳ will retry in %.1f seconds...", delay_sec))

  local room = self

  local on_error = nil
  local on_open = nil

  on_error = function(e)
    room.connection:off("error", on_error)

    if room.reconnection.retry_count < room.reconnection.max_retries then
      room:_retry_reconnection()
    else
      print("[Colyseus reconnection]: ❌ Failed to reconnect. Is your server running? Please check server logs.")
      room.reconnection.is_reconnecting = false
      room:emit("leave", { code = protocol.CLOSE_CODE.ABNORMAL_CLOSURE, reason = "reconnection failed" })
    end
  end

  on_open = function()
    room.connection:off("open", on_open)
    room.connection:off("error", on_error)
  end

  timer.delay(delay_sec, false, function()
    print(string.format("[Colyseus reconnection]: ░ Re-establishing sessionId '%s' with roomId '%s'... (attempt %d of %d)", room.session_id, room.room_id, room.reconnection.retry_count, room.reconnection.max_retries))

    room.connection:on("error", on_error)
    room.connection:on("open", on_open)
    room.connection:reconnect({
      reconnectionToken = room.reconnection_token.reconnection_token,
      skipHandshake = 1 -- we already applied the handshake on first join
    })
  end)
end

---@private
function Room:_enqueue_message(message)
  table.insert(self.reconnection.enqueued_messages, { data = message })
  if #self.reconnection.enqueued_messages > self.reconnection.max_enqueued_messages then
    table.remove(self.reconnection.enqueued_messages, 1)
  end
end

---@param consented nil|boolean
function Room:leave(consented)
  if self.connection.state == "OPEN" then
    if consented or consented == nil then
      self.connection:send(utils.byte_array_to_string({ protocol.LEAVE_ROOM, 0 }))
    else
      self.connection:close()
    end
  else
    self:emit("leave")
  end
end

function Room:ping(callback)
  -- skip if connection is not open
  if self.connection.state ~= "OPEN" then
    return
  end

  self.last_ping_time = os.time()
  self.ping_callback = callback
  self.connection:send(utils.byte_array_to_string({ protocol.PING }))
end

---@param message_type number|string
---@param message table|boolean|number|string
function Room:send (message_type, message)
  local initial_bytes = { protocol.ROOM_DATA }
  local mtype = type(message_type)

  if mtype == "string" then
      encode.string(initial_bytes, message_type);

  elseif mtype == "number" then
      encode.number(initial_bytes, message_type);
  else
    error("Protocol.ROOM_DATA: message type not supported '" .. tostring(type) .. "'")
  end

  local encoded

  if message ~= nil then
    encoded = msgpack.pack(message)
  else
    encoded = ''
  end

  local data = utils.byte_array_to_string(initial_bytes) .. encoded
  if self.connection.state ~= "OPEN" then
    self:_enqueue_message(data)
  else
    self.connection:send(data)
  end
end

---@param message_type string
---@param bytes table
function Room:send_bytes (message_type, bytes)
  local initial_bytes = { protocol.ROOM_DATA }
  local mtype = type(message_type)

  if mtype == "string" then
      encode.string(initial_bytes, message_type);

  elseif mtype == "number" then
      encode.number(initial_bytes, message_type);
  else
    error("Protocol.ROOM_DATA_BYTES: message type not supported '" .. tostring(type) .. "'")
  end

  local data = utils.byte_array_to_string(initial_bytes) .. utils.byte_array_to_string(bytes)
  if self.connection.state ~= "OPEN" then
    self:_enqueue_message(data)
  else
    self.connection:send(data)
  end
end

---@private
function Room:destroy()
  if self.serializer and self.serializer.teardown ~= nil then
    self.serializer:teardown();
  end
end

---@private
function Room:_dispatch_message (message_type, message)
  local type_key = self:get_message_handler_key(message_type);

  if self.on_message_handlers[type_key] then
    self.on_message_handlers[type_key](message);

  elseif self.on_message_handlers['*'] then
    self.on_message_handlers['*'](message_type, message)

  elseif string.sub(type_key, 1, 3) ~= "s__" then -- ignore internal messages
    print('on_message not registered for type "' .. tostring(message_type) .. '".')
  end
end

---@private
function Room:get_message_handler_key(message_type)
  local t = type(message_type)

  if t == "string" then
    return "s" .. message_type
  elseif t == "number" then
    return "i" .. tostring(message_type)
  else
    error("invalid message type.")
  end
end

return Room
