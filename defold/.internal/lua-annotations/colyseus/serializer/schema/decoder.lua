---@meta
local bit = require 'colyseus.serializer.bit'
local map_schema = require 'colyseus.serializer.schema.types.map_schema'
local array_schema = require 'colyseus.serializer.schema.types.array_schema'
local decode = require 'colyseus.serializer.schema.encoding.decode'
local constants = require 'colyseus.serializer.schema.constants'
local reference_tracker = require 'colyseus.serializer.schema.reference_tracker'
local type_context = require 'colyseus.serializer.schema.type_context'
local types = require 'colyseus.serializer.schema.types'
local schema = require 'colyseus.serializer.schema.schema'

local SPEC = constants.SPEC;
local OPERATION = constants.OPERATION;

local function instance_of(subject, super)
  super = tostring(super)
  local mt = getmetatable(subject)

  while true do
    if mt == nil then return false end
    if tostring(mt) == super then return true end

    mt = getmetatable(mt)
  end
end

---@param decoder Decoder
---@param bytes number[]
---@param it table
---@param ref Schema
---@param all_changes table
schema.Schema.__decode = function(decoder, bytes, it, ref, all_changes)
  local byte = bytes[it.offset]
  it.offset = it.offset + 1

  --
  -- compressed operation:
  -- index + operation -> (byte >> 6) << 6
  --
  local operation = (bit.lshift(bit.arshift(byte, 6), 6))
  local field_index = (byte % ((operation == 0) and 255 or operation)) + 1

  local field_name = ref._fields_by_index[field_index]
  if field_name == nil then return constants.SCHEMA_MISMATCH end

  local field_type = ref._schema[field_name]
  local value, previous_value = decoder:decode_value(decoder, operation, ref, field_index, field_type, bytes, it, all_changes)

  if value ~= nil then
    ref[field_name] = value
  end

  if value ~= previous_value then
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = operation,
      field = field_name,
      value = value,
      previous_value = previous_value,
    })
  end
end

---@param decoder Decoder
---@param bytes number[]
---@param it table
---@param ref MapSchema
---@param all_changes table
map_schema.__decode = function(decoder, bytes, it, ref, all_changes)
  local operation = bytes[it.offset]
  it.offset = it.offset + 1

  if operation == OPERATION.CLEAR then
    ref:clear(all_changes, decoder.refs)
    return
  end

  local field_index = decode.number(bytes, it) + 1 -- lua indexes start in 1 instead of 0
  local field_type = ref._child_type

  local dynamic_index
  if bit.band(operation, OPERATION.ADD) == OPERATION.ADD then
    -- map schema dynamic index
    dynamic_index = (instance_of(ref, map_schema))
        and decode.string(bytes, it)
        or field_index

    ref:set_index(field_index, dynamic_index)
  else
    dynamic_index = ref:get_index(field_index)
  end

  local value, previous_value = decoder:decode_value(decoder, operation, ref, field_index, field_type, bytes, it, all_changes)

  if value ~= nil then
    ref:set_by_index(field_index, dynamic_index, value)
  end

  if value ~= previous_value then
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = operation,
      field = nil,
      dynamic_index = dynamic_index,
      value = value,
      previous_value = previous_value,
    })
  end
end

---@param decoder Decoder
---@param bytes number[]
---@param it table
---@param ref ArraySchema
---@param all_changes table
array_schema.__decode = function(decoder, bytes, it, ref, all_changes)
  local operation = bytes[it.offset]
  it.offset = it.offset + 1

  local index

  if operation == OPERATION.CLEAR then
    ref:clear(all_changes, decoder.refs)
    return

  elseif operation == OPERATION.REVERSE then
    ref:reverse()
    return

  elseif operation == OPERATION.DELETE_BY_REFID then
    local ref_id = decode.number(bytes, it) + 1
    local item = decoder.refs:get(ref_id)
    local index = ref:index_of(item)
    if index ~= -1 then
      ref:delete_by_index(index)
    end
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = OPERATION.DELETE,
      field = nil,
      dynamic_index = index,
      value = nil,
      previous_value = item,
    })
    return

  elseif operation == OPERATION.ADD_BY_REFID then
    local ref_id = decode.number(bytes, it) + 1
    local item = decoder.refs:get(ref_id)

    if item ~= nil then
      index = ref:index_of(item)
    end

    -- fallback to use last index
    if index == -1 or index == nil then
      index = ref:length() + 1
    end

  else
    index = decode.number(bytes, it) + 1
  end

  local field_type = ref._child_type

  local value, previous_value = decoder:decode_value(decoder, operation, ref, index, field_type, bytes, it, all_changes)

  if value ~= nil and value ~= previous_value then
    ref:set_by_index(index, value, operation)
  end

  if value ~= previous_value then
    table.insert(all_changes, {
      __refid = ref.__refid,
      op = operation,
      field = nil,
      dynamic_index = index,
      value = value,
      previous_value = previous_value,
    })
  end
end

local function decode_primitive_type(field_type, bytes, it)
    local func = decode[field_type]
    if func then return func(bytes, it) else return nil end
end

---@class Decoder
---@field state Schema
---@field refs reference_tracker
---@field context type_context
---@field _trigger_changes function
local Decoder = {}
Decoder.__index = Decoder

---@param state Schema
---@param context type_context|nil
---@return Decoder
function Decoder:new(state, context)
  local instance = {
    state = state,
    context = context or type_context:new(),
		refs = reference_tracker:new(),
    _trigger_changes = function() end
	}
  setmetatable(instance, Decoder)

  -- set root state refid
  state.__refid = 1
  instance.refs:add(state.__refid, state, true)

	return instance
end

function Decoder:decode(bytes, it)
    if it == nil then it = { offset = 1 } end

    local ref_id = 1
    local ref = self.state

    local all_changes = {}

    local total_bytes = #bytes
    while it.offset <= total_bytes do repeat
        if bytes[it.offset] == SPEC.SWITCH_TO_STRUCTURE then
            it.offset = it.offset + 1

            ref_id = decode.number(bytes, it) + 1
            local next_ref = self.refs:get(ref_id)

            --
            -- Trying to access a reference that haven't been decoded yet.
            --
            if next_ref == nil then error('"ref_id" not found: ' .. ref_id) end

            if ref['__on_decode_end'] ~= nil then ref:__on_decode_end() end

            ref = next_ref
            break -- LUA "continue" workaround.
        end

        if ref.__decode(self, bytes, it, ref, all_changes) == constants.SCHEMA_MISMATCH then
          print("@colyseus/schema: definition mismatch (offset: " .. it.offset .. ", total: " .. total_bytes .. ")");

          --
          -- keep skipping next bytes until reaches a known structure
          -- by local decoder.
          --
          local next_iterator = { offset = it.offset }
          while it.offset <= total_bytes do
              if bytes[it.offset] == SPEC.SWITCH_TO_STRUCTURE then
                  next_iterator.offset = it.offset + 1;

                  if self.refs:has(decode.number(bytes, next_iterator)) then
                      break
                  end
              end

              it.offset = it.offset + 1
          end

          -- LUA "continue" workaround.
          break
        end

    until true end

    if ref['__on_decode_end'] ~= nil then ref:__on_decode_end() end

    self:_trigger_changes(all_changes, self.refs)

    self.refs:garbage_collection()

    return self
end

---@return any, any
function Decoder:decode_value(decoder, operation, ref, field_index, field_type, bytes, it, all_changes)
  local value = nil
  local previous_value = ref:get_by_index(field_index)

  --
  -- DELETE operations
  --
  if bit.band(operation, OPERATION.DELETE) == OPERATION.DELETE then
    -- Flag `ref_id` for garbage collection.
    if type(previous_value) == "table" and previous_value.__refid ~= nil then
      decoder.refs:remove(previous_value.__refid)
    end

    if operation ~= OPERATION.DELETE_AND_ADD then
      ref:delete_by_index(field_index)
    end

    value = nil
  end

  if operation == OPERATION.DELETE then
    --
    -- Don't do anything...
    --
  elseif field_type['_schema'] ~= nil then
    --
    -- Direct schema reference ("ref")
    --
    local __refid = decode.number(bytes, it) + 1
    value = decoder.refs:get(__refid)

    if bit.band(operation, OPERATION.ADD) == OPERATION.ADD then
      local concrete_child_type = decoder:get_schema_type(bytes, it, field_type);
      if value == nil then
        value = concrete_child_type:new()
        value.__refid = __refid
      end

      decoder.refs:add(__refid, value, (
        value ~= previous_value or
        (operation == OPERATION.DELETE_AND_ADD and value == previous_value)
      ));
    end

  elseif type(field_type) == "string" then
    --
    -- primitive value!
    --
    value = decode_primitive_type(field_type, bytes, it)
  else
    local collection_type_id = next(field_type)

    local __refid = decode.number(bytes, it) + 1
    value = decoder.refs:get(__refid)

    local value_ref
    if decoder.refs:has(__refid) then
      value_ref = previous_value or decoder.refs:get(__refid)
    else
      value_ref = types.get_type(collection_type_id):new()     -- get 'map_schema'/'array_schema' constructor
    end

    value = value_ref:clone()
    value.__refid = __refid
    value._child_type = field_type[collection_type_id]

    if previous_value ~= nil then
      if previous_value.__refid ~= nil and previous_value.__refid ~= __refid then

        --
        -- Trigger on_remove() if structure has been replaced.
        --
        previous_value:each(function(val, key)
          if type(val) == "table" and val.__refid ~= nil then
            decoder.refs:remove(val.__refid)
          end

          table.insert(all_changes, {
            __refid = previous_value.__refid,
            op = OPERATION.DELETE,
            field = key,
            value = nil,
            previous_value = val,
          })
        end)
      end
    end

    decoder.refs:add(__refid, value, (
      value_ref ~= previous_value or
      (operation == OPERATION.DELETE_AND_ADD and value_ref == previous_value)
    ))
  end

  return value, previous_value
end

function Decoder:get_schema_type(bytes, it, default_type)
  local schema_type = default_type;

  if (bytes[it.offset] == SPEC.TYPE_ID) then
    it.offset = it.offset + 1

    local type_id = decode.number(bytes, it)
    schema_type = self.context:get(type_id)
  end

  return schema_type;
end

function Decoder:create_instance_type(bytes, it, typeref)
    if bytes[it.offset] == SPEC.TYPE_ID then
        it.offset = it.offset + 1
        local another_type = self.context:get(decode.uint8(bytes, it))
        return another_type:new()
    else
        return typeref:new()
    end
end

return Decoder