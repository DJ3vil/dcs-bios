module("CniPageResolver", package.seeall)

-- Works out which CNI-MU page is on screen. The sim publishes no page identifier, so this reads
-- the title the page draws, breaks ties on the page counter and on how many of a page's static
-- strings are visible, and returns nil rather than a guess for a page it does not recognise.
-- Lua port of CniPageResolver.cs of WCtrlDcsBiosBridge, see LICENSE-WCtrlDcsBiosBridge.txt.

local CniFormat = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniFormat")

--- @class CniPageResolver
--- @field private by_title { [string]: CniPage[] }
--- @field private by_pattern { tokens: CniFormatToken[], page: CniPage }[]
--- @field private untitled CniPage[]
local CniPageResolver = {}

local COUNTER_PATTERN = "^%s*%d+%s*/%s*%d+%s*$"

--- @param pages CniPage[]
--- @return CniPageResolver
function CniPageResolver:new(pages)
	local o = {
		by_title = {},
		by_pattern = {},
		untitled = {},
	}

	for _, page in ipairs(pages) do
		if page.title and page.title ~= "" then
			o.by_title[page.title] = o.by_title[page.title] or {}
			table.insert(o.by_title[page.title], page)
		elseif page.title_formats and #page.title_formats > 0 then
			for _, tokens in ipairs(page.title_formats) do
				table.insert(o.by_pattern, { tokens = tokens, page = page })
			end
		else
			table.insert(o.untitled, page)
		end
	end

	setmetatable(o, self)
	self.__index = self
	return o
end

local function normalise(counter)
	return (counter:gsub("[ \t]", ""))
end

--- How many of a page's static strings the sim actually drew
--- @param page CniPage
--- @param drawn { [string]: boolean }
--- @return integer
local function landmark_score(page, drawn)
	local score = 0
	for _, value in ipairs(page.landmarks) do
		if drawn[value] then
			score = score + 1
		end
	end
	return score
end

--- Whether the page has a counter format naming its page number that fits the counter drawn
--- @param page CniPage
--- @param counter string
--- @return boolean
local function counter_format_fits(page, counter)
	local normalised = normalise(counter)
	for _, slot in ipairs(page.slots) do
		if slot.formats then
			for i, tokens in ipairs(slot.formats) do
				if CniFormat.pins_page_number(slot.format_sources[i]) and CniFormat.accepts(tokens, normalised) then
					return true
				end
			end
		end
	end
	return false
end

--- @param title string
--- @return CniPage[]
function CniPageResolver:candidates(title)
	if self.by_title[title] then
		return self.by_title[title]
	end

	local found, seen = {}, {}
	for _, entry in ipairs(self.by_pattern) do
		if not seen[entry.page] and CniFormat.accepts(entry.tokens, title) then
			seen[entry.page] = true
			found[#found + 1] = entry.page
		end
	end
	return found
end

--- @param drawn { [string]: boolean }
--- @param block_count integer
--- @return CniPage?
function CniPageResolver:resolve_untitled(drawn, block_count)
	local best, best_score, best_delta = nil, -1, math.huge

	for _, page in ipairs(self.untitled) do
		local score = landmark_score(page, drawn)
		local delta = math.abs(#page.slots - block_count)
		if score > best_score or (score == best_score and delta < best_delta) then
			best, best_score, best_delta = page, score, delta
		end
	end

	if best_score > 0 or best_delta <= 4 then
		return best
	end
	return nil
end

--- @param title string the value of the page's cni_title element, "" when it has none
--- @param blocks CniBlock[] the page's blocks in document order
--- @return CniPage?
function CniPageResolver:resolve(title, blocks)
	local drawn = {}
	for _, block in ipairs(blocks) do
		if block.v ~= "" then
			drawn[block.v] = true
		end
	end

	-- the shape alone decides only for a page that genuinely draws no title
	if title == "" then
		return self:resolve_untitled(drawn, #blocks)
	end

	local candidates = self:candidates(title)
	if #candidates <= 1 then
		return candidates[1]
	end

	local counter = nil
	for _, block in ipairs(blocks) do
		if block.v ~= "" and block.v:match(COUNTER_PATTERN) then
			counter = block.v
			break
		end
	end

	if counter then
		local normalised = normalise(counter)
		local on_counter = {}
		for _, page in ipairs(candidates) do
			if page.counter and normalise(page.counter) == normalised then
				on_counter[#on_counter + 1] = page
			end
		end

		if #on_counter == 1 then
			return on_counter[1]
		elseif #on_counter > 1 then
			candidates = on_counter
		else
			-- pages whose counter is drawn from a format, like the six CARP INIT pages
			local on_format = {}
			for _, page in ipairs(candidates) do
				if counter_format_fits(page, counter) then
					on_format[#on_format + 1] = page
				end
			end

			if #on_format == 1 then
				return on_format[1]
			elseif #on_format > 1 then
				candidates = on_format
			end
		end
	end

	-- still tied: the page whose landmarks the sim drew, then the closest size
	local best, best_score, best_delta = nil, -1, math.huge
	for _, page in ipairs(candidates) do
		local score = landmark_score(page, drawn)
		local delta = math.abs(#page.slots - #blocks)
		if score > best_score or (score == best_score and (delta < best_delta or (delta == best_delta and page.id < best.id))) then
			best, best_score, best_delta = page, score, delta
		end
	end
	return best
end

return CniPageResolver
