local CniBlockMatcher = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniBlockMatcher")
local CniGrid = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniGrid")
local CniIndication = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniIndication")
local CniSchema = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchema")
local lu = require("Scripts.DCS-BIOS.test.ext.luaunit")

--- @class TestC130JCniMatcher
TestC130JCniMatcher = {}

local SPLIT = "-----------------------------------------"

local function slot(n, fields)
	fields.n = n
	fields.kind = fields.kind or "ceStringPoly"
	fields.anchor = fields.anchor or "Left"
	return fields
end

--- The slots of one leg of the LEGS page, as the extractor records them: the small line above the
--- leg's key and the large one beside it
--- @param slots CniRawSlot[]
--- @param line integer the large line
local function leg(slots, line)
	local function add(fields)
		slots[#slots + 1] = slot(#slots + 1, fields)
	end
	add({ ctrl = "legs_bearing", fmt = { "%03.f^" }, line = line - 1, col = 7, small = true })
	add({ ctrl = "legs_dist", fmt = { "%s" }, line = line - 1, col = 18, anchor = "Right", small = true })
	add({ ctrl = "legs_eta", fmt = { "%02d%02d:%02d" }, line = line - 1, col = 25, anchor = "Right", small = true })
	add({ ctrl = "legs_name", fmt = { "%s" }, line = line, col = 0 })
	add({ ctrl = "legs_disc", fmt = { "%s" }, line = line - 1, col = 13, anchor = "Center", small = true })
	add({ ctrl = "legs_via", fmt = { "%s" }, line = line - 1, col = 0, small = true })
	add({ ctrl = "legs_speed", fmt = { "%03.f/", "%03.f%s/" }, line = line, col = 19, anchor = "Right", small = true })
	add({ ctrl = "legs_speed_ord", fmt = { "%03.f/", "%03.f%s/" }, line = line, col = 19, anchor = "Right" })
	add({ ctrl = "legs_alt", fmt = { "%05.f%s", "FL%03.f%s" }, line = line, col = 25, anchor = "Right", small = true })
	add({ ctrl = "legs_alt_ord", fmt = { "%05.f%s", "FL%03.f%s" }, line = line, col = 25, anchor = "Right" })
end

--- The parts of the module's LEGS page that matter here: the title, two legs, and the bottom line
--- @return CniPage
local function legs_page()
	local slots = {
		slot(1, { name = "cni_title", ctrl = "leg_pg_title", fmt = { "%sLEGS %d" }, anchor = "Center", line = 0, col = 13 }),
		slot(2, { ctrl = "leg_progress_pages", fmt = { "%0.f/%0.f" }, line = 0, col = 25, anchor = "Right", small = true }),
	}
	leg(slots, 2)
	leg(slots, 4)
	slots[#slots + 1] = slot(#slots + 1, { value = "-------------------------", line = 11, col = 13, anchor = "Center" })
	slots[#slots + 1] = slot(#slots + 1, { ctrl = "legs_route_num", fmt = { "ROUTE %d>" }, line = 12, col = 25, anchor = "Right" })
	slots[#slots + 1] = slot(#slots + 1, { ctrl = "legs_progress_erase", fmt = { "%s" }, line = 12, col = 0 })
	slots[#slots + 1] = slot(#slots + 1, { name = "cni_scratchpad", ctrl = "scratch", fmt = { "%s" }, line = 13, col = 0 })
	return CniSchema.prepare_page({ id = 1, name = "LEGS_PROGRESS", slots = slots })
end

--- @param texts string[] the text of every element in the order the sim sends them, the title and
--- the scratchpad included
--- @return string[] the lines drawn
local function render(texts)
	local parts = {}
	for i, text in ipairs(texts) do
		local key = "{E" .. i .. "}"
		if i == 1 then
			key = "cni_title"
		elseif i == #texts then
			key = "cni_scratchpad"
		end
		parts[i] = SPLIT .. "\n" .. key .. "\n" .. text
	end
	local flat = CniIndication.flatten((CniIndication.parse(table.concat(parts, "\n") .. "\n")))
	local lines = CniGrid.render(flat, CniBlockMatcher.align(flat, legs_page().slots))
	return lines
end

--- @param count integer
--- @return string[]
local function blanks(count)
	local out = {}
	for i = 1, count do
		out[i] = ""
	end
	return out
end

--- @param ... string[]
--- @return string[]
local function joined(...)
	local out = {}
	for _, part in ipairs({ ... }) do
		for _, text in ipairs(part) do
			out[#out + 1] = text
		end
	end
	return out
end

local BOTTOM = { "-------------------------", "ROUTE 1>", "<PROGRESS", "" }

function TestC130JCniMatcher:testAWaypointNotYetEnteredIsTheLegsName()
	-- the second page of a route with nothing in it: the first leg draws its name as dashes, every
	-- other field of it blank, and the second leg nothing but blanks
	local lines = render(joined({ "LEGS 1", "2/2" }, { "", "", "-----", "", "", "", "" }, blanks(7), BOTTOM))

	lu.assertEquals(lines[2], string.rep(" ", 25))
	lu.assertEquals(lines[3], "-----                    ")
end

function TestC130JCniMatcher:testTheEndOfARouteIsTheLegsName()
	-- a leg with everything filled in, then the one after the last waypoint, which draws more
	-- blanks than a leg has cells and its name as dashes
	local lines = render(joined({ "LEGS 1", "2/2" }, { "101^", "0.5NM ", "0000:07", "RW31", "DIR", "210/", "01574" }, { "", "", "", "-----", "", "", "", "", "" }, BOTTOM))

	-- the degree sign is drawn with a glyph of its own
	lu.assertEquals(lines[2]:gsub("[\128-\255]", "^"), "DIR    101^ 0.5NM 0000:07")
	lu.assertEquals(lines[3], "RW31           210/ 01574")
	lu.assertEquals(lines[4], string.rep(" ", 25))
	lu.assertEquals(lines[5], "-----                    ")
end
