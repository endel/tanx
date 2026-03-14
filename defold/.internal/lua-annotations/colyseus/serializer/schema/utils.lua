---@meta
local consts = require('colyseus.serializer.schema.constants')
local OPERATION = consts.OPERATION

local exports = {}

exports.remove_child_refs = function(collection, changes, refs)
  local need_remove_ref = (collection._child_type['_schema'] ~= nil);

  collection:each(function(item, key)
      table.insert(changes, {
          __refid = collection.__refid,
          op = OPERATION.DELETE,
          dynamic_index = key,
          -- field = key,
          value = nil,
          previous_value = item
      })

      if need_remove_ref then
          refs:remove(item.__refid)
      end
  end)
end


function table.clone(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = orig_value
        end
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function table.keys(orig)
    local keyset = {}
    for k,v in pairs(orig) do
      keyset[#keyset + 1] = k
    end
    return keyset
end

return exports