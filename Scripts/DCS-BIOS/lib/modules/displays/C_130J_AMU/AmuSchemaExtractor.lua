module("AmuSchemaExtractor", package.seeall)

-- Records the layout of the AMU pages from the module's own page scripts, in the form the CNI-MU
-- page machinery works with (see CniSchema). The indication only carries element names and
-- values, so every page script is replayed in the same sandbox as the CNI-MU pages and every
-- element it Add()s is recorded. Nothing is shipped with DCS-BIOS: the layout is read from the
-- user's own installation at runtime.
--
-- An AMU page is a title and up to eight entries, one beside each line select key: the left keys
-- sit beside lines 2, 4, 6 and 8, the right keys beside lines 3, 5, 7 and 9. An entry is laid out
-- word by word, from the key towards the middle, with a sliver of space after every word. A
-- character grid cannot show a sliver, so the words of one part of an entry are put next to
-- each other and the parts of it one space apart.

local CniFormat = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniFormat")
local CniSchemaExtractor = require("Scripts.DCS-BIOS.lib.modules.displays.C_130J_CNI.CniSchemaExtractor")

--- @class AmuSchemaExtractor
local AmuSchemaExtractor = {}

-- the width between the two rows of keys, (horz_edge * 2) / advance is 22.6
AmuSchemaExtractor.COLUMNS = 23
-- the title, the lines below it with the keys beside lines 2 to 9, and one more at the bottom
AmuSchemaExtractor.LINES = 11

local INIT_GEN = "AMU_CNBP/init_gen.lua"

--- Finds the module's cockpit scripts in the DCS installation
--- @return string? script_path
--- @return string? common_path
function AmuSchemaExtractor.find_script_root()
	return CniSchemaExtractor.find_script_root(INIT_GEN)
end

-- fallbacks for a page that does not load the module's definitions
local DEFAULT_EDGE = 0.9
local DEFAULT_ADVANCE = 0.07975
-- how the module turns a text width into a position: strdefcenter[2] * (length + gap) * scale
local WIDTH_SCALE = 11.6
local WORD_GAP = 0.45

local function round(x)
	return math.floor(x + 0.5)
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

--- The width of one character in page coordinates
--- @param env table
--- @return number
local function advance(env)
	local strdef = rawget(env, "strdefcenter")
	if type(strdef) == "table" and type(strdef[2]) == "number" and strdef[2] > 0 then
		return strdef[2] * WIDTH_SCALE
	end
	return DEFAULT_ADVANCE
end

--- @param env table
--- @return number
local function edge(env)
	local e = rawget(env, "horz_edge")
	return type(e) == "number" and e or DEFAULT_EDGE
end

--- The line of a position: the keys sit on whole lines below the top, the title above them
--- @param env table
--- @param y number?
--- @return integer?
local function line_of(env, y)
	local top, pitch = rawget(env, "height_start_amu"), rawget(env, "amu_line")
	if type(y) ~= "number" or type(top) ~= "number" or type(pitch) ~= "number" or pitch <= 0 then
		return nil
	end
	local n = (top - y) / pitch
	if n < 1 then
		return 0
	end
	local line = round(n)
	if line >= AmuSchemaExtractor.LINES then
		return nil
	end
	return line
end

--- The column a text is anchored on: its first column when anchored on the left or the centre,
--- one past its last when anchored on the right
--- @param env table
--- @param el table
--- @param x number?
--- @param anchor string
--- @return integer?
local function column_of(env, el, x, anchor)
	if type(x) ~= "number" then
		return nil
	end
	local adv, e = advance(env), edge(env)
	local word = el.__amu_word

	if word then
		-- how far along the entry the module put the word, less the slivers after the words before
		-- it, plus one space for every part of the entry before this one
		local along = math.abs(x - word.x0) / adv - WORD_GAP * word.index
		if anchor == "Right" then
			local last = AmuSchemaExtractor.COLUMNS - round((e - word.x0) / adv)
			return round(last - along - (word.part - 1))
		end
		local first = round((word.x0 + e) / adv)
		return round(first + along + (word.part - 1))
	end

	-- text placed a little outside the keys is kept on the grid
	if anchor == "Right" then
		return math.min(AmuSchemaExtractor.COLUMNS, AmuSchemaExtractor.COLUMNS - round((e - x) / adv))
	end
	return math.max(0, round((x + e) / adv))
end

--- @param env table
--- @param el table
--- @param ordinal integer
--- @return CniRawSlot
local function describe(env, el, ordinal)
	local pos = type(el.init_pos) == "table" and el.init_pos or {}
	local anchor = anchor_of(el.alignment)

	local fmts
	if type(el.formats) == "table" then
		for _, f in ipairs(el.formats) do
			if type(f) == "string" then
				fmts = fmts or {}
				fmts[#fmts + 1] = f
			end
		end
	end

	local value = type(el.value) == "string" and el.value or nil
	if value and CniFormat.has_conversion(value) then
		fmts = fmts or {}
		fmts[#fmts + 1] = value
		value = nil
	end

	return {
		n = ordinal,
		kind = el.__kind,
		name = el.name,
		value = value,
		fmt = fmts,
		anchor = anchor,
		line = line_of(env, pos[2]),
		col = column_of(env, el, pos[1], anchor),
	}
end

--- Lists the AMU pages declared by the module, each page file once
--- @param script_path string
--- @param common_path string
--- @return CniCatalogueEntry[]
function AmuSchemaExtractor.catalogue(script_path, common_path)
	local env = CniSchemaExtractor.new_sandbox({}, script_path, common_path)
	env.AMU = { { 1, 17 } }
	local ok, err = CniSchemaExtractor.run_file(script_path .. INIT_GEN, env)
	if not ok then
		error("AMU init_gen.lua: " .. tostring(err), 0)
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
		-- the blank page drawn while the unit is off has nothing to show
		if type(id) == "number" and type(path) == "string" and id ~= env.BASE then
			pages[#pages + 1] = { id = id, name = names[id] or ("PAGE_" .. tostring(id)), path = path }
		end
	end
	table.sort(pages, function(a, b)
		return a.id < b.id
	end)

	-- several pages are drawn by the same file (the HDD POS variants); read each file once
	local unique, seen = {}, {}
	for _, page in ipairs(pages) do
		if not seen[page.path] then
			seen[page.path] = true
			unique[#unique + 1] = page
		end
	end
	return unique
end

--- Replays one page script and records what it builds. A page that fails part-way still yields
--- everything added before the fault.
--- @param script_path string
--- @param common_path string
--- @param page CniCatalogueEntry
--- @return CniRawPage
function AmuSchemaExtractor.extract_page(script_path, common_path, page)
	-- the entry being laid out: which key it belongs to and how far along it the module is
	local entry = nil
	local entries = {}

	local recorded = setmetatable({}, {
		__newindex = function(t, i, el)
			rawset(t, i, el)
			if entry and type(el) == "table" then
				local pos = type(el.init_pos) == "table" and el.init_pos or {}
				entry.x0 = entry.x0 or pos[1]
				el.__amu_word = { x0 = entry.x0, index = entry.words, part = entry.parts }
				entry.words = entry.words + 1
			end
		end,
	})

	local wrapped = {}
	local function after_dofile(name, env)
		if name ~= "definitions.lua" then
			return
		end
		local inner = rawget(env, "make_single_entry")
		if type(inner) ~= "function" or wrapped[inner] then
			return
		end

		local function finish(ok, ...)
			entry = nil
			if not ok then
				error((...), 0)
			end
			return ...
		end
		local function make_single_entry(k, ...)
			local current = entries[k] or { words = 0, parts = 0 }
			entries[k] = current
			current.parts = current.parts + 1
			entry = current
			return finish(pcall(inner, k, ...))
		end
		wrapped[make_single_entry] = true
		env.make_single_entry = make_single_entry
	end

	local env = CniSchemaExtractor.new_sandbox(recorded, script_path, common_path, after_dofile)
	local ok, err = CniSchemaExtractor.run_file(page.path, env)

	local slots = {}
	for i, el in ipairs(recorded) do
		slots[i] = describe(env, el, i)
	end

	return {
		id = page.id,
		name = page.name,
		partial = (not ok) or nil,
		error = (not ok) and err or nil,
		slots = slots,
	}
end

return AmuSchemaExtractor
