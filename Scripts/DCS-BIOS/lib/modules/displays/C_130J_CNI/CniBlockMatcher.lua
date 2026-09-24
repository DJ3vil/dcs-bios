module("CniBlockMatcher", package.seeall)

-- Pairs the blocks the sim emitted with the slots the page schema describes, so each block can
-- be given the position the indication does not carry. The schema holds every variant of every
-- field while the sim only sends what is visible, so the two sequences are aligned
-- (Needleman-Wunsch) with static text as landmarks that pin the alignment.
-- Lua port of CniBlockMatcher.cs of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

local CniFormat = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniFormat")

--- @class CniBlockMatcher
local CniBlockMatcher = {}

local SCORE_LITERAL_HIT = 4
local SCORE_CONTAINER = 3
local SCORE_DYNAMIC = 1
local SCORE_UNINFORMATIVE = -2 -- a slot accepting any text: filled only when nothing better fits
local SCORE_FORMAT_MISS = -2
local SCORE_UNSET_MISMATCH = -3 -- an empty field on a slot whose format carries punctuation
local SCORE_BANNER = 14 -- the route discontinuity banner on its own slot
local GAP_SLOT = -1 -- skipping a slot: a variant the sim did not draw
local GAP_BLOCK = -8 -- leaving a block unplaced
local GAP_EMPTY_BLOCK = -4 -- leaving a blank unplaced costs the screen nothing
local PENALTY_HIGHLIGHTED = -1 -- prefer the plain half of a pair on a tie
local FORBIDDEN = -1000000

local DIAGONAL = 0
local SKIP_SLOT = 1
local SKIP_BLOCK = 2

-- which texts the formats of a slot accept; most values stay the same from one update of a
-- page to the next, and many slots share their formats
local MAX_CACHED_FORMAT_RESULTS = 20000
local format_results = {}
local format_result_count = 0

--- @param slot CniSlot
--- @param value string
--- @return boolean
local function formats_accept(slot, value)
	local key = slot.format_key .. "\1" .. value
	local result = format_results[key]
	if result == nil then
		if format_result_count >= MAX_CACHED_FORMAT_RESULTS then
			format_results = {}
			format_result_count = 0
		end
		result = CniFormat.accepts_any(slot.formats, value)
		format_results[key] = result
		format_result_count = format_result_count + 1
	end
	return result
end

local function ends_with(s, suffix)
	return s ~= nil and #s >= #suffix and s:sub(-#suffix) == suffix
end

--- @param slot CniSlot?
--- @return boolean
local function is_marker(slot)
	return slot ~= nil and slot.line ~= nil and ends_with(slot.source, "_disc")
end

--- @param slot CniSlot
--- @return boolean
local function is_leg_name(slot)
	return ends_with(slot.source, "_name")
end

--- Whether the text is nothing but the module's way of writing an empty field
--- @param text string
--- @return boolean
local function is_unset(text)
	return #text > 0 and text:find("^[%-%] ]+$") ~= nil
end

--- @param block CniBlock
--- @return integer
local function gap(block)
	return block.v == "" and GAP_EMPTY_BLOCK or GAP_BLOCK
end

--- The two halves of a size pair: the ordinary field and the one drawn large (_ord), or a
--- soft key label built at both sizes (_sf)
--- @param a CniSlot
--- @param b CniSlot
--- @return boolean
local function same_cell(a, b)
	return a.line ~= nil and a.line == b.line and a.col == b.col and a.anchor == b.anchor and a.value == nil and b.value == nil and a.source ~= nil and (b.source == a.source .. "_ord" or b.source == a.source .. "_sf")
end

--- Drops the second of two dynamic slots that are one cell drawn at two sizes
--- @param slots CniSlot[]
--- @return CniSlot[]
local function one_per_cell(slots)
	local kept = {}
	for i, slot in ipairs(slots) do
		if not (i > 1 and same_cell(slots[i - 1], slot)) then
			kept[#kept + 1] = slot
		end
	end
	return kept
end

--- What it is worth to pair this block with this slot, before the table and route rules
--- @param block CniBlock
--- @param slot CniSlot
--- @return integer
local function pair_score(block, slot)
	local value = block.v
	local has_children = block.c ~= nil and #block.c > 0

	-- the title and the scratchpad are the only elements the sim names
	local role = 0
	if block.k == "cni_title" then
		role = 1
	elseif block.k == "cni_scratchpad" then
		role = 2
	end
	if role ~= 0 or slot.named_role ~= 0 then
		return role == slot.named_role and SCORE_LITERAL_HIT or FORBIDDEN
	end

	if slot.container then
		if has_children then
			return SCORE_CONTAINER
		end
		-- a toggle whose words are all hidden still draws its container, empty
		return value == "" and SCORE_DYNAMIC or FORBIDDEN
	end

	if has_children then
		return FORBIDDEN
	end

	if slot.value ~= nil then
		return value == slot.value and SCORE_LITERAL_HIT or FORBIDDEN
	end

	-- the route discontinuity banner goes on its marker slot and nowhere else
	local banner = value:find("DISCONTINUIT", 1, true) ~= nil
	local marker = ends_with(slot.source, "_disc")
	if banner or marker then
		return (banner and marker) and SCORE_BANNER or FORBIDDEN
	end

	if slot.formats and not formats_accept(slot, value) then
		return SCORE_FORMAT_MISS
	end

	if slot.format_weight > 0 then
		return is_unset(value) and SCORE_UNSET_MISMATCH or (SCORE_DYNAMIC + slot.format_weight)
	end

	return SCORE_UNINFORMATIVE
end

--- @param fit integer
--- @param slot CniSlot
--- @param selected { [string]: boolean }?
--- @param banners { [integer]: boolean }?
--- @return integer
local function score(fit, slot, selected, banners)
	if fit == FORBIDDEN then
		return fit
	end

	-- a leg the route is broken at draws only the banner and its name
	if banners and slot.line ~= nil and slot.value == nil and (banners[slot.line] or banners[slot.line - 1]) and not is_marker(slot) and not is_leg_name(slot) then
		return FORBIDDEN
	end

	local other = slot.counterpart
	if not other then
		return fit
	end

	-- a cell of the selected table column is drawn highlighted, so its plain half is not drawn
	if slot.column and selected and selected[slot.column] then
		if slot.invert or not other.invert then
			return fit
		end
		return FORBIDDEN
	end

	return slot.invert and (fit + PENALTY_HIGHLIGHTED) or fit
end

--- @param blocks CniBlock[]
--- @param slots CniSlot[]
--- @param fits integer[] pair scores, index (i - 1) * m + j
--- @param selected { [string]: boolean }?
--- @param banners { [integer]: boolean }?
--- @return (CniSlot|nil)[]
local function align_pass(blocks, slots, fits, selected, banners)
	local n, m = #blocks, #slots
	local result = {}
	local width = m + 1

	-- score of the best alignment of the first i blocks against the first j slots; ties are
	-- broken on the smaller total of slot indices used, keeping a value on the earlier slot
	local best, used, from = {}, {}, {}
	best[0] = 0
	used[0] = 0
	for j = 1, m do
		best[j] = best[j - 1] + GAP_SLOT
		used[j] = 0
		from[j] = SKIP_SLOT
	end
	for i = 1, n do
		local row = i * width
		best[row] = best[row - width] + gap(blocks[i])
		used[row] = 0
		from[row] = SKIP_BLOCK
	end

	for i = 1, n do
		local row = i * width
		local up = row - width
		local block_gap = gap(blocks[i])
		local fit_row = (i - 1) * m
		for j = 1, m do
			local s = score(fits[fit_row + j], slots[j], selected, banners)
			local diagonal = s == FORBIDDEN and FORBIDDEN or (best[up + j - 1] + s)
			local skip_slot = best[row + j - 1] + GAP_SLOT
			local skip_block = best[up + j] + block_gap

			local top = math.max(diagonal, skip_slot, skip_block)

			local diagonal_used = used[up + j - 1] + j
			local skip_slot_used = used[row + j - 1]
			local skip_block_used = used[up + j]

			if diagonal == top and (skip_slot ~= top or diagonal_used <= skip_slot_used) and (skip_block ~= top or diagonal_used <= skip_block_used) then
				best[row + j] = diagonal
				used[row + j] = diagonal_used
				from[row + j] = DIAGONAL
			elseif skip_slot == top and (skip_block ~= top or skip_slot_used <= skip_block_used) then
				best[row + j] = skip_slot
				used[row + j] = skip_slot_used
				from[row + j] = SKIP_SLOT
			else
				best[row + j] = skip_block
				used[row + j] = skip_block_used
				from[row + j] = SKIP_BLOCK
			end
		end
	end

	local x, y = n, m
	while x > 0 and y > 0 do
		local step = from[x * width + y]
		if step == DIAGONAL then
			result[x] = slots[y]
			x = x - 1
			y = y - 1
		elseif step == SKIP_SLOT then
			y = y - 1
		else
			x = x - 1
		end
	end

	return result
end

--- Returns, for each block, the slot it was matched to (nil where it was left unplaced).
--- A second pass settles the selected column of a table and the lines of a broken route leg
--- once the first pass has found them.
--- @param blocks CniBlock[] in document order
--- @param page_slots CniSlot[]
--- @return (CniSlot|nil)[]
function CniBlockMatcher.align(blocks, page_slots)
	if #blocks == 0 or #page_slots == 0 then
		return {}
	end

	local slots = one_per_cell(page_slots)
	local m = #slots

	local fits = {}
	for i, block in ipairs(blocks) do
		local offset = (i - 1) * m
		for j, slot in ipairs(slots) do
			fits[offset + j] = pair_score(block, slot)
		end
	end

	local first = align_pass(blocks, slots, fits, nil, nil)

	local selected, banners = nil, nil
	for i = 1, #blocks do
		local slot = first[i]
		if slot then
			if slot.invert and slot.column then
				selected = selected or {}
				selected[slot.column] = true
			end
			if is_marker(slot) then
				banners = banners or {}
				banners[slot.line] = true
			end
		end
	end

	if not selected and not banners then
		return first
	end

	return align_pass(blocks, slots, fits, selected or {}, banners or {})
end

return CniBlockMatcher
