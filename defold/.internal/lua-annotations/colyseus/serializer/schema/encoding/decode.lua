---@meta

local function utf8_read(bytes, offset, length)
  local bytearr = {}
  local len = offset + length
  for i = offset, len - 1 do
      local byte = bytes[i]
      local utf8byte = byte < 0 and (0xff + byte + 1) or byte
      table.insert(bytearr, string.char(utf8byte))
  end
  return table.concat(bytearr)
end

local function uint8 (bytes, it)
    local int = bytes[it.offset]
    it.offset = it.offset + 1
    return int
end

local function int8 (bytes, it)
    return bit.arshift(bit.lshift(uint8(bytes, it), 24), 24)
end

local function boolean (bytes, it)
    return uint8(bytes, it) == 1
end

local function uint16 (bytes, it)
    local n1 = bytes[it.offset]
    it.offset = it.offset + 1

    local n2 = bytes[it.offset]
    it.offset = it.offset + 1

    return bit.bor(n1, bit.lshift(n2, 8))
end

local function int16 (bytes, it)
    return bit.arshift(bit.lshift(uint16(bytes, it), 16), 16)
end

local function int32 (bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    it.offset = it.offset + 4
    if b1 < 0x80 then
        return ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
    else
        return ((((b1 - 0xFF) * 0x100 + (b2 - 0xFF)) * 0x100 + (b3 - 0xFF)) * 0x100 + (b4 - 0xFF)) - 1
    end
end

local function uint32 (bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    it.offset = it.offset + 4
    return ((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4
end

local function int64 (bytes, it)
    local b8 = bytes[it.offset]
    local b7 = bytes[it.offset + 1]
    local b6 = bytes[it.offset + 2]
    local b5 = bytes[it.offset + 3]
    local b4 = bytes[it.offset + 4]
    local b3 = bytes[it.offset + 5]
    local b2 = bytes[it.offset + 6]
    local b1 = bytes[it.offset + 7]
    it.offset = it.offset + 8
    if b1 < 0x80 then
        return ((((((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    else
        return ((((((((b1 - 0xFF) * 0x100 + (b2 - 0xFF)) * 0x100 + (b3 - 0xFF)) * 0x100 + (b4 - 0xFF)) * 0x100 + (b5 - 0xFF)) * 0x100 + (b6 - 0xFF)) * 0x100 + (b7 - 0xFF)) * 0x100 + (b8 - 0xFF)) - 1
    end
end

local function uint64 (bytes, it)
    local b8 = bytes[it.offset]
    local b7 = bytes[it.offset + 1]
    local b6 = bytes[it.offset + 2]
    local b5 = bytes[it.offset + 3]
    local b4 = bytes[it.offset + 4]
    local b3 = bytes[it.offset + 5]
    local b2 = bytes[it.offset + 6]
    local b1 = bytes[it.offset + 7]
    it.offset = it.offset + 8
    return ((((((b1 * 0x100 + b2) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
end

local function float32(bytes, it)
    local b4 = bytes[it.offset]
    local b3 = bytes[it.offset + 1]
    local b2 = bytes[it.offset + 2]
    local b1 = bytes[it.offset + 3]
    local expo = (b1 % 0x80) * 0x2 + math.floor(b2 / 0x80)
    local mant = ((b2 % 0x80) * 0x100 + b3) * 0x100 + b4
    local sign = 1
    if b1 > 0x7F then
        sign = -1
    end
    local n
    if mant == 0 and expo == 0 then
        n = sign * 0.0
    elseif expo == 0xFF then
        if mant == 0 then
            n = sign * math.huge
        else
            n = 0.0/0.0
        end
    else
        n = sign * math.ldexp(1.0 + mant / 0x800000, expo - 0x7F)
    end
    it.offset = it.offset + 4
    return n
end

local function float64(bytes, it)
    local b8 = bytes[it.offset]
    local b7 = bytes[it.offset + 1]
    local b6 = bytes[it.offset + 2]
    local b5 = bytes[it.offset + 3]
    local b4 = bytes[it.offset + 4]
    local b3 = bytes[it.offset + 5]
    local b2 = bytes[it.offset + 6]
    local b1 = bytes[it.offset + 7]

    -- TODO: detect big/little endian?

    -- local b1 = bytes[it.offset]
    -- local b2 = bytes[it.offset + 1]
    -- local b3 = bytes[it.offset + 2]
    -- local b4 = bytes[it.offset + 3]
    -- local b5 = bytes[it.offset + 4]
    -- local b6 = bytes[it.offset + 5]
    -- local b7 = bytes[it.offset + 6]
    -- local b8 = bytes[it.offset + 7]

    local expo = (b1 % 0x80) * 0x10 + math.floor(b2 / 0x10)
    local mant = ((((((b2 % 0x10) * 0x100 + b3) * 0x100 + b4) * 0x100 + b5) * 0x100 + b6) * 0x100 + b7) * 0x100 + b8
    local sign = 1
    if b1 > 0x7F then
        sign = -1
    end
    local n
    if mant == 0 and expo == 0 then
        n = sign * 0.0
    elseif expo == 0x7FF then
        if mant == 0 then
            n = sign * math.huge
        else
            n = 0.0/0.0
        end
    else
        n = sign * math.ldexp(1.0 + mant / 4503599627370496.0, expo - 0x3FF)
    end
    it.offset = it.offset + 8
    return n
end

local function _string (bytes, it)
  local prefix = bytes[it.offset]
  it.offset = it.offset + 1

  local length

  if prefix < 0xc0 then
    length = bit.band(prefix, 0x1f) -- fixstr
  elseif prefix == 0xd9 then
    length = uint8(bytes, it)
  elseif prefix == 0xda then
    length = uint16(bytes, it)
  elseif prefix == 0xdb then
    length = uint32(bytes, it)
  else
    length = 0
  end

  local value = utf8_read(bytes, it.offset, length)
  it.offset = it.offset + length

  return value
end

local function string_check (bytes, it)
  local prefix = bytes[it.offset]
  return (
    -- fixstr
    (prefix < 192 and prefix > 160) or
    -- str 8
    prefix == 217 or
    -- str 16
    prefix == 218 or
    -- str 32
    prefix == 219
  )
end

local function number (bytes, it)
  local prefix = bytes[it.offset]
  it.offset = it.offset + 1

  if (prefix < 128) then
    -- positive fixint
    return prefix

  elseif (prefix == 202) then
    -- float 32
    return float32(bytes, it)

  elseif (prefix == 203) then
    -- float 64
    return float64(bytes, it)

  elseif (prefix == 204) then
    -- uint 8
    return uint8(bytes, it)

  elseif (prefix == 205) then
    -- uint 16
    return uint16(bytes, it)

  elseif (prefix == 206) then
    -- uint 32
    return uint32(bytes, it)

  elseif (prefix == 207) then
    return uint64(bytes, it)

  elseif (prefix == 208) then
    -- int 8
    return int8(bytes, it)

  elseif (prefix == 209) then
    -- int 16
    return int16(bytes, it)

  elseif (prefix == 210) then
    -- int 32
    return int32(bytes, it)

  elseif (prefix == 211) then
    -- int 64
    return int64(bytes, it)

  elseif (prefix > 223) then
    -- negative fixint
    return (255 - prefix + 1) * -1
  else
    -- error!
    print("decode.number() ERROR! prefix => " .. prefix)
    return 0
  end
end

return {
    boolean = boolean,
    int8 = int8,
    uint8 = uint8,
    int16 = int16,
    uint16 = uint16,
    int32 = int32,
    uint32 = uint32,
    int64 = int64,
    uint64 = uint64,
    float32 = float32,
    float64 = float64,
    number = number,
    string = _string,
    string_check = string_check,
}
