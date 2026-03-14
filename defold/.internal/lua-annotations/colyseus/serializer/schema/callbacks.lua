---@meta
local bit = require 'colyseus.serializer.bit'
local constants = require 'colyseus.serializer.schema.constants'
local OPERATION = constants.OPERATION;

---@class Callbacks
---@field private decoder Decoder
---@field private is_triggering boolean
Callbacks = {}
Callbacks.__index = Callbacks

---@package
---@return Callbacks
function Callbacks:new(decoder)
	local instance = {
    decoder = decoder,
    is_triggering = false,
  }
  setmetatable(instance, Callbacks)
  -- assign decoder's _trigger_changes to this instance.
  -- this is required to preserve "self" context when calling Callbacks:_trigger_changes.
  decoder._trigger_changes = function (self, changes, refs)
    instance:_trigger_changes(changes, refs)
  end
  return instance
end

---@param instance_or_field Schema|string
---@param callback_or_field string|fun(value: any, key: any)
---@param callback nil|fun(value: any, key: any)
function Callbacks:on_add(instance_or_field, callback_or_field, immediate_or_callback, immediate)
  local instance = self.decoder.state
  local field_name = instance_or_field
  local callback = callback_or_field
  if type(instance_or_field) ~= "string" then
    instance = instance_or_field
    field_name = callback_or_field
    callback = immediate_or_callback
  else
    immediate = immediate_or_callback
  end
  immediate = ((immediate == nil and true) or immediate)
  return self:add_callback_or_wait_collection_available(instance, field_name, OPERATION.ADD, callback, immediate)
end

---@param instance Schema
---@param callback fun()
function Callbacks:on_change(instance, callback)
  return self:add_callback(instance.__refid, OPERATION.REPLACE, callback)
end

---@param instance_or_field Schema|string
---@param callback_or_field string|fun(value: any, key: any)
---@param callback nil|fun(value: any, key: any)
function Callbacks:on_remove(instance_or_field, callback_or_field, callback)
  local instance = self.decoder.state
  local field_name = instance_or_field
  if type(instance_or_field) ~= "string" then
    instance = instance_or_field
    field_name = callback_or_field
  else
    callback = callback_or_field
  end
  return self:add_callback_or_wait_collection_available(instance, field_name, OPERATION.DELETE, callback)
end

---@param instance_or_field Schema|string
---@param callback_or_field string|fun(value: any, previous_value: any)
---@param immediate_or_callback nil|fun(value: any, previous_value: any)
---@param immediate boolean|nil
function Callbacks:listen(instance_or_field, callback_or_field, immediate_or_callback, immediate)
  local instance = self.decoder.state
  local field_name = instance_or_field
  local callback = callback_or_field

  -- instance provided as first argument...
  if type(instance_or_field) ~= "string" then
    instance = instance_or_field
    field_name = callback_or_field
    callback = immediate_or_callback
  else
    immediate = immediate_or_callback
  end

  -- immediately trigger callback if field is already set
  immediate = ((immediate == nil and true) or immediate) and self.is_triggering == false
  if immediate == true and instance[field_name] ~= nil then
    callback(instance[field_name], nil)
  end

  return self:add_callback(instance.__refid, field_name, callback)
end

---@package
---@param changes table
---@param refs reference_tracker
function Callbacks:_trigger_changes(changes, refs)
  local unique_ref_ids = {}

  for _, change in pairs(changes) do
    repeat
      local ref_id = change.__refid
      local ref = refs:get(ref_id)
      local is_schema = (ref['_schema'] ~= nil)
      local callbacks = refs.callbacks[ref_id]

      -- "continue" if no callbacks are set
      if callbacks == nil then break end -- "continue"

      --
      -- trigger on_remove() on child structure.
      --
      if (
        bit.band(change.op, OPERATION.DELETE) == OPERATION.DELETE and
        type(change.previous_value) == "table" and
        change.previous_value['_schema'] ~= nil
      ) then
        local previous_value_callbacks = refs.callbacks[change.previous_value.__refid]

        if previous_value_callbacks ~= nil and previous_value_callbacks[OPERATION.DELETE] ~= nil then
          for _, callback in pairs(previous_value_callbacks[OPERATION.DELETE]) do
            callback()
          end
        end
      end

      if is_schema then
        -- is schema

        -- ensure on_change() is triggered only once per schema instance.
        if unique_ref_ids[ref_id] == nil then
          local replace_callbacks = callbacks[OPERATION.REPLACE]
          if replace_callbacks ~= nil then
            for _, callback in pairs(replace_callbacks) do
              callback(changes)
            end
          end
        end

        -- trigger :listen() callbacks
        local field_callbacks = callbacks[change.field]
        if field_callbacks ~= nil then
          self.is_triggering = true
          for _, callback in pairs(field_callbacks) do
            callback(change.value, change.previous_value)
          end
          self.is_triggering = false
        end

      else
        -- is a collection/custom type

        if bit.band(change.op, OPERATION.DELETE) == OPERATION.DELETE then
          local delete_callbacks = callbacks[OPERATION.DELETE]
          if change.previous_value ~= nil and delete_callbacks ~= nil then
            -- triger "on_remove"
            for _, callback in pairs(delete_callbacks) do
              callback(change.previous_value, change.dynamic_index or change.field)
            end
          end

          if bit.band(change.op, OPERATION.ADD) == OPERATION.ADD then
            -- Handle DELETE_AND_ADD operations
            local add_callbacks = callbacks[OPERATION.ADD]
            if add_callbacks ~= nil then
              self.is_triggering = true
              for _, callback in pairs(add_callbacks) do
                callback(change.value, change.dynamic_index or change.field)
              end
              self.is_triggering = false
            end
          end

        elseif bit.band(change.op, OPERATION.ADD) == OPERATION.ADD and change.previous_value ~= change.value then
          -- trigger "on_add"
          local add_callbacks = callbacks[OPERATION.ADD]
          if add_callbacks ~= nil then
            self.is_triggering = true
            for _, callback in pairs(add_callbacks) do
              callback(change.value, change.dynamic_index)
            end
            self.is_triggering = false
          end

        end

        -- trigger "on_change"
        if change.value ~= change.previous_value then
          local replace_callbacks = callbacks[OPERATION.REPLACE]
          if replace_callbacks ~= nil then
            for _, callback in pairs(replace_callbacks) do
              callback(change.value, change.dynamic_index or change.field)
            end
          end
        end

      end

      unique_ref_ids[ref_id] = true

      break
    until true
  end
end

---@package
function Callbacks:add_callback_or_wait_collection_available(instance, field_name, operation, callback, immediate)
  local _self = self
  local remove_handler = function() end
  local remove_callback = function() remove_handler() end
  if instance[field_name] == nil then
    remove_handler = _self:listen(instance, field_name, function(collection, _)
      remove_handler = _self:add_callback(collection.__refid, operation, callback)
    end)
    return remove_callback
  else
    -- immediately trigger callback for each item in the collection
    if operation == OPERATION.ADD and immediate and self.is_triggering == false then
      instance[field_name]:each(function(value, key)
        callback(value, key)
      end)
    end
    return _self:add_callback(instance[field_name].__refid, operation, callback)
  end
end

---@param __refid number
---@param operation_or_field string|number
---@param callback fun(value: any, key: any)
---@package
function Callbacks:add_callback(__refid, operation_or_field, callback)
  local handlers = self.decoder.refs.callbacks[__refid]

  if handlers == nil then
    handlers = {}
    self.decoder.refs.callbacks[__refid] = handlers
  end

  if handlers[operation_or_field] == nil then
    handlers[operation_or_field] = {}
  end

  table.insert(handlers[operation_or_field], callback)

  -- return a callback that removes the callback when called
  return function()
    for index, value in pairs(handlers[operation_or_field]) do
      if value == callback then
        table.remove(handlers[operation_or_field], index)
        break
      end
    end
  end
end

---@param room_or_decoder Room|Decoder
---@return Callbacks
return function(room_or_decoder)
  if room_or_decoder.room_id ~= nil then
    return Callbacks:new(room_or_decoder.serializer.decoder)

  elseif room_or_decoder._trigger_changes ~= nil then
    return Callbacks:new(room_or_decoder)
  end
end
