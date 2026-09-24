local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestF15EUfc
TestF15EUfc = {}

local SPLIT = "-----------------------------------------"

--- @param items { [string]: string }
--- @return string
local function indication(items)
	local lines = {}
	for key, value in pairs(items) do
		table.insert(lines, SPLIT .. "\n" .. key .. "\n" .. value)
	end
	return table.concat(lines, "\n") .. "\n"
end

--- Reads a string output of a module from its memory map
--- @param module Module
--- @param category string
--- @param identifier string
--- @return string
local function read_string(module, category, identifier)
	local output = module.documentation[category][identifier].outputs[1]
	local chars = {}
	for i = 0, output.max_length - 1 do
		local address = output.address + i
		local entry = module.memoryMap.entries[address - address % 2]
		local word = entry and entry:getValue() or 0
		table.insert(chars, string.char(address % 2 == 0 and word % 256 or math.floor(word / 256)))
	end
	return table.concat(chars)
end

function TestF15EUfc:testEverySpecialCharacterReachesTheDotsLine()
	local saved_list_indication = list_indication
	function list_indication(id)
		if id == 9 or id == 18 then
			return indication({ UFC_SC_01 = "N 41°24.123", UFC_SC_12 = "12:34:56" })
		end
		return ""
	end

	local F_15E = require("Scripts.DCS-BIOS.lib.modules.aircraft_modules.F-15E")
	local dev0 = {
		get_argument_value = function()
			return 0
		end,
	}
	for _, hook in ipairs(F_15E.exportHooks) do
		pcall(hook, dev0)
	end
	list_indication = saved_list_indication

	lu.assertEquals(read_string(F_15E, "Front UFC Display", "F_UFC_LINE1_DISPLAY"), "N 4124123     123456")
	-- degree, decimal point and both colons, each after the character it follows
	lu.assertEquals(read_string(F_15E, "Front UFC Display", "F_UFC_LINE1_DISPLAY_DOTS"), "   ' .         : :  ")
end
