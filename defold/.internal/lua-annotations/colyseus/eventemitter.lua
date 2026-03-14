---@meta
--
-- Based on https://github.com/wscherphof/lua-events/
--

---@class EventEmitter
local EventEmitter = {}

function table_find(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

---@param object table|nil
---@return EventEmitterInstance|table
function EventEmitter:new(object)

  ---@class EventEmitterInstance
  object = object or {}
  object._on = {}
  object._once = {}

  ---@function on
  ---@param event string
  ---@param listener function
  ---@return function
  function object:on (event, listener)
    self._on[event] = self._on[event] or {}
    table.insert(self._on[event], listener)
    return listener
  end

  ---@function once
  ---@param event string
  ---@param listener function
  ---@return function
  function object:once (event, listener)
    self._once[event] = listener
    return self:on(event, listener)
  end

  ---@function off
  ---@param event nil|string
  ---@param listener nil|function
  function object:off (event, listener)
    if event then
      -- clear from "once"
      self._once[event] = nil
      if not listener then
        table.remove(self._on[event])
      else
        table.remove(self._on[event], table_find(self._on[event], listener))
      end
    else
      for event, listener in pairs(self._on) do
        self:off(event)
      end
    end
  end

  ---@function listeners
  ---@param event string
  function object:listeners (event)
    return self._on[event] or {}
  end

  function object:emit (event, ...)
    -- copy list before iterating over it
    -- (make sure all previously registered callbacks are called, even if some are removed in-between)
    local listeners = {}
    for i, listener in ipairs(self:listeners(event)) do
      listeners[i] = listener
    end

    for i, listener in ipairs(listeners) do
      if "function" == type(listener) then
        listener(...)

        -- clear from "once"
        if self._once[event] == listener then
          self:off(event, listener)
        end
      end
    end
  end

  return object
end

return EventEmitter
