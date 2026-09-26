module("HighlightDefaults", package.seeall)

-- Keeps, across sessions, the position the crew said a display's toggles start in. Neither the
-- CNI-MU nor the AMU says which word of a toggle is lit, so the displays take a toggle to start
-- where it was said to, and follow it from there. The file is a Lua table, written whenever the
-- crew says something new; delete it to start over.

local Log = require("Scripts.DCS-BIOS.lib.common.Log")

--- @class HighlightDefaultsOptions
--- @field file string? where to keep them; without one they last for the session
--- @field read (fun(path: string): string?)?
--- @field write (fun(path: string, text: string): boolean)?

--- @class HighlightDefaults
--- @field private file string?
--- @field private read fun(path: string): string?
--- @field private write fun(path: string, text: string): boolean
--- @field private data { [string]: { [string]: { [string]: any } } } per section, page and toggle
local HighlightDefaults = {}

local HEADER = "-- The positions the C-130J displays take their toggles to start in, as the crew set them.\n" .. "-- Written by DCS-BIOS; delete this file to start over.\n"

local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

local function write_file(path, text)
	local file = io.open(path, "w")
	if not file then
		return false
	end
	file:write(text)
	file:close()
	return true
end

--- @param options HighlightDefaultsOptions?
--- @return HighlightDefaults
function HighlightDefaults:new(options)
	options = options or {}
	local o = {
		file = options.file,
		read = options.read or read_file,
		write = options.write or write_file,
		data = {},
	}
	setmetatable(o, self)
	self.__index = self
	o:load()
	return o
end

--- @private
function HighlightDefaults:load()
	if not self.file then
		return
	end

	local text = self.read(self.file)
	if not text then
		return
	end

	local chunk = loadstring(text)
	local ok, data = false, nil
	if chunk then
		-- the file is data: it gets nothing to call
		setfenv(chunk, {})
		ok, data = pcall(chunk)
	end
	if not ok or type(data) ~= "table" then
		Log:log_warn("C-130J highlights: ignoring " .. self.file .. ", it is not a table of defaults")
		return
	end

	for section, pages in pairs(data) do
		if type(section) == "string" and type(pages) == "table" then
			local kept = {}
			for page, toggles in pairs(pages) do
				if type(page) == "string" and type(toggles) == "table" then
					kept[page] = toggles
				end
			end
			self.data[section] = kept
		end
	end
end

--- The defaults of one display, per page and toggle. The table is the live one, so a default
--- remembered later is seen by whoever holds it.
--- @param section string e.g. cni
--- @return { [string]: { [string]: any } }
function HighlightDefaults:section(section)
	local pages = self.data[section]
	if not pages then
		pages = {}
		self.data[section] = pages
	end
	return pages
end

--- Remembers the position a toggle starts in, and writes the file
--- @param section string
--- @param page string
--- @param key string
--- @param value any
function HighlightDefaults:remember(section, page, key, value)
	local pages = self:section(section)
	local toggles = pages[page]
	if not toggles then
		toggles = {}
		pages[page] = toggles
	end
	toggles[key] = value
	self:save()
end

--- @param value any
--- @param indent string
--- @param out string[]
local function serialize(value, indent, out)
	local kind = type(value)
	if kind == "table" then
		local keys = {}
		for k in pairs(value) do
			keys[#keys + 1] = k
		end
		table.sort(keys, function(a, b)
			return tostring(a) < tostring(b)
		end)
		out[#out + 1] = "{\n"
		for _, k in ipairs(keys) do
			out[#out + 1] = indent .. "\t["
			out[#out + 1] = type(k) == "string" and string.format("%q", k) or tostring(k)
			out[#out + 1] = "] = "
			serialize(value[k], indent .. "\t", out)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = indent .. "}"
	elseif kind == "string" then
		out[#out + 1] = string.format("%q", value)
	else
		out[#out + 1] = tostring(value)
	end
end

--- @private
function HighlightDefaults:save()
	if not self.file then
		return
	end
	local out = { HEADER, "return " }
	serialize(self.data, "", out)
	out[#out + 1] = "\n"
	if not self.write(self.file, table.concat(out)) then
		Log:log_warn("C-130J highlights: unable to write " .. self.file)
	end
end

return HighlightDefaults
