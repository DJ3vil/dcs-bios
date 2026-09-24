local ConnectionManager = require("Scripts.DCS-BIOS.lib.ConnectionManager")
local MockServer = require("Scripts.DCS-BIOS.test.io.MockServer")

local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestConnectionManager
--- @field connection_manager ConnectionManager
TestConnectionManager = {}

function TestConnectionManager:setUp()
	self.connection_manager = ConnectionManager:new({})
end

function TestConnectionManager:testFlush()
	local testBuffer = "test"
	local server = MockServer:new()
	self.connection_manager:addConnection(server)

	self.connection_manager:queue(testBuffer)
	self.connection_manager:send_queue()

	lu.assertEquals(#server.sent_messages, 1)
	lu.assertEquals(server.sent_messages[1], testBuffer)
end

function TestConnectionManager:testFlushEmptyBuffer()
	local server = MockServer:new()
	self.connection_manager:addConnection(server)

	self.connection_manager:send_queue()

	lu.assertEquals(#server.sent_messages, 0)
end

function TestConnectionManager:testFlushOverMaxBuffer()
	local testBuffer = ""
	for _ = 1, 200, 1 do
		testBuffer = testBuffer .. "test" -- build testbuffer to be 800 bytes long
	end

	local server = MockServer:new()
	self.connection_manager:addConnection(server)

	self.connection_manager:queue(testBuffer)
	self.connection_manager:queue(testBuffer)
	self.connection_manager:queue(testBuffer)
	self.connection_manager:send_queue()

	lu.assertEquals(#server.sent_messages, 3)
	lu.assertEquals(server.sent_messages[1], testBuffer) -- max buffer size is 1460 bytes, so each 800-byte buffer gets its own packet
	lu.assertEquals(server.sent_messages[2], testBuffer)
	lu.assertEquals(server.sent_messages[3], testBuffer)
end

--- @param address integer
--- @param data string
--- @return string
local function write_access(address, data)
	return string.char(address % 256, math.floor(address / 256), #data % 256, math.floor(#data / 256)) .. data
end

--- Applies the write accesses of all sent packets to a memory image
--- @param packets string[]
--- @return { [integer]: integer }
local function apply_writes(packets)
	local memory = {}
	local stream = table.concat(packets)
	local pos = 1
	while pos <= #stream do
		local address = stream:byte(pos) + stream:byte(pos + 1) * 256
		local length = stream:byte(pos + 2) + stream:byte(pos + 3) * 256
		for i = 0, length - 1 do
			memory[address + i] = stream:byte(pos + 4 + i)
		end
		pos = pos + 4 + length
	end
	return memory
end

function TestConnectionManager:testSplitOversizedWriteAccesses()
	local server = MockServer:new()
	self.connection_manager:addConnection(server)

	-- a long contiguous write followed by a short one, 3024 bytes in total like a full C-130J frame
	local long = string.rep("AB", 1400)
	local short = "CDEF"
	local msg = write_access(0xB000, long) .. write_access(0xC000, short)
	lu.assertTrue(#msg > self.connection_manager.MAX_PAYLOAD_SIZE)

	self.connection_manager:queue(msg)
	self.connection_manager:send_queue()

	lu.assertTrue(#server.sent_messages > 1)
	for _, packet in ipairs(server.sent_messages) do
		lu.assertTrue(#packet <= self.connection_manager.MAX_PAYLOAD_SIZE)
	end

	local memory = apply_writes(server.sent_messages)
	for i = 1, #long do
		lu.assertEquals(memory[0xB000 + i - 1], long:byte(i))
	end
	for i = 1, #short do
		lu.assertEquals(memory[0xC000 + i - 1], short:byte(i))
	end
end

function TestConnectionManager:testOversizedMessageThatIsNotWriteAccessesFails()
	local msg = string.rep("x", self.connection_manager.MAX_PAYLOAD_SIZE + 1)
	lu.assertErrorMsgContains("exceeded max buffer size", function()
		self.connection_manager:queue(msg)
	end)
end
