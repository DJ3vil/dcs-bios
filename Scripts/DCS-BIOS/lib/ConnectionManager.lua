module("ConnectionManager", package.seeall)

--- @class ConnectionManager
--- @field connections Server[] the connections to send messages to
--- @field private msg_buf string[] the buffer of messages to send
--- @field private MAX_PAYLOAD_SIZE integer the maximum payload that can be accepted and sent
local ConnectionManager = {}

--- Constructs a new connection handler
--- @param connections Server[] the connections to send messages to
--- @return ConnectionManager
function ConnectionManager:new(connections)
	--- @type ConnectionManager
	local o = {
		connections = connections,
		msg_buf = {},
		MAX_PAYLOAD_SIZE = 1460,
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

--- Adds a new connection
--- @param server Server
function ConnectionManager:addConnection(server)
	table.insert(self.connections, server)
end

local function read_u16(s, pos)
	return s:byte(pos) + s:byte(pos + 1) * 256
end

local function encode_u16(value)
	return string.char(value % 256, math.floor(value / 256) % 256)
end

--- Splits a sequence of write accesses (address, length and data) into pieces of at most
--- max_size bytes. A write access that does not fit is split into several consecutive ones.
--- @param msg string
--- @param max_size integer
--- @return string[]? pieces nil if the message is not a sequence of write accesses
local function split_write_accesses(msg, max_size)
	local pieces = {}
	local current, current_size = {}, 0

	local function finish_piece()
		if current_size > 0 then
			pieces[#pieces + 1] = table.concat(current)
			current, current_size = {}, 0
		end
	end

	local pos = 1
	while pos <= #msg do
		if pos + 3 > #msg then
			return nil
		end
		local address = read_u16(msg, pos)
		local length = read_u16(msg, pos + 2)
		if length == 0 or length % 2 ~= 0 or pos + 3 + length > #msg then
			return nil
		end

		local offset = 0
		while offset < length do
			local room = max_size - current_size - 4
			if room < 2 then
				finish_piece()
				room = max_size - 4
			end
			local size = math.min(length - offset, room - room % 2)
			current[#current + 1] = encode_u16(address + offset) .. encode_u16(size) .. msg:sub(pos + 4 + offset, pos + 3 + offset + size)
			current_size = current_size + 4 + size
			offset = offset + size
		end

		pos = pos + 4 + length
	end

	finish_piece()
	return pieces
end

--- Queues a message to be sent to any connections. A message of write accesses that exceeds the
--- maximum payload size is split into several messages.
---@param msg string the message to send
function ConnectionManager:queue(msg)
	if msg:len() > self.MAX_PAYLOAD_SIZE then
		local pieces = split_write_accesses(msg, self.MAX_PAYLOAD_SIZE)
		if not pieces then
			error(string.format("Message (%d) exceeded max buffer size (%d) :: %s", msg:len(), self.MAX_PAYLOAD_SIZE, msg))
		end
		for _, piece in ipairs(pieces) do
			table.insert(self.msg_buf, piece)
		end
		return
	end

	table.insert(self.msg_buf, msg)
end

--- Flushes the message buffer, sending any queued messages
function ConnectionManager:send_queue()
	local packet = ""
	while #self.msg_buf > 0 do
		local msg = table.remove(self.msg_buf, 1)
		if packet:len() + msg:len() > self.MAX_PAYLOAD_SIZE then
			-- packet would be too big, so send what we have now
			self:send_packet(packet)
			packet = ""
		end
		packet = packet .. msg
	end

	if packet:len() > 0 then
		self:send_packet(packet)
	end
end

--- @private
--- Sends a packet to all open connections
--- @param packet string
function ConnectionManager:send_packet(packet)
	for _, conn in ipairs(self.connections) do
		if conn.send then
			conn:send(packet)
		end
	end
end

return ConnectionManager
