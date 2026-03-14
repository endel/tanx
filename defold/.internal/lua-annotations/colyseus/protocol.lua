---@meta
-- Use codes between 0~127 for lesser throughput (1 byte)

return {
  -- User-related (0~8)
  USER_ID = 1,

  -- Room-related (9~19)
  JOIN_REQUEST = 9,
  JOIN_ROOM = 10,
  ERROR = 11,
  LEAVE_ROOM = 12,
  ROOM_DATA = 13,
  ROOM_STATE = 14,
  ROOM_STATE_PATCH = 15,

  ROOM_DATA_SCHEMA = 16,
  ROOM_DATA_BYTES = 17,
  PING = 18,

  CLOSE_CODE = {
    NORMAL_CLOSURE = 1000,
    GOING_AWAY = 1001,
    NO_STATUS_RECEIVED = 1005,
    ABNORMAL_CLOSURE = 1006,
    CONSENTED = 4000,
    SERVER_SHUTDOWN = 4001,
    WITH_ERROR = 4002,
    MAY_TRY_RECONNECT = 4010,
  }
}
