---@meta
--
-- @colyseus/social has been deprecated.
-- you can manually require "colyseus.auth" if you still rely on it.
--
local utils = require "colyseus.utils.utils"
local storage = require "colyseus.storage"
local EventEmitter = require('colyseus.eventemitter')

---@class Auth
---@field token string
---@field http HTTP
---@field settings table
local Auth = {}

Auth.__index = function (self, key)
  if key == "token" then
    return self.http.auth_token
  else
    return Auth[key]
  end
end

Auth.__newindex = function (self, key, value)
  if key == "token" then
    -- cache token on storage
    storage.set_item("colyseus-auth-token", value)
    self.http.auth_token = value
  else
    rawset(self, key, value)
  end
end

function Auth.new (client)
  local instance = {
    http = client.http,
    settings = { path = "auth" },
    events = EventEmitter.new({}),
    _initialized = false,
  }
  setmetatable(instance, Auth)
  -- restore token from storage
  instance.token = storage.get_item("colyseus-auth-token")
  return instance
end

--
-- PUBLIC METHODS
--

function Auth:on_change(handler)
  local _self = self
  self.events:on('change', handler)

  if self._initialized == false then
    self._initialized = true
    self:get_user_data(function(err, user_data)
      if err ~= nil then
        _self:emit_change({ token = _self.token, user = user_data, })
      else
        _self:emit_change({ token = nil, user = nil, })
      end
    end)
  end

  return function()
    _self.events:off('change', handler)
  end
end

function Auth:get_user_data(callback)
  if self.token ~= nil then
    self.http:get(self.settings.path .. "/userdata", callback)
  else
    callback("missing auth token", nil)
  end
end

function Auth:register_with_email_and_password(email, password, options_or_callback, callback)
  local options = { body = { email = email, password = password }, }

  if type(options_or_callback) == "table" then
    -- append headers
    for k, v in pairs(options_or_callback) do
      options[k] = v
    end
  else
    callback = options_or_callback
  end

  local _self = self
  self.http:post(self.settings.path .. "/register", options, function(err, data)
    if err == nil then _self:emit_change(data) end
    callback(err, data)
  end)
end

function Auth:sign_in_with_email_and_password(email, password, callback)
  local _self = self
  self.http:post(self.settings.path .. "/login", {
    body = { email = email, password = password },
  }, function(err, data)
    if err == nil then _self:emit_change(data) end
    callback(err, data)
  end)
end

function Auth:sign_in_anonymously(options_or_callback, callback)
  local options = { body = { options = {} }, }

  if type(options_or_callback) == "table" then
    -- append headers
    for k, v in pairs(options_or_callback) do
      options.body.options[k] = v
    end
  else
    callback = options_or_callback
  end

  local _self = self
  self.http:post(self.settings.path .. "/anonymous", options, function(err, data)
    if err == nil then _self:emit_change(data) end
    callback(err, data)
  end)
end

function Auth:send_password_reset_email(email, callback)
  self.http:post(self.settings.path .. "/forgot-password", {
    body = { email = email },
  }, callback)
end

function Auth:sign_in_with_provider(provider_name, settings_or_callback, callback)
  print("'sign_in_with_provider' is not implemented yet!")
  callback("not_implemented", nil)
end

function Auth:sign_out()
  self:emit_change({ token = nil, user = nil, })
end

function Auth:emit_change(auth_data)
  self.token = auth_data.token
  self.events:emit('change', auth_data)
end

return Auth
