local CniDisplay = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniDisplay")
local CniExecLamp = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniExecLamp")
local CniFormat = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniFormat")
local CniGrid = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniGrid")
local CniIndication = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniIndication")
local CniSchemaExtractor = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchemaExtractor")
local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestC130JCni
TestC130JCni = {}

local SPLIT = "-----------------------------------------"
local TEST_INSTALL = "Scripts/DCS-BIOS/test/c130j_cni/"

local function indication(...)
	return table.concat({ ... }, "\n") .. "\n"
end

local function element(key, value)
	if value == nil then
		return SPLIT .. "\n" .. key
	end
	return SPLIT .. "\n" .. key .. "\n" .. value
end

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

local function test_page_indication(scratchpad)
	return indication(
		element("{BG}"),
		element("cni_title", "TEST PAGE"),
		element("{COUNTER}", "1/2"),
		element("{FREQ-LABEL}", "FREQ"),
		element("{FREQ}", "1/243.000"),
		element("{SQL-LABEL}", "SQL"),
		element("{SQL-TOGGLE}", ""),
		"children are {",
		element("{SQL-ON}", "ON"),
		element("{SQL-OFF}", "OFF"),
		"}",
		element("{INDEX}", "<INDEX"),
		element("cni_scratchpad", scratchpad)
	)
end

local function route_indication(title)
	return indication(element("cni_title", title), element("{ORIGIN-LABEL}", "ORIGIN"), element("{ORIGIN}", "KLSV"), element("{A}", ""), element("{B}", ""), element("{ERASE}", "ERASE>"))
end

--- @param indications { [integer]: string }
--- @return CniDisplay
local function new_display(indications)
	local display = CniDisplay:new({
		list_indication = function(id)
			return indications[id] or ""
		end,
		get_device = function()
			return nil
		end,
	})
	return display
end

local dev0 = {
	args = {},
	get_argument_value = function(self, arg)
		return self.args[arg] or 0
	end,
}

--- runs export ticks until every seat has been processed at least once after the layouts loaded
local function run(display, ticks)
	for _ = 1, ticks or 200 do
		display:update(dev0)
	end
end

function TestC130JCni:testFormats()
	local frequency = CniFormat.compile("%d/%s")
	lu.assertTrue(CniFormat.accepts(frequency, "1/243.000"))
	lu.assertFalse(CniFormat.accepts(frequency, "243.000"))
	lu.assertTrue(CniFormat.accepts(frequency, "-----"), "a field drawn as placeholders fits every format")

	local bearing = CniFormat.compile("%03.f^")
	lu.assertTrue(CniFormat.accepts(bearing, "243^"))
	lu.assertTrue(CniFormat.accepts(bearing, "---^"))
	lu.assertFalse(CniFormat.accepts(bearing, "243"))

	local padded = CniFormat.compile("LZ %2d INIT")
	lu.assertTrue(CniFormat.accepts(padded, "LZ  1 INIT"))
	lu.assertFalse(CniFormat.accepts(padded, "LZ A INIT"))

	lu.assertTrue(CniFormat.accepts(CniFormat.compile("%s"), "ANYTHING AT ALL"))
	lu.assertEquals(CniFormat.specificity({ "%s" }), 0)
	lu.assertEquals(CniFormat.specificity({ "%d/%s" }), 1)
	lu.assertTrue(CniFormat.pins_page_number("2/%d"))
	lu.assertFalse(CniFormat.pins_page_number("%d/%d"))
end

function TestC130JCni:testIndicationKeepsChildren()
	local blocks, total = CniIndication.parse(test_page_indication("ABC"))
	lu.assertEquals(total, 11)
	lu.assertEquals(#blocks, 9)

	local toggle = blocks[7]
	lu.assertEquals(toggle.k, "{SQL-TOGGLE}")
	lu.assertEquals(#toggle.c, 2)
	lu.assertEquals(toggle.c[1].v, "ON")

	local flat = CniIndication.flatten(blocks)
	lu.assertEquals(#flat, 11)
	lu.assertEquals(flat[8].v, "ON")
	lu.assertEquals(flat[10].v, "<INDEX")
	lu.assertEquals(CniIndication.find_named(blocks, "cni_title").v, "TEST PAGE")
end

function TestC130JCni:testGlyphs()
	lu.assertEquals(CniGrid.map_glyphs("N42^14.56"), "N42" .. string.char(0xB0) .. "14.56")
	lu.assertEquals(CniGrid.map_glyphs("\226\128\148\226\128\148"), "--")
	lu.assertEquals(CniGrid.map_glyphs("]]]KT"), "]]]KT")
end

function TestC130JCni:testExtractorReadsPageScripts()
	with_test_install(function()
		local script_path, common_path = CniSchemaExtractor.find_script_root()
		lu.assertEquals(script_path, TEST_INSTALL .. "Mods/aircraft/C130J/Cockpit/Scripts/")
		lu.assertEquals(common_path, TEST_INSTALL .. "Scripts/Aircrafts/_Common/Cockpit/")

		local catalogue = CniSchemaExtractor.catalogue(script_path, common_path)
		lu.assertEquals(#catalogue, 2)
		lu.assertEquals(catalogue[1].name, "TEST_PAGE")
		lu.assertEquals(catalogue[2].name, "ROUTE")

		local page = CniSchemaExtractor.extract_page(script_path, common_path, catalogue[1])
		lu.assertNil(page.error)

		local by_value = {}
		for _, slot in ipairs(page.slots) do
			if slot.value then
				by_value[slot.value] = slot
			end
		end

		lu.assertEquals(by_value["TEST PAGE"].name, "cni_title")
		lu.assertEquals(by_value["TEST PAGE"].anchor, "Center")
		lu.assertEquals(by_value["TEST PAGE"].col, 13)
		-- small text is placed on its own line despite the nudge
		lu.assertEquals(by_value["1/2"].line, 0)
		lu.assertTrue(by_value["1/2"].small)
		lu.assertEquals(by_value["1/2"].anchor, "Right")
		lu.assertEquals(by_value["FREQ"].line, 1)
		lu.assertEquals(by_value["<INDEX"].line, 12)
		-- the scratchpad asks for line 13, one past the module's table
		lu.assertEquals(page.slots[#page.slots].name, "cni_scratchpad")
		lu.assertEquals(page.slots[#page.slots].line, 13)
		lu.assertEquals(page.slots[1].kind, "ceTexPoly")
	end)
end

function TestC130JCni:testDisplayRendersPages()
	with_test_install(function()
		local indications = { [8] = test_page_indication("ABC") }
		local display = new_display(indications)
		run(display)

		lu.assertEquals(display.schema_state, "ready")
		lu.assertEquals(display:get_page(1), "TEST_PAGE")
		lu.assertEquals(display:get_line(1, 1), "         TEST PAGE    1/2")
		lu.assertEquals(display:get_format(1, 1), "0000000000000000000000111")
		lu.assertEquals(display:get_line(1, 2), " FREQ                    ")
		lu.assertEquals(display:get_format(1, 2), "0111100000000000000000000")
		lu.assertEquals(display:get_line(1, 3), "1/243.000                ")
		lu.assertEquals(display:get_line(1, 4), " SQL                     ")
		-- nothing tells which word of the toggle is lit, so neither is drawn highlighted
		lu.assertEquals(display:get_line(1, 5), "ON  OFF                  ")
		lu.assertEquals(display:get_format(1, 5), "0000000000000000000000000")
		lu.assertEquals(display:get_line(1, 13), "<INDEX                   ")
		lu.assertEquals(display:get_line(1, 14), "ABC                      ")

		-- the copilot's display is dark
		lu.assertEquals(display:get_line(2, 1), string.rep(" ", 25))
		lu.assertEquals(display:get_page(2), "")

		-- a formatted title, and the EXEC light following it
		indications[9] = route_indication("MOD RTE 1")
		run(display, 10)
		lu.assertEquals(display:get_page(2), "ROUTE")
		lu.assertEquals(display:get_line(2, 1), "         MOD RTE 1       ")
		lu.assertEquals(display:get_line(2, 3), "KLSV                     ")
		lu.assertEquals(display:get_line(2, 13), "                   ERASE>")
		lu.assertTrue(display:get_exec_lamp(2))

		-- latched while another page is shown, released by an EXEC press
		indications[9] = route_indication("LEGS 1")
		run(display, 10)
		lu.assertTrue(display:get_exec_lamp(2))

		dev0.args[1187] = 1
		run(display, 1)
		dev0.args[1187] = 0
		run(display, 10)
		lu.assertFalse(display:get_exec_lamp(2))
	end)
end

function TestC130JCni:testDisplayReportsMissingModule()
	local saved_currentdir = lfs.currentdir
	lfs.currentdir = function()
		return "Scripts/DCS-BIOS/test/does-not-exist/"
	end
	local display = new_display({ [8] = test_page_indication("ABC") })
	local ok, err = pcall(run, display, 20)
	lfs.currentdir = saved_currentdir
	lu.assertTrue(ok, err)

	lu.assertEquals(display.schema_state, "failed")
	lu.assertStrContains(display:get_line(1, 6), "CNI LAYOUT UNAVAILABLE")
end

function TestC130JCni:testExecLamp()
	local lamp = CniExecLamp:new()
	lu.assertFalse(lamp:update("RTE 1", 0))
	lu.assertTrue(lamp:update("MOD RTE 1", 0))
	-- latched while another page is shown
	lu.assertTrue(lamp:update("LEGS 1", 0))
	-- released when the modified page comes back without its marker
	lu.assertFalse(lamp:update("ACT RTE 1", 0))

	lu.assertTrue(lamp:update("MOD RTE 1", 0))
	-- or by an EXEC press from anywhere
	lu.assertFalse(lamp:update("LEGS 1", 1))
end
