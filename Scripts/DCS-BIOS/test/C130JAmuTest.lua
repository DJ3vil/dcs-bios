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
-- the entry beside L1 being edited: its boxed copy is drawn instead of the plain one
local EDITING = indication({ "<LEVEL 50", "", "EDIT PAGE", "SET>", "MENU>" }, "E")
local EDIT_DONE = indication({ "", "EDIT PAGE", "<LEVEL 50%", "SET>", "MENU>" }, "F")
local PLAIN = string.rep("0", AmuDisplay.COLUMNS)

--- @param indications { [integer]: string }
--- @param defaults HighlightDefaults?
--- @return AmuDisplay
local function new_display(indications, defaults)
	return AmuDisplay:new({
		list_indication = function(id)
			return indications[id] or ""
		end,
		defaults = defaults,
	})
end

--- @param display AmuDisplay
--- @param ticks integer?
--- @param dev0 table? the cockpit device, for the keys
local function run(display, ticks, dev0)
	for _ = 1, ticks or 100 do
		display:update(dev0)
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
		lu.assertEquals(names, { "MENU", "DISPLAY", "RANGE_PAGE", "EDIT" })

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

function TestC130JAmu:testExtractorMarksBoxedEntries()
	with_test_install(function()
		local script_path, common_path = CniSchemaExtractor.find_script_root()
		local catalogue = AmuSchemaExtractor.catalogue(script_path, common_path)
		local page = AmuSchemaExtractor.extract_page(script_path, common_path, catalogue[4])
		lu.assertNil(page.error)

		local boxed = {}
		for _, slot in ipairs(page.slots) do
			if slot.fmt then
				boxed[slot.fmt[1]] = slot.invert == true
			end
		end
		lu.assertEquals(boxed, { ["<LEVEL %s"] = true, ["<LEVEL %s%%"] = false })
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

function TestC130JAmu:testEntryBeingEditedIsHighlighted()
	with_test_install(function()
		local indications = { [18] = EDITING, [19] = DISPLAY }
		local display = new_display(indications)
		run(display)

		lu.assertEquals(display:get_page(1), "EDIT")
		lu.assertEquals(display:get_line(1, 3), "<LEVEL 50              ")
		lu.assertEquals(display:get_format(1, 3), "222222222" .. string.rep("0", 14))
		lu.assertEquals(display:get_line(1, 4), "                   SET>")
		lu.assertEquals(display:get_format(1, 4), PLAIN)

		-- of the toggles, only PILOT/COPILOT is known before anything is pressed: the pilot's AMUs
		-- start on PILOT
		for line = 1, AmuDisplay.LINES do
			lu.assertEquals(display:get_format(2, line), line == 3 and ("22222" .. string.rep("0", 18)) or PLAIN)
		end

		indications[18] = EDIT_DONE
		run(display, 8)
		lu.assertEquals(display:get_line(1, 3), "<LEVEL 50%             ")
		lu.assertEquals(display:get_format(1, 3), PLAIN)

		indications[18] = DARK
		run(display, 8)
		lu.assertEquals(display:get_format(1, 3), PLAIN)
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

-- the cockpit argument of L1 of each unit; L2-L4 and R1-R4 follow on
local FIRST_KEY_ARG = { 133, 141, 174, 182 }

--- A cockpit device whose keys can be pressed
local function cockpit()
	local args = {}
	return {
		args = args,
		get_argument_value = function(_, arg)
			return args[arg] or 0
		end,
	}
end

--- Presses and lets go of a key of a unit: 1-4 for L1-L4, 5-8 for R1-R4
local function press(display, dev0, unit, key)
	local arg = FIRST_KEY_ARG[unit] + key - 1
	dev0.args[arg] = 1
	run(display, 1, dev0)
	dev0.args[arg] = 0
	run(display, 8, dev0)
end

--- The words of a line of a unit drawn boxed
local function boxed(display, unit, line)
	local text, format = display:get_line(unit, line), display:get_format(unit, line)
	local words = {}
	for start, word, stop in text:gmatch("()([%w]+)()") do
		if format:sub(start, stop - 1):match("^2+$") then
			words[#words + 1] = word
		end
	end
	return table.concat(words, ",")
end

function TestC130JAmu:testExtractorFindsTheToggles()
	with_test_install(function()
		local script_path, common_path = CniSchemaExtractor.find_script_root()
		local catalogue = AmuSchemaExtractor.catalogue(script_path, common_path)
		local toggles = AmuDisplay.toggles_of(AmuSchemaExtractor.extract_page(script_path, common_path, catalogue[2]))

		local found = {}
		for key, toggle in pairs(toggles.toggles) do
			local texts = {}
			for word = 1, toggle.count do
				texts[word] = toggle.texts[word]
			end
			found[key] = table.concat(texts, "/")
		end
		-- a word on its own, like BARO or REF UNIT, is no toggle; 2/1 reads 1/2 from the right key
		lu.assertEquals(found, { [1] = "PILOT/COPILOT", [2] = "IN/MB", [3] = "MAG/TRUE/GRID", [5] = "2/1" })
		lu.assertEquals(toggles.side, 1)
	end)
end

function TestC130JAmu:testPressesMoveTheBox()
	with_test_install(function()
		local dev0 = cockpit()
		local display = new_display({ [18] = DISPLAY })
		run(display, 100, dev0)

		-- the pilot's AMUs start on PILOT; nothing is known of the other toggles
		lu.assertEquals(boxed(display, 1, 3), "PILOT")
		lu.assertEquals(boxed(display, 1, 7), "")

		press(display, dev0, 1, 1)
		lu.assertEquals(boxed(display, 1, 3), "COPILOT")
		press(display, dev0, 1, 1)
		lu.assertEquals(boxed(display, 1, 3), "PILOT")

		-- the crew says where MAG/TRUE/GRID is, and every press is followed from there
		display:shift_highlight(1, 3)
		run(display, 8, dev0)
		lu.assertEquals(boxed(display, 1, 7), "MAG")
		press(display, dev0, 1, 3)
		lu.assertEquals(boxed(display, 1, 7), "TRUE")
		press(display, dev0, 1, 3)
		press(display, dev0, 1, 3)
		lu.assertEquals(boxed(display, 1, 7), "MAG")

		-- a key held down is one press, and a key with no toggle beside it changes nothing
		dev0.args[FIRST_KEY_ARG[1] + 2] = 1
		run(display, 5, dev0)
		dev0.args[FIRST_KEY_ARG[1] + 2] = 0
		run(display, 8, dev0)
		lu.assertEquals(boxed(display, 1, 7), "TRUE")
		press(display, dev0, 1, 8)
		display:shift_highlight(1, 8)
		run(display, 8, dev0)
		lu.assertEquals(boxed(display, 1, 7), "TRUE")
		lu.assertEquals(boxed(display, 1, 3), "PILOT")
	end)
end

function TestC130JAmu:testTogglesAreFollowedPerSide()
	with_test_install(function()
		local dev0 = cockpit()
		local display = new_display({ [18] = DISPLAY, [20] = DISPLAY })
		run(display, 100, dev0)

		-- the copilot's AMUs start on COPILOT
		lu.assertEquals(boxed(display, 3, 3), "COPILOT")

		-- BARO is IN for the pilot's side
		display:shift_highlight(1, 2)
		run(display, 8, dev0)
		lu.assertEquals(boxed(display, 1, 5), "IN")

		-- and not known for the copilot's, until the crew says so
		press(display, dev0, 1, 1)
		lu.assertEquals(boxed(display, 1, 3), "COPILOT")
		lu.assertEquals(boxed(display, 1, 5), "")
		display:shift_highlight(1, 2)
		display:shift_highlight(1, 2)
		run(display, 8, dev0)
		lu.assertEquals(boxed(display, 1, 5), "MB")

		-- each side keeps its own
		press(display, dev0, 1, 1)
		lu.assertEquals(boxed(display, 1, 5), "IN")
	end)
end

function TestC130JAmu:testCorrectionIsKeptAsWhereTheToggleStarts()
	with_test_install(function()
		local HighlightDefaults = require("Scripts.DCS-BIOS.lib.modules.displays.HighlightDefaults")
		local defaults = HighlightDefaults:new()
		local dev0 = cockpit()
		local display = new_display({ [20] = DISPLAY }, defaults)
		run(display, 100, dev0)

		-- MAG/TRUE/GRID pressed twice before the crew says it is on MAG now: it started on TRUE
		press(display, dev0, 3, 3)
		press(display, dev0, 3, 3)
		display:shift_highlight(3, 3)
		run(display, 8, dev0)
		lu.assertEquals(boxed(display, 3, 7), "MAG")
		lu.assertEquals(defaults:section("amu_ri").DISPLAY, { ["3|COPILOT"] = 2 })

		-- the next session starts it there
		local next_session = new_display({ [20] = DISPLAY }, defaults)
		run(next_session, 100, dev0)
		lu.assertEquals(boxed(next_session, 3, 7), "TRUE")
		press(next_session, dev0, 3, 3)
		lu.assertEquals(boxed(next_session, 3, 7), "GRID")

		-- the other units keep defaults of their own
		local other = new_display({ [21] = DISPLAY }, defaults)
		run(other, 100, dev0)
		lu.assertEquals(boxed(other, 4, 7), "")
	end)
end

function TestC130JAmu:testModuleOffersTheCorrectionForEveryUnit()
	local C_130J = require("Scripts.DCS-BIOS.lib.modules.aircraft_modules.C-130J")
	for _, prefix in ipairs({ "LO", "LI", "RI", "RO" }) do
		local shift = C_130J.inputProcessors[prefix .. "_AMU_SHIFT_HIGHLIGHT"]
		lu.assertNotNil(shift, prefix)
		shift("3")
		shift("not a key")
	end
end
