-- A minimal stand-in for the C-130J AMU page definitions, used by the AMU tests.
-- It lays pages out by the same rules as the module (keys beside fixed lines, entries built word
-- by word from the key inwards with a small gap after every word); it is not taken from it.

horz_edge = 0.9
height_start_amu = 0.825
amu_line = 0.147675
strdefcenter = { 0.00825, 0.006875 }

local title_y = height_start_amu - amu_line * 0.66
local word_scale = 11.6
local word_gap = 0.45

-- left keys beside lines 2, 4, 6 and 8, right keys beside lines 3, 5, 7 and 9
amu_points = {}
for k = 1, 4 do
	amu_points[k] = { -horz_edge, height_start_amu - amu_line * (2 * k), "LeftCenter" }
	amu_points[k + 4] = { horz_edge, height_start_amu - amu_line * (2 * k + 1), "RightCenter" }
end

local function add_text(value, format, x, y, alignment)
	local el = CreateElement("ceStringPoly")
	el.name = create_guid_string()
	el.value = value
	el.formats = { format }
	el.init_pos = { x, y }
	el.alignment = alignment
	Add(el)
	return el
end

local function words(label)
	if label:sub(1, 1) == "<" or label:sub(-1) == ">" then
		return { label }
	end
	local list = {}
	for word in label:gsub("%s/%s", "/"):gmatch("[^/]+") do
		if #list > 0 then
			list[#list + 1] = "/"
		end
		list[#list + 1] = word
	end
	return list
end

-- the running position along the entry, shared by its parts
local along = 0

function make_single_entry(k, y, alignment, label, is_format)
	local direction = k > 4 and -1 or 1
	for _, word in ipairs(words(label)) do
		if is_format then
			add_text(nil, word, along, y, alignment)
		else
			add_text(word, nil, along, y, alignment)
		end
		along = along + direction * strdefcenter[2] * (#word + word_gap) * word_scale
	end
end

function add_amu_page(entries, title)
	local main = CreateElement("ceTexPoly")
	main.name = create_guid_string()
	AddGeneral(main)

	add_text(title, nil, 0, title_y, "CenterCenter")

	for k = 1, 8 do
		local entry = entries[k]
		if entry ~= nil then
			local point = amu_points[k]
			along = point[1]
			if type(entry) == "table" then
				for _, part in ipairs(entry) do
					make_single_entry(k, point[2], point[3], part[1], part[2])
				end
			else
				make_single_entry(k, point[2], point[3], entry, false)
			end
		end
	end
end
