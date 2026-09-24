module("IndicatorDump", package.seeall)

-- Writes what an aircraft's indicators report through list_indication to a file whenever one of
-- them changes, for working out how a display that is not exported yet could be. Meant to be
-- switched on for a session while troubleshooting: every indicator is written at most every few
-- seconds, and only up to a size limit.

--- @class IndicatorDumpOptions
--- @field file string the file to append to
--- @field first integer? first indicator id to look at, 0 by default
--- @field last integer? last indicator id to look at, 40 by default
--- @field min_interval integer? seconds between two writes of one indicator, 2 by default
--- @field max_bytes integer? bytes written per indicator before it is left alone, 300000 by default
--- @field per_update integer? indicators looked at per update, 2 by default
--- @field list_indication (fun(id: integer): string)?
--- @field time (fun(): integer)?

--- @class IndicatorDump
--- @field private file string
--- @field private first integer
--- @field private last integer
--- @field private min_interval integer
--- @field private max_bytes integer
--- @field private per_update integer
--- @field private list_indication fun(id: integer): string
--- @field private time fun(): integer
--- @field private next_id integer
--- @field private last_text { [integer]: string }
--- @field private last_write { [integer]: integer }
--- @field private written { [integer]: integer }
local IndicatorDump = {}

--- @param options IndicatorDumpOptions
--- @return IndicatorDump
function IndicatorDump:new(options)
	local first = options.first or 0
	local o = {
		file = options.file,
		first = first,
		last = options.last or 40,
		min_interval = options.min_interval or 2,
		max_bytes = options.max_bytes or 300000,
		per_update = options.per_update or 2,
		list_indication = options.list_indication or function(id)
			return list_indication(id)
		end,
		time = options.time or os.time,
		next_id = first,
		last_text = {},
		last_write = {},
		written = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

--- Looks at the next few indicators, so that all of them are covered within a second or so
function IndicatorDump:update()
	for _ = 1, self.per_update do
		local id = self.next_id
		self.next_id = id >= self.last and self.first or id + 1
		self:check(id)
	end
end

--- @private
--- @param id integer
function IndicatorDump:check(id)
	if (self.written[id] or 0) >= self.max_bytes then
		return
	end

	local ok, text = pcall(self.list_indication, id)
	if not ok or type(text) ~= "string" or text == "" or text == self.last_text[id] then
		return
	end

	local now = self.time()
	if self.last_write[id] and now - self.last_write[id] < self.min_interval then
		return
	end

	self.last_text[id] = text
	self.last_write[id] = now
	self.written[id] = (self.written[id] or 0) + #text

	local file = io.open(self.file, "a")
	if not file then
		return
	end
	file:write(string.format("=== %s indicator %d\n", os.date("%H:%M:%S"), id), text, "\n")
	file:close()
end

return IndicatorDump
