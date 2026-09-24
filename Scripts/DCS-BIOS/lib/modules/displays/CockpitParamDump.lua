module("CockpitParamDump", package.seeall)

-- Writes the cockpit parameters an aircraft publishes (list_cockpit_params) to a file, for finding
-- out whether a state its displays draw, but do not report as text, is published there. Meant to
-- be switched on for a session while troubleshooting, like IndicatorDump: the first write holds
-- every parameter, the later ones only those that changed, and a parameter that keeps changing
-- (a gauge, a timer) is left out after a few changes. Presses of the keys given are written as
-- they happen, so that a change can be put down to the press before it. The methods the devices
-- given offer are written once as well.

--- @class CockpitParamDumpOptions
--- @field file string the file to append to
--- @field keys { [integer]: string }? draw arguments of the keys to note presses of, with their names
--- @field devices { [integer]: string }? ids of the devices to list the methods of, with their names
--- @field interval integer? seconds between two looks at the parameters, 2 by default
--- @field noisy_after integer? changes after which a parameter is left out, 10 by default
--- @field max_bytes integer? bytes written before the dump stops, 2000000 by default
--- @field list_cockpit_params (fun(): string)?
--- @field get_device (fun(id: integer): any)?
--- @field time (fun(): integer)?

--- @class CockpitParamDumpKey
--- @field arg integer
--- @field name string

--- @class CockpitParamDump
--- @field private file string
--- @field private keys CockpitParamDumpKey[]
--- @field private devices { [integer]: string }
--- @field private interval integer
--- @field private noisy_after integer
--- @field private max_bytes integer
--- @field private list_cockpit_params fun(): string
--- @field private get_device fun(id: integer): any
--- @field private time fun(): integer
--- @field private written integer
--- @field private last_look integer?
--- @field private params { [string]: string }?
--- @field private changes { [string]: integer }
--- @field private pressed { [integer]: boolean }
local CockpitParamDump = {}

--- @param options CockpitParamDumpOptions
--- @return CockpitParamDump
function CockpitParamDump:new(options)
	local keys = {}
	for arg, name in pairs(options.keys or {}) do
		keys[#keys + 1] = { arg = arg, name = name }
	end
	table.sort(keys, function(a, b)
		return a.arg < b.arg
	end)

	local o = {
		file = options.file,
		keys = keys,
		devices = options.devices or {},
		interval = options.interval or 2,
		noisy_after = options.noisy_after or 10,
		max_bytes = options.max_bytes or 2000000,
		list_cockpit_params = options.list_cockpit_params or function()
			return list_cockpit_params()
		end,
		get_device = options.get_device or function(id)
			return GetDevice(id)
		end,
		time = options.time or os.time,
		written = 0,
		last_look = nil,
		params = nil,
		changes = {},
		pressed = {},
	}
	setmetatable(o, self)
	self.__index = self
	return o
end

--- Called on every export tick
--- @param dev0 CockpitDevice? the cockpit device, to read the keys from
function CockpitParamDump:update(dev0)
	if self.written >= self.max_bytes then
		return
	end

	if dev0 then
		self:check_keys(dev0)
	end

	local now = self.time()
	if self.last_look and now - self.last_look < self.interval then
		return
	end
	self.last_look = now
	self:check_params()
end

--- @private
--- @param text string
function CockpitParamDump:write(text)
	local file = io.open(self.file, "a")
	if not file then
		return
	end
	file:write(text)
	file:close()
	self.written = self.written + #text
end

--- @private
--- @param dev0 CockpitDevice
function CockpitParamDump:check_keys(dev0)
	local presses = {}
	for _, key in ipairs(self.keys) do
		local ok, value = pcall(dev0.get_argument_value, dev0, key.arg)
		local down = ok and type(value) == "number" and value > 0.5
		-- a key found down on the first look was not seen being pressed
		if down and self.pressed[key.arg] == false then
			presses[#presses + 1] = key.name
		end
		self.pressed[key.arg] = down
	end

	if #presses > 0 then
		self:write(string.format("=== %s pressed %s\n", os.date("%H:%M:%S"), table.concat(presses, " ")))
	end
end

--- @param text string one parameter per line, name and value split at the last colon
--- @return { [string]: string }
local function parse(text)
	local params = {}
	for line in text:gmatch("[^\r\n]+") do
		local name, value = line:match("^(.*):([^:]*)$")
		if name then
			params[name] = value
		end
	end
	return params
end

--- @param ... { [string]: any }
--- @return string[]
local function sorted_names(...)
	local names, seen = {}, {}
	for _, map in ipairs({ ... }) do
		for name in pairs(map) do
			if not seen[name] then
				seen[name] = true
				names[#names + 1] = name
			end
		end
	end
	table.sort(names)
	return names
end

--- The names a device answers to, where its metatable gives them away
--- @param device any
--- @return string?
local function methods_of(device)
	local mt = getmetatable(device)
	local index = type(mt) == "table" and rawget(mt, "__index") or nil
	if type(index) ~= "table" then
		return nil
	end

	local names = {}
	for name in pairs(index) do
		names[#names + 1] = tostring(name)
	end
	table.sort(names)
	return table.concat(names, " ")
end

--- @private
--- @param stamp string
--- @return string
function CockpitParamDump:describe_devices(stamp)
	local ids = {}
	for id in pairs(self.devices) do
		ids[#ids + 1] = id
	end
	table.sort(ids)

	local out = {}
	for _, id in ipairs(ids) do
		local ok, device = pcall(self.get_device, id)
		local methods = nil
		if ok and device ~= nil then
			local listed, names = pcall(methods_of, device)
			methods = listed and names or nil
		end
		out[#out + 1] = string.format("=== %s device %d %s: %s\n", stamp, id, self.devices[id], (not ok or device == nil) and "not found" or (methods or "methods not listed"))
	end
	return table.concat(out)
end

--- @private
function CockpitParamDump:check_params()
	local ok, text = pcall(self.list_cockpit_params)
	if not ok or type(text) ~= "string" then
		return
	end

	local params = parse(text)
	local stamp = os.date("%H:%M:%S")

	if not self.params then
		self.params = params
		local names = sorted_names(params)
		local out = { self:describe_devices(stamp), string.format("=== %s all %d parameters\n", stamp, #names) }
		for _, name in ipairs(names) do
			out[#out + 1] = name .. " = " .. params[name] .. "\n"
		end
		self:write(table.concat(out))
		return
	end

	local out = {}
	for _, name in ipairs(sorted_names(self.params, params)) do
		local before, after = self.params[name], params[name]
		if before ~= after then
			local changes = (self.changes[name] or 0) + 1
			self.changes[name] = changes
			if changes <= self.noisy_after then
				local note = changes == self.noisy_after and " (keeps changing, left out from now on)" or ""
				out[#out + 1] = string.format("%s: %s -> %s%s\n", name, tostring(before), tostring(after), note)
			end
		end
	end
	self.params = params

	if #out > 0 then
		self:write(string.format("=== %s changed\n", stamp) .. table.concat(out))
	end
end

return CockpitParamDump
