---@meta
local compare = require('colyseus.state_listener.compare')
local EventEmitter = require('colyseus.eventemitter')

local function split(str, delimiter)
  local result = { }
  local from  = 1
  local delim_from, delim_to = string.find( str, delimiter, from  )
  while delim_from do
    table.insert( result, string.sub( str, from , delim_from-1 ) )
    from  = delim_to + 1
    delim_from, delim_to = string.find( str, delimiter, from  )
  end
  table.insert( result, string.sub( str, from  ) )
  return result
end

local function map(array, func)
  local new_array = {}
  for i, v in ipairs(array) do
    new_array[i] = func(v)
  end
  return new_array
end

StateContainer = {}
local StateContainer_mt = { __index = StateContainer }

function StateContainer.new (state)
  local instance = EventEmitter:new({
    defaultListener = nil,
  })
  setmetatable(instance, StateContainer_mt)
  instance:init(state)
  return instance
end

function StateContainer:init (state)
  self.state = state or {}

  self.matcherPlaceholders = {}
  self.matcherPlaceholders[":id"] = "^([%a%d-_]+)$"
  self.matcherPlaceholders[":number"] = "^(%d+)$"
  self.matcherPlaceholders[":string"] = "^(%a+)$"
  self.matcherPlaceholders[":axis"] = "^([xyz])$"
  self.matcherPlaceholders[":*"] = "^(.*)$"

  self:reset()
end

function StateContainer:set (new_state)
  local patches = compare(self.state, new_state)
  self.state = new_state
  self:check_patches(patches, self._listeners, self.defaultListener)
  return patches
end

function StateContainer:register_placeholder (placeholder, matcher)
  self.matcherPlaceholders[placeholder] = matcher
end

function StateContainer:listen (segments, callback, immediate)
  local rules

  if type(segments) == "function" then
    rules = {}
    callback = segments

  else
    rules = split(segments, "/")
  end

  local listener = {
    callback = callback,
    rawRules = rules,
    rules = map(rules, function(segment)
      if type(segment) == "string" then
        -- replace placeholder matchers
        return (string.find(segment, ":") == 1)
          and (self.matcherPlaceholders[segment] or self.matcherPlaceholders[":*"])
          or "^" .. segment .. "$"
      else
        return segment
      end
    end)
  }

  if (#rules == 0) then
    self.defaultListener = listener

  else
    table.insert(self._listeners, listener)
  end

  if immediate then
    self:check_patches(compare({}, self.state), { listener })
  end

  return listener
end

function StateContainer:remove_listener (listener)
  for k, l in ipairs(self._listeners) do
    if l == listener then
      table.remove(self._listeners, k)
    end
  end
end

function StateContainer:remove_all_listeners ()
  self:reset()
end

function StateContainer:check_patches (patches, listeners, default_listener)
  for i = #patches, 1, -1 do
    local matched = false

    local j = 1
    local total = #listeners
    while j <= total do
      local listener = listeners[j]
      local path_variables = listener and self:get_path_variables(patches[i], listener)

      if path_variables then
        listener.callback({
          path = path_variables,
          raw_path = patches[i].path,
          operation = patches[i].operation,
          value = patches[i].value
        })
        matched = true
      end

      j = j + 1
    end

    -- check for fallback listener
    if (not matched and default_listener) then
      default_listener["callback"](patches[i])
    end

  end
end

function StateContainer:get_path_variables (patch, listener)
  -- skip if rules count differ from patch

  if #patch.path ~= #listener.rules then
    return false
  end

  local path = {}

  -- for (var i = 0, len = listener.rules.length; i < len; i++) {
  local i = 1
  local len = #listener.rules
  while i <= len do
    local match = string.match(patch.path[i], listener.rules[i])

    if match == nil then
      return false

    elseif (string.sub(listener.rawRules[i], 1, 1) == ":") then
      path[ string.sub(listener.rawRules[i], 2) ] = match
    end

    i = i + 1
  end

  return path
end

function StateContainer:reset ()
  self._listeners = {}
end

return StateContainer