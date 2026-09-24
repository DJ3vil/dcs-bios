local AmuDisplay = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_AMU.AmuDisplay")
local AmuSchemaExtractor = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_AMU.AmuSchemaExtractor")
local CniSchemaExtractor = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchemaExtractor")
local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestC130JAmu
TestC130JAmu = {}

local SPLIT = "-----------------------------------------"
local TEST_INSTALL = "Scripts/DCS-BIOS/test/c130j_cni/"
local BLANK = string.rep(" ", AmuDisplay.COLUMNS)

--- points lfs at the stand-in module under test/c130j_cni for the duration of a test
local function with_test_install(fn)
	local saved_currentdir, saved_attributes, saved_dir = lfs.currentdir, lfs.attributes, lfs.dir
	lfs.currentdir = function()
		return TEST_INSTALL
	end
	lfs.attributes = function(path)
		local file = io.open(path, "r")
		if file then
			file:close()
			return {}
		end
		return nil
	end
	lfs.dir = nil

	local ok, err = pcall(fn)

	lfs.currentdir, lfs.attributes, lfs.dir = saved_currentdir, saved_attributes, saved_dir
	if not ok then
		error(err, 0)
	end
end

--- @param values string[] the text of every element, in the order the sim sends them
--- @param tag string? distinguishes the element names of different units
--- @return string
local function indication(values, tag)
	local parts = {}
	for i, value in ipairs(values) do
		parts[i] = SPLIT .. "\n{" .. (tag or "A") .. "-" .. i .. "}\n" .. value
	end
	return table.concat(parts, "\n") .. "\n"
end

local MENU = indication({ "", "TEST MENU", "<ALPHA", "<BRAVO", "<CHARLIE", "DELTA>", "ECHO>", "FOXTROT>", "GOLF HOTEL>" }, "M")
local DISPLAY = indication({ "", "TEST DISPLAY", "PILOT", "/", "COPILOT", "BARO", "IN", "/", "MB", "MAG", "/", "TRUE", "/", "GRID", "SOURCE", "CP", "2", "/", "1", "REF UNIT", "MENU>" }, "D")
local RANGE = indication({ "RANGE     >", "20>", "", "RANGE PAGE", "TEST RANGE", "MENU>" }, "R")
local DARK = indication({ "" }, "B")

--- @param indications { [integer]: string }
--- @return AmuDisplay
local function new_display(indications)
	return AmuDisplay:new({
		list_indication = function(id)
			return indications[id] or ""
		end,
	})
end

local function run(display, ticks)
	for _ = 1, ticks or 100 do
		display:update()
	end
end

function TestC130JAmu:testExtractorReadsThePages()
	with_test_install(function()
		local script_path, common_path = CniSchemaExtractor.find_script_root()
		local catalogue = AmuSchemaExtractor.catalogue(script_path, common_path)

		-- the blank page is left out, and a file drawing two pages is read once
		local names = {}
		for i, entry in ipairs(catalogue) do
			names[i] = entry.name
		end
		lu.assertEquals(names, { "MENU", "DISPLAY", "RANGE_PAGE" })

		local page = AmuSchemaExtractor.extract_page(script_path, common_path, catalogue[2])
		lu.assertNil(page.error)

		local at = {}
		for _, slot in ipairs(page.slots) do
			local text = slot.value or (slot.fmt and slot.fmt[1])
			if text then
				at[#at + 1] = string.format("%s %d:%d%s", text, slot.line, slot.col, slot.anchor:sub(1, 1))
			end
		end
		lu.assertEquals(at, {
			-- the title above the lines of the keys
			"TEST DISPLAY 0:11C",
			-- the words of an entry side by side, its parts one space apart
			"PILOT 2:0L",
			"/ 2:5L",
			"COPILOT 2:6L",
			"BARO 4:0L",
			"IN 4:5L",
			"/ 4:7L",
			"MB 4:8L",
			"MAG 6:0L",
			"/ 6:3L",
			"TRUE 6:4L",
			"/ 6:8L",
			"GRID 6:9L",
			"SOURCE 8:0L",
			"%s 8:7L",
			-- from the right key inwards: 2/1 reads 1/2
			"2 3:23R",
			"/ 3:22R",
			"1 3:21R",
			"REF UNIT 3:19R",
			"MENU> 9:23R",
		})
	end)
end

function TestC130JAmu:testDisplayRendersTheFourUnits()
	with_test_install(function()
		local display = new_display({ [18] = MENU, [19] = DISPLAY, [20] = RANGE, [21] = DARK })
		run(display)

		lu.assertEquals(display.schema_state, "ready")

		lu.assertEquals(display:get_page(1), "MENU")
		lu.assertEquals(display:get_line(1, 1), "       TEST MENU       ")
		lu.assertEquals(display:get_line(1, 2), BLANK)
		lu.assertEquals(display:get_line(1, 3), "<ALPHA                 ")
		lu.assertEquals(display:get_line(1, 4), "                 DELTA>")
		lu.assertEquals(display:get_line(1, 9), "                       ")
		lu.assertEquals(display:get_line(1, 10), "            GOLF HOTEL>")

		lu.assertEquals(display:get_line(2, 1), "     TEST DISPLAY      ")
		lu.assertEquals(display:get_line(2, 3), "PILOT/COPILOT          ")
		lu.assertEquals(display:get_line(2, 4), "           REF UNIT 1/2")
		lu.assertEquals(display:get_line(2, 5), "BARO IN/MB             ")
		lu.assertEquals(display:get_line(2, 7), "MAG/TRUE/GRID          ")
		lu.assertEquals(display:get_line(2, 9), "SOURCE CP              ")

		-- a value drawn over the blank of its label
		lu.assertEquals(display:get_line(3, 4), "            RANGE   20>")

		-- a dark unit
		lu.assertEquals(display:get_page(4), "")
		for line = 1, AmuDisplay.LINES do
			lu.assertEquals(display:get_line(4, line), BLANK)
		end
	end)
end

function TestC130JAmu:testUnitsFollowTheirPages()
	with_test_install(function()
		local indications = { [18] = MENU }
		local display = new_display(indications)
		run(display)
		lu.assertEquals(display:get_page(1), "MENU")

		indications[18] = DISPLAY
		run(display, 8)
		lu.assertEquals(display:get_page(1), "DISPLAY")
		lu.assertEquals(display:get_line(1, 3), "PILOT/COPILOT          ")

		indications[18] = DARK
		run(display, 8)
		lu.assertEquals(display:get_line(1, 3), BLANK)
	end)
end

function TestC130JAmu:testFindsUnitsRegisteredElsewhere()
	with_test_install(function()
		local display = new_display({ [24] = MENU, [25] = DISPLAY })
		run(display, 1000)

		lu.assertEquals(display:get_page(1), "MENU")
		lu.assertEquals(display:get_page(2), "DISPLAY")
	end)
end

function TestC130JAmu:testMissingModuleLeavesTheUnitsDark()
	local saved_currentdir = lfs.currentdir
	lfs.currentdir = function()
		return "Scripts/DCS-BIOS/test/does-not-exist/"
	end
	local display = new_display({ [18] = MENU })
	local ok, err = pcall(run, display, 20)
	lfs.currentdir = saved_currentdir
	lu.assertTrue(ok, err)

	lu.assertEquals(display.schema_state, "failed")
	lu.assertEquals(display:get_line(1, 1), BLANK)
end
