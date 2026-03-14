---@meta
local bit = require 'colyseus.serializer.bit'

local function uint8 (bytes, num)
  table.insert(bytes, bit.band(num, 255))
end

local function uint16(bytes, value)
  table.insert(bytes, bit.band(value, 255))
  table.insert(bytes, bit.band(bit.arshift(value, 8), 255))
end

local function uint32(bytes, value)
  local b4 = bit.arshift(value, 24)
  local b3 = bit.arshift(value, 16)
  local b2 = bit.arshift(value, 8)
  local b1 = value

  table.insert(bytes, bit.band(b1, 255))
  table.insert(bytes, bit.band(b2, 255))
  table.insert(bytes, bit.band(b3, 255))
  table.insert(bytes, bit.band(b4, 255))
end

local function utf8_length(str)
  local c = 0
  local length = 0

  local i = 1
  local strlen = #str
  while i <= strlen do
    c = str:byte(i)

    if c < 0x80 then
      length = length + 1

    elseif c < 0x800 then
      length = length + 2

    elseif c < 0xd800 or c >= 0xe000 then
      length = length + 3

    else
      i = i + 1
      length = length + 4
    end

    i = i + 1
  end

  return length
end

-- START ENCODE --
local function utf8_write(bytes, offset, str)
  local len = #str
  local c = 0
  local i = 1

  while i <= len do
    c = str:byte(i)

    if c < 0x80 then
      offset = offset + 1
      bytes[offset] = c

    elseif c < 0x800 then
      offset = offset + 1
      bytes[offset] = bit.bor(0xc0, bit.arshift(c, 6))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(c, 0x3f))

    elseif c < 0xd800 or c >= 0xe000 then
      offset = offset + 1
      bytes[offset] = bit.bor(0xe0, bit.arshift(c, 12))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(bit.arshift(c, 6), 0x3f))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(c, 0x3f))

    else
      i = i + 1
      c = 0x10000 + bit.bor(bit.lshift(bit.band(c, 0x3ff), 10), bit.band(str:byte(i), 0x3ff))
      -- c = 0x10000 + (((c & 0x3ff) << 10) | (str.charCodeAt(i) & 0x3ff))

      offset = offset + 1
      bytes[offset] = bit.bor(0xf0, bit.arshift(c, 18))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(bit.arshift(c, 12), 0x3f))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(bit.arshift(c, 6), 0x3f))

      offset = offset + 1
      bytes[offset] = bit.bor(0x80, bit.band(c, 0x3f))
    end

    i = i + 1
  end
end

local function encode_string(bytes, value)
  -- encode `null` strings as empty.
  if not value then value = "" end

  local length = utf8_length(value)
  local size = 0

  -- fixstr
  if length < 0x20 then
    table.insert(bytes, bit.bor(length, 0xa0))
    size = 1

  -- str 8
  elseif length < 0x100 then
    table.insert(bytes, 0xd9)
    uint8(bytes, length)
    size = 2

  -- str 16
  elseif length < 0x10000 then
    table.insert(bytes, 0xda)
    uint16(bytes, length)
    size = 3

  -- str 32
  elseif length < 0x100000000 then
    table.insert(bytes, 0xdb)
    uint32(bytes, length)
    size = 5

  else
    error('String too long')
  end

  utf8_write(bytes, #bytes, value)

  return size + length
end

local function encode_number(bytes, num)
  table.insert(bytes, num)
end

return {
  string = encode_string,
  number = encode_number
}
