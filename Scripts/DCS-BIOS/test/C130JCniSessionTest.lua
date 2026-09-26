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

-- and of the route page, where WPT SEQ and WP TRANS are two decisions whose fields share a stem
local ROUTE = {
	id = 3,
	name = "ROUTE_GEN",
	slots = {
		slot(1, { name = "cni_title", ctrl = "rte_pg_title", fmt = { "%sRTE %d" }, anchor = "Center", line = 0, col = 13 }),
		slot(2, { value = " ORIGIN", line = 1, col = 0, small = true }),
		slot(3, { value = "WPT SEQ ", line = 7, col = 25, anchor = "Right", small = true }),
		slot(4, { ctrl = "route_auto_on", value = "AUTO", line = 8, col = 25, anchor = "Right", invert = true }),
		slot(5, { ctrl = "route_auto_off", value = "AUTO", line = 8, col = 25, anchor = "Right", small = true }),
		slot(6, { ctrl = "route_auto_on", value = "/", line = 8, col = 21, anchor = "Right" }),
		slot(7, { ctrl = "route_auto_off", value = "/", line = 8, col = 21, anchor = "Right" }),
		slot(8, { ctrl = "route_man_on", value = "MAN", line = 8, col = 20, anchor = "Right", invert = true }),
		slot(9, { ctrl = "route_man_off", value = "MAN", line = 8, col = 20, anchor = "Right", small = true }),
		slot(10, { value = "WP TRANS ", line = 9, col = 25, anchor = "Right", small = true }),
		slot(11, { ctrl = "route_pp_on", value = "P-P", line = 10, col = 25, anchor = "Right", invert = true }),
		slot(12, { ctrl = "route_pp_off", value = "P-P", line = 10, col = 25, anchor = "Right", small = true }),
		slot(13, { ctrl = "route_pp_on", value = "/", line = 10, col = 22, anchor = "Right" }),
		slot(14, { ctrl = "route_pp_off", value = "/", line = 10, col = 22, anchor = "Right" }),
		slot(15, { ctrl = "route_nom_on", value = "ROT", line = 10, col = 21, anchor = "Right", invert = true }),
		slot(16, { ctrl = "route_nom_off", value = "ROT", line = 10, col = 21, anchor = "Right", small = true }),
		slot(17, { ctrl = "route_nom_on", value = "/", line = 10, col = 18, anchor = "Right" }),
		slot(18, { ctrl = "route_nom_off", value = "/", line = 10, col = 18, anchor = "Right" }),
		slot(19, { ctrl = "route_cp_on", value = "CP", line = 10, col = 17, anchor = "Right", invert = true }),
		slot(20, { ctrl = "route_cp_off", value = "CP", line = 10, col = 17, anchor = "Right", small = true }),
		slot(21, { value = "<DEP/ARR", line = 10, col = 0 }),
		slot(22, { name = "cni_scratchpad", ctrl = "scratch", fmt = { "%s" }, line = 13, col = 0 }),
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
--- @param replace { [string]: string }? element names to use instead, by the name they replace
--- @return string
local function power_up(lit, session, replace)
	session = session or "A"
	local function el(name, on)
		local element = "{" .. session .. "-" .. name .. (on and "-LIT}" or "-PLAIN}")
		return replace and replace[element] or element
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

--- The route page with the given WPT SEQ and WP TRANS positions lit
--- @param seq string AUTO or MAN
--- @param trans string P-P, ROT or CP
--- @return string
local function route(seq, trans)
	local function el(name, on)
		return "{" .. name .. (on and "-LIT}" or "-PLAIN}")
	end
	return indication({
		{ "cni_title", "RTE 1" },
		{ "{ORIGIN}", " ORIGIN" },
		{ "{WPT-SEQ}", "WPT SEQ " },
		{ el("AUTO", seq == "AUTO"), "AUTO" },
		{ el("AUTO-SLASH", seq == "AUTO"), "/" },
		{ el("MAN", seq == "MAN"), "MAN" },
		{ "{WP-TRANS}", "WP TRANS " },
		{ el("PP", trans == "P-P"), "P-P" },
		{ el("PP-SLASH", trans == "P-P"), "/" },
		{ el("ROT", trans == "ROT"), "ROT" },
		{ el("ROT-SLASH", trans == "ROT"), "/" },
		{ el("CP", trans == "CP"), "CP" },
		{ "{DEP-ARR}", "<DEP/ARR" },
		{ "cni_scratchpad", "" },
	})
end

--- COMM TUNE U1 with the power toggle and the ADF/BTH/MN rotary drawn by the given elements
--- @param options { channel: string?, power: string?, adf_lit: boolean?, bth: string?, mn: string?, prefix: string? }
--- @return string
local function comm_tune(options)
	local power = options.power or "ON"
	local adf_lit = options.adf_lit
	local elements = {
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
	}
	-- another page drawing the same fields does so with elements of its own
	if options.prefix then
		for _, element in ipairs(elements) do
			if element[1] ~= "cni_title" and element[1] ~= "cni_scratchpad" then
				element[1] = "{" .. options.prefix .. "}" .. element[1]
			end
		end
	end
	return indication(elements)
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
		for start, word, stop in lines[line]:gmatch("()([%u%-]+)()") do
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

function TestC130JCniSession:testTwoDecisionsSharingAStemStayApart()
	local page = CniSchema.prepare_page(ROUTE)
	-- WPT SEQ has two positions only, WP TRANS two lines below is a rotary of its own
	lu.assertEquals(page.selectors, {
		{ key = "route@10", members = { "route_cp", "route_nom", "route_pp" } },
	})

	-- without the starting state WPT SEQ is taken to be in
	local map = CniSessionMap:new({})
	local frames = {
		{ "AUTO", "P-P" },
		{ "MAN", "P-P" },
		{ "MAN", "ROT" },
		{ "AUTO", "ROT" },
		{ "AUTO", "CP" },
		{ "MAN", "CP" },
		{ "MAN", "P-P" },
		{ "AUTO", "P-P" },
	}
	for _, frame in ipairs(frames) do
		-- a highlight is only ever drawn where the cockpit has one
		for _, word in ipairs(lit_words(map, page, route(frame[1], frame[2]))) do
			lu.assertTrue(word == frame[2], word .. " drawn lit with " .. frame[1] .. " and " .. frame[2] .. " selected")
		end
	end

	-- WP TRANS has been through its three positions and follows the cockpit, WPT SEQ cannot be told
	lu.assertEquals(lit_words(map, page, route("MAN", "ROT")), { "ROT" })
	lu.assertEquals(lit_words(map, page, route("AUTO", "CP")), { "CP" })
end

--- The lit WPT SEQ word of the route page, or nil for neither
local function wpt_seq(map, page, seq, trans)
	local lit = nil
	for _, word in ipairs(lit_words(map, page, route(seq, trans or "P-P"))) do
		if word == "AUTO" or word == "MAN" then
			lu.assertNil(lit, "AUTO and MAN drawn lit together")
			lit = word
		end
	end
	return lit
end

function TestC130JCniSession:testWptSeqStartsOnAutoAndFollowsEverySwitch()
	local page = CniSchema.prepare_page(ROUTE)
	local map = CniSessionMap:new()

	lu.assertEquals(wpt_seq(map, page, "AUTO"), "AUTO")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "MAN")
	lu.assertEquals(wpt_seq(map, page, "MAN", "ROT"), "MAN")
	lu.assertEquals(wpt_seq(map, page, "AUTO", "ROT"), "AUTO")
	lu.assertEquals(wpt_seq(map, page, "MAN", "CP"), "MAN")
end

function TestC130JCniSession:testSwapTurnsTheStartingPositionAround()
	local page = CniSchema.prepare_page(ROUTE)
	local map = CniSessionMap:new()

	-- this aircraft started on MAN, which the display cannot tell from AUTO
	lu.assertEquals(wpt_seq(map, page, "MAN"), "AUTO")

	map:swap("WPT_SEQ")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "MAN")
	lu.assertEquals(wpt_seq(map, page, "AUTO"), "AUTO")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "MAN")

	-- swapping again turns it back
	map:swap("WPT_SEQ")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "AUTO")

	-- a name that is no starting state changes nothing
	map:swap("NO_SUCH_TOGGLE")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "AUTO")
end

function TestC130JCniSession:testSwapBeforeTheToggleIsSeen()
	local page = CniSchema.prepare_page(ROUTE)
	local map = CniSessionMap:new()

	map:swap("WPT_SEQ")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "MAN")
	lu.assertEquals(wpt_seq(map, page, "AUTO"), "AUTO")
end

function TestC130JCniSession:testRebuiltPageStartsOverFromTheStartingPosition()
	local page = CniSchema.prepare_page(ROUTE)
	local map = CniSessionMap:new()
	lu.assertEquals(wpt_seq(map, page, "AUTO"), "AUTO")
	lu.assertEquals(wpt_seq(map, page, "MAN"), "MAN")

	-- the same page built anew: every element name changes, the aircraft starts over
	local rebuilt = route("AUTO", "P-P"):gsub("{", "{NEW-")
	local lit = lit_words(map, page, rebuilt)
	lu.assertEquals(lit, { "AUTO" })
end

function TestC130JCniSession:testPagesKeepWhatWasLearnedApart()
	local first = CniSchema.prepare_page(COMM_TUNE_U1)
	local second = CniSchema.prepare_page({ id = 4, name = "UHF1_OTHER", slots = COMM_TUNE_U1.slots })
	local map = CniSessionMap:new()

	-- the radio is off, which the first page proves while it prints the frequency the radio is on
	lu.assertEquals(lit_word(map, first, comm_tune({ power = "OFF" }), { { frequency = 243000, on = false } }), "OFF")

	-- the second page draws the same fields with elements of its own and proves nothing
	lu.assertNil(lit_word(map, second, comm_tune({ power = "OFF", prefix = "B", channel = "   /---.---" }), {}))
	lu.assertNil(lit_word(map, second, comm_tune({ power = "ON", prefix = "B", channel = "   /---.---" }), {}))

	-- and what the first page proved is still there when it comes back
	lu.assertEquals(lit_word(map, first, comm_tune({ power = "OFF", channel = "   /---.---" }), {}), "OFF")
end

function TestC130JCniSession:testAChangeThatIsNoTurnTeachesNothing()
	local page = CniSchema.prepare_page(POWER_UP)
	local map = CniSessionMap:new()
	lu.assertNil(lit_word(map, page, power_up("LAST")))

	-- only GPS changed element, which no turn of a rotary does
	lu.assertNil(lit_word(map, page, power_up("LAST", "A", { ["{A-GPS-PLAIN}"] = "{A-GPS-OTHER}" })))
	lu.assertNil(lit_word(map, page, power_up("LAST")))
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

function TestC130JCniSession:testDisplaySwapsWptSeqPerSeat()
	local indications = {}
	local display = CniDisplay:new({
		list_indication = function(id)
			return indications[id] or ""
		end,
		get_device = function()
			return nil
		end,
		load_pages = function()
			return { ROUTE }
		end,
	})
	local function run(ticks)
		for _ = 1, ticks do
			display:update(nil)
		end
	end
	-- line 9 holds WPT SEQ: MAN in columns 17-19, AUTO in columns 22-25
	local function wpt_seq_format(seat)
		local format = display:get_format(seat, 9)
		return format:sub(18, 20) .. " " .. format:sub(22, 25)
	end

	indications[8] = route("MAN", "P-P")
	indications[9] = route("MAN", "P-P")
	run(30)
	lu.assertEquals(display:get_line(1, 9), "                 MAN/AUTO")
	lu.assertEquals(wpt_seq_format(1), "111 2222")

	display:swap_starting_state(1, "WPT_SEQ")
	run(6)
	lu.assertEquals(wpt_seq_format(1), "222 1111")
	lu.assertEquals(wpt_seq_format(2), "111 2222")
end

function TestC130JCniSession:testModuleOffersTheSwapForEverySeat()
	local C_130J = require("Scripts.DCS-BIOS.lib.modules.aircraft_modules.C-130J")
	for _, prefix in ipairs({ "PLT", "CPLT", "AUG" }) do
		local swap = C_130J.inputProcessors[prefix .. "_CNI_WPT_SEQ_SWAP"]
		lu.assertNotNil(swap, prefix)
		swap("TOGGLE")
	end
end

-- a lone field switching between its two forms, like TACAN's REC
local TACAN = {
	id = 5,
	name = "TACAN1",
	slots = {
		slot(1, { name = "cni_title", value = "TACAN 1", anchor = "Center", line = 0, col = 13 }),
		slot(2, { value = "MODE ", line = 3, col = 25, anchor = "Right", small = true }),
		slot(3, { ctrl = "tac1_rec_on", value = "REC", line = 4, col = 25, anchor = "Right", invert = true }),
		slot(4, { ctrl = "tac1_rec_off", value = "REC", line = 4, col = 25, anchor = "Right" }),
		slot(5, { value = "<INDEX", line = 12, col = 0 }),
		slot(6, { name = "cni_scratchpad", ctrl = "scratch", fmt = { "%s" }, line = 13, col = 0 }),
	},
}

--- TACAN 1 with REC drawn by the given element
local function tacan(element)
	return indication({
		{ "cni_title", "TACAN 1" },
		{ "{MODE}", "MODE " },
		{ element, "REC" },
		{ "{INDEX}", "<INDEX" },
		{ "cni_scratchpad", "" },
	})
end

--- @param page CniPage
--- @param key string
--- @return CniToggle?
local function toggle_named(page, key)
	for _, toggle in ipairs(page.toggles) do
		if toggle.key == key then
			return toggle
		end
	end
	return nil
end

function TestC130JCniSession:testTogglesAreTiedToTheKeyBesideThem()
	local keys = {}
	for _, raw in ipairs({ ROUTE, POWER_UP, COMM_TUNE_U1, TACAN }) do
		for _, toggle in ipairs(CniSchema.prepare_page(raw).toggles) do
			keys[#keys + 1] = toggle.key .. " " .. table.concat(toggle.members, ",")
		end
	end
	lu.assertEquals(keys, {
		-- the positions in reading order
		"4R:route route_man,route_auto",
		"5R:route route_cp,route_nom,route_pp",
		"5L:power_up_align power_up_align_gps,power_up_align_last,power_up_align_ref",
		"1R:uhf1_power uhf1_power_off,uhf1_power_on",
		-- a rotary wrapping from the label line onto the key's own
		"3R:uhf1_adf uhf1_adf_adf,uhf1_adf_mn,uhf1_adf_bth",
		"2R:tac1 tac1_rec",
	})
end

function TestC130JCniSession:testShiftSetsATogglePositionAndSwitchesAreFollowed()
	local page = CniSchema.prepare_page(ROUTE)
	-- without the starting state WPT SEQ is taken to be in, so nothing is known of it
	local map = CniSessionMap:new({})
	local toggle = toggle_named(page, "4R:route")

	lu.assertNil(wpt_seq(map, page, "AUTO"))

	-- the crew says: the first position, then the next
	map:shift(page, toggle)
	lu.assertEquals(wpt_seq(map, page, "AUTO"), "MAN")
	map:shift(page, toggle)
	lu.assertEquals(wpt_seq(map, page, "AUTO"), "AUTO")

	-- every switch in the aircraft is followed from there
	lu.assertEquals(wpt_seq(map, page, "MAN"), "MAN")
	lu.assertEquals(wpt_seq(map, page, "AUTO", "ROT"), "AUTO")
end

function TestC130JCniSession:testShiftTurnsALoneFieldOver()
	local page = CniSchema.prepare_page(TACAN)
	local map = CniSessionMap:new({})
	local toggle = toggle_named(page, "2R:tac1")

	lu.assertNil(lit_word(map, page, tacan("{REC-A}")))
	map:shift(page, toggle)
	lu.assertEquals(lit_word(map, page, tacan("{REC-A}")), "REC")

	-- the aircraft switches it: the other form is drawn, and that one is the plain one
	lu.assertNil(lit_word(map, page, tacan("{REC-B}")))
	lu.assertEquals(lit_word(map, page, tacan("{REC-A}")), "REC")

	map:shift(page, toggle)
	lu.assertNil(lit_word(map, page, tacan("{REC-A}")))
end

--- A CNI-MU display reading the given pages, with the indications and defaults given
local function new_display(pages, indications, defaults)
	return CniDisplay:new({
		list_indication = function(id)
			return indications[id] or ""
		end,
		get_device = function()
			return nil
		end,
		load_pages = function()
			return pages
		end,
		defaults = defaults,
	})
end

local function run(display, ticks)
	for _ = 1, ticks do
		display:update(nil)
	end
end

--- The WP TRANS words drawn lit on the pilot's route page (line 11: CP, ROT, P-P)
local function wp_trans(display)
	local line, format = display:get_line(1, 11), display:get_format(1, 11)
	local lit = {}
	for start, word, stop in line:gmatch("()([%u%-]+)()") do
		if format:sub(start, stop - 1):match("^[23]+$") then
			lit[#lit + 1] = word
		end
	end
	return table.concat(lit, ",")
end

function TestC130JCniSession:testCorrectionIsKeptAsWhereTheToggleStarts()
	local HighlightDefaults = require("Scripts.DCS-BIOS.lib.modules.displays.HighlightDefaults")
	local defaults = HighlightDefaults:new()
	local indications = { [8] = route("AUTO", "ROT") }

	local display = new_display({ ROUTE }, indications, defaults)
	run(display, 30)
	lu.assertEquals(display:get_line(1, 11), "<DEP/ARR       CP/ROT/P-P")
	lu.assertEquals(wp_trans(display), "")

	-- R5: CP first, then ROT, which is where the aircraft is
	display:shift_highlight(1, 11)
	run(display, 6)
	lu.assertEquals(wp_trans(display), "CP")
	display:shift_highlight(1, 11)
	run(display, 6)
	lu.assertEquals(wp_trans(display), "ROT")

	-- nothing had switched it yet, so that is where it starts
	lu.assertEquals(defaults:section("cni").ROUTE_GEN["5R:route"], { route_cp = false, route_nom = true, route_pp = false })

	-- the next session takes it to start there, and follows it from there
	local next_session = new_display({ ROUTE }, indications, defaults)
	run(next_session, 30)
	lu.assertEquals(wp_trans(next_session), "ROT")
	indications[8] = route("AUTO", "CP")
	run(next_session, 6)
	lu.assertEquals(wp_trans(next_session), "CP")

	-- said after a switch, a position is no longer the one it starts in
	next_session:shift_highlight(1, 11)
	run(next_session, 6)
	lu.assertEquals(wp_trans(next_session), "ROT")
	lu.assertEquals(defaults:section("cni").ROUTE_GEN["5R:route"], { route_cp = false, route_nom = true, route_pp = false })

	-- a key with no toggle beside it changes nothing
	next_session:shift_highlight(1, 1)
	next_session:shift_highlight(1, 99)
	run(next_session, 6)
	lu.assertEquals(wp_trans(next_session), "ROT")
end

function TestC130JCniSession:testRememberedStartComesBeforeTheBuiltInOne()
	local HighlightDefaults = require("Scripts.DCS-BIOS.lib.modules.displays.HighlightDefaults")
	local defaults = HighlightDefaults:new()
	defaults:remember("cni", "ROUTE_GEN", "4R:route", { route_man = true, route_auto = false })

	local display = new_display({ ROUTE }, { [8] = route("MAN", "P-P") }, defaults)
	run(display, 30)
	-- line 9 holds WPT SEQ: MAN in columns 17-19, AUTO in columns 22-25
	local format = display:get_format(1, 9)
	lu.assertEquals(format:sub(18, 20) .. " " .. format:sub(22, 25), "222 1111")
end

function TestC130JCniSession:testDefaultsAreKeptInAFile()
	local HighlightDefaults = require("Scripts.DCS-BIOS.lib.modules.displays.HighlightDefaults")
	local path = os.tmpname()

	local defaults = HighlightDefaults:new({ file = path })
	defaults:remember("cni", "ROUTE_GEN", "5R:route", { route_cp = false, route_nom = true, route_pp = false })
	defaults:remember("amu_lo", "PFD", "2", 2)

	local again = HighlightDefaults:new({ file = path })
	lu.assertEquals(again:section("cni"), { ROUTE_GEN = { ["5R:route"] = { route_cp = false, route_nom = true, route_pp = false } } })
	lu.assertEquals(again:section("amu_lo"), { PFD = { ["2"] = 2 } })

	-- a file that is not a table of defaults, or tries to call anything, is left alone
	for _, text in ipairs({ "return 42", "not lua at all {", "return { cni = os.exit() }" }) do
		local file = io.open(path, "w")
		lu.assertNotNil(file)
		if file then
			file:write(text)
			file:close()
		end
		lu.assertEquals(HighlightDefaults:new({ file = path }):section("cni"), {})
	end
	os.remove(path)
end

function TestC130JCniSession:testModuleOffersTheCorrectionForEverySeat()
	local C_130J = require("Scripts.DCS-BIOS.lib.modules.aircraft_modules.C-130J")
	for _, prefix in ipairs({ "PLT", "CPLT", "AUG" }) do
		local shift = C_130J.inputProcessors[prefix .. "_CNI_SHIFT_HIGHLIGHT"]
		lu.assertNotNil(shift, prefix)
		shift("7")
		shift("not a key")
	end
end
