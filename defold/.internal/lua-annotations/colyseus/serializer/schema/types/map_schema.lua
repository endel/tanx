---@meta
local utils = require("colyseus.serializer.schema.utils")

--
-- Lua Language Server doesn't support generics like this yet.
-- https://github.com/LuaLS/lua-language-server/issues/2945
-- ---@class map_schema<T>: {[string]: T}
--

---@class MapSchema
---@field __refid integer
---@field private items table
---@field private dynamic_indexes table
---@field private inexes table
---@field private props table
local MapSchema = {}
MapSchema.__index = MapSchema

---@return MapSchema
function MapSchema:new(obj)
  obj = obj or {
    items = {},
    dynamic_indexes = {},
    indexes = {},
    props = {},
  }
  setmetatable(obj, MapSchema)
  return obj
end

-- getter
function MapSchema:__index(key)
  if MapSchema[key] ~= nil then
    return MapSchema[key]
  else
    return self.props[key] ~= nil
      and self.props[key]
      or self.items[key]
  end
end

-- setter
function MapSchema:__newindex(key, value)
  -- if type(key) == "number" then
  --   self.items[key] = value
  -- else
  --   self.props[key] = value
  -- end
  self.props[key] = value
end

function MapSchema:set_index(index, dynamic_index)
  self.indexes[index] = dynamic_index
end

function MapSchema:set_by_index(index, dynamic_index, value)
  self.indexes[index] = dynamic_index

  -- insert key
  if self.items[dynamic_index] == nil then
      table.insert(self.dynamic_indexes, dynamic_index)
  end

  -- insert value
  self.items[dynamic_index] = value
end

function MapSchema:get_index(index)
  return self.indexes[index]
end

function MapSchema:get_by_index(index)
  return self.items[self.indexes[index]]
end

function MapSchema:delete_by_index(index)
  local dynamic_index = self.indexes[index]

  if dynamic_index ~= nil then
    -- delete key
    for i, k in pairs(self.dynamic_indexes) do
      if k == dynamic_index then
        table.remove(self.dynamic_indexes, i)
        break
      end
    end

    self.items[dynamic_index] = nil
  end

  self.indexes[index] = nil
end

function MapSchema:clear(changes, refs)
  utils.remove_child_refs(self, changes, refs)
  self.indexes = {}
  self.items = {}
end

---@return number
function MapSchema:length()
    return #self.indexes
end

---@return table<string>
function MapSchema:keys()
    return self.dynamic_indexes
end

---@return table
function MapSchema:values()
    local values = {}
    for _, key in ipairs(self.dynamic_indexes) do
        table.insert(values, self.items[key])
    end
    return values
end

---@param cb fun(value: any, key: string)
function MapSchema:each(cb)
    for _, key in ipairs(self.dynamic_indexes) do
        cb(self.items[key], key)
    end
end

function MapSchema:clone()
  return MapSchema:new({
    items = table.clone(self.items),
    indexes = table.clone(self.indexes),
    dynamic_indexes = table.clone(self.dynamic_indexes),
    props = self.props,
  })
end

function MapSchema:to_json()
  local map = {}

  self:each(function(value, key)
    if type(value) == "table" and type(value['to_json']) == "function" then
      map[key] = value:to_json()
    else
      map[key] = value
    end
  end)

  return map
end

return MapSchema
