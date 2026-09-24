module("CniVariants", package.seeall)

-- Works out which state each toggleable field of a page is in and swaps every matched element
-- to the variant that matches. The indication carries no highlight, so a state is only known
-- where the page gives itself away (an element built for one state only was drawn, the two
-- forms spell different text, a radio's power or the INAV solution settles it) or where the
-- session map learned it earlier in the session. A field without evidence is drawn in the form
-- that claims the least.
-- Lua port of CniVariants.cs, CniRadios.cs and CniShipSolution.cs of WCtrlDcsBiosBridge, see
-- LICENSE-WCtrlDcsBiosBridge.txt.

local CniSchema = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchema")

--- @class CniRadio
--- @field frequency integer? tuned frequency in kHz
--- @field on boolean? whether the radio is powered

--- @class CniVariants
local CniVariants = {}

local CONFLICT = "conflict" -- the elements of a field disagree

--- Whether this element being on screen settles its field
--- @param slot CniSlot
--- @return boolean
local function decisive(slot)
	if not slot.two_state then
		return false
	end

	local other = slot.counterpart
	if not other then
		-- built for one state only, so drawing it is the answer
		return true
	end

	-- the matcher only seats a block on the highlighted cell of a table column where no plain
	-- reading fits, which makes the seating itself an answer
	if slot.column and slot.invert and not other.invert then
		return true
	end

	if slot.value == nil or other.value == nil then
		return false
	end

	return slot.value ~= other.value
end

--- @param states { [string]: boolean|string }
--- @param field string
--- @param selected boolean
local function record(states, field, selected)
	local seen = states[field]
	if seen ~= nil and seen ~= selected then
		states[field] = CONFLICT
	else
		states[field] = selected
	end
end

--- What the drawn elements prove about each field
--- @param matched (CniSlot|nil)[]
--- @param count integer
--- @return { [string]: boolean|string }
local function observe(matched, count)
	local states = {}
	for i = 1, count do
		local slot = matched[i]
		if slot and slot.controller and decisive(slot) then
			record(states, slot.controller, slot.selected)
		end
	end
	return states
end

--- What the page proves by what it did not draw: an element built for one state only is
--- drawn exactly when that state holds
--- @param states { [string]: boolean|string }
--- @param matched (CniSlot|nil)[]
--- @param count integer
--- @param page CniPage
local function observe_absences(states, matched, count, page)
	local drawn = {}
	for i = 1, count do
		if matched[i] then
			drawn[matched[i]] = true
		end
	end

	for _, slot in ipairs(page.slots) do
		local field = slot.controller
		if field and slot.two_state and not slot.counterpart and slot.value ~= nil and CniSchema.is_placeable(slot) and not drawn[slot] and states[field] == nil then
			states[field] = not slot.selected
		end
	end
end

--- A frequency as the CNI prints it ("1/243.000", "243.000R"), in kHz
--- @param text string
--- @return integer?
local function parse_kilohertz(text)
	local mhz, frac = text:match("(%d+)%.(%d%d?%d?)")
	if not mhz then
		return nil
	end
	frac = frac .. string.rep("0", 3 - #frac)
	return tonumber(mhz) * 1000 + tonumber(frac)
end

--- The power of every radio the page names, keyed by the controller prefix naming it: the page
--- prints the frequency a radio is tuned to, which is what pairs a device with the page
--- @param matched (CniSlot|nil)[]
--- @param blocks CniBlock[]
--- @param radios CniRadio[]
--- @return { [string]: boolean }
local function tuned_radios(matched, blocks, radios)
	local found = {}
	for i = 1, #blocks do
		local slot = matched[i]
		local named = slot and (slot.source or slot.controller)
		local prefix = named and named:match("^([^_]+)_")
		if prefix and found[prefix] == nil then
			local tuned = parse_kilohertz(blocks[i].v)
			if tuned then
				for _, radio in ipairs(radios) do
					if radio.frequency and math.abs(radio.frequency - tuned) <= 1 then
						if radio.on ~= nil then
							found[prefix] = radio.on
						end
						break
					end
				end
			end
		end
	end
	return found
end

--- Adds what the radios prove for the power fields of the radios the page identifies
--- @param states { [string]: boolean|string }
--- @param matched (CniSlot|nil)[]
--- @param blocks CniBlock[]
--- @param radios CniRadio[]?
local function observe_radios(states, matched, blocks, radios)
	if not radios or #radios == 0 then
		return
	end

	local powered = tuned_radios(matched, blocks, radios)
	if next(powered) == nil then
		return
	end

	for i = 1, #blocks do
		local slot = matched[i]
		local field = slot and slot.controller
		if field then
			local radio, word = field:match("^(.+)_power_(o[nf]f?)$")
			if radio and (word == "on" or word == "off") and powered[radio] ~= nil then
				-- the ON word is lit when the radio is on and the OFF word when it is not
				local lit = powered[radio]
				if word == "off" then
					lit = not lit
				end
				record(states, field, lit)
			end
		end
	end
end

--- The corner digit every page prints for the INAV feeding its seat, boxed when that INAV is
--- the one the aircraft has settled on
--- @param slot CniSlot
--- @param other CniSlot
--- @param text string
--- @param solution integer?
--- @return CniSlot?
local function choose_ship_solution(slot, other, text, solution)
	if not solution then
		return nil
	end
	if slot.source ~= "cni_sp" and other.source ~= "cni_sp" then
		return nil
	end

	local digit = text:match("^%s*(%d)%s*$")
	if not digit then
		return nil
	end

	local boxed = tonumber(digit) == solution
	if slot.invert == boxed then
		return slot
	end
	return other
end

--- How loudly a slot claims to be the selected one
--- @param slot CniSlot
--- @return integer
local function emphasis(slot)
	return (slot.invert and 2 or 0) + (slot.small and 0 or 1)
end

--- Which of a pair to draw when nothing has settled the field
--- @param slot CniSlot
--- @param other CniSlot
--- @return CniSlot
local function neutral(slot, other)
	-- marked by size alone: the unselected form is what the page shows before anything happened
	if not slot.invert and not other.invert and slot.selected ~= other.selected then
		return slot.selected and other or slot
	end

	if emphasis(slot) <= emphasis(other) then
		return slot
	end
	return other
end

--- What the elements on screen were shown to be earlier in the session, for the fields the page
--- does not settle by itself this frame
--- @param states { [string]: boolean|string }
--- @param matched (CniSlot|nil)[]
--- @param count integer
--- @param session CniSessionMap
local function observe_session(states, matched, count, session)
	for i = 1, count do
		local field = matched[i] and matched[i].controller
		if field and states[field] == nil then
			local lit = session:lit(field)
			if lit ~= nil then
				states[field] = lit
			end
		end
	end
end

--- Rewrites matched in place, one entry per block
--- @param matched (CniSlot|nil)[]
--- @param page CniPage
--- @param blocks CniBlock[]
--- @param radios CniRadio[]?
--- @param ship_solution integer?
--- @param session CniSessionMap? what was learned about the elements of this display so far
function CniVariants.apply(matched, page, blocks, radios, ship_solution, session)
	local count = #blocks
	local states = observe(matched, count)
	observe_absences(states, matched, count, page)
	observe_radios(states, matched, blocks, radios)

	if session then
		-- everything settled above is as much a reading of the element that carried it as of the
		-- state, and the element is still there on the frames where the reading is not
		session:observe(page, blocks, matched, states)
		observe_session(states, matched, count, session)
	end

	for i = 1, count do
		local slot = matched[i]
		local other = slot and slot.counterpart
		if other then
			local state = slot.controller and states[slot.controller]
			if state == true or state == false then
				matched[i] = (state == slot.selected) and slot or other
			else
				matched[i] = choose_ship_solution(slot, other, blocks[i].v, ship_solution) or neutral(slot, other)
			end
		end
	end
end

return CniVariants
