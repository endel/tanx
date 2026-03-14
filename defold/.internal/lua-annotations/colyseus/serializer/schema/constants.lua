---@meta
local M = {}

-- START SPEC + OPERATION --
M.SPEC = {
    SWITCH_TO_STRUCTURE = 255,
    TYPE_ID = 213,
}

M.SCHEMA_MISMATCH = -1;

M.OPERATION = {
  -- ADD new structure/primitive
  ADD = 128,

  -- REPLACE structure/primitive
  REPLACE = 0,

  -- DELETE field
  DELETE = 64,

  -- DELETE field, followed by an ADD
  DELETE_AND_ADD = 192,
  DELETE_AND_MOVE = 96, -- ArraySchema

  -- Collection Operations
  CLEAR = 10,

  -- ArraySchema operations
  REVERSE = 15,
  DELETE_BY_REFID = 33,
  ADD_BY_REFID = 129,
}
-- END SPEC + OPERATION --

return M