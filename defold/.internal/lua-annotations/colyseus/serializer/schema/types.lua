---@meta
local map_schema = require('colyseus.serializer.schema.types.map_schema')
local array_schema = require('colyseus.serializer.schema.types.array_schema')

local types = {}
local typemap = {}

function types.register_type(id, constructor)
  typemap[id] = constructor
end

function types.unregister_type(id)
  typemap[id] = nil
end

function types.get_type(id)
  return typemap[id]
end

-- built-in types
types.register_type('map', map_schema)
types.register_type('array', array_schema)

return types