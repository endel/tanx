---@meta
local EventEmitter = require('colyseus.eventemitter')
local utils = require('colyseus.utils.utils')

---@class Connection : EventEmitterInstance
local Connection = {}
Connection.config = { connect_timeout = 10 }
Connection.__index = Connection

---@return Connection
function Connection.new()
  local instance = EventEmitter:new()
  setmetatable(instance, Connection)
  instance:init()
  return instance
end

function Connection:init()
  self.state = "CONNECTING"
end

function Connection:send(data)
  if self.state ~= "OPEN" then
    print("[Colyseus] connection hasn't been established. You shouldn't be sending messages yet.")
    return
  end
  websocket.send(self.ws, data)
end

---@function
---@param endpoint string
function Connection:open(endpoint)
  -- skip if connection is already open
  if self.state == 'OPEN' then return end
  self.endpoint = endpoint
  self:_connect(endpoint, {})
end

function Connection:reconnect(query_params)
  local endpoint = self.endpoint

  -- replace reconnectionToken and skipHandshake query params
  endpoint = string.gsub(endpoint, "reconnectionToken=[^&]*", "")
  endpoint = string.gsub(endpoint, "skipHandshake=[^&]*", "")
  -- cleanup empty params
  endpoint = string.gsub(endpoint, "[?&]+$", "")
  endpoint = string.gsub(endpoint, "&&", "&")

  local query_parts = {}
  for k, v in pairs(query_params) do
    table.insert(query_parts, k .. "=" .. v)
  end

  self:_connect(endpoint .. "&" .. utils.concat(query_parts, "&"), {})
end

function Connection:close(close_code)
  self._force_close_code = close_code -- used for testing reconnection
  self.state = "CLOSED"
  websocket.disconnect(self.ws)
  self.ws = nil
end

function Connection:_connect(endpoint, params)
  local this = self
  self.ws = websocket.connect(endpoint, params, function(self, conn, data)
    if data.event == websocket.EVENT_DISCONNECTED then
      this.state = "CLOSED"

      if this._force_close_code ~= nil then
        data.code = this._force_close_code
        this._force_close_code = nil
      end

      this:emit("close", data)
      this.ws = nil

    elseif data.event == websocket.EVENT_CONNECTED then
      print("[Colyseus] websocket connected ")
      this.state = "OPEN"
      this:emit("open")

    elseif data.event == websocket.EVENT_ERROR then
      print("[Colyseus] websocket error")
      this:emit("error", data)

    elseif data.event == websocket.EVENT_MESSAGE then
      this:emit("message", data.message)
    end
  end)
end

return Connection
