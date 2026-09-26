module("CniDisplay", package.seeall)

-- Builds the text of the three C-130J CNI-MU displays (pilot, copilot, augmented crew).
--
-- list_indication gives the elements a page draws but not where they go, so the page layouts are
-- read from the module's own page scripts when the aircraft is first seen (a few milliseconds per
-- export tick until done), and every page is matched against them to place its text on the
-- 25x14 grid. One seat is updated per export tick, and only when its indication changed.

local CniBlockMatcher = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniBlockMatcher")
local CniExecLamp = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniExecLamp")
local CniGrid = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniGrid")
local CniIndication = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniIndication")
local CniPageResolver = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniPageResolver")
local CniSchema = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchema")
local CniSchemaExtractor = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchemaExtractor")
local CniSessionMap = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSessionMap")
local CniVariants = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniVariants")
local Log = require("Scripts.DCS-BIOS.lib.common.Log")

--- @class CniSeatState
--- @field raw string? the indication last processed
--- @field title string? the title of the page on screen, nil while the display is dark
--- @field dirty boolean whether the page has to be processed again even if unchanged

--- @class CniDisplayOptions
--- @field list_indication (fun(id: integer): string)?
--- @field get_device (fun(id: integer): table?)?
--- @field load_pages (fun(): CniRawPage[])? source of the page layouts, instead of the module's scripts
--- @field debug_file string? file to write every rendered page to, for troubleshooting
--- @field defaults HighlightDefaults? where the positions the crew said toggles start in are kept

--- @class CniDisplay
local CniDisplay = {}

CniDisplay.COLUMNS = CniGrid.COLUMNS
CniDisplay.LINES = CniGrid.LINES
CniDisplay.SEATS = 3

-- the three CNI-MUs are registered consecutively: pilot, copilot, augmented crew
local DEFAULT_FIRST_INDICATOR = 8
local MIN_BLOCKS = 6 -- a lit page never has fewer
local SCAN_LIMIT = 40
local SCAN_INTERVAL = 150 -- export ticks between looking for the CNI-MU indicators elsewhere
local LOAD_BUDGET = 0.004 -- seconds of layout loading per export tick
local SOLUTION_INTERVAL = 150 -- export ticks between re-reading the active INAV solution
local MAX_DEBUG_ENTRIES = 2000

-- cockpit arguments of the pilot, copilot and augmented crew EXEC keys
local EXEC_ARGS = { 1122, 1187, 1262 }
local RADIO_SCAN_LIMIT = 100
local PFD_INDICATORS = { 0, 2 }

local BLANK_LINE = string.rep(" ", CniGrid.COLUMNS)
local BLANK_FORMAT = string.rep("0", CniGrid.COLUMNS)

local function centered(text)
	local left = math.floor((CniGrid.COLUMNS - #text) / 2)
	return (string.rep(" ", left) .. text .. BLANK_LINE):sub(1, CniGrid.COLUMNS)
end

--- @param options CniDisplayOptions?
--- @return CniDisplay
function CniDisplay:new(options)
	options = options or {}

	local o = {
		list_indication = options.list_indication or function(id)
			return list_indication(id)
		end,
		get_device = options.get_device or function(id)
			return GetDevice(id)
		end,
		load_pages = options.load_pages,
		debug_file = options.debug_file,
		debug_entries = 0,
		defaults = options.defaults,

		lines = {},
		formats = {},
		page_names = {},
		pages = {},
		exec_lamps = {},
		lamps = {},
		seats = {},
		sessions = {},

		tick = 0,
		first_indicator = DEFAULT_FIRST_INDICATOR,
		indicator_confirmed = false,
		scan_countdown = math.floor(SCAN_INTERVAL / CniDisplay.SEATS),

		schema_state = "pending",
		loader = nil,
		load_deadline = 0,
		load_started = 0,
		load_work = 0,
		resolver = nil,

		exec_presses = 0,
		exec_down = {},

		radio_devices = nil,
		radio_scan_countdown = 0,
		radios = {},
		radio_signature = "",

		ship_solution = nil,
		solution_countdown = 0,

		logged_errors = {},
	}

	for seat = 1, CniDisplay.SEATS do
		o.lines[seat] = {}
		o.formats[seat] = {}
		o.page_names[seat] = ""
		o.exec_lamps[seat] = false
		o.lamps[seat] = CniExecLamp:new()
		o.seats[seat] = { raw = nil, title = nil, dirty = false }
		-- every CNI-MU draws with elements of its own
		o.sessions[seat] = CniSessionMap:new(nil, o.defaults and o.defaults:section("cni"))
		for line = 1, CniGrid.LINES do
			o.lines[seat][line] = BLANK_LINE
			o.formats[seat][line] = BLANK_FORMAT
		end
	end

	setmetatable(o, self)
	self.__index = self
	return o
end

--- @param seat integer 1 = pilot, 2 = copilot, 3 = augmented crew
--- @param line integer 1-14
--- @return string
function CniDisplay:get_line(seat, line)
	return self.lines[seat][line]
end

--- @param seat integer 1 = pilot, 2 = copilot, 3 = augmented crew
--- @param line integer 1-14
--- @return string
function CniDisplay:get_format(seat, line)
	return self.formats[seat][line]
end

--- @param seat integer 1 = pilot, 2 = copilot, 3 = augmented crew
--- @return string
function CniDisplay:get_page(seat)
	return self.page_names[seat]
end

--- @param seat integer 1 = pilot, 2 = copilot, 3 = augmented crew
--- @return boolean
function CniDisplay:get_exec_lamp(seat)
	return self.exec_lamps[seat]
end

--- Turns around the position a toggle with a starting state is taken to be in, for an aircraft
--- that did not start in it (see CniSessionMap.STARTING_STATES)
--- @param seat integer 1 = pilot, 2 = copilot, 3 = augmented crew
--- @param toggle string
function CniDisplay:swap_starting_state(seat, toggle)
	self.sessions[seat]:swap(toggle)
	self.seats[seat].dirty = true
end

--- Moves the highlight of the toggle beside a line select key on to its next position, for a
--- display that shows it wrong or not at all. Only the exported display changes, not the
--- aircraft; every switch from then on is followed. Said of a toggle still as it was first seen,
--- the position is also kept as the one it starts in.
--- @param seat integer 1 = pilot, 2 = copilot, 3 = augmented crew
--- @param key integer 1-6 for L1-L6, 7-12 for R1-R6
function CniDisplay:shift_highlight(seat, key)
	local page = self.pages[seat]
	if not page or key < 1 or key > 12 then
		return
	end

	local session = self.sessions[seat]
	local toggle = session:toggle_at(page, (key - 1) % 6 + 1, key <= 6 and "L" or "R")
	if not toggle then
		return
	end

	local fields, unchanged = session:shift(page, toggle)
	if fields and unchanged and self.defaults then
		self.defaults:remember("cni", page.name, toggle.key, fields)
	end
	self.seats[seat].dirty = true
end

--- @private
function CniDisplay:log_error_once(message)
	message = tostring(message)
	if not self.logged_errors[message] then
		self.logged_errors[message] = true
		Log:log_error("C-130J CNI-MU: " .. message)
	end
end

--- Called on every export tick
--- @param dev0 table? the main panel device
function CniDisplay:update(dev0)
	local ok, err = pcall(self.step, self, dev0)
	if not ok then
		self:log_error_once(err)
	end
end

--- @private
--- @param dev0 table?
function CniDisplay:step(dev0)
	self.tick = self.tick + 1
	self:poll_exec_keys(dev0)

	if self.schema_state ~= "ready" then
		self:load_schema()
		if self.schema_state ~= "ready" then
			return
		end
	end

	local seat = (self.tick % CniDisplay.SEATS) + 1
	if seat == 1 then
		self:read_radios()
		self:refresh_ship_solution()
		self:find_indicators()
	end

	self:process_seat(seat)
end

--- Counts presses of the EXEC keys. The EXEC light is not exported, and a press made from a page
--- other than the modified one changes nothing on screen, so the presses themselves are counted.
--- @private
--- @param dev0 table?
function CniDisplay:poll_exec_keys(dev0)
	if not dev0 then
		return
	end
	for i, arg in ipairs(EXEC_ARGS) do
		local ok, value = pcall(dev0.get_argument_value, dev0, arg)
		local down = ok and type(value) == "number" and value > 0.5
		if down and not self.exec_down[i] then
			self.exec_presses = self.exec_presses + 1
		end
		self.exec_down[i] = down
	end
end

--- Loads the page layouts a slice at a time
--- @private
function CniDisplay:load_schema()
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
		CniSchemaExtractor.clear_cache()
		self:log_error_once("unable to read the page layouts: " .. tostring(result))
		self:show_message("CNI LAYOUT UNAVAILABLE", "SEE DCS-BIOS.LOG")
	elseif coroutine.status(self.loader) == "dead" then
		self.resolver = result
		self.schema_state = "ready"
		Log:log_info(string.format("C-130J CNI-MU: %s in %.0f ms, spread over %.1f s", summary, self.load_work * 1000, now - self.load_started))
	end
end

--- @private
function CniDisplay:yield_if_due()
	if os.clock() >= self.load_deadline then
		coroutine.yield()
	end
end

--- @private
--- @return CniPageResolver
--- @return string summary
function CniDisplay:build_resolver()
	local raw_pages
	local source = "test data"

	if self.load_pages then
		raw_pages = self.load_pages()
	else
		local script_path, common_path = CniSchemaExtractor.find_script_root()
		if not script_path or not common_path then
			error("the C-130J cockpit scripts were not found in the DCS installation", 0)
		end
		source = script_path

		raw_pages = {}
		for _, entry in ipairs(CniSchemaExtractor.catalogue(script_path, common_path)) do
			raw_pages[#raw_pages + 1] = CniSchemaExtractor.extract_page(script_path, common_path, entry)
			self:yield_if_due()
		end
		CniSchemaExtractor.clear_cache()
	end

	local pages, partial = {}, 0
	for _, raw in ipairs(raw_pages) do
		if raw.partial then
			partial = partial + 1
			Log:log_warn(string.format("C-130J CNI-MU: page %s only partially read: %s", tostring(raw.name), tostring(raw.error)))
		end
		pages[#pages + 1] = CniSchema.prepare_page(raw)
		self:yield_if_due()
	end

	if #pages == 0 then
		error("no pages found in " .. source, 0)
	end

	return CniPageResolver:new(pages), string.format("read %d page layouts (%d partial) from %s", #pages, partial, source)
end

--- Writes a message onto every display, for problems the crew would otherwise only see as a
--- blank screen
--- @private
function CniDisplay:show_message(first, second)
	for seat = 1, CniDisplay.SEATS do
		for line = 1, CniGrid.LINES do
			self.lines[seat][line] = BLANK_LINE
			self.formats[seat][line] = BLANK_FORMAT
		end
		self.lines[seat][6] = centered(first)
		self.lines[seat][8] = centered(second)
	end
end

--- Whether an indication looks like a lit CNI-MU page, without parsing all of it
--- @param raw string?
--- @return boolean
local function looks_like_cni(raw)
	return raw ~= nil and raw:find("\ncni_title\n", 1, true) ~= nil
end

--- Makes sure the displays are read from the right indicators. The module registers the three
--- CNI-MUs one after another; if none of the expected ones has ever shown a page while another
--- indicator does, the numbering has moved and is taken from there.
--- @private
function CniDisplay:find_indicators()
	if self.indicator_confirmed then
		return
	end
	if self.scan_countdown > 0 then
		self.scan_countdown = self.scan_countdown - 1
		return
	end
	self.scan_countdown = math.floor(SCAN_INTERVAL / CniDisplay.SEATS)

	for id = 0, SCAN_LIMIT do
		if looks_like_cni(self.list_indication(id)) then
			if id < self.first_indicator or id >= self.first_indicator + CniDisplay.SEATS then
				Log:log_warn(string.format("C-130J CNI-MU: found a display at indicator %d, reading the displays from there", id))
				self.first_indicator = id
				for seat = 1, CniDisplay.SEATS do
					self.seats[seat].raw = nil
				end
			end
			return
		end
	end
end

--- Reads the power and frequency of the radios, used to tell which of a radio's ON/OFF words is
--- lit. A change marks every page for another pass.
--- @private
function CniDisplay:read_radios()
	if not self.radio_devices then
		-- the avionics may not answer yet, so a failed search is retried now and then
		self.radios = {}
		if self.radio_scan_countdown > 0 then
			self.radio_scan_countdown = self.radio_scan_countdown - 1
			return
		end
		self.radio_scan_countdown = math.floor(SCAN_INTERVAL / CniDisplay.SEATS)

		local found = {}
		for id = 1, RADIO_SCAN_LIMIT do
			local ok, answers = pcall(function()
				local dev = self.get_device(id)
				if dev == nil or dev.get_frequency == nil or dev.is_on == nil then
					return false
				end
				dev:get_frequency()
				dev:is_on()
				return true
			end)
			if ok and answers then
				found[#found + 1] = id
			end
		end
		if #found == 0 then
			return
		end
		self.radio_devices = found
	end

	local radios, parts = {}, {}
	for _, id in ipairs(self.radio_devices) do
		local ok, frequency, on = pcall(function()
			local dev = self.get_device(id)
			return dev:get_frequency(), dev:is_on()
		end)
		if ok and type(frequency) == "number" then
			-- to the kilohertz: the raw reading drifts between frames
			local khz = math.floor(frequency / 1000 + 0.5)
			radios[#radios + 1] = { frequency = khz, on = on and true or false }
			parts[#parts + 1] = khz .. (on and "+" or "-")
		end
	end

	self.radios = radios
	local signature = table.concat(parts, ",")
	if signature ~= self.radio_signature then
		self.radio_signature = signature
		self:mark_dirty()
	end
end

--- @private
--- @return integer?
function CniDisplay:read_ship_solution()
	for _, id in ipairs(PFD_INDICATORS) do
		local digit = (self.list_indication(id) or ""):match("INAV_(%d)")
		if digit then
			return tonumber(digit)
		end
	end
	return nil
end

--- Re-reads the INAV solution the aircraft has settled on, which decides the boxed corner digit
--- of every page, from time to time; pages that change re-read it themselves
--- @private
function CniDisplay:refresh_ship_solution()
	if self.solution_countdown > 0 then
		self.solution_countdown = self.solution_countdown - 1
		return
	end
	self.solution_countdown = math.floor(SOLUTION_INTERVAL / CniDisplay.SEATS)

	local solution = self:read_ship_solution()
	if solution ~= self.ship_solution then
		self.ship_solution = solution
		self:mark_dirty()
	end
end

--- @private
function CniDisplay:mark_dirty()
	for seat = 1, CniDisplay.SEATS do
		self.seats[seat].dirty = true
	end
end

--- @private
--- @param seat integer
function CniDisplay:blank(seat)
	for line = 1, CniGrid.LINES do
		self.lines[seat][line] = BLANK_LINE
		self.formats[seat][line] = BLANK_FORMAT
	end
	self.page_names[seat] = ""
	self.pages[seat] = nil
end

--- @private
--- @param seat integer
function CniDisplay:process_seat(seat)
	local state = self.seats[seat]
	local indicator = self.first_indicator + seat - 1
	local raw = self.list_indication(indicator) or ""

	if raw ~= state.raw or state.dirty then
		local changed = raw ~= state.raw
		state.raw = raw
		state.dirty = false
		self:render_seat(seat, indicator, raw, changed)
	end

	-- the lamp follows EXEC presses even while the page does not change
	self.exec_lamps[seat] = self.lamps[seat]:update(state.title, self.exec_presses)
end

--- @private
--- @param seat integer
--- @param indicator integer
--- @param raw string
--- @param changed boolean whether the page itself changed, rather than the aircraft state
function CniDisplay:render_seat(seat, indicator, raw, changed)
	local state = self.seats[seat]
	local blocks, total = CniIndication.parse(raw)
	if not blocks or total < MIN_BLOCKS then
		-- the display is off
		state.title = nil
		self:blank(seat)
		return
	end

	local title_block = CniIndication.find_named(blocks, "cni_title")
	if title_block then
		self.indicator_confirmed = true
	end
	local title = title_block and title_block.v or ""
	state.title = title

	local flat = CniIndication.flatten(blocks)
	local page = self.resolver:resolve(title, flat)
	if not page then
		-- an unknown page keeps what is on screen rather than being drawn with a wrong layout
		self.page_names[seat] = ""
		self.pages[seat] = nil
		self:write_debug(seat, indicator, raw, title, nil)
		return
	end

	-- a page change is when a new ship solution shows, so it is read right away
	if changed then
		self.ship_solution = self:read_ship_solution()
	end

	local matched = CniBlockMatcher.align(flat, page.slots)
	CniVariants.apply(matched, page, flat, self.radios, self.ship_solution, self.sessions[seat])
	local lines, formats = CniGrid.render(flat, matched)

	self.lines[seat] = lines
	self.formats[seat] = formats
	self.page_names[seat] = page.name
	self.pages[seat] = page
	self:write_debug(seat, indicator, raw, title, page.name)
end

--- @private
function CniDisplay:write_debug(seat, indicator, raw, title, page_name)
	if not self.debug_file or self.debug_entries >= MAX_DEBUG_ENTRIES then
		return
	end
	self.debug_entries = self.debug_entries + 1

	local file = io.open(self.debug_file, "a")
	if not file then
		return
	end
	file:write(string.format("=== %s seat %d indicator %d title %q page %s\n", os.date("%H:%M:%S"), seat, indicator, title, tostring(page_name)))
	for line = 1, CniGrid.LINES do
		file:write("|", self.lines[seat][line], "|  ", self.formats[seat][line], "\n")
	end
	file:write("--- indication\n", raw, "\n")
	file:close()
end

return CniDisplay
