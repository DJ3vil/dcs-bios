local IndicatorDump = require("Scripts.DCS-BIOS.lib.modules.displays.IndicatorDump")
local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestIndicatorDump
TestIndicatorDump = {}

local function read_all(path)
	local file = io.open(path, "r")
	if not file then
		return ""
	end
	local text = file:read("*a")
	file:close()
	return text
end

local function count(text, pattern)
	local n = 0
	for _ in text:gmatch(pattern) do
		n = n + 1
	end
	return n
end

function TestIndicatorDump:setUp()
	self.path = os.tmpname()
	os.remove(self.path)
	self.indications = {}
	self.now = 100
	self.dump = IndicatorDump:new({
		file = self.path,
		first = 0,
		last = 3,
		min_interval = 2,
		max_bytes = 40,
		per_update = 2,
		list_indication = function(id)
			if id == 3 then
				error("no such indicator")
			end
			return self.indications[id] or ""
		end,
		time = function()
			return self.now
		end,
	})
end

function TestIndicatorDump:tearDown()
	os.remove(self.path)
end

function TestIndicatorDump:sweep()
	-- four indicators, two per update
	self.dump:update()
	self.dump:update()
end

function TestIndicatorDump:testWritesChangesOnly()
	self.indications[1] = "PAGE A"
	self:sweep()
	self:sweep()

	local text = read_all(self.path)
	lu.assertEquals(count(text, "=== [%d:]+ indicator 1\n"), 1)
	lu.assertStrContains(text, "PAGE A")
	-- dark and failing indicators are left out
	lu.assertEquals(count(text, "indicator 0\n"), 0)
	lu.assertEquals(count(text, "indicator 3\n"), 0)
end

function TestIndicatorDump:testWaitsBetweenWritesOfOneIndicator()
	self.indications[1] = "PAGE A"
	self:sweep()

	self.indications[1] = "PAGE B"
	self.now = self.now + 1
	self:sweep()
	lu.assertEquals(count(read_all(self.path), "indicator 1\n"), 1)

	self.now = self.now + 1
	self:sweep()
	local text = read_all(self.path)
	lu.assertEquals(count(text, "indicator 1\n"), 2)
	lu.assertStrContains(text, "PAGE B")
end

function TestIndicatorDump:testStopsAtTheSizeLimit()
	for i = 1, 10 do
		self.indications[2] = string.format("VALUE %02d", i)
		self.now = self.now + 2
		self:sweep()
	end

	-- 8 bytes each, so the fifth write reaches the 40 byte limit
	lu.assertEquals(count(read_all(self.path), "indicator 2\n"), 5)
end
