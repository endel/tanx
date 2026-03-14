---@meta
local messagepack = require('colyseus.messagepack.MessagePack')

--
-- MessagePack Extensions:
-- * undefined
-- * timestamp
--
messagepack.UNDEFINED = setmetatable({}, { __tostring = function() return "undefined" end })
function messagepack.build_ext (tag, data)
    -- Extension type 0 with 1 byte of data: undefined
    if tag == 0 and #data == 1 then
        return messagepack.UNDEFINED
    end
    -- MessagePack Timestamp extension type is -1 (0xFF when unsigned)
    if tag == -1 then
        local n = #data
        if n == 4 then
            -- Timestamp 32: seconds in 32-bit unsigned int
            local b1, b2, b3, b4 = data:byte(1, 4)
            local seconds = ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
            return { seconds = seconds, nanoseconds = 0 }
        elseif n == 8 then
            -- Timestamp 64: nanoseconds in upper 30 bits, seconds in lower 34 bits
            local b1, b2, b3, b4, b5, b6, b7, b8 = data:byte(1, 8)
            local hi = ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
            local lo = ((b5 * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
            local nanoseconds = math.floor(hi / 4)  -- upper 30 bits
            local seconds = (hi % 4) * 0x100000000 + lo  -- lower 34 bits
            return { seconds = seconds, nanoseconds = nanoseconds }
        elseif n == 12 then
            -- Timestamp 96: nanoseconds in 32-bit, seconds in 64-bit signed
            local b1, b2, b3, b4 = data:byte(1, 4)
            local nanoseconds = ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
            local b5, b6, b7, b8, b9, b10, b11, b12 = data:byte(5, 12)
            local seconds
            if b5 < 0x80 then
                seconds = ((((((b5
                    * 0x100 + b6)
                    * 0x100 + b7)
                    * 0x100 + b8)
                    * 0x100 + b9)
                    * 0x100 + b10)
                    * 0x100 + b11)
                    * 0x100 + b12
            else
                seconds = ((((((((b5 - 0xFF)
                    * 0x100 + (b6 - 0xFF))
                    * 0x100 + (b7 - 0xFF))
                    * 0x100 + (b8 - 0xFF))
                    * 0x100 + (b9 - 0xFF))
                    * 0x100 + (b10 - 0xFF))
                    * 0x100 + (b11 - 0xFF))
                    * 0x100 + (b12 - 0xFF)) - 1
            end
            return { seconds = seconds, nanoseconds = nanoseconds }
        end
    end
    return nil
end

local m = {}

function m.concat(t, sep)
    sep = sep or ""
    local s = ""
    for i = 1, #t do
        if i > 1 then
            s = s .. sep
        end
        s = s .. t[i]
    end
    return s
end

function m.table_slice(tbl, first, last, step)
  local sliced = {}

  for i = first or 1, last or #tbl, step or 1 do
    sliced[#sliced+1] = tbl[i]
  end

  return sliced
end

function m.string_to_byte_array (str)
  local arr = {}
  for i = 1, #str do
    table.insert(arr, string.byte(str, i, i))
  end
  return arr
end

function m.byte_array_to_string (arr)
  local str = ''
  for i = 1, #arr do
    str = str .. string.char(arr[i])
  end
  return str
end

local char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

function m.urlencode (url)
  if url == nil then
    return
  end
  url = url:gsub("\n", "\r\n")
  url = url:gsub("([^%w ])", char_to_hex)
  url = url:gsub(" ", "+")
  return url
end

m.pprint = pprint or function(node)
    -- to make output beautiful
    local function tab(amt)
        local str = ""
        for i=1,amt do
            str = str .. "\t"
        end
        return str
    end

    local cache, stack, output = {},{},{}
    local depth = 1
    local output_str = "{\n"

    while true do
        local size = 0
        for k,v in pairs(node) do
            size = size + 1
        end

        local cur_index = 1
        for k,v in pairs(node) do
            if (cache[node] == nil) or (cur_index >= cache[node]) then

                if (string.find(output_str,"}",output_str:len())) then
                    output_str = output_str .. ",\n"
                elseif not (string.find(output_str,"\n",output_str:len())) then
                    output_str = output_str .. "\n"
                end

                -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
                table.insert(output,output_str)
                output_str = ""

                local key
                if (type(k) == "number" or type(k) == "boolean") then
                    key = "["..tostring(k).."]"
                else
                    key = "['"..tostring(k).."']"
                end

                if (type(v) == "number" or type(v) == "boolean") then
                    output_str = output_str .. tab(depth) .. key .. " = "..tostring(v)
                elseif (type(v) == "table") then
                    output_str = output_str .. tab(depth) .. key .. " = {\n"
                    table.insert(stack,node)
                    table.insert(stack,v)
                    cache[node] = cur_index+1
                    break
                else
                    output_str = output_str .. tab(depth) .. key .. " = '"..tostring(v).."'"
                end

                if (cur_index == size) then
                    output_str = output_str .. "\n" .. tab(depth-1) .. "}"
                else
                    output_str = output_str .. ","
                end
            else
                -- close the table
                if (cur_index == size) then
                    output_str = output_str .. "\n" .. tab(depth-1) .. "}"
                end
            end

            cur_index = cur_index + 1
        end

        if (size == 0) then
            output_str = output_str .. "\n" .. tab(depth-1) .. "}"
        end

        if (#stack > 0) then
            node = stack[#stack]
            stack[#stack] = nil
            depth = cache[node] == nil and depth + 1 or depth - 1
        else
            break
        end
    end

    -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
    table.insert(output,output_str)
    output_str = m.concat(output)

    print(output_str)
end

return m