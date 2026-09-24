local CniBlockMatcher = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniBlockMatcher")
local CniDisplay = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniDisplay")
local CniGrid = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniGrid")
local CniIndication = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniIndication")
local CniSchema = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchema")
local CniSessionMap = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSessionMap")
local CniVariants = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniVariants")
local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestC130JCniSession
TestC130JCniSession = {}

local SPLIT = "-----------------------------------------"

local function slot(n, fields)
	fields.n = n
	fields.kind = fields.kind or "ceStringPoly"
	fields.anchor = fields.anchor or "Left"
	return fields
end

-- the parts of the module's POWER UP page that matter here, as the extractor records them
local POWER_UP = {
	id = 1,
	name = "POWER_UP",
	slots = {
		slot(1, { name = "cni_title", value = "POWER UP", anchor = "Center", line = 0, col = 13 }),
		slot(2, { value = " NAV DB", line = 1, col = 0, small = true }),
		slot(3, { value = "GLOBAL", line = 2, col = 0, small = true }),
		slot(4, { value = " ALIGN POS", line = 6, col = 0, small = true }),
		slot(5, { ctrl = "power_up_align_gps_on", value = "GPS", line = 10, col = 0, invert = true }),
		slot(6, { ctrl = "power_up_align_gps_off", value = "GPS", line = 10, col = 0, small = true }),
		slot(7, { ctrl = "power_up_align_gps_on", value = "/", line = 10, col = 3 }),
		slot(8, { ctrl = "power_up_align_gps_off", value = "/", line = 10, col = 3 }),
		slot(9, { ctrl = "power_up_align_last_on", value = "LAST", line = 10, col = 4, invert = true }),
		slot(10, { ctrl = "power_up_align_last_off", value = "LAST", line = 10, col = 4, small = true }),
		slot(11, { ctrl = "power_up_align_last_on", value = "/", line = 10, col = 8 }),
		slot(12, { ctrl = "power_up_align_last_off", value = "/", line = 10, col = 8 }),
		slot(13, { ctrl = "power_up_align_ref_on", value = "REF", line = 10, col = 9, invert = true }),
		slot(14, { ctrl = "power_up_align_ref_off", value = "REF", line = 10, col = 9, small = true }),
		slot(15, { value = "<DATA XFR", line = 12, col = 0 }),
		slot(16, { value = "ROUTE 1>", line = 12, col = 25, anchor = "Right" }),
		slot(17, { name = "cni_scratchpad", ctrl = "scratch", fmt = { "%s" }, line = 13, col = 0 }),
	},
}

-- and of COMM TUNE U1: the radio's power toggle and its ADF/BTH/MN rotary
local COMM_TUNE_U1 = {
	id = 2,
	name = "UHF1",
	slots = {
		slot(1, { name = "cni_title", value = "COMM TUNE U1", anchor = "Center", line = 0, col = 11 }),
		slot(2, { value = "IDENT", line = 1, col = 0, small = true }),
		slot(3, { ctrl = "uhf1_chan", fmt = { "%3d/%s", "   /%s" }, line = 2, col = 5 }),
		slot(4, { value = "PWR ", line = 1, col = 25, anchor = "Right", small = true }),
		slot(5, { ctrl = "uhf1_power_on_on", value = "ON", line = 2, col = 25, anchor = "Right", invert = true }),
		slot(6, { ctrl = "uhf1_power_on_off", value = "ON", line = 2, col = 25, anchor = "Right", small = true }),
		slot(7, { ctrl = "uhf1_power_on_on", value = "/", line = 2, col = 23, anchor = "Right" }),
		slot(8, { ctrl = "uhf1_power_on_off", value = "/", line = 2, col = 23, anchor = "Right" }),
		slot(9, { ctrl = "uhf1_power_off_on", value = "OFF", line = 2, col = 22, anchor = "Right", invert = true }),
		slot(10, { ctrl = "uhf1_power_off_off", value = "OFF", line = 2, col = 22, anchor = "Right", small = true }),
		slot(11, { ctrl = "uhf1_adf_adf_off", value = "ADF/ ", line = 5, col = 25, anchor = "Right", small = true }),
		slot(12, { ctrl = "uhf1_adf_adf_on", value = "ADF", line = 5, col = 23, anchor = "Right", invert = true }),
		slot(13, { value = "/ ", line = 5, col = 25, anchor = "Right" }),
		slot(14, { ctrl = "uhf1_adf_bth_on", value = "BTH", line = 6, col = 25, anchor = "Right", invert = true }),
		slot(15, { ctrl = "uhf1_adf_bth_off", value = "BTH", line = 6, col = 25, anchor = "Right", small = true }),
		slot(16, { ctrl = "uhf1_adf_bth_on", value = "/", line = 6, col = 22, anchor = "Right" }),
		slot(17, { ctrl = "uhf1_adf_bth_off", value = "/", line = 6, col = 22, anchor = "Right" }),
		slot(18, { ctrl = "uhf1_adf_mn_on", value = "MN", line = 6, col = 21, anchor = "Right", invert = true }),
		slot(19, { ctrl = "uhf1_adf_mn_off", value = "MN", line = 6, col = 21, anchor = "Right", small = true }),
		slot(20, { value = "<COMM INDEX", line = 12, col = 0 }),
		slot(21, { name = "cni_scratchpad", ctrl = "scratch", fmt = { "%s" }, line = 13, col = 0 }),
	},
}

--- @param elements string[][] name and text of every element, in the order the sim sends them
--- @return string
local function indication(elements)
	local parts = {}
	for i, element in ipairs(elements) do
		parts[i] = SPLIT .. "\n" .. element[1] .. "\n" .. element[2]
	end
	return table.concat(parts, "\n") .. "\n"
end

--- POWER UP with the given alignment source lit. Every element of a position follows its state,
--- the slash beside the word included, and a session tag stands for the element names the sim
--- generates anew whenever it builds the page
--- @param lit string GPS, LAST or REF
--- @param session string?
--- @return string
local function power_up(lit, session)
	session = session or "A"
	local function el(name, on)
		return "{" .. session .. "-" .. name .. (on and "-LIT}" or "-PLAIN}")
	end
	local function fixed(name)
		return "{" .. session .. "-" .. name .. "}"
	end
	return indication({
		{ "cni_title", "POWER UP" },
		{ fixed("NAV-DB"), " NAV DB" },
		{ fixed("GLOBAL"), "GLOBAL" },
		{ fixed("ALIGN-POS"), " ALIGN POS" },
		{ el("GPS", lit == "GPS"), "GPS" },
		{ el("GPS-SLASH", lit == "GPS"), "/" },
		{ el("LAST", lit == "LAST"), "LAST" },
		{ el("LAST-SLASH", lit == "LAST"), "/" },
		{ el("REF", lit == "REF"), "REF" },
		{ fixed("DATA-XFR"), "<DATA XFR" },
		{ fixed("ROUTE"), "ROUTE 1>" },
		{ "cni_scratchpad", "" },
	})
end

--- COMM TUNE U1 with the power toggle and the ADF/BTH/MN rotary drawn by the given elements
--- @param options { channel: string?, power: string?, adf_lit: boolean?, bth: string?, mn: string? }
--- @return string
local function comm_tune(options)
	local power = options.power or "ON"
	local adf_lit = options.adf_lit
	return indication({
		{ "cni_title", "COMM TUNE U1" },
		{ "{IDENT}", "IDENT" },
		{ "{CHAN}", options.channel or "  1/243.000R" },
		{ "{PWR}", "PWR " },
		{ "{ON-" .. (power == "ON" and "LIT" or "PLAIN") .. "}", "ON" },
		{ "{ON-SLASH-" .. (power == "ON" and "LIT" or "PLAIN") .. "}", "/" },
		{ "{OFF-" .. (power == "OFF" and "LIT" or "PLAIN") .. "}", "OFF" },
		{ adf_lit and "{ADF-LIT}" or "{ADF-PLAIN}", adf_lit and "ADF" or "ADF/ " },
		{ "{ADF-SLASH}", "/ " },
		{ options.bth or "{BTH-PLAIN}", "BTH" },
		{ (options.bth or "{BTH-PLAIN}") .. "-SLASH", "/" },
		{ options.mn or "{MN-PLAIN}", "MN" },
		{ "{COMM-INDEX}", "<COMM INDEX" },
		{ "cni_scratchpad", "" },
	})
end

--- Renders a page and returns the words drawn highlighted
--- @param map CniSessionMap?
--- @param page CniPage
--- @param raw string
--- @param radios CniRadio[]?
--- @return string[]
local function lit_words(map, page, raw, radios)
	local flat = CniIndication.flatten((CniIndication.parse(raw)))
	local matched = CniBlockMatcher.align(flat, page.slots)
	CniVariants.apply(matched, page, flat, radios, nil, map)
	local lines, formats = CniGrid.render(flat, matched)

	local words = {}
	for line = 1, CniGrid.LINES do
		for start, word, stop in lines[line]:gmatch("()(%u+)()") do
			if formats[line]:sub(start, stop - 1):match("^[23]+$") then
				words[#words + 1] = word
			end
		end
	end
	return words
end

local function lit_word(map, page, raw, radios)
	return lit_words(map, page, raw, radios)[1]
end

function TestC130JCniSession:testAlignmentRotaryIsASelector()
	local page = CniSchema.prepare_page(POWER_UP)
	lu.assertEquals(page.selectors, {
		{ key = "power_up_align", members = { "power_up_align_gps", "power_up_align_last", "power_up_align_ref" } },
	})

	-- the power toggle has two positions only, too few to reason from
	local comm_tune_page = CniSchema.prepare_page(COMM_TUNE_U1)
	lu.assertEquals(comm_tune_page.selectors, {
		{ key = "uhf1_adf", members = { "uhf1_adf_adf", "uhf1_adf_bth", "uhf1_adf_mn" } },
	})
end

function TestC130JCniSession:testTwoTurnsSettleTheRotary()
	local page = CniSchema.prepare_page(POWER_UP)
	local map = CniSessionMap:new()

	-- nothing is known of a rotary that has not moved
	lu.assertNil(lit_word(map, page, power_up("LAST")))
	-- first turn: GPS held, so it is not the lit one on either side of the turn
	lu.assertNil(lit_word(map, page, power_up("REF")))
	-- second turn: LAST held, so REF was lit before and GPS is now
	lu.assertEquals(lit_word(map, page, power_up("GPS")), "GPS")

	-- and what was learned holds when the crew turns back
	lu.assertEquals(lit_word(map, page, power_up("REF")), "REF")
	lu.assertEquals(lit_word(map, page, power_up("LAST")), "LAST")
	lu.assertEquals(lit_word(map, page, power_up("LAST")), "LAST")
end

function TestC130JCniSession:testWithoutMapNothingIsLit()
	local page = CniSchema.prepare_page(POWER_UP)
	for _, lit in ipairs({ "LAST", "REF", "GPS", "REF" }) do
		lu.assertNil(lit_word(nil, page, power_up(lit)))
	end
end

function TestC130JCniSession:testNeverLightsTwoPositions()
	local page = CniSchema.prepare_page(POWER_UP)
	local map = CniSessionMap:new()
	for _, lit in ipairs({ "LAST", "REF", "GPS", "LAST", "GPS", "REF", "REF", "LAST" }) do
		lu.assertTrue(#lit_words(map, page, power_up(lit)) <= 1)
	end
end

function TestC130JCniSession:testForgetsARebuiltPage()
	local page = CniSchema.prepare_page(POWER_UP)
	local map = CniSessionMap:new()
	lit_word(map, page, power_up("LAST"))
	lit_word(map, page, power_up("REF"))
	lu.assertEquals(lit_word(map, page, power_up("GPS")), "GPS")

	-- every element name is new, so nothing learned about the old ones applies
	lu.assertNil(lit_word(map, page, power_up("GPS", "B")))
	lu.assertNil(lit_word(map, page, power_up("LAST", "B")))

	-- until two turns have settled the new elements too
	lu.assertEquals(lit_word(map, page, power_up("REF", "B")), "REF")
	lu.assertEquals(lit_word(map, page, power_up("GPS", "B")), "GPS")
end

function TestC130JCniSession:testRadioPowerOutlivesTheFrameThatProvedIt()
	local page = CniSchema.prepare_page(COMM_TUNE_U1)
	local map = CniSessionMap:new()
	local radios = { { frequency = 243000, on = true } }

	lu.assertEquals(lit_word(map, page, comm_tune({}), radios), "ON")

	-- the same elements behind PWR, and no frequency a radio could be paired on
	lu.assertEquals(lit_word(map, page, comm_tune({ channel = "   /---.---" }), {}), "ON")

	-- other elements behind PWR: a field draws one of two forms and no more
	lu.assertEquals(lit_word(map, page, comm_tune({ channel = "   /---.---", power = "OFF" }), {}), "OFF")

	-- nothing carries over to a map that saw none of it
	lu.assertNil(lit_word(CniSessionMap:new(), page, comm_tune({ channel = "   /---.---" }), {}))
end

function TestC130JCniSession:testTextEvidenceSettlesTheMembersBesideIt()
	local page = CniSchema.prepare_page(COMM_TUNE_U1)
	local map = CniSessionMap:new()
	local radios = { { frequency = 243000, on = true } }

	-- ADF spells itself "ADF/ " unless it is the selected one, which also says MN and BTH are not
	lu.assertEquals(lit_words(map, page, comm_tune({ adf_lit = true, bth = "{BTH-A}", mn = "{MN-A}" }), radios), { "ON", "ADF" })

	-- so the first turn away from ADF already says which of the two it went to
	lu.assertEquals(lit_words(map, page, comm_tune({ adf_lit = false, bth = "{BTH-B}", mn = "{MN-A}" }), radios), { "ON", "BTH" })
	lu.assertEquals(lit_words(map, page, comm_tune({ adf_lit = false, bth = "{BTH-A}", mn = "{MN-B}" }), radios), { "ON", "MN" })
end

function TestC130JCniSession:testDisplayLearnsPerSeat()
	local indications = {}
	local display = CniDisplay:new({
		list_indication = function(id)
			return indications[id] or ""
		end,
		get_device = function()
			return nil
		end,
		load_pages = function()
			return { POWER_UP }
		end,
	})
	local function run(ticks)
		for _ = 1, ticks do
			display:update(nil)
		end
	end
	local function alignment(seat)
		return display:get_format(seat, 11):sub(1, 12)
	end

	indications[8] = power_up("LAST", "PILOT")
	indications[9] = power_up("GPS", "COPILOT")
	run(30)
	lu.assertEquals(display.schema_state, "ready")
	lu.assertEquals(display:get_line(1, 11), "GPS/LAST/REF             ")
	lu.assertEquals(alignment(1), "111011110111")

	-- the pilot turns the rotary twice
	indications[8] = power_up("REF", "PILOT")
	run(6)
	indications[8] = power_up("GPS", "PILOT")
	run(6)
	lu.assertEquals(alignment(1), "222011110111")

	-- the copilot's CNI-MU draws with elements of its own, and nothing was learned about them
	lu.assertEquals(alignment(2), "111011110111")
end
