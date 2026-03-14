---@meta
local Client = require('colyseus.client')
local protocol = require('colyseus.protocol')
local callbacks = require('colyseus.serializer.schema.callbacks')

local M = {
	Client = Client,
	callbacks = callbacks,
	protocol = protocol
}

return M