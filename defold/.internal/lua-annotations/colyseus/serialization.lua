---@meta
local serializers = {
    ['none'] = require('colyseus.serializer.none'),
    ['fossil-delta'] = require('colyseus.serializer.fossil_delta'),
    ['schema'] = require('colyseus.serializer.schema_serializer'),
}

local exports = {}

exports.register_serializer = function(id, handler)
    serializers[id] = handler
end

exports.get_serializer = function(id)
    return serializers[id]
end

return exports