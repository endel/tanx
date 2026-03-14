---@meta
local reflection = require('colyseus.serializer.schema.reflection')
local reference_tracker = require('colyseus.serializer.schema.reference_tracker')
local Decoder = require('colyseus.serializer.schema.decoder')

---@class schema_serializer
---@field decoder Decoder
local schema_serializer = {}
schema_serializer.__index = schema_serializer

---@return schema_serializer
function schema_serializer:new ()
  local instance = { decoder = nil, }
  setmetatable(instance, schema_serializer)
  return instance
end

function schema_serializer:get_state()
  return self.decoder.state
end

function schema_serializer:set_state(encoded_state, it)
  self.decoder:decode(encoded_state, it)
end

function schema_serializer:patch(binary_patch, it)
  self.decoder:decode(binary_patch, it)
end

function schema_serializer:teardown()
  self.decoder.refs:clear()
end

function schema_serializer:handshake(bytes, it)
  self.decoder = reflection.decode(bytes, it)
end

return schema_serializer
