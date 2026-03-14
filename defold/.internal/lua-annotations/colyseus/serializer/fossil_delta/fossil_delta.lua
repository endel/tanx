---@meta
-- Fossil SCM delta compression algorithm
-- ======================================
--
-- Format:
-- http://www.fossil-scm.org/index.html/doc/tip/www/delta_format.wiki
--
-- Algorithm:
-- http://www.fossil-scm.org/index.html/doc/tip/www/delta_encoder_algorithm.wiki
--
-- Original implementation:
-- http://www.fossil-scm.org/index.html/artifact/d1b0598adcd650b3551f63b17dfc864e73775c3d
--
-- LICENSE
-- -------
--
-- Copyright 2018 Endel Dreyer (LUA port)
-- Copyright 2014 Dmitry Chestnykh (JavaScript port)
-- Copyright 2007 D. Richard Hipp  (original C version)
-- All rights reserved.
--
-- Redistribution and use in source and binary forms, with or
-- without modification, are permitted provided that the
-- following conditions are met:
--
--   1. Redistributions of source code must retain the above
--      copyright notice, this list of conditions and the
--      following disclaimer.
--
--   2. Redistributions in binary form must reproduce the above
--      copyright notice, this list of conditions and the
--      following disclaimer in the documentation and/or other
--      materials provided with the distribution.
--
-- THIS SOFTWARE IS PROVIDED BY THE AUTHORS ``AS IS'' AND ANY EXPRESS
-- OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
-- WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
-- ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE
-- LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
-- CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
-- SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
-- BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
-- WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
-- OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
-- EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
--
-- The views and conclusions contained in the software and documentation
-- are those of the authors and contributors and should not be interpreted
-- as representing official policies, either expressed or implied, of anybody
-- else.

-- local bit = bit or require"bit"
local bit = bit

local fossil_delta = {}

-- TODO: this shoulnd't be necessary.
-- return value >>> 0
function bit_rshift(value, n)
  local r = bit.rshift(value, n)

  if r < 0 and n == 0 then
    return bit.rshift(r, 1) * 2
  else
    return r
  end
end

-- Hash window width in bytes. Must be a power of two.
local NHASH = 16

RollingHash = {}
RollingHash.__index = RollingHash
function RollingHash.new ()
  local instance = {
    a = 0, -- hash     (16-bit unsigned)
    b = 0, -- values   (16-bit unsigned)
    i = 0, -- start of the hash window (16-bit unsigned)
    -- this.z = new Array(NHASH);
    z = {} -- the values that have been hashed
  }
  setmetatable(instance, RollingHash)
  return instance
end

-- Initialize the rolling hash using the first NHASH bytes of
-- z at the given position.
function RollingHash:init (z, pos)
  local a = 0
  local b = 0
  local i = 0
  local x

  -- for(i = 0; i < NHASH; i++){
  while i < NHASH do
    x = z[pos + i + 1]
    a = bit.band(a + x, 0xffff)
    b = bit.band(b + (NHASH - i) * x, 0xffff)
    self.z[i] = x

    i = i + 1
  end

  self.a = bit.band(a, 0xffff)
  self.b = bit.band(b, 0xffff)
  self.i = 0
end

-- Advance the rolling hash by a single byte "c".
function RollingHash:next (c)
  local old = self.z[self.i]
  self.z[self.i] = c
  self.i = bit.band(self.i+1, NHASH-1)
  self.a = bit.band(self.a - old + c, 0xffff)
  self.b = bit.band(self.b - NHASH*old + self.a, 0xffff)
end

-- Return a 32-bit hash value.
function RollingHash:value()
  return bit_rshift(bit.bor(bit.band(self.a, 0xffff), bit.lshift(bit.band(self.b, 0xffff), 16)), 0)
end

-- "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz~"
local z_digits = {
  [0] = 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 65, 66, 67, 68, 69, 70, 71, 72, 73,
  74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 95, 97, 98,
  99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114,
  115, 116, 117, 118, 119, 120, 121, 122, 126
}

local z_value = {
  [0] = -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
  -1, -1, -1, -1, -1, -1, -1, -1,   -1, -1, -1, -1, -1, -1, -1, -1,
   0,  1,  2,  3,  4,  5,  6,  7,    8,  9, -1, -1, -1, -1, -1, -1,
  -1, 10, 11, 12, 13, 14, 15, 16,   17, 18, 19, 20, 21, 22, 23, 24,
  25, 26, 27, 28, 29, 30, 31, 32,   33, 34, 35, -1, -1, -1, -1, 36,
  -1, 37, 38, 39, 40, 41, 42, 43,   44, 45, 46, 47, 48, 49, 50, 51,
  52, 53, 54, 55, 56, 57, 58, 59,   60, 61, 62, -1, -1, -1, 63, -1
}

-- Reader reads bytes, chars, ints from array.
Reader = {}
Reader.__index = Reader
function Reader.new (array)
  local instance = {
    a = array, -- source array
    pos = 0,   -- current position in array
  }
  setmetatable(instance, Reader)
  return instance
end

function Reader:have_bytes ()
  return self.pos < #self.a
end

function Reader:get_byte ()
  local b = self.a[self.pos + 1]
  self.pos = self.pos + 1

  if self.pos > #self.a then
    error('out of bounds')
  end

  return b
end

function Reader:get_char()
  return string.char(self:get_byte())
end

-- Read base64-encoded unsigned integer.
function Reader:get_int()
  local v = 0
  local c

  while self:have_bytes() do
     c = z_value[ bit.band(0x7f, self:get_byte()) ]
     if c < 0 then break end
     v = bit.lshift(v, 6) + c
  end

  self.pos = self.pos - 1

  return bit_rshift(v, 0)
end


-- Write writes an array.
Writer = {}
Writer.__index = Writer
function Writer.new (array)
  local instance = {
    a = {}
  }
  setmetatable(instance, Writer)
  return instance
end

function Writer:to_array()
  return self.a
end

function Writer:put_byte(b)
  table.insert(self.a, bit.band(b, 0xff))
end

-- Write an ASCII character (s is a one-char string).
function Writer:put_char(s)
  self:put_byte(string.byte(s, 1))
end

-- Write a base64 unsigned integer.
function Writer:put_int(v)
  local i
  local j
  local z_buf = {}

  if (v == 0) then
    self:put_char('0')
    return
  end

  i = 0
  -- for (i = 0; v > 0; i++, v >>>= 6)
  while v > 0 do
    z_buf[i] = z_digits[bit.band(v, 0x3f)]
    i = i + 1
    v = bit.rshift(v, 6)
  end

  -- for (j = i-1; j >= 0; j--)
  --   self:put_byte(z_buf[j]);
  j = i-1
  while j >= 0 do
    self:put_byte(z_buf[j])
    j = j - 1
  end
end

-- Copy from array at start to end.
function Writer:put_array(a, start, _end)
  local i = start
  while i < _end do
    table.insert(self.a, a[i])
    i = i + 1
  end
end

-- Return the number digits in the base64 representation of a positive integer.
local function digit_count(v)
  local i = 1
  local x = 64

  while v >= x do
    i = i + 1
    x = bit.lshift(x, 6)
  end

  return i
end

-- Return a 32-bit checksum of the array.
function checksum(arr)
  local sum0 = 0
  local sum1 = 0
  local sum2 = 0
  local sum3 = 0
  local z = 0

  local N = #arr

  -- TODO measure if self unrolling is helpful.
  while (N >= 16) do
    sum0 = bit.bor(sum0 + arr[z + 1], 0)
    sum1 = bit.bor(sum1 + arr[z + 2], 0)
    sum2 = bit.bor(sum2 + arr[z + 3], 0)
    sum3 = bit.bor(sum3 + arr[z + 4], 0)

    sum0 = bit.bor(sum0 + arr[z + 5], 0)
    sum1 = bit.bor(sum1 + arr[z + 6], 0)
    sum2 = bit.bor(sum2 + arr[z + 7], 0)
    sum3 = bit.bor(sum3 + arr[z + 8], 0)

    sum0 = bit.bor(sum0 + arr[z + 9], 0)
    sum1 = bit.bor(sum1 + arr[z + 10], 0)
    sum2 = bit.bor(sum2 + arr[z + 11], 0)
    sum3 = bit.bor(sum3 + arr[z + 12], 0)

    sum0 = bit.bor(sum0 + arr[z + 13], 0)
    sum1 = bit.bor(sum1 + arr[z + 14], 0)
    sum2 = bit.bor(sum2 + arr[z + 15], 0)
    sum3 = bit.bor(sum3 + arr[z + 16], 0)

    z = z + 16
    N = N - 16
  end

  while (N >= 4) do
    sum0 = bit.bor(sum0 + arr[z + 1], 0)
    sum1 = bit.bor(sum1 + arr[z + 2], 0)
    sum2 = bit.bor(sum2 + arr[z + 3], 0)
    sum3 = bit.bor(sum3 + arr[z + 4], 0)
    z = z + 4
    N = N - 4
  end

  sum3 = ((bit.bor(sum3 + (bit.lshift(sum2, 8)), 0) + bit.bor(bit.lshift(sum1, 16), 0)) + bit.bor(bit.lshift(sum0, 24), 0))

  if N >= 3 then
    sum3 = bit.bor(sum3 + bit.lshift(arr[z + 3], 8), 0)
  end

  if N >= 2 then
    sum3 = bit.bor(sum3 + bit.lshift(arr[z + 2], 16), 0)
  end

  if N >= 1 then
    sum3 = bit.bor(sum3 + bit.lshift(arr[z + 1], 24), 0)
  end

  return bit_rshift(sum3, 0)
end

-- Create a new delta from src to out.
fossil_delta.create = function(src, out)
  local z_delta = Writer.new()
  local len_out = #out
  local len_src = #src
  local i
  local last_read = -1

  z_delta:put_int(len_out)
  z_delta:put_char('\n')

  -- If the source is very small, it means that we have no
  -- chance of ever doing a copy command.  Just output a single
  -- literal segment for the entire target and exit.
  if (len_src <= NHASH) then
    z_delta:put_int(len_out)
    z_delta:put_char(':')
    z_delta:put_array(out, 1, len_out + 1)
    z_delta:put_int(checksum(out))
    z_delta:put_char(';')
    return z_delta:to_array()
  end

  -- Compute the hash table used to locate matching sections in the source.
  local n_hash = math.ceil(len_src / NHASH)
  local collide = {}
  local landmark = {}

  i = 0
  while i < n_hash do
    collide[i] = -1
    i = i + 1
  end

  i = 0
  while i < n_hash do
    landmark[i] = -1
    i = i + 1
  end

  local hv
  local h = RollingHash.new()

  i = 0
  while i < len_src - NHASH do
    h:init(src, i)
    hv = h:value() % n_hash
    collide[i/NHASH] = landmark[hv]
    landmark[hv] = i / NHASH
    i = i + NHASH
  end

  local base = 0
  local i_src
  local i_block
  local best_cnt
  local best_offset
  local best_litsz

  while base + NHASH < len_out do
    best_offset=0
    best_litsz=0
    h:init(out, base)
    i = 0 -- Trying to match a landmark against z_out[base+i]
    best_cnt = 0

    while true do
      local limit = 250
      hv = h:value() % n_hash

      i_block = landmark[hv]
      while i_block >= 0 do
        limit = limit - 1
        if limit <= 0 then break end

        --
        -- The hash window has identified a potential match against
        -- landmark block i_block.  But we need to investigate further.
        --
        -- Look for a region in z_out that matches zSrc. Anchor the search
        -- at zSrc[i_src] and z_out[base+i].  Do not include anything prior to
        -- z_out[base] or after z_out[outLen] nor anything after zSrc[srcLen].
        --
        -- Set cnt equal to the length of the match and set ofst so that
        -- zSrc[ofst] is the first element of the match.  litsz is the number
        -- of characters between z_out[base] and the beginning of the match.
        -- sz will be the overhead (in bytes) needed to encode the copy
        -- command.  Only generate copy command if the overhead of the
        -- copy command is less than the amount of literal text to be copied.
        --
        local cnt, ofst, litsz
        local j, k, x, y
        local sz

        -- Beginning at i_src, match forwards as far as we can.
        -- j counts the number of characters that match.
        i_src = i_block * NHASH

        j = 0
        x = i_src
        y = base+i
        -- for (j = 0, x = i_src, y = base+i; x < len_src && y < len_out; j++, x++, y++) {
        while x < len_src and y < len_out do
          -- if src[x] ~= out[y] then break end
          if src[x+1] ~= out[y+1] then break end
          j = j + 1
          x = x + 1
          y = y + 1
        end
        j = j - 1

        -- Beginning at i_src-1, match backwards as far as we can.
        -- k counts the number of characters that match.
        k = 1
        while k < i_src and k <= i do
          -- if (src[i_src-k] ~= out[base+i-k]) then break end
          if (src[i_src-k + 1] ~= out[base+i-k + 1]) then break end
          k = k + 1
        end
        k = k - 1

        -- Compute the offset and size of the matching region.
        ofst = i_src-k
        cnt = j+k+1
        litsz = i-k -- Number of bytes of literal text before the copy
        -- sz will hold the number of bytes needed to encode the "insert"
        -- command and the copy command, not counting the "insert" text.
        sz = digit_count(i-k)+digit_count(cnt)+digit_count(ofst)+3
        if (cnt >= sz and cnt > best_cnt) then
          -- Remember self match only if it is the best so far and it
          -- does not increase the file size.
          best_cnt = cnt
          best_offset = i_src - k
          best_litsz = litsz
        end

        -- Check the next matching block
        i_block = collide[i_block]
      end

      -- We have a copy command that does not cause the delta to be larger
      -- than a literal insert.  So add the copy command to the delta.
      if best_cnt > 0 then
        if best_litsz > 0 then
          -- Add an insert command before the copy.
          z_delta:put_int(best_litsz)
          z_delta:put_char(':')
          z_delta:put_array(out, base + 1, base+best_litsz+1)
          base = base + best_litsz
        end
        base = base + best_cnt
        z_delta:put_int(best_cnt)
        z_delta:put_char('@')
        z_delta:put_int(best_offset)
        z_delta:put_char(',')
        if best_offset + best_cnt -1 > last_read then
          last_read = best_offset + best_cnt - 1
        end
        best_cnt = 0
        break
      end

      -- If we reach this point, it means no match is found so far
      if base+i+NHASH >= len_out then
        -- We have reached the end and have not found any
        -- matches.  Do an "insert" for everything that does not match
        z_delta:put_int(len_out-base)
        z_delta:put_char(':')
        z_delta:put_array(out, base+1, base+len_out-base+1)
        base = len_out
        break
      end

      -- Advance the hash by one character. Keep looking for a match.
      h:next(out[base+i+NHASH+1])

      i = i + 1
    end
  end

  -- Output a final "insert" record to get all the text at the end of
  -- the file that does not match anything in the source.
  if base < len_out then
    z_delta:put_int(len_out - base)
    z_delta:put_char(':')
    z_delta:put_array(out, base+1, base+len_out-base+1)
  end

  -- Output the final checksum record.
  z_delta:put_int(checksum(out))
  z_delta:put_char(';')
  return z_delta:to_array()
end

-- Return the size (in bytes) of the output from applying a delta.
function fossil_delta.output_size (delta)
  local z_delta = Reader.new(delta)
  local size = z_delta:get_int()
  if (z_delta:get_char() ~= '\n') then
    error('size integer not terminated by \'\\n\'')
  end
  return size
end

-- Apply a delta.
function fossil_delta.apply (src, delta, opts)
  local limit
  local total = 0
  local z_delta = Reader.new(delta)
  local len_src = #src
  local len_delta = #delta

  limit = z_delta:get_int()
  if (z_delta:get_char() ~= '\n') then
    error('size integer not terminated by \'\\n\'')
  end

  local z_out = Writer.new()
  while z_delta:have_bytes() do
    local cnt, ofst
    cnt = z_delta:get_int()

    local next_char = z_delta:get_char()
    if next_char == '@' then
      ofst = z_delta:get_int()
      if (z_delta:have_bytes() and z_delta:get_char() ~= ',') then
        error('copy command not terminated by \',\'')
      end
      total = total + cnt

      if (total > limit) then
        error('copy exceeds output file size')
      end
      if (ofst+cnt > len_src) then
        error('copy extends past end of input')
      end
      z_out:put_array(src, ofst+1, ofst+cnt+1)

    elseif next_char == ':' then
      total = total + cnt
      if (total > limit) then
        error('insert command gives an output larger than predicted')
      end
      if (cnt > len_delta) then
        error('insert count exceeds size of delta')
      end
      z_out:put_array(z_delta.a, z_delta.pos+1, z_delta.pos+cnt+1)
      z_delta.pos = z_delta.pos + cnt

    elseif next_char == ';' then
      local out = z_out:to_array()
      if ((not opts or opts.verify_checksum ~= false) and cnt ~= checksum(out)) then
        error('bad checksum')
      end
      if total ~= limit then
        error('generated size does not match predicted size')
      end

      return out

    else
        error('unknown delta operator')
    end
  end
  error('unterminated delta')
end

return fossil_delta
