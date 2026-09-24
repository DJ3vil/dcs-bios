module("CniSchema", package.seeall)

-- Turns the pages recorded by CniSchemaExtractor into the form the page resolver and the block
-- matcher work with. Lua port of slim.py and CniPageSchema.cs of WCtrlDcsBiosBridge, see
-- LICENSE-WCtrlDcsBiosBridge.txt.

local CniFormat = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniFormat")

--- @class CniRawSlot one element as the page script builds it, in Add() order
--- @field n integer
--- @field kind string?
--- @field name string?
--- @field value string?
--- @field fmt string[]?
--- @field ctrl string?
--- @field anchor string? Left, Center or Right
--- @field line integer?
--- @field lineErr number?
--- @field col integer?
--- @field small boolean?
--- @field invert boolean?
--- @field parent string?

--- @class CniRawPage
--- @field id integer
--- @field name string
--- @field slots CniRawSlot[]

--- @class CniSlot
--- @field n integer position in Add() order, 1-based
--- @field anchor integer 0 left, 1 center, 2 right
--- @field line integer?
--- @field col integer?
--- @field value string? static text, the landmarks of a page
--- @field formats CniFormatToken[][]?
--- @field format_sources string[]?
--- @field format_key string
--- @field format_weight integer
--- @field small boolean
--- @field invert boolean
--- @field container boolean
--- @field off_grid boolean
--- @field named_role integer 1 for the title, 2 for the scratchpad
--- @field controller string? the field of a two-state element, without its state tail
--- @field selected boolean whether this is the form drawn when its field is selected
--- @field source string? controller of an element drawn in a single form
--- @field counterpart CniSlot? the same element in its other state
--- @field two_state boolean whether the field is built in two states
--- @field column string? the table column the slot belongs to

--- @class CniSelector a rotary: fields of one page of which exactly one is selected
--- @field key string the stem the member fields are named off, e.g. power_up_align
--- @field members string[] the member fields, sorted

--- @class CniPage
--- @field id integer
--- @field name string
--- @field title string?
--- @field title_formats CniFormatToken[][]?
--- @field counter string?
--- @field slots CniSlot[] in indication order
--- @field landmarks string[] distinct static values
--- @field selectors CniSelector[]

--- @class CniSchema
local CniSchema = {}

CniSchema.ANCHOR_LEFT = 0
CniSchema.ANCHOR_CENTER = 1
CniSchema.ANCHOR_RIGHT = 2

local ANCHORS = { Left = CniSchema.ANCHOR_LEFT, Center = CniSchema.ANCHOR_CENTER, Right = CniSchema.ANCHOR_RIGHT }

local STATES = { on = true, off = true, out = true }
local SEATS = { [""] = true, _cp = true, _p = true }

--- The field a controller drives and whether it names the selected state of it, e.g.
--- uhf1_power_on_on is the selected form of uhf1_power_on and nav_ctrl_1_gps1_sol_off_cp the
--- unselected form of nav_ctrl_1_gps1_sol_cp
--- @param ctrl string?
--- @return string? field
--- @return boolean selected
local function variant_of(ctrl)
	if not ctrl then
		return nil, false
	end

	-- the shortest head that leaves "_<state>" with an optional seat suffix
	for i = 2, #ctrl do
		if ctrl:sub(i, i) == "_" then
			local state, seat = ctrl:sub(i + 1):match("^(%l+)(.*)$")
			if state and STATES[state] and SEATS[seat] then
				return ctrl:sub(1, i - 1) .. seat, state == "on"
			end
		end
	end

	return nil, false
end

--- Each slot's controller, a toggle's words inheriting the one of their container
--- @param slots CniRawSlot[]
--- @return { [integer]: string }
local function effective_controllers(slots)
	local by_name = {}
	for _, s in ipairs(slots) do
		if s.name then
			by_name[s.name] = s
		end
	end

	local out = {}
	for _, s in ipairs(slots) do
		local ctrl = s.ctrl
		local parent = s.parent
		local depth = 0
		while not ctrl and parent and depth < 16 do
			local up = by_name[parent]
			if not up then
				break
			end
			ctrl = up.ctrl
			parent = up.parent
			depth = depth + 1
		end
		out[s.n] = ctrl
	end
	return out
end

--- Add() order regrouped into the order the indication reports: a container's visible
--- children follow it directly
--- @param slots CniRawSlot[]
--- @return CniRawSlot[]
local function indication_order(slots)
	local children = {}
	for _, s in ipairs(slots) do
		if s.parent then
			children[s.parent] = children[s.parent] or {}
			table.insert(children[s.parent], s)
		end
	end

	local ordered, emitted = {}, {}
	for _, s in ipairs(slots) do
		if not s.parent then
			ordered[#ordered + 1] = s
			emitted[s] = true
			for _, child in ipairs(s.name and children[s.name] or {}) do
				ordered[#ordered + 1] = child
				emitted[child] = true
			end
		end
	end

	-- a child whose parent is not itself a top level slot would otherwise vanish
	for _, s in ipairs(slots) do
		if not emitted[s] then
			ordered[#ordered + 1] = s
		end
	end

	return ordered
end

--- Groups items by key, keeping the order in which keys first appear
--- @param items any[]
--- @param key fun(item: any): string
--- @return any[][]
local function group_by(items, key)
	local buckets, order = {}, {}
	for _, item in ipairs(items) do
		local k = key(item)
		if not buckets[k] then
			buckets[k] = {}
			order[#order + 1] = k
		end
		table.insert(buckets[k], item)
	end

	local groups = {}
	for i, k in ipairs(order) do
		groups[i] = buckets[k]
	end
	return groups
end

local function key_of(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, "\2")
end

local function pair(a, b)
	a.counterpart = b
	b.counterpart = a
end

--- Pairs opposite states inside each bucket, in schema order
--- @param slots CniSlot[]
--- @param key fun(slot: CniSlot): string
--- @param opposed fun(a: CniSlot, b: CniSlot): boolean
local function pair_within(slots, key, opposed)
	for _, bucket in ipairs(group_by(slots, key)) do
		local pending = nil
		for _, slot in ipairs(bucket) do
			if pending and opposed(pending, slot) then
				pair(pending, slot)
				pending = nil
			else
				pending = slot
			end
		end
	end
end

local function selection_differs(a, b)
	return a.selected ~= b.selected
end

local function highlight_differs(a, b)
	return a.invert ~= b.invert
end

local function last_name(field)
	return field:match("_([^_]*)$") or field
end

--- Joins each element to itself in its other state, and finds the fields and table columns
--- that can be read as evidence of a state
--- @param slots CniSlot[]
local function resolve_variants(slots)
	local named = {}
	for _, s in ipairs(slots) do
		if s.controller then
			named[#named + 1] = s
		end
	end

	-- position first, which is how a toggle's words pair
	pair_within(named, function(s)
		return key_of(s.controller, s.line, s.col, s.anchor)
	end, selection_differs)

	-- then on the line alone, for the fields whose two forms are not the same width
	local unpaired = {}
	for _, s in ipairs(named) do
		if not s.counterpart then
			unpaired[#unpaired + 1] = s
		end
	end
	pair_within(unpaired, function(s)
		return key_of(s.controller, s.line)
	end, selection_differs)

	-- highlighted and plain forms that share position and text but no state name
	local loose = {}
	for _, s in ipairs(slots) do
		if not s.counterpart and s.line ~= nil then
			loose[#loose + 1] = s
		end
	end
	pair_within(loose, function(s)
		return key_of(s.line, s.col, s.anchor, s.value, s.format_key)
	end, highlight_differs)

	-- only a field built in both states can be read as evidence of one
	for _, field in
		ipairs(group_by(named, function(s)
			return s.controller
		end))
	do
		local has_selected, has_unselected = false, false
		for _, s in ipairs(field) do
			if s.selected then
				has_selected = true
			else
				has_unselected = true
			end
		end
		if has_selected and has_unselected then
			for _, s in ipairs(field) do
				s.two_state = true
			end
		end
	end

	-- the fields of one table column are one decision, like the flap setting of LANDING DATA
	local columnar = {}
	for _, s in ipairs(slots) do
		if s.two_state and s.controller and s.col ~= nil and s.counterpart then
			columnar[#columnar + 1] = s
		end
	end
	for _, group in
		ipairs(group_by(columnar, function(s)
			return last_name(s.controller) .. "|" .. tostring(s.col) .. "|" .. tostring(s.anchor)
		end))
	do
		local lines, controllers = {}, {}
		local line_count, controller_count = 0, 0
		for _, s in ipairs(group) do
			if not lines[s.line or "nil"] then
				lines[s.line or "nil"] = true
				line_count = line_count + 1
			end
			if not controllers[s.controller] then
				controllers[s.controller] = true
				controller_count = controller_count + 1
			end
		end
		if line_count >= 2 and controller_count >= 2 then
			local column = last_name(group[1].controller) .. "|" .. tostring(group[1].col) .. "|" .. tostring(group[1].anchor)
			for _, s in ipairs(group) do
				s.column = column
			end
		end
	end
end

--- The name a field shares with the other positions of its rotary, e.g. power_up_align of
--- power_up_align_gps
--- @param field string
--- @return string
local function stem_of(field)
	return field:match("^(.+)_[^_]*$") or ""
end

--- Splits the positions sharing a stem into the groups drawn together: a rotary sits on one line,
--- or wraps onto the next like ADF/MN/BTH. Positions further apart are separate decisions, like
--- WPT SEQ and WP TRANS on the route page, which are both named route_*
--- @param members string[]
--- @param lines_of { [string]: { low: integer, high: integer } }
--- @return { members: string[], low: integer, high: integer }[]
local function line_groups(members, lines_of)
	local ordered = {}
	for i, member in ipairs(members) do
		ordered[i] = member
	end
	table.sort(ordered, function(a, b)
		if lines_of[a].low ~= lines_of[b].low then
			return lines_of[a].low < lines_of[b].low
		end
		return a < b
	end)

	local groups = {}
	local group = nil
	for _, member in ipairs(ordered) do
		local lines = lines_of[member]
		if group and lines.low <= group.high + 1 then
			group.members[#group.members + 1] = member
			group.high = math.max(group.high, lines.high)
		else
			group = { members = { member }, low = lines.low, high = lines.high }
			groups[#groups + 1] = group
		end
	end
	return groups
end

--- The rotaries of a page. The module names their positions off a common stem, but a stem alone
--- is not enough (uhf1_guard and uhf1_chan share one too): a rotary has at least three
--- highlightable positions, drawn on one line or wrapped onto the next. With only two positions
--- every switch moves both, which leaves nothing to reason from
--- @param slots CniSlot[]
--- @return CniSelector[]
local function find_selectors(slots)
	local fields, field_order = {}, {}
	for _, s in ipairs(slots) do
		if s.controller and s.two_state then
			local field = fields[s.controller]
			if not field then
				field = { slots = {}, invert = false }
				fields[s.controller] = field
				field_order[#field_order + 1] = s.controller
			end
			field.slots[#field.slots + 1] = s
			field.invert = field.invert or s.invert
		end
	end

	local stems, stem_order = {}, {}
	for _, name in ipairs(field_order) do
		local stem = stem_of(name)
		if fields[name].invert and stem ~= "" then
			if not stems[stem] then
				stems[stem] = {}
				stem_order[#stem_order + 1] = stem
			end
			table.insert(stems[stem], name)
		end
	end

	local found = {}
	for _, stem in ipairs(stem_order) do
		local members = stems[stem]

		-- a position that is not on the grid could be the lit one without ever being seen
		local lines_of, placed = {}, true
		for _, member in ipairs(members) do
			local low, high = nil, nil
			for _, s in ipairs(fields[member].slots) do
				if s.line ~= nil then
					low = math.min(low or s.line, s.line)
					high = math.max(high or s.line, s.line)
				end
			end
			if not low then
				placed = false
				break
			end
			lines_of[member] = { low = low, high = high }
		end

		if placed and #members >= 3 then
			local groups = line_groups(members, lines_of)
			for _, group in ipairs(groups) do
				-- a group that still spans more than two lines is not one the module wraps
				if #group.members >= 3 and group.high - group.low <= 1 then
					table.sort(group.members)
					local key = #groups == 1 and stem or (stem .. "@" .. group.low)
					found[#found + 1] = { key = key, members = group.members }
				end
			end
		end
	end
	return found
end

--- Prepares one page recorded by the extractor
--- @param raw CniRawPage
--- @return CniPage
function CniSchema.prepare_page(raw)
	local title, title_sources, counter = nil, nil, nil
	for _, s in ipairs(raw.slots) do
		if s.name == "cni_title" then
			if s.value then
				title = s.value
			elseif s.fmt then
				title_sources = s.fmt
			end
		end
		if not counter and s.value and s.value:match("^%s*%d+/%d+%s*$") then
			counter = s.value
		end
	end

	local parents = {}
	for _, s in ipairs(raw.slots) do
		if s.parent then
			parents[s.parent] = true
		end
	end

	local ctrl_of = effective_controllers(raw.slots)

	local slots = {}
	for _, s in ipairs(indication_order(raw.slots)) do
		local ctrl = ctrl_of[s.n]
		if ctrl == "" then
			ctrl = nil
		end
		local field, selected = variant_of(ctrl)

		local slot = {
			n = s.n,
			anchor = ANCHORS[s.anchor or "Left"] or CniSchema.ANCHOR_LEFT,
			controller = field,
			selected = field ~= nil and selected,
			source = field == nil and ctrl or nil,
			off_grid = s.kind == "ceTexPoly" or (s.lineErr or 0) > 0.02,
			line = s.line,
			col = s.col,
			value = s.value,
			format_key = "",
			format_weight = 0,
			small = s.small == true,
			invert = s.invert == true,
			container = s.name ~= nil and parents[s.name] == true,
			named_role = s.name == "cni_title" and 1 or (s.name == "cni_scratchpad" and 2 or 0),
			two_state = false,
		}

		if s.fmt and #s.fmt > 0 then
			slot.formats = {}
			slot.format_sources = s.fmt
			local keys = {}
			for i, f in ipairs(s.fmt) do
				slot.formats[i] = CniFormat.compile(f)
				keys[i] = CniFormat.signature(slot.formats[i])
			end
			slot.format_key = table.concat(keys, "|")
			slot.format_weight = CniFormat.specificity(s.fmt)
		end

		slots[#slots + 1] = slot
	end

	resolve_variants(slots)

	local landmarks, seen = {}, {}
	for _, slot in ipairs(slots) do
		if slot.value and slot.value ~= "" and not seen[slot.value] then
			seen[slot.value] = true
			landmarks[#landmarks + 1] = slot.value
		end
	end

	local title_formats = nil
	if title_sources then
		title_formats = {}
		for i, f in ipairs(title_sources) do
			title_formats[i] = CniFormat.compile(f)
		end
	end

	return {
		id = raw.id,
		name = raw.name,
		title = title,
		title_formats = title_formats,
		counter = counter,
		slots = slots,
		landmarks = landmarks,
		selectors = find_selectors(slots),
	}
end

--- Whether a slot can be placed on the display grid
--- @param slot CniSlot
--- @return boolean
function CniSchema.is_placeable(slot)
	return not slot.off_grid and slot.line ~= nil and slot.line >= 0 and slot.col ~= nil
end

return CniSchema
