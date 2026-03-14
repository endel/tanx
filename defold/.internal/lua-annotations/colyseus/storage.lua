---@meta
local storage = {}
local data = {}

local storage_file_path = sys.get_save_file("colyseus", "storage")

function storage.get_item (key)
  data = sys.load(storage_file_path)
  return data[key] or ""
end

function storage.set_item (key, value)
  data[key] = value

  if not sys.save(storage_file_path, data) then
    print("colyseus.client: storage.set_item couldn't set '" .. key .. "' locally.")
  end
end

return storage