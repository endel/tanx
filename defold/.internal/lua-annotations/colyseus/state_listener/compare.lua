---@meta
local function concat(arr, value)
  local new_arr = {}

  for key, value in pairs(arr) do
    new_arr[key] = value
  end

  table.insert(new_arr, value)

  return new_arr
end

local function is_array(t)
  local i = 0
  for _ in pairs(t) do
    i = i + 1
    if t[i] == nil then return false end
  end
  return true
end

local function table_keys (obj)
  local keys = {}

  for k, v in pairs(obj) do
    table.insert(keys, k)
  end

  return keys
end

-- Dirty check if obj is different from mirror, generate patches and update mirror
local function generate(mirror, obj, patches, path)
  local new_keys = table_keys(obj)
  local old_keys = table_keys(mirror)
  local changed = false
  local deleted = false

  local t = #old_keys
  while t > 0 do
    local key = old_keys[t]
    local old_val = mirror[key]

    if obj[key] ~= nil and not (obj[key] == nil and old_val ~= nil and not is_array(obj)) then
        local new_val = obj[key]

        if type(old_val) == "table" and old_val ~= nil and type(new_val) == "table" and new_val ~= nil then
          generate(old_val, new_val, patches, concat(path, key))

        elseif old_val ~= new_val then
          changed = true

          table.insert(patches, {
            operation = "replace",
            path = concat(path, key),
            value = new_val,
            previous_value = old_val
          })
        end

    else
      table.insert(patches, {
        operation = "remove",
        path = concat(path, key)
      })
      deleted = true -- property has been deleted
    end

    t = t - 1
  end

  if not deleted and #new_keys == #old_keys then
      return
  end

  t = #new_keys
  while t > 0 do
    local key = new_keys[t]

    if mirror[key] == nil and obj[key] ~= nil then
      local new_val = obj[key]
      local add_path = concat(path, key)

      -- compare deeper additions
      if type(new_val) == "table" and new_val ~= nil then
          generate({}, new_val, patches, add_path)
      end

      table.insert(patches, {
        operation = "add",
        path = add_path,
        value = new_val
      })
    end

    t = t - 1
  end
end

local function compare(tree1, tree2)
  local patches = {}
  generate(tree1, tree2, patches, {})
  return patches;
end

return compare
