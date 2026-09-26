local CockpitParamDump = require("Scripts.DCS-BIOS.lib.modules.displays.CockpitParamDump")
local TempPath = require("Scripts.DCS-BIOS.test.io.TempPath")
local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestCockpitParamDump
TestCockpitParamDump = {}

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

--- @param params { [string]: string }
--- @return string
local function listing(params)
	local lines = {}
	for name, value in pairs(params) do
		lines[#lines + 1] = name .. ":" .. value
	end
	table.sort(lines)
	return table.concat(lines, "\n") .. "\n"
end

function TestCockpitParamDump:setUp()
	self.path = TempPath.new()
	os.remove(self.path)
	self.params = { AMU_PAGE = "1.000000", ["EXT:FUEL"] = "0.500000" }
	self.args = {}
	self.now = 100

	local amu = setmetatable({}, { __index = { performClickableAction = true, SetCommand = true } })
	self.dev0 = {
		get_argument_value = function(_, arg)
			return self.args[arg] or 0
		end,
	}
	self.dump = CockpitParamDump:new({
		file = self.path,
		keys = { [133] = "LO_AMU_L1", [134] = "LO_AMU_L2" },
		devices = { [29] = "AMU001", [99] = "NOWHERE" },
		interval = 2,
		noisy_after = 3,
		list_cockpit_params = function()
			return listing(self.params)
		end,
		get_device = function(id)
			return id == 29 and amu or nil
		end,
		time = function()
			return self.now
		end,
	})
end

function TestCockpitParamDump:tearDown()
	os.remove(self.path)
end

--- one export tick, the given seconds after the last
function TestCockpitParamDump:tick(seconds)
	self.now = self.now + (seconds or 0)
	self.dump:update(self.dev0)
end

function TestCockpitParamDump:testWritesEverythingOnceThenTheChanges()
	self:tick()
	local text = read_all(self.path)
	lu.assertStrContains(text, "all 2 parameters\nAMU_PAGE = 1.000000\nEXT:FUEL = 0.500000\n")
	lu.assertStrContains(text, "device 29 AMU001: SetCommand performClickableAction\n")
	lu.assertStrContains(text, "device 99 NOWHERE: not found\n")

	-- nothing new, and a change within the interval waits for the next look
	self:tick(2)
	self.params.AMU_PAGE = "6.000000"
	self:tick(1)
	lu.assertEquals(count(read_all(self.path), "changed\n"), 0)

	self:tick(1)
	self.params.AMU_BOX = "1.000000"
	self.params["EXT:FUEL"] = nil
	self:tick(2)
	text = read_all(self.path)
	lu.assertStrContains(text, "changed\nAMU_PAGE: 1.000000 -> 6.000000\n")
	lu.assertStrContains(text, "changed\nAMU_BOX: nil -> 1.000000\nEXT:FUEL: 0.500000 -> nil\n")
end

function TestCockpitParamDump:testLeavesOutParametersThatKeepChanging()
	self:tick()
	for i = 1, 6 do
		self.params["EXT:FUEL"] = string.format("0.%d00000", i)
		self:tick(2)
	end

	local text = read_all(self.path)
	lu.assertEquals(count(text, "EXT:FUEL: "), 3)
	lu.assertStrContains(text, "EXT:FUEL: 0.200000 -> 0.300000 (keeps changing, left out from now on)\n")
end

function TestCockpitParamDump:testNotesKeyPresses()
	-- a key already down when the dump starts was not seen being pressed
	self.args[134] = 1
	self:tick()
	self:tick()
	lu.assertEquals(count(read_all(self.path), "pressed"), 0)

	self.args[133] = 1
	self.args[134] = 0
	self:tick()
	self:tick()
	self.args[133] = 0
	self:tick()
	self.args[133] = 1
	self.args[134] = 1
	self:tick()

	local text = read_all(self.path)
	lu.assertEquals(count(text, "pressed LO_AMU_L1\n"), 1)
	lu.assertEquals(count(text, "pressed LO_AMU_L1 LO_AMU_L2\n"), 1)
end

function TestCockpitParamDump:testStopsAtTheSizeLimit()
	self.dump = CockpitParamDump:new({
		file = self.path,
		max_bytes = 1,
		list_cockpit_params = function()
			return listing(self.params)
		end,
		time = function()
			return self.now
		end,
	})
	self:tick()
	local size = #read_all(self.path)
	lu.assertTrue(size > 0)

	self.params.AMU_PAGE = "2.000000"
	self:tick(2)
	lu.assertEquals(#read_all(self.path), size)
end

function TestCockpitParamDump:testSurvivesAFailingSource()
	self.dump = CockpitParamDump:new({
		file = self.path,
		list_cockpit_params = function()
			error("not in this aircraft")
		end,
		time = function()
			return self.now
		end,
	})
	self:tick()
	lu.assertEquals(read_all(self.path), "")
end
