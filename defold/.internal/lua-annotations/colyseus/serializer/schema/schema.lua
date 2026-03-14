---@meta

---@class Schema
---@field __refid number
---@field private _schema table
---@field private _fields_by_index table
local Schema = {}

function Schema:new(instance)
    instance = instance or {}
    setmetatable(instance, self)
    self.__index = self
    return instance
end

function Schema:set_by_index(field_index, dynamic_index, value)
  self[self._fields_by_index[field_index]] = value
end

function Schema:get_by_index(field_index)
  return self[self._fields_by_index[field_index]]
end

function Schema:delete_by_index(field_index)
  self[self._fields_by_index[field_index]] = nil
end

---@deprecated use :to_json() instead
function Schema:to_raw()
  return self:to_json()
end

---Get raw JSON representation of the schema
---@return table
function Schema:to_json()
  local raw = {}

  for field, _ in pairs(self._schema) do
    if type(self[field]) == "table" and type(self[field]['to_json']) == "function" then
      raw[field] = self[field]:to_json()
    else
      raw[field] = self[field]
    end
  end

  return raw
end

---@param fields table
---@param extends Schema|nil
local define = function(fields, extends)
    local schemaClass = Schema:new()
    schemaClass._schema = {}
    schemaClass.__index = extends or Schema

    local fields_by_index = {}

    if extends ~= nil and extends._fields_by_index ~= nil then
      for _, field in pairs(extends._fields_by_index) do
          fields[field] = extends._schema[field]
          table.insert(fields_by_index, field)
      end
    end

    if fields._fields_by_index ~= nil then
      for _, field in pairs(fields._fields_by_index) do
        table.insert(fields_by_index, field)
        schemaClass._schema[field] = fields[field]
      end
    end

    schemaClass._fields_by_index = fields_by_index

    return schemaClass
end

return {
  define = define,
  Schema = Schema,
}
