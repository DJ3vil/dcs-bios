module("CniSessionMap", package.seeall)

-- Remembers which element of a field is the highlighted one, for as long as the sim keeps
-- issuing that element.
--
-- A toggle is built as one element per state (lit and plain, same word, same place) and the
-- indication does not say which of them is drawn. The elements are named by GUIDs the sim
-- generates anew every session, but within a session they hold steady, so an answer is worth
-- keeping once it has been had. Answers come from two places:
-- - what a page proved about a field by itself (see CniVariants), kept against the element that
--   carried it, so the reading still holds on the frames that cannot give it
-- - the crew turning a rotary: the position that went out and the one that came in swap element
--   and the rest hold, and a position that held was not the lit one on either side of the turn.
--   That alone reads POWER UP's GPS/LAST/REF, which nothing else in the aircraft follows
-- A field draws one of two forms, so knowing either one settles the other.
--
-- Every page builds elements of its own, also for the fields it shares with other pages (the
-- runway list of ROUTE ARR and LZ RWY SEL, for one), so everything is kept per page. Nothing is
-- known about a field until something gave it away, and everything learned about a page is
-- dropped when the sim builds the page anew.
--
-- A toggle with two positions gives nothing away: both positions move with every switch. Those
-- that always start in the same position are taken to be in it the first time they are seen,
-- and every switch is followed from there. Should an aircraft start otherwise, swap() turns the
-- assumption around.
-- Lua port of CniSessionMap.cs of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

--- @class CniSessionPage what is known about the elements of one page
--- @field name string the page name
--- @field known { [string]: { [string]: boolean } } per field, whether each of its elements is the lit one
--- @field seen { [string]: { [string]: string } } per rotary, the elements last drawn for each member
--- @field landmarks { [integer]: string }? the elements behind the page's fixed text, by slot

--- @class CniStartingState a toggle that always starts in the same position
--- @field page string the page drawing it
--- @field fields { [string]: boolean } whether each of its fields is lit in that position

--- @class CniSessionMap
--- @field private pages { [integer]: CniSessionPage }
--- @field private current { [string]: string } the elements drawing each field on the page last observed
--- @field private current_page CniSessionPage? the page last observed
--- @field private starting { [string]: CniStartingState }
--- @field private swap_pending { [string]: boolean } toggles to take the other way round when first seen
local CniSessionMap = {}

--- @type { [string]: CniStartingState }
CniSessionMap.STARTING_STATES = {
	-- RTE: waypoint sequencing starts on AUTO
	WPT_SEQ = { page = "ROUTE_GEN", fields = { route_auto = true, route_man = false } },
}

--- @param starting_states { [string]: CniStartingState }? defaults to STARTING_STATES
--- @return CniSessionMap
function CniSessionMap:new(starting_states)
	local o = {
		pages = {},
		current = {},
		current_page = nil,
		starting = starting_states or CniSessionMap.STARTING_STATES,
		swap_pending = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

--- What is drawing each two-state field: all of its elements, since a position is usually a word
--- and the slash beside it, swapped together when the field changes
--- @param blocks CniBlock[]
--- @param matched (CniSlot|nil)[]
--- @return { [string]: string }
local function drawn_fields(blocks, matched)
	local parts = {}
	for i = 1, #blocks do
		local slot = matched[i]
		local element = blocks[i].k
		if slot and slot.two_state and slot.controller and element and element ~= "" then
			local elements = parts[slot.controller]
			if not elements then
				elements = {}
				parts[slot.controller] = elements
			end
			elements[#elements + 1] = element
		end
	end

	local drawn = {}
	for field, elements in pairs(parts) do
		table.sort(elements)
		drawn[field] = table.concat(elements, "|")
	end
	return drawn
end

--- @param selector CniSelector
--- @param drawn { [string]: string }
--- @return { [string]: string } members
--- @return integer count
local function members_of(selector, drawn)
	local members, count = {}, 0
	for _, member in ipairs(selector.members) do
		local identity = drawn[member]
		if identity then
			members[member] = identity
			count = count + 1
		end
	end
	return members, count
end

--- Whether that element of the field is the lit one, nil if not known
--- @param known { [string]: { [string]: boolean } }
--- @param field string
--- @param identity string
--- @return boolean?
local function is_lit(known, field, identity)
	local elements = known[field]
	if not elements then
		return nil
	end

	local lit = elements[identity]
	if lit ~= nil then
		return lit
	end

	-- not the form known to be lit is the plain one, not the form known to be plain is the lit one
	local any_lit, any_plain = false, false
	for _, value in pairs(elements) do
		if value then
			any_lit = true
		else
			any_plain = true
		end
	end
	if any_lit then
		return false
	end
	if any_plain then
		return true
	end
	return nil
end

--- @param known { [string]: { [string]: boolean } }
--- @param field string
--- @param identity string
--- @param lit boolean
local function mark(known, field, identity, lit)
	local elements = known[field]
	if not elements then
		elements = {}
		known[field] = elements
	end

	local was = elements[identity]
	if was ~= nil and was ~= lit then
		for key in pairs(elements) do
			elements[key] = nil
		end
	end
	elements[identity] = lit

	-- a pair has one of each, so naming the lit one names the other
	if lit then
		for key in pairs(elements) do
			if key ~= identity then
				elements[key] = false
			end
		end
	end
end

--- Writes down what the frame proved, as a fact about the elements that carried it
--- @param known { [string]: { [string]: boolean } }
--- @param states { [string]: boolean|string }
--- @param drawn { [string]: string }
local function record(known, states, drawn)
	for field, state in pairs(states) do
		local identity = drawn[field]
		if (state == true or state == false) and identity then
			mark(known, field, identity, state)
		end
	end
end

--- @param known { [string]: { [string]: boolean } }
--- @param selector CniSelector
--- @param before { [string]: string }
--- @param now { [string]: string }
local function compare(known, selector, before, now)
	local held = {}
	for _, member in ipairs(selector.members) do
		if before[member] ~= nil and before[member] == now[member] then
			held[#held + 1] = member
		end
	end

	-- every member moved, so the page was rebuilt and the old elements mean nothing any more
	if #held == 0 then
		for _, member in ipairs(selector.members) do
			known[member] = nil
		end
		return
	end

	-- a turn moves the position that went out and the one that came in, nothing else; any other
	-- change is not one this can reason about
	if #selector.members - #held ~= 2 then
		return
	end

	for _, member in ipairs(held) do
		mark(known, member, now[member], false)
	end
end

--- Reads off what the picture forces, given everything known so far
--- @param known { [string]: { [string]: boolean } }
--- @param selector CniSelector
--- @param drawn { [string]: string }
local function close(known, selector, drawn)
	local lit, any_lit = {}, false
	for _, member in ipairs(selector.members) do
		if is_lit(known, member, drawn[member]) == true then
			lit[member] = true
			any_lit = true
		end
	end

	-- the lit one is spoken for, so the rest are not
	if any_lit then
		for _, member in ipairs(selector.members) do
			if not lit[member] then
				mark(known, member, drawn[member], false)
			end
		end
		return
	end

	local open = {}
	for _, member in ipairs(selector.members) do
		if is_lit(known, member, drawn[member]) == nil then
			open[#open + 1] = member
		end
	end
	if #open == 1 then
		mark(known, open[1], drawn[open[1]], true)
	end
end

--- Whether the sim has built the page afresh since it was last seen. A literal written into the
--- page script cannot move with any state, so the element behind it only changes when the whole
--- page is rebuilt, and then all of them change
--- @param page_record CniSessionPage
--- @param blocks CniBlock[]
--- @param matched (CniSlot|nil)[]
--- @return boolean
local function rebuilt(page_record, blocks, matched)
	local now, any = {}, false
	for i = 1, #blocks do
		local slot = matched[i]
		local element = blocks[i].k
		-- fixed text tied to no state; the title and the scratchpad are named by the sim itself
		if slot and slot.value ~= nil and slot.controller == nil and slot.named_role == 0 and slot.counterpart == nil and element and element ~= "" then
			now[slot.n] = element
			any = true
		end
	end

	local before = page_record.landmarks
	if not before then
		if any then
			page_record.landmarks = now
		end
		return false
	end

	local shared, agreed = 0, 0
	for n, element in pairs(now) do
		local was = before[n]
		if was ~= nil then
			shared = shared + 1
			if was == element then
				agreed = agreed + 1
			end
		end
	end

	-- merged rather than replaced: a landmark the page did not draw this time is still the one it
	-- draws next time
	for n, element in pairs(now) do
		before[n] = element
	end

	return shared > 0 and agreed == 0
end

--- Takes in the page just matched, together with what the page proved about its fields
--- @param page CniPage
--- @param blocks CniBlock[]
--- @param matched (CniSlot|nil)[] the slots as the matcher seated the blocks, before any variant was chosen
--- @param states { [string]: boolean|string }? the states the page settled by itself
function CniSessionMap:observe(page, blocks, matched, states)
	local page_record = self.pages[page.id]
	if not page_record then
		page_record = { name = page.name, known = {}, seen = {}, landmarks = nil }
		self.pages[page.id] = page_record
	end

	if rebuilt(page_record, blocks, matched) then
		page_record.known = {}
		page_record.seen = {}
	end

	local known = page_record.known
	local drawn = drawn_fields(blocks, matched)
	self.current = drawn
	self.current_page = page_record

	if states then
		record(known, states, drawn)
	end

	for _, selector in ipairs(page.selectors) do
		local members, count = members_of(selector, drawn)

		-- a member merely missing from the screen looks exactly like one that held
		if count == #selector.members then
			local before = page_record.seen[selector.key]
			if before then
				compare(known, selector, before, members)
				-- the turn can settle the picture it came from as much as the one it arrived at
				close(known, selector, before)
			end

			page_record.seen[selector.key] = members
			close(known, selector, members)
		end
	end

	for name, toggle in pairs(self.starting) do
		if toggle.page == page.name then
			self:assume(name, toggle, known, drawn)
		end
	end
end

--- Takes a toggle nothing is known about to be in its starting position
--- @private
--- @param name string
--- @param toggle CniStartingState
--- @param known { [string]: { [string]: boolean } }
--- @param drawn { [string]: string }
function CniSessionMap:assume(name, toggle, known, drawn)
	local swapped = self.swap_pending[name] == true
	local assumed = false
	for field, lit in pairs(toggle.fields) do
		local identity = drawn[field]
		if identity and is_lit(known, field, identity) == nil then
			mark(known, field, identity, lit ~= swapped)
			assumed = true
		end
	end
	if assumed then
		self.swap_pending[name] = nil
	end
end

--- Turns around which position a toggle with a starting state is taken to be in, for an
--- aircraft that did not start in it. A toggle not seen yet is taken the other way round when it
--- is first seen.
--- @param name string a key of the starting states
function CniSessionMap:swap(name)
	local toggle = self.starting[name]
	if not toggle then
		return
	end

	local swapped = false
	for _, page_record in pairs(self.pages) do
		if page_record.name == toggle.page then
			for field in pairs(toggle.fields) do
				for identity, lit in pairs(page_record.known[field] or {}) do
					page_record.known[field][identity] = not lit
					swapped = true
				end
			end
		end
	end

	if not swapped then
		self.swap_pending[name] = not self.swap_pending[name] or nil
	end
end

--- Whether the field is the lit one on the page last observed, nil where that is not known
--- @param field string
--- @return boolean?
function CniSessionMap:lit(field)
	local drawn = self.current[field]
	if not drawn or not self.current_page then
		return nil
	end
	return is_lit(self.current_page.known, field, drawn)
end

return CniSessionMap
