module("CniSchemaExtractor", package.seeall)

-- Records the layout of the CNI-MU pages from the module's own page scripts. The indication
-- only carries element names and values; position, font size and highlight exist only in the
-- page scripts, so each one is replayed under stubbed cockpit globals and every element it
-- Add()s is recorded. Nothing is written to the DCS installation, and no module data is shipped
-- with DCS-BIOS: the layout is read from the user's own installation at runtime.
-- Lua port of tools/cni-schema/extract.lua of WCtrlDcsBiosBridge, see
-- LICENSE-WCtrlDcsBiosBridge.txt.

local CniFormat = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniFormat")

--- @class CniCatalogueEntry
--- @field id integer
--- @field name string
--- @field path string

--- @class CniSchemaExtractor
local CniSchemaExtractor = {}

local MODULE_FOLDERS = { "C130J", "C-130J", "C-130J-30", "C130J-30" }

-- files that only pull in engine-backed element machinery, which is stubbed instead
local SKIP = {
	["elements_defs.lua"] = true,
	["devices_defs.lua"] = true,
	["materials.lua"] = true,
	["i_18n"] = true,
}

-- the display is 25 characters wide: (rpos - lpos) / advance is 25.05
local DEFAULT_ADVANCE = 0.003944

local function norm(path)
	return (path:gsub("\\", "/"))
end

local function with_slash(path)
	path = norm(path)
	if path:sub(-1) ~= "/" then
		path = path .. "/"
	end
	return path
end

local function basename(path)
	return norm(path):match("([^/]+)$") or path
end

local function noop() end

-- every page script loads the same shared files, so each file is compiled only once
local compiled = {}

--- @param path string
--- @return function? chunk
--- @return string? error
local function compile(path)
	local key = norm(path)
	local chunk = compiled[key]
	if chunk == nil then
		local err
		chunk, err = loadfile(key)
		if not chunk then
			return nil, err
		end
		compiled[key] = chunk
	end
	return chunk
end

--- Releases the compiled scripts once all pages have been read
function CniSchemaExtractor.clear_cache()
	compiled = {}
end

--- Builds the sandbox a page script runs in
--- @param recorder table receives every element the script Add()s
--- @param script_path string
--- @param common_path string
--- @param after_dofile (fun(name: string, env: table))? called after every file a script loads
--- @return table
local function new_env(recorder, script_path, common_path, after_dofile)
	local guid_seq = 0

	-- deterministic stand-ins for the engine's random GUIDs, which change every session
	local function create_guid_string()
		guid_seq = guid_seq + 1
		return string.format("stub-%04d", guid_seq)
	end

	local function CreateElement(kind)
		return { __kind = kind }
	end

	-- only elements built by add_cni_el are nudged vertically, and the nudge has to be undone
	-- to recover their line
	local in_add_cni_el = false

	local function Add(object)
		if in_add_cni_el then
			object.__nudged = true
		end
		recorder[#recorder + 1] = object
		return object
	end

	local function passthrough()
		return setmetatable({}, {
			__index = function(_, k)
				return k
			end,
		})
	end

	local base = {
		pairs = pairs,
		ipairs = ipairs,
		type = type,
		tostring = tostring,
		tonumber = tonumber,
		string = string,
		table = table,
		math = math,
		os = os,
		io = io,
		select = select,
		rawget = rawget,
		rawset = rawset,
		setmetatable = setmetatable,
		getmetatable = getmetatable,
		unpack = unpack,
		error = error,
		assert = assert,
		pcall = pcall,
		xpcall = xpcall,
		next = next,
		print = noop,
		require = function(name)
			if name == "lfs" then
				return {
					attributes = function()
						return nil
					end,
					mkdir = function()
						return true
					end,
				}
			end
			return setmetatable({}, {
				__index = function()
					return noop
				end,
			})
		end,

		-- cockpit globals normally provided by the engine
		CreateElement = CreateElement,
		Add = Add,
		AddGeneral = Add,
		create_guid_string = create_guid_string,
		SetScale = noop,
		GetScale = function()
			return 1.0
		end,
		GetAspect = function()
			return 0.75
		end,
		MakeMaterial = function(a, b)
			return { a, b }
		end,
		METERS = "METERS",
		LIGHT_SOURCES = {},
		blend_mode = passthrough(),
		indicator_types = passthrough(),
		render_purpose = passthrough(),
		materials = passthrough(),
		fonts = passthrough(),
		gettext = setmetatable({}, {
			__index = function()
				return function(s)
					return s
				end
			end,
		}),
		_ = function(s)
			return s
		end,

		-- from elements_defs.lua, which is skipped
		h_clip_relations = { REWRITE_LEVEL = 0, COMPARE = 1, NULL = 2 },
		default_box_indices = { 0, 1, 2, 0, 2, 3 },

		LockOn_Options = {
			script_path = script_path,
			common_script_path = common_path,
			init_conditions = { Aircraft = "C-130J-30" },
		},
	}

	base._G = base

	base.dofile = function(path)
		if SKIP[basename(path)] then
			return
		end
		local chunk, err = compile(path)
		if not chunk then
			error("dofile " .. tostring(path) .. ": " .. tostring(err), 0)
		end
		setfenv(chunk, base)
		local result = chunk()

		if basename(path) == "definitions.lua" then
			local inner = rawget(base, "add_cni_el")
			if type(inner) == "function" then
				local function finish(ok, ...)
					in_add_cni_el = false
					if not ok then
						error((...), 0)
					end
					return ...
				end
				base.add_cni_el = function(...)
					in_add_cni_el = true
					return finish(pcall(inner, ...))
				end
			end

			-- the lines stop at index 12, yet COMM TUNE asks for line 13 and the sim renders the
			-- whole page; extend the table by one line using the module's own spacing
			local lines = rawget(base, "cni_lines_")
			if type(lines) == "table" and lines[13] == nil and lines[12] and lines[11] then
				lines[13] = lines[12] - (lines[11] - lines[12])
			end
		end

		if after_dofile then
			after_dofile(basename(path), base)
		end

		return result
	end

	base.loadfile = function(path)
		local chunk = compile(path)
		if chunk then
			setfenv(chunk, base)
		end
		return chunk
	end

	return base
end

--- @param path string
--- @param env table
--- @return boolean? ok
--- @return string? error
local function run_file(path, env)
	local chunk, err = compile(path)
	if not chunk then
		return nil, "load: " .. tostring(err)
	end
	setfenv(chunk, env)
	local ok, run_err = pcall(chunk)
	if not ok then
		return nil, "run: " .. tostring(run_err)
	end
	return true
end

--- @param env table
--- @param y number?
--- @return integer? line
--- @return number? distance
local function nearest_line(env, y)
	local lines = env.cni_lines_
	if type(lines) ~= "table" or type(y) ~= "number" then
		return nil, nil
	end
	local best, best_d
	for i = 0, 13 do
		local ly = lines[i]
		if type(ly) == "number" then
			local d = math.abs(ly - y)
			if not best_d or d < best_d then
				best, best_d = i, d
			end
		end
	end
	return best, best_d
end

--- The character advance, from the module's own font tables
--- @param env table
--- @return number
local function advance(env)
	local large = env.LARGE_FONT_CNI
	if type(large) == "table" and type(large[2]) == "number" then
		return large[2]
	end
	return DEFAULT_ADVANCE
end

--- Character advances from the left edge of the page
--- @param env table
--- @param x number?
--- @return integer?
local function grid_column(env, x)
	if type(x) ~= "number" then
		return nil
	end
	local adv = advance(env)
	local left = env.lpos
	if type(left) ~= "number" or adv <= 0 then
		return nil
	end
	return math.floor((x - left) / adv + 0.5)
end

--- The rest of a value that is the page's own filler rather than text: a run of placeholders
--- ("------") or one letter repeated to the field's width ("AAA/")
--- @param value string
--- @return string?
local function placeholder_suffix(value)
	if value == "" then
		return nil
	end
	if value:match("^[%]%-]+$") then
		return ""
	end

	local letters, rest = value:match("^(%a+)(.-)$")
	if not letters or #letters < 2 or rest:match("%a") then
		return nil
	end
	for i = 2, #letters do
		if letters:sub(i, i) ~= letters:sub(1, 1) then
			return nil
		end
	end
	return rest
end

local function anchor_of(alignment)
	if type(alignment) ~= "string" then
		return "Left"
	end
	if alignment:find("^Center") then
		return "Center"
	end
	if alignment:find("^Right") then
		return "Right"
	end
	return "Left"
end

--- Undoes the vertical nudge add_cni_el gives small text, away from the centre
local function unshift(env, el, y)
	if type(y) ~= "number" then
		return y
	end
	if not el.__nudged or el.stringdefs ~= env.SMALL_FONT_CNI then
		return y
	end
	return y > 0 and (y - 0.01) or (y + 0.01)
end

--- @param env table
--- @param el table
--- @param ordinal integer
--- @return CniRawSlot
local function describe(env, el, ordinal)
	local pos = type(el.init_pos) == "table" and el.init_pos or {}
	local x, y = pos[1], unshift(env, el, pos[2])
	local line, dist = nearest_line(env, y)

	local ctrl
	if type(el.controllers) == "table" then
		for _, c in ipairs(el.controllers) do
			if type(c) == "table" and type(c[1]) == "string" then
				ctrl = c[1]
				break
			end
		end
	end

	-- formats may be a list of alternatives the controller selects between
	local fmts
	if type(el.formats) == "table" then
		fmts = {}
		for _, f in ipairs(el.formats) do
			if type(f) == "string" then
				fmts[#fmts + 1] = f
			end
		end
		if #fmts == 0 then
			fmts = nil
		end
	elseif type(el.formats) == "string" then
		fmts = { el.formats }
	end

	-- a value still carrying a conversion is a format the page never filled in, and a
	-- controller-driven value holding its own filler is not text the sim will draw again
	local value = type(el.value) == "string" and el.value or nil
	if value and CniFormat.has_conversion(value) then
		fmts = fmts or {}
		fmts[#fmts + 1] = value
		value = nil
	elseif value and ctrl then
		local suffix = placeholder_suffix(value)
		if suffix then
			fmts = fmts or {}
			fmts[#fmts + 1] = "%s" .. suffix
			value = nil
		end
	end

	local small = el.stringdefs ~= nil and (el.stringdefs == env.SMALL_FONT_CNI or el.stringdefs == env.SMALL_FONT_CNI0)

	return {
		n = ordinal,
		kind = el.__kind,
		name = el.name,
		value = value,
		fmt = fmts,
		ctrl = ctrl,
		anchor = anchor_of(el.alignment),
		line = line,
		lineErr = (dist and dist > 0.0015) and dist or nil,
		col = grid_column(env, x),
		small = small or nil,
		invert = el.material == "cni_font_green_invert" or nil,
		parent = el.parent_element,
	}
end

local function exists(path)
	return lfs ~= nil and lfs.attributes ~= nil and lfs.attributes(path) ~= nil
end

--- Finds the module's cockpit scripts in the DCS installation
--- @param marker string? a file the scripts folder holds, CNI_MU/init_gen.lua by default
--- @return string? script_path
--- @return string? common_path
function CniSchemaExtractor.find_script_root(marker)
	marker = marker or "CNI_MU/init_gen.lua"
	if lfs == nil or lfs.currentdir == nil then
		return nil, nil
	end

	local install = with_slash(lfs.currentdir())
	local common = install .. "Scripts/Aircrafts/_Common/Cockpit/"

	local roots = { install }
	if lfs.writedir then
		roots[#roots + 1] = with_slash(lfs.writedir())
	end

	for _, root in ipairs(roots) do
		local folders = {}
		for _, folder in ipairs(MODULE_FOLDERS) do
			folders[#folders + 1] = folder
		end
		if lfs.dir then
			pcall(function()
				for entry in lfs.dir(root .. "Mods/aircraft") do
					if entry ~= "." and entry ~= ".." then
						folders[#folders + 1] = entry
					end
				end
			end)
		end

		for _, folder in ipairs(folders) do
			local scripts = root .. "Mods/aircraft/" .. folder .. "/Cockpit/Scripts/"
			if exists(scripts .. marker) then
				return scripts, common
			end
		end
	end

	return nil, nil
end

--- Lists the CNI-MU pages declared by the module
--- @param script_path string
--- @param common_path string
--- @return CniCatalogueEntry[]
function CniSchemaExtractor.catalogue(script_path, common_path)
	local env = new_env({}, script_path, common_path)
	local ok, err = run_file(script_path .. "CNI_MU/init_gen.lua", env)
	if not ok then
		error("init_gen.lua: " .. tostring(err), 0)
	end

	-- page_subsets is keyed by the numeric page constants; recover their names
	local names = {}
	for k, v in pairs(env) do
		if type(k) == "string" and type(v) == "number" and k:upper() == k then
			if names[v] == nil or k < names[v] then
				names[v] = k
			end
		end
	end

	local pages = {}
	for id, path in pairs(env.page_subsets or {}) do
		if type(id) == "number" and type(path) == "string" then
			pages[#pages + 1] = { id = id, name = names[id] or ("PAGE_" .. tostring(id)), path = path }
		end
	end
	table.sort(pages, function(a, b)
		return a.id < b.id
	end)
	return pages
end

--- The sandbox the page scripts run in, for the other displays the module builds the same way
--- @param recorder table receives every element the script Add()s
--- @param script_path string
--- @param common_path string
--- @param after_dofile (fun(name: string, env: table))? called after every file a script loads
--- @return table
function CniSchemaExtractor.new_sandbox(recorder, script_path, common_path, after_dofile)
	return new_env(recorder, script_path, common_path, after_dofile)
end

--- Runs a script in a sandbox
--- @param path string
--- @param env table
--- @return boolean? ok
--- @return string? error
function CniSchemaExtractor.run_file(path, env)
	return run_file(path, env)
end

--- Replays one page script and records what it builds. A page that fails part-way still
--- yields everything added before the fault.
--- @param script_path string
--- @param common_path string
--- @param page CniCatalogueEntry
--- @return CniRawPage
function CniSchemaExtractor.extract_page(script_path, common_path, page)
	local recorded = {}
	local env = new_env(recorded, script_path, common_path)
	local ok, err = run_file(page.path, env)

	local slots = {}
	for i, el in ipairs(recorded) do
		slots[i] = describe(env, el, i)
	end

	return {
		id = page.id,
		name = page.name,
		file = basename(page.path),
		partial = (not ok) or nil,
		error = (not ok) and err or nil,
		slots = slots,
	}
end

return CniSchemaExtractor
