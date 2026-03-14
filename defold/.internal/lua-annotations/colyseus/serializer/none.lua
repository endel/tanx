---@meta
local none = {}
none.__index = none

function none.new ()
  local instance = {}
  setmetatable(instance, none)
  return instance
end

function none:get_state() end
function none:set_state(encoded_state, it) end
function none:patch(binary_patch, it) end
function none:teardown() end

return none
