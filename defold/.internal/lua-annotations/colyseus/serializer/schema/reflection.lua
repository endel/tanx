---@meta
local schema = require 'colyseus.serializer.schema.schema'
local type_context = require 'colyseus.serializer.schema.type_context'
local Decoder = require 'colyseus.serializer.schema.decoder'

local function reverse_table(t)
  local reversed = {}
  for i = #t, 1, -1 do
      table.insert(reversed, t[i])
  end
  return reversed
end

---@class ReflectionField : Schema
---@field name string
---@field type string
---@field referenced_type number
local ReflectionField = schema.define({
    ["name"] = "string",
    ["type"] = "string",
    ["referenced_type"] = "number",
    ["_fields_by_index"] = {"name", "type", "referenced_type"}
})

---@class ReflectionType : Schema
---@field id number
---@field extends_id number
---@field fields ReflectionField[]
local ReflectionType = schema.define({
    ["id"] = "number",
    ["extends_id"] = "number",
    ["fields"] = { array = ReflectionField },
    ["_fields_by_index"] = {"id", "extends_id", "fields"}
})

---@class Reflection : Schema
---@field types ReflectionType[]
---@field root_type number
local Reflection = schema.define({
    ["types"] = { array = ReflectionType },
    ["root_type"] = "number",
    ["_fields_by_index"] = {"types", "root_type"}
})

---@param bytes number[]
---@param it table
---@return Decoder
local decode = function (bytes, it)
    local reflection = Reflection:new()

    local reflection_decoder = Decoder:new(reflection)
    reflection_decoder:decode(bytes, it)

    local context = type_context:new()

    local add_field = function(schema_class, field_index, field_name, field_type)
        schema_class._schema[field_name] = field_type
        schema_class._fields_by_index[field_index] = field_name
    end

    ---@param schema_type Schema
    ---@param reflection_type ReflectionType
    ---@param parent_field_index number
    local add_fields = function(schema_type, reflection_type, parent_field_index)
        for i = 1, reflection_type.fields:length() do
            local field = reflection_type.fields[i]
            local field_index = parent_field_index + i

            if field.referenced_type ~= nil then
                local referenced_type = context:get(field.referenced_type)

                if referenced_type == nil then
                    local child_type_index = string.find(field.type, ":")
                    referenced_type = string.sub(
                        field.type,
                        child_type_index + 1,
                        string.len(field.type)
                    )
                    field.type = string.sub(field.type, 1, child_type_index - 1)
                end

                if field.type == "ref" then
                    add_field(schema_type, field_index, field.name, referenced_type)

                else
                    -- { map = referenced_type }
                    -- { array = referenced_type }
                    -- ...etc
                    add_field(schema_type, field_index, field.name, { [field.type] = referenced_type })
                end

            else
                add_field(schema_type, field_index, field.name, field.type)
            end
        end

    end

    -- 1st pass: define types & inheritance
    reflection.types:each(function(reflection_type)
        local parent_class = context:get(reflection_type.extends_id) or schema.Schema
        local schema_class = schema.define({}, parent_class)

        -- add type by id
        context:add(schema_class, reflection_type.id)
    end)

    -- 2nd pass: add fields to schema types
    for i = 1, reflection.types:length() do
        local reflection_type = reflection.types[i]
        local schema_class = context:get(reflection_type.id)

        local inherited_types = {}

        local parent_type = reflection_type
        while parent_type do
            table.insert(inherited_types, parent_type)
            local found_parent = false
            reflection.types:each(function (t)
                if not found_parent then
                    if t.id == parent_type.extends_id then
                        parent_type = t
                        found_parent = true
                    end
                end
            end)
            if not found_parent then
                parent_type = nil
            end
        end

        -- Reverse the table to process from parent to child
        inherited_types = reverse_table(inherited_types)

        local parent_field_index = 0

        for _, reflection_type in ipairs(inherited_types) do
            -- add fields from all inherited classes
            -- TODO: refactor this to avoid adding fields from parent classes
            add_fields(schema_class, reflection_type, parent_field_index)
            parent_field_index = parent_field_index + reflection_type.fields:length()
        end

    end

    local root_type = context:get(reflection.root_type or 0)
    local root_instance = root_type:new()

    return Decoder:new(root_instance, context)
end

return {
		decode = decode
}