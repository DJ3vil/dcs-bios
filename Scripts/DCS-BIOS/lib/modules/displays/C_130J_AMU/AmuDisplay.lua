module("AmuDisplay", package.seeall)

-- Builds the text of the four C-130J AMU displays (pilot left and right, copilot left and right).
--
-- list_indication gives the elements a page draws but not where they go, so the page layouts are
-- read from the module's own page scripts when the aircraft is first seen (a few milliseconds per
-- export tick until done), and every page is matched against them to place its text on a 23x11
-- grid, the same way as the CNI-MU. One unit is updated per export tick, and only when its
-- indication changed. An entry the page draws on a box of its own, such as one being edited,
-- comes with a highlight format.
--
-- Which word of a toggle (PILOT/COPILOT, MAG/TRUE/GRID) is selected is a box the module switches on
-- and off itself: nothing about it reaches the indication, the cockpit parameters or the device.
-- So it is followed instead: every press of the key beside a toggle moves the box on by one word,
-- counted from the word the toggle starts in. That is the crew's own side for PILOT/COPILOT and
-- otherwise what the crew said it is (shift_highlight), which is also kept for later sessions.
-- A page with a PILOT/COPILOT toggle sets up the side chosen there, so its other toggles are
-- followed once per side.

local AmuSchemaExtractor = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_AMU.AmuSchemaExtractor")
local CniBlockMatcher = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniBlockMatcher")
local CniGrid = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniGrid")
local CniIndication = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniIndication")
local CniPageResolver = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniPageResolver")
local CniSchema = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchema")
local Log = require("Scripts.DCS-BIOS.lib.common.Log")

--- @class AmuDisplayOptions
--- @field list_indication (fun(id: integer): string)?
--- @field load_pages (fun(): CniRawPage[])? source of the page layouts, instead of the module's scripts
--- @field defaults HighlightDefaults? where the words the crew said toggles start on are kept

--- @class AmuUnitState
--- @field raw string? the indication last processed
--- @field dirty boolean whether the page has to be drawn again even if unchanged
--- @field page CniPage? the page on screen

--- @class AmuToggle the words beside one key, of which the module boxes one
--- @field count integer
--- @field texts { [integer]: string }

--- @class AmuPageToggles
--- @field toggles { [integer]: AmuToggle } by key, 1-4 for L1-L4 and 5-8 for R1-R4
--- @field words { [integer]: AmuBox } by slot, the word each element draws
--- @field side integer? the key of the page's PILOT/COPILOT toggle

--- @class AmuDisplay
local AmuDisplay = {}

AmuDisplay.COLUMNS = AmuSchemaExtractor.COLUMNS
AmuDisplay.LINES = AmuSchemaExtractor.LINES
AmuDisplay.UNITS = 4

-- the four AMUs are registered consecutively: pilot left, pilot right, copilot left, copilot right
local DEFAULT_FIRST_INDICATOR = 18
local SCAN_LIMIT = 40
local SCAN_INTERVAL = 200 -- export ticks between looking for the AMUs elsewhere
local LOAD_BUDGET = 0.003 -- seconds of layout loading per export tick
-- fixed texts of a page that have to be on screen for it to count as an AMU page when looking
local MIN_LANDMARKS = 2

-- the cockpit argument of each unit's L1; L2-L4 and R1-R4 follow on
local KEY_ARGS = { 133, 141, 174, 182 }
local KEYS = 8
-- the first two units are the pilot's, which start on PILOT; the copilot's start on COPILOT
local SIDES = { 1, 1, 2, 2 }
local SIDE_WORDS = { "PILOT", "COPILOT" }
local UNIT_NAMES = { "lo", "li", "ri", "ro" }

local BLANK_LINE = string.rep(" ", AmuDisplay.COLUMNS)
local PLAIN_FORMAT = string.rep("0", AmuDisplay.COLUMNS)

--- @param options AmuDisplayOptions?
--- @return AmuDisplay
function AmuDisplay:new(options)
	options = options or {}

	local o = {
		list_indication = options.list_indication or function(id)
			return list_indication(id)
		end,
		load_pages = options.load_pages,
		defaults = options.defaults,

		lines = {},
		formats = {},
		page_names = {},
		units = {},

		-- per page id, its toggles
		page_toggles = {},
		-- per unit: whether each key was down last tick, and per toggle (see scope) the word
		-- boxed, how often its key was pressed and whether it was given its starting word
		key_down = {},
		tracked = {},
		presses = {},
		started = {},

		tick = 0,
		first_indicator = DEFAULT_FIRST_INDICATOR,
		indicator_confirmed = false,
		scan_countdown = SCAN_INTERVAL,

		schema_state = "pending",
		loader = nil,
		load_deadline = 0,
		load_started = 0,
		load_work = 0,
		resolver = nil,

		logged_errors = {},
	}

	for unit = 1, AmuDisplay.UNITS do
		o.units[unit] = { raw = nil, dirty = false, page = nil }
		o.key_down[unit] = {}
		o.tracked[unit] = {}
		o.presses[unit] = {}
		o.started[unit] = {}
		o.page_names[unit] = ""
		o.lines[unit] = {}
		o.formats[unit] = {}
		for line = 1, AmuDisplay.LINES do
			o.lines[unit][line] = BLANK_LINE
			o.formats[unit][line] = PLAIN_FORMAT
		end
	end

	setmetatable(o, self)
	self.__index = self
	return o
end

--- @param unit integer 1 = pilot left, 2 = pilot right, 3 = copilot left, 4 = copilot right
--- @param line integer 1-11
--- @return string
function AmuDisplay:get_line(unit, line)
	return self.lines[unit][line] or BLANK_LINE
end

--- How each character of a line is drawn, as for the CNI-MU: 0 plain, 2 highlighted
--- @param unit integer
--- @param line integer 1-11
--- @return string
function AmuDisplay:get_format(unit, line)
	return self.formats[unit][line] or PLAIN_FORMAT
end

--- @param unit integer
--- @return string
function AmuDisplay:get_page(unit)
	return self.page_names[unit]
end

--- @private
--- @param message string
function AmuDisplay:log_error_once(message)
	if not self.logged_errors[message] then
		self.logged_errors[message] = true
		Log:log_error("C-130J AMU: " .. message)
	end
end

--- Called on every export tick
--- @param dev0 table? the cockpit device, to read the keys from
function AmuDisplay:update(dev0)
	local ok, err = pcall(self.step, self, dev0)
	if not ok then
		self:log_error_once(tostring(err))
	end
end

--- @private
--- @param dev0 table?
function AmuDisplay:step(dev0)
	self.tick = self.tick + 1
	self:poll_keys(dev0)

	if self.schema_state ~= "ready" then
		self:load_schema()
		if self.schema_state ~= "ready" then
			return
		end
	end

	local unit = (self.tick % AmuDisplay.UNITS) + 1
	if unit == 1 then
		self:find_indicators()
	end
	self:process_unit(unit)
end

--- Loads the page layouts a slice at a time
--- @private
function AmuDisplay:load_schema()
	if self.schema_state == "failed" then
		return
	end

	local slice_start = os.clock()
	if not self.loader then
		self.load_started = slice_start
		self.loader = coroutine.create(function()
			return self:build_resolver()
		end)
	end

	self.load_deadline = slice_start + LOAD_BUDGET
	local ok, result, summary = coroutine.resume(self.loader)
	local now = os.clock()
	self.load_work = self.load_work + (now - slice_start)

	if not ok then
		self.schema_state = "failed"
		self:log_error_once("unable to read the page layouts: " .. tostring(result))
	elseif coroutine.status(self.loader) == "dead" then
		self.resolver = result
		self.schema_state = "ready"
		Log:log_info(string.format("C-130J AMU: %s in %.0f ms, spread over %.1f s", summary, self.load_work * 1000, now - self.load_started))
	end
end

--- @private
function AmuDisplay:yield_if_due()
	if os.clock() >= self.load_deadline then
		coroutine.yield()
	end
end

--- @private
--- @return CniPageResolver
--- @return string summary
function AmuDisplay:build_resolver()
	local raw_pages
	local source = "test data"

	if self.load_pages then
		raw_pages = self.load_pages()
	else
		local script_path, common_path = AmuSchemaExtractor.find_script_root()
		if not script_path or not common_path then
			error("the C-130J cockpit scripts were not found in the DCS installation", 0)
		end
		source = script_path

		raw_pages = {}
		for _, entry in ipairs(AmuSchemaExtractor.catalogue(script_path, common_path)) do
			raw_pages[#raw_pages + 1] = AmuSchemaExtractor.extract_page(script_path, common_path, entry)
			self:yield_if_due()
		end
	end

	local pages, partial = {}, 0
	for _, raw in ipairs(raw_pages) do
		if raw.partial then
			partial = partial + 1
			Log:log_warn(string.format("C-130J AMU: page %s only partially read: %s", tostring(raw.name), tostring(raw.error)))
		end
		pages[#pages + 1] = CniSchema.prepare_page(raw, AmuDisplay.COLUMNS)
		self.page_toggles[raw.id] = AmuDisplay.toggles_of(raw)
		self:yield_if_due()
	end

	if #pages == 0 then
		error("no pages found in " .. source, 0)
	end

	return CniPageResolver:new(pages), string.format("read %d page layouts (%d partial) from %s", #pages, partial, source)
end

--- The page an indication shows and how many of its fixed texts are on screen, nil for a unit
--- that draws nothing
--- @private
--- @param raw string
--- @return CniBlock[]? flat
--- @return CniPage? page
--- @return integer landmarks
function AmuDisplay:resolve(raw)
	local blocks = CniIndication.parse(raw)
	if not blocks then
		return nil, nil, 0
	end

	local flat = CniIndication.flatten(blocks)
	local drawn, any_text = {}, false
	for _, block in ipairs(flat) do
		if block.v ~= "" then
			drawn[block.v] = true
			any_text = true
		end
	end
	if not any_text then
		return nil, nil, 0
	end

	local page = self.resolver:resolve("", flat)
	local landmarks = 0
	for _, value in ipairs(page and page.landmarks or {}) do
		if drawn[value] then
			landmarks = landmarks + 1
		end
	end
	return flat, page, landmarks
end

--- Looks for the AMUs among the other indicators while the expected ones show no AMU page
--- @private
function AmuDisplay:find_indicators()
	if self.indicator_confirmed then
		return
	end

	self.scan_countdown = self.scan_countdown - 1
	if self.scan_countdown > 0 then
		return
	end
	self.scan_countdown = SCAN_INTERVAL

	for id = 0, SCAN_LIMIT do
		local ok, raw = pcall(self.list_indication, id)
		if ok and type(raw) == "string" and raw ~= "" then
			local _, page, landmarks = self:resolve(raw)
			if page and landmarks >= MIN_LANDMARKS then
				if id ~= self.first_indicator then
					Log:log_info(string.format("C-130J AMU: first AMU found at indicator %d", id))
					self.first_indicator = id
					for unit = 1, AmuDisplay.UNITS do
						self.units[unit].raw = nil
					end
				end
				self.indicator_confirmed = true
				return
			end
		end
	end
end

--- @private
--- @param unit integer
function AmuDisplay:blank(unit)
	for line = 1, AmuDisplay.LINES do
		self.lines[unit][line] = BLANK_LINE
		self.formats[unit][line] = PLAIN_FORMAT
	end
	self.page_names[unit] = ""
	self.units[unit].page = nil
end

--- @private
--- @param unit integer
function AmuDisplay:process_unit(unit)
	local state = self.units[unit]
	local raw = self.list_indication(self.first_indicator + unit - 1) or ""
	if raw == state.raw and not state.dirty then
		return
	end
	state.raw = raw
	state.dirty = false

	local flat, page, landmarks = self:resolve(raw)
	if not flat then
		-- the unit is off or between pages
		self:blank(unit)
		return
	end
	if not page then
		-- an unknown page keeps what is on screen rather than being drawn with a wrong layout
		return
	end
	if landmarks >= MIN_LANDMARKS then
		self.indicator_confirmed = true
	end
	state.page = page

	local matched = CniBlockMatcher.align(flat, page.slots)
	local lines, formats = CniGrid.render(flat, matched, AmuDisplay.COLUMNS, AmuDisplay.LINES, self:boxed_words(unit, page, matched))

	self.lines[unit] = lines
	self.formats[unit] = formats
	self.page_names[unit] = page.name
end

--- The toggles of a page as the extractor recorded them: every word the module boxes by itself
--- @param raw CniRawPage
--- @return AmuPageToggles
function AmuDisplay.toggles_of(raw)
	local toggles, words = {}, {}
	for _, s in ipairs(raw.slots) do
		local box = s.box
		if box then
			local toggle = toggles[box.key]
			if not toggle then
				toggle = { count = 0, texts = {} }
				toggles[box.key] = toggle
			end
			toggle.count = math.max(toggle.count, box.word)
			toggle.texts[box.word] = s.value
			words[s.n] = box
		end
	end

	local side = nil
	for key, toggle in pairs(toggles) do
		if toggle.count == 2 and toggle.texts[1] == SIDE_WORDS[1] and toggle.texts[2] == SIDE_WORDS[2] then
			side = key
		end
	end
	return { toggles = toggles, words = words, side = side }
end

--- What a toggle's word is followed under. A page with a PILOT/COPILOT toggle sets up the side
--- chosen there, so its other toggles are followed per side.
--- @private
--- @param unit integer
--- @param page CniPage
--- @param key integer
--- @return string scope unique to the unit
--- @return string key what it is kept under in the defaults of the page
function AmuDisplay:scope(unit, page, key)
	local side = self.page_toggles[page.id] and self.page_toggles[page.id].side
	local name = tostring(key)
	if side and side ~= key then
		local chosen = self.tracked[unit][page.name .. "|" .. side]
		name = name .. "|" .. (SIDE_WORDS[chosen] or "?")
	end
	return page.name .. "|" .. name, name
end

--- Gives the toggles of the page on screen that were never seen before the word they start on:
--- what the crew said they start on, or the crew's own side for PILOT/COPILOT
--- @private
--- @param unit integer
--- @param page CniPage
--- @param page_toggles AmuPageToggles
function AmuDisplay:start_toggles(unit, page, page_toggles)
	local keys = {}
	for key in pairs(page_toggles.toggles) do
		keys[#keys + 1] = key
	end
	-- the side first: the other toggles are followed per side
	table.sort(keys, function(a, b)
		if (a == page_toggles.side) ~= (b == page_toggles.side) then
			return a == page_toggles.side
		end
		return a < b
	end)

	local remembered = self.defaults and self.defaults:section("amu_" .. UNIT_NAMES[unit])[page.name]
	for _, key in ipairs(keys) do
		local scope, name = self:scope(unit, page, key)
		if not self.started[unit][scope] then
			self.started[unit][scope] = true
			local toggle = page_toggles.toggles[key]
			local word = remembered and remembered[name]
			if type(word) ~= "number" or word < 1 or word > toggle.count or word ~= math.floor(word) then
				word = key == page_toggles.side and SIDES[unit] or nil
			end
			self.tracked[unit][scope] = word
		end
	end
end

--- The blocks that draw a word the module boxes now
--- @private
--- @param unit integer
--- @param page CniPage
--- @param matched (CniSlot|nil)[]
--- @return { [integer]: boolean }?
function AmuDisplay:boxed_words(unit, page, matched)
	local page_toggles = self.page_toggles[page.id]
	if not page_toggles or next(page_toggles.toggles) == nil then
		return nil
	end
	self:start_toggles(unit, page, page_toggles)

	local boxed = {}
	for i, slot in pairs(matched) do
		local box = slot and page_toggles.words[slot.n]
		if box and self.tracked[unit][(self:scope(unit, page, box.key))] == box.word then
			boxed[i] = true
		end
	end
	return boxed
end

--- Follows the presses of every unit's keys: a press moves the toggle beside the key on by one word
--- @private
--- @param dev0 table?
function AmuDisplay:poll_keys(dev0)
	if not dev0 then
		return
	end
	for unit = 1, AmuDisplay.UNITS do
		local down_before = self.key_down[unit]
		for key = 1, KEYS do
			local ok, value = pcall(dev0.get_argument_value, dev0, KEY_ARGS[unit] + key - 1)
			local down = ok and type(value) == "number" and value > 0.5
			-- a key found down on the first look was not seen being pressed
			if down and down_before[key] == false then
				self:advance(unit, key, true)
			end
			down_before[key] = down
		end
	end
end

--- Moves the toggle beside a key of the page on screen on by one word
--- @private
--- @param unit integer
--- @param key integer
--- @param pressed boolean whether the key was pressed, rather than the crew saying where it is
--- @return string? scope
--- @return string? name
--- @return AmuToggle? toggle
function AmuDisplay:advance(unit, key, pressed)
	local page = self.units[unit].page
	local page_toggles = page and self.page_toggles[page.id]
	local toggle = page_toggles and page_toggles.toggles[key]
	if not toggle then
		return nil
	end

	local scope, name = self:scope(unit, page, key)
	local word = self.tracked[unit][scope]
	if word then
		self.tracked[unit][scope] = word % toggle.count + 1
	elseif not pressed then
		self.tracked[unit][scope] = 1
	end
	self.started[unit][scope] = true
	if pressed then
		self.presses[unit][scope] = (self.presses[unit][scope] or 0) + 1
	end
	self.units[unit].dirty = true
	return scope, name, toggle
end

--- Moves the box of the toggle beside a key on to the next word, for a display that shows it
--- wrong or not at all. Only the exported display changes, not the aircraft. Every press from
--- then on is followed, and the word the toggle started on is kept for later sessions.
--- @param unit integer 1 = pilot left, 2 = pilot right, 3 = copilot left, 4 = copilot right
--- @param key integer 1-4 for L1-L4, 5-8 for R1-R4
function AmuDisplay:shift_highlight(unit, key)
	if not self.units[unit] then
		return
	end
	local scope, name, toggle = self:advance(unit, key, false)
	if not scope or not toggle or not self.defaults then
		return
	end

	-- every press since the toggle was first seen moved it on by one
	local presses = self.presses[unit][scope] or 0
	local start = (self.tracked[unit][scope] - 1 - presses) % toggle.count + 1
	self.defaults:remember("amu_" .. UNIT_NAMES[unit], self.units[unit].page.name, name, start)
end

return AmuDisplay
