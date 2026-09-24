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
-- - the crew turning a rotary: two positions swap element and the rest hold, and a position that
--   held was not the lit one on either side of the turn. That alone reads POWER UP's
--   GPS/LAST/REF, which nothing else in the aircraft follows
-- A field draws one of two forms, so knowing either one settles the other.
--
-- Nothing is known about a field until something gave it away, and everything learned about a
-- page is dropped when the sim builds the page anew.
-- Lua port of CniSessionMap.cs of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

--- @class CniSessionMap
--- @field private known { [string]: { [string]: boolean } } per field, whether each of its elements is the lit one
--- @field private seen { [string]: { [string]: string } } per rotary, the elements last drawn for each member
--- @field private current { [string]: string } the elements drawing each field on the page last observed
--- @field private landmarks { [integer]: { [integer]: string } } per page, the elements behind its fixed text
local CniSessionMap = {}

--- @return CniSessionMap
function CniSessionMap:new()
	local o = {
		known = {},
		seen = {},
		current = {},
		landmarks = {},
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
--- @private
--- @param field string
--- @param identity string
--- @return boolean?
function CniSessionMap:is_lit(field, identity)
	local elements = self.known[field]
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

--- @private
--- @param field string
--- @param identity string
--- @param lit boolean
function CniSessionMap:mark(field, identity, lit)
	local elements = self.known[field]
	if not elements then
		elements = {}
		self.known[field] = elements
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
--- @private
--- @param states { [string]: boolean|string }
--- @param drawn { [string]: string }
function CniSessionMap:record(states, drawn)
	for field, state in pairs(states) do
		local identity = drawn[field]
		if (state == true or state == false) and identity then
			self:mark(field, identity, state)
		end
	end
end

--- @private
--- @param selector CniSelector
--- @param before { [string]: string }
--- @param now { [string]: string }
function CniSessionMap:compare(selector, before, now)
	local held = {}
	for _, member in ipairs(selector.members) do
		if before[member] ~= nil and before[member] == now[member] then
			held[#held + 1] = member
		end
	end

	-- nothing moved, so nothing happened
	if #held == #selector.members then
		return
	end

	-- every member moved, so the page was rebuilt and the old elements mean nothing any more
	if #held == 0 then
		for _, member in ipairs(selector.members) do
			self.known[member] = nil
		end
		return
	end

	for _, member in ipairs(held) do
		self:mark(member, now[member], false)
	end
end

--- Reads off what the picture forces, given everything known so far
--- @private
--- @param selector CniSelector
--- @param drawn { [string]: string }
function CniSessionMap:close(selector, drawn)
	local lit, any_lit = {}, false
	for _, member in ipairs(selector.members) do
		if self:is_lit(member, drawn[member]) == true then
			lit[member] = true
			any_lit = true
		end
	end

	-- the lit one is spoken for, so the rest are not
	if any_lit then
		for _, member in ipairs(selector.members) do
			if not lit[member] then
				self:mark(member, drawn[member], false)
			end
		end
		return
	end

	local open = {}
	for _, member in ipairs(selector.members) do
		if self:is_lit(member, drawn[member]) == nil then
			open[#open + 1] = member
		end
	end
	if #open == 1 then
		self:mark(open[1], drawn[open[1]], true)
	end
end

--- Whether the sim has built this page afresh since it was last seen. A literal written into
--- the page script cannot move with any state, so the element behind it only changes when the
--- whole page is rebuilt, and then all of them change
--- @private
--- @param page CniPage
--- @param blocks CniBlock[]
--- @param matched (CniSlot|nil)[]
--- @return boolean
function CniSessionMap:rebuilt(page, blocks, matched)
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

	local before = self.landmarks[page.id]
	if not before then
		if any then
			self.landmarks[page.id] = now
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

--- Drops everything learned about a page whose elements are no longer the same
--- @private
--- @param page CniPage
function CniSessionMap:forget(page)
	for _, slot in ipairs(page.slots) do
		if slot.controller then
			self.known[slot.controller] = nil
		end
	end
	for _, selector in ipairs(page.selectors) do
		self.seen[selector.key] = nil
	end
end

--- Takes in the page just matched, together with what the page proved about its fields
--- @param page CniPage
--- @param blocks CniBlock[]
--- @param matched (CniSlot|nil)[] the slots as the matcher seated the blocks, before any variant was chosen
--- @param states { [string]: boolean|string }? the states the page settled by itself
function CniSessionMap:observe(page, blocks, matched, states)
	if self:rebuilt(page, blocks, matched) then
		self:forget(page)
	end

	local drawn = drawn_fields(blocks, matched)
	self.current = drawn

	if states then
		self:record(states, drawn)
	end

	for _, selector in ipairs(page.selectors) do
		local members, count = members_of(selector, drawn)

		-- a member merely missing from the screen looks exactly like one that held
		if count == #selector.members then
			local before = self.seen[selector.key]
			if before then
				self:compare(selector, before, members)
				-- the turn can settle the picture it came from as much as the one it arrived at
				self:close(selector, before)
			end

			self.seen[selector.key] = members
			self:close(selector, members)
		end
	end
end

--- Whether the field is the lit one on the page last observed, nil where that is not known
--- @param field string
--- @return boolean?
function CniSessionMap:lit(field)
	local drawn = self.current[field]
	if not drawn then
		return nil
	end
	return self:is_lit(field, drawn)
end

return CniSessionMap
