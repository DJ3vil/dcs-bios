module("AmuDisplay", package.seeall)

-- Builds the text of the four C-130J AMU displays (pilot left and right, copilot left and right).
--
-- list_indication gives the elements a page draws but not where they go, so the page layouts are
-- read from the module's own page scripts when the aircraft is first seen (a few milliseconds per
-- export tick until done), and every page is matched against them to place its text on a 23x11
-- grid, the same way as the CNI-MU. One unit is updated per export tick, and only when its
-- indication changed. An entry the page draws on a box of its own, such as one being edited,
-- comes with a highlight format. Which word of a toggle is selected is a box the module switches
-- on and off itself, which the indication does not report, so toggles come without it.

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

--- @class AmuUnitState
--- @field raw string? the indication last processed

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

		lines = {},
		formats = {},
		page_names = {},
		units = {},

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
		o.units[unit] = { raw = nil }
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
function AmuDisplay:update()
	local ok, err = pcall(self.step, self)
	if not ok then
		self:log_error_once(tostring(err))
	end
end

--- @private
function AmuDisplay:step()
	self.tick = self.tick + 1

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
		pages[#pages + 1] = CniSchema.prepare_page(raw)
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
end

--- @private
--- @param unit integer
function AmuDisplay:process_unit(unit)
	local state = self.units[unit]
	local raw = self.list_indication(self.first_indicator + unit - 1) or ""
	if raw == state.raw then
		return
	end
	state.raw = raw

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

	local matched = CniBlockMatcher.align(flat, page.slots)
	local lines, formats = CniGrid.render(flat, matched, AmuDisplay.COLUMNS, AmuDisplay.LINES)

	self.lines[unit] = lines
	self.formats[unit] = formats
	self.page_names[unit] = page.name
end

return AmuDisplay
