---@meta
local os = require('os')

local Connection = require('colyseus.connection')
local Protocol = require('colyseus.protocol')

local Room = require('colyseus.room')
local Auth = require('colyseus.auth')
local HTTP = require('colyseus.http')

local EventEmitter = require('colyseus.eventemitter')
local URL = require('colyseus.utils.url')

local info = sys.get_sys_info()

---@class Client : EventEmitterInstance
---@field auth Auth
---@field http HTTP
local Client = {}
Client.__index = Client

---@private
function Client:init(endpoint_or_settings)
  if type(endpoint_or_settings) == "string" then
    local parsed_url = URL.parse(endpoint_or_settings)
    self.settings = {}
    self.settings.hostname = parsed_url.host
    self.settings.port = parsed_url.port
      or ((parsed_url.scheme == "wss" or parsed_url.scheme == "https") and 443)
      or ((parsed_url.scheme == "ws" or parsed_url.scheme == "http") and 80)
    self.settings.use_ssl = (parsed_url.scheme == "wss" or parsed_url.scheme == "https")

    -- force SSL on HTML5 if running on HTTPS protocol
    if info.system_name == "HTML5" then
      self.settings.use_ssl = html5.run("window['location']['protocol']") == "https:"
    end

  else
    self.settings = endpoint_or_settings
  end

  -- ensure hostname does not end with "/"
  if string.sub(self.settings.hostname, -1) == "/" then
    self.settings.hostname = self.settings.hostname:sub(0, -2)
  end

  self.http = HTTP.new(self)
  self.auth = Auth.new(self)
end

---@param room_name string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:join_or_create(room_name, options_or_callback, callback)
  return self:create_matchmake_request('joinOrCreate', room_name, options_or_callback or {}, callback)
end

---@param room_name string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:create(room_name, options_or_callback, callback)
  return self:create_matchmake_request('create', room_name, options_or_callback or {}, callback)
end

---@param room_name string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:join(room_name, options_or_callback, callback)
  return self:create_matchmake_request('join', room_name, options_or_callback or {}, callback)
end

---@param room_id string
---@param options_or_callback nil|table|fun(err:table, room:Room)
---@param callback nil|fun(err:table, room:Room)
function Client:join_by_id(room_id, options_or_callback, callback)
  return self:create_matchmake_request('joinById', room_id, options_or_callback or {}, callback)
end

---@param reconnection_token table
---@param callback fun(err:table, room:Room)
function Client:reconnect(reconnection_token, callback)
  if type(reconnection_token) == "string" and type(callback) == "string" then
    error("DEPRECATED: :reconnect() now only accepts 'reconnection_token' as argument.\nYou can get this token from previously connected `room.reconnection_token`")
  end

  return self:create_matchmake_request('reconnect', reconnection_token.room_id, {
    reconnectionToken = reconnection_token.reconnection_token
  }, callback)
end

---@private
function Client:create_matchmake_request(method, room_name, options_or_callback, callback)
  local options = nil

  if type(options_or_callback) == "function" then
    callback = options_or_callback
    options = {}
  else
    options = options_or_callback
  end

  self.http:request('POST', "matchmake/" .. method .. "/" .. room_name, { body = options, }, function(err, response)
    if (err) then return callback(err) end

    -- forward reconnection token during "reconnect" methods.
    if method == "reconnect" then
      response.reconnectionToken = options_or_callback.reconnectionToken
    end

    self:consume_seat_reservation(response, callback)
  end)
end

---@param response table
---@param callback fun(err:table, room:Room)
function Client:consume_seat_reservation(response, callback)
  local room = Room.new(response.name)

  room.room_id = response.roomId
  room.session_id = response.sessionId

  local options = { sessionId = room.session_id }

  -- forward "reconnection token" in case of reconnection.
  if response.reconnectionToken ~= nil then
    options.reconnectionToken = response.reconnectionToken
  end

  room:connect(self.http:_get_ws_endpoint(response, options), response)

  local on_join = nil
  local on_error = nil

  on_error = function(err)
    room:off('join', on_join)
    callback(err, nil)
  end

  on_join = function()
    room:off('error', on_error)
    callback(nil, room)
  end

  room:once('error', on_error)
  room:once('join', on_join)
end

--- Measures the latency of the connection to the server.
---@param ping_count number
---@param callback fun(err:string, latency:number)
function Client:get_latency(ping_count, callback)
  if type(ping_count) == "function" then
    callback = ping_count
    ping_count = 1
  end

  local conn = Connection.new()
  local latencies = {}
  local start_time = 0
  local endpoint = self.http:_get_ws_endpoint()

  local has_resolved = false
  local resolve = function(err, latency)
    if has_resolved then return end
    has_resolved = true
    conn:close()
    callback(err, latency)
  end

  conn:on("open", function()
    start_time = os.time()
    conn:send(string.char(Protocol.PING))
  end)

  conn:on("message", function(message)
    local now = os.time()
    table.insert(latencies, (now - start_time))

    if #latencies < ping_count then
      start_time = os.time()
      conn:send(string.char(Protocol.PING))
    else
      local sum = 0
      for _, l in ipairs(latencies) do sum = sum + l end
      resolve(nil, sum / #latencies)
    end
  end)

  conn:on("error", function(err)
    resolve("Failed to calculate latency for " .. endpoint)
  end)

  conn:open(endpoint)
end

--- Selects the best endpoint from a list of endpoints based on latency.
---@param endpoints table<string> List of endpoints
---@param callback fun(err:string, client:Client)
function Client.select_by_latency(endpoints, callback)
  local results = {}
  local completed = 0
  local total = #endpoints

  if total == 0 then
    callback("No endpoints provided", nil)
    return
  end

  for i, endpoint in ipairs(endpoints) do
    local client = Client(endpoint)
    client:get_latency(function(err, latency)
      completed = completed + 1
      if not err then
        table.insert(results, { client = client, latency = latency })
        local settings = client.settings
        print(string.format("🛜 Endpoint Latency: %dms - %s:%d%s", latency, settings.hostname, settings.port, settings.pathname))
      end

      if completed == total then
        if #results == 0 then
          callback("All endpoints failed to respond", nil)
        else
          table.sort(results, function(a, b) return a.latency < b.latency end)
          callback(nil, results[1].client)
        end
      end
    end)
  end
end

---@param endpoint_or_settings string|{hostname:string, port:number, use_ssl:boolean}
---@return Client
return function (endpoint_or_settings)
  local instance = EventEmitter:new()
  setmetatable(instance, Client)
  instance:init(endpoint_or_settings)
  return instance
end