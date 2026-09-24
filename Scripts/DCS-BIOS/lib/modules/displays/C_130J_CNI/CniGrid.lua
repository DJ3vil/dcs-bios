module("CniGrid", package.seeall)

-- Lays the matched blocks of a CNI-MU page onto a 25x14 character grid, keeping text size and
-- highlight per cell. Lua port of CniGrid.cs of WCtrlDcsBiosBridge, see
-- LICENSE-WCtrlDcsBiosBridge.txt.

local CniSchema = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchema")

--- @class CniGrid
local CniGrid = {}

CniGrid.COLUMNS = 25
CniGrid.LINES = 14

local SPACE = " "
local UNSET_ORIGIN = -1000000

-- the CNI font repurposes "^" as the degree sign; "]" (an empty entry box) is passed through
local DEGREE = string.char(0xB0)
local UTF8_REPLACEMENTS = {
	["\226\128\148"] = "-", -- em dash, used for the rules of the alternate route pages
	["\194\176"] = DEGREE,
}

--- Translates the characters the CNI font repurposes and reduces text to one byte per cell
--- @param raw string?
--- @return string
function CniGrid.map_glyphs(raw)
	if not raw or raw == "" then
		return ""
	end

	local text = raw:gsub("[\194-\244][\128-\191]+", function(sequence)
		return UTF8_REPLACEMENTS[sequence] or "?"
	end)
	text = text:gsub("%^", DEGREE)
	return text
end

--- Where a run of text begins, given its anchor and the column it is anchored on
--- @param anchor integer
--- @param origin integer
--- @param length integer
--- @return integer
function CniGrid.start_column(anchor, origin, length)
	if anchor == CniSchema.ANCHOR_RIGHT then
		return origin - length
	elseif anchor == CniSchema.ANCHOR_CENTER then
		return origin - math.floor(length / 2)
	end
	return origin
end

--- Free for this element: empty, or holding text drawn from the same anchor (a field the sim
--- deliberately draws over another)
local function is_free(grid, origins, start, length, origin)
	for i = 0, length - 1 do
		local col = start + i
		if col >= 1 and col <= CniGrid.COLUMNS and grid[col] ~= SPACE and origins[col] ~= origin then
			return false
		end
	end
	return true
end

--- Nudges a run clear of text already on the line: a page can mix fonts on one line and place
--- labels at the running width of the ones before them, which a monospaced grid cannot express
local function reflow(grid, origins, start, length, anchor, origin)
	if is_free(grid, origins, start, length, origin) then
		return start
	end

	local step = anchor == CniSchema.ANCHOR_RIGHT and -1 or 1
	for shift = 1, CniGrid.COLUMNS - 1 do
		local candidate = start + shift * step
		if candidate < 1 or candidate + length - 1 > CniGrid.COLUMNS then
			break
		end
		if is_free(grid, origins, candidate, length, origin) then
			return candidate
		end
	end

	return start
end

--- @param row table
--- @param slot CniSlot
--- @param text string
local function place(row, slot, text)
	local origin = slot.col
	local length = #text

	-- columns are 1-based here, the schema's 0-based
	local start = CniGrid.start_column(slot.anchor, origin, length) + 1
	start = reflow(row.chars, row.origins, start, length, slot.anchor, origin)

	for i = 1, length do
		local col = start + i - 1
		if col >= 1 and col <= CniGrid.COLUMNS then
			local ch = text:sub(i, i)
			-- a space never rubs out what is already there
			if not (ch == SPACE and row.chars[col] ~= SPACE) then
				row.chars[col] = ch
				row.small[col] = slot.small
				row.invert[col] = slot.invert
				row.origins[col] = origin
			end
		end
	end
end

--- Renders a page
--- @param blocks CniBlock[] in document order
--- @param matched (CniSlot|nil)[] the slot of each block
--- @return string[] lines 14 lines of 25 characters
--- @return string[] formats per character 0 large, 1 small, 2 large inverted, 3 small inverted
function CniGrid.render(blocks, matched)
	local rows = {}
	for l = 0, CniGrid.LINES - 1 do
		local row = { chars = {}, small = {}, invert = {}, origins = {} }
		for c = 1, CniGrid.COLUMNS do
			row.chars[c] = SPACE
			row.small[c] = false
			row.invert[c] = false
			row.origins[c] = UNSET_ORIGIN
		end
		rows[l] = row
	end

	for i = 1, #blocks do
		local slot = matched[i]
		if slot and CniSchema.is_placeable(slot) and slot.line < CniGrid.LINES then
			local text = CniGrid.map_glyphs(blocks[i].v)
			if text ~= "" then
				place(rows[slot.line], slot, text)
			end
		end
	end

	local lines, formats = {}, {}
	for l = 0, CniGrid.LINES - 1 do
		local row = rows[l]
		local format = {}
		for c = 1, CniGrid.COLUMNS do
			-- a blank belongs to a run only inside inverted text, whose background covers it
			if row.chars[c] ~= SPACE or row.invert[c] then
				format[c] = (row.small[c] and 1 or 0) + (row.invert[c] and 2 or 0)
			else
				format[c] = 0
			end
		end
		lines[l + 1] = table.concat(row.chars)
		formats[l + 1] = table.concat(format)
	end

	return lines, formats
end

return CniGrid
