---@meta

---@class reference_tracker
---@field refs table
---@field ref_counts table
---@field deleted_refs table
---@field callbacks table
local reference_tracker = {}
reference_tracker.__index = reference_tracker

function reference_tracker:new()
    local instance = {
      refs = {},
      ref_counts = {},
      deleted_refs = {},
      callbacks = {},
    }
    setmetatable(instance, reference_tracker)
    return instance
end

function reference_tracker:has(ref_id)
  return self.refs[ref_id] ~= nil
end

function reference_tracker:get(ref_id)
  return self.refs[ref_id]
end

function reference_tracker:add(ref_id, ref, increment_count)
  self.refs[ref_id] = ref

  if increment_count == true then
    self.ref_counts[ref_id] = (self.ref_counts[ref_id] or 0) + 1
  end

  if self.deleted_refs[ref_id] ~= nil then
    self.deleted_refs[ref_id] = nil
  end
end

function reference_tracker:remove(ref_id)
  local ref_count = self.ref_counts[ref_id]

  -- skip if ref_id is not being tracked
  if ref_count == nil then
    print("trying to remove ref_id that doesn't exist: " .. tostring(ref_id))
    return false
  end

  if ref_count == 0 then
    print("trying to remove ref_id with 0 ref_count: " .. tostring(ref_id))
    return false
  end

  self.ref_counts[ref_id] = ref_count - 1;

  if self.ref_counts[ref_id] <= 0 then
    self.deleted_refs[ref_id] = true
    return true
  end

  return false
end

function reference_tracker:count()
  -- count refs
  local count = 0
  for _, _ in pairs(self.refs) do
    count = count + 1
  end
  return count
end

function reference_tracker:garbage_collection()
  local deleted_refs = {}

  for ref_id, _ in pairs(self.deleted_refs) do
    table.insert(deleted_refs, ref_id)
  end

  for _, ref_id in ipairs(deleted_refs) do
    if self.ref_counts[ref_id] <= 0 then
      local ref = self:get(ref_id)

      --
      -- Ensure child schema instances have their references removed as well.
      --
      if ref._schema ~= nil then
        for field, field_type in pairs(ref._schema) do
          if type(field_type) ~= "string" and ref[field] ~= nil then
            local child_ref_id = ref[field].__refid
            if child_ref_id ~= nil and self.deleted_refs[child_ref_id] == nil and self:remove(child_ref_id) then
              table.insert(deleted_refs, child_ref_id)
            end
          end
        end

      elseif ref._child_type['new'] ~= nil then
        ref:each(function(value)
          if type(value) == "table" and value.__refid ~= nil then
            local child_ref_id = value.__refid
            if self.deleted_refs[child_ref_id] == nil and self:remove(child_ref_id) then
              table.insert(deleted_refs, child_ref_id)
            end
          end
        end)
      end

      self.refs[ref_id] = nil
      self.ref_counts[ref_id] = nil
      self.callbacks[ref_id] = nil
    end
  end

  -- clear deleted refs
  self.deleted_refs = {}
end

function reference_tracker:clear()
  self.refs = {};
  self.ref_counts = {};
  self.callbacks = {};
  self.deleted_refs = {};
end

return reference_tracker
