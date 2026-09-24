-- A minimal stand-in for the CNI-MU page helpers, used by the CNI-MU tests.

dofile(LockOn_Options.common_script_path .. "elements_defs.lua")

LARGE_FONT_CNI = { 0.0045, 0.004, 0, 0 }
SMALL_FONT_CNI = { 0.0035, 0.004, 0, 0 }
SMALL_FONT_CNI0 = { 0.0035, 0.004, 0, 0 }

lpos = -0.05

-- lines 0 (title) to 12; the scratchpad asks for line 13 like the module's pages do
cni_lines_ = {}
for i = 0, 12 do
	cni_lines_[i] = 0.052 - i * 0.008
end

function add_cni_el(value, line, col, font, alignment, controller, formats)
	local el = CreateElement("ceStringPoly")
	el.name = create_guid_string()
	el.value = value
	el.stringdefs = font
	el.alignment = alignment
	el.init_pos = { lpos + col * LARGE_FONT_CNI[2], cni_lines_[line] }
	-- small text is nudged away from the centre
	if font == SMALL_FONT_CNI then
		el.init_pos[2] = el.init_pos[2] > 0 and el.init_pos[2] + 0.01 or el.init_pos[2] - 0.01
	end
	if controller then
		el.controllers = { { controller } }
	end
	el.formats = formats
	Add(el)
	return el
end

-- one container per position, each holding both words; the selected word is inverted
function add_cni_toggle(field, line, col, first, second)
	for _, state in ipairs({ "on", "off" }) do
		local container = CreateElement("ceSimple")
		container.name = create_guid_string()
		container.init_pos = { lpos + col * LARGE_FONT_CNI[2], cni_lines_[line] }
		container.controllers = { { field .. "_" .. state } }
		Add(container)

		for i, word in ipairs({ first, second }) do
			local el = CreateElement("ceStringPoly")
			el.name = create_guid_string()
			el.value = word
			el.parent_element = container.name
			el.stringdefs = LARGE_FONT_CNI
			el.alignment = "LeftCenter"
			el.init_pos = { lpos + (col + (i - 1) * 4) * LARGE_FONT_CNI[2], cni_lines_[line] }
			if (state == "on") == (i == 1) then
				el.material = materials.cni_font_green_invert
			end
			Add(el)
		end
	end
end
