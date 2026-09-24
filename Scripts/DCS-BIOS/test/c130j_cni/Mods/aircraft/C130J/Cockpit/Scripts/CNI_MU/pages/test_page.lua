dofile(LockOn_Options.script_path .. "CNI_MU/definitions.lua")

local background = CreateElement("ceTexPoly")
background.name = create_guid_string()
background.init_pos = { 0, 0 }
Add(background)

local title = add_cni_el("TEST PAGE", 0, 13, LARGE_FONT_CNI, "CenterCenter")
title.name = "cni_title"
add_cni_el("1/2", 0, 25, SMALL_FONT_CNI, "RightCenter")
add_cni_el("FREQ", 1, 1, SMALL_FONT_CNI, "LeftCenter")
add_cni_el(nil, 2, 0, LARGE_FONT_CNI, "LeftCenter", "uhf1_freq", { "%d/%s" })
add_cni_el("SQL", 3, 1, SMALL_FONT_CNI, "LeftCenter")
add_cni_toggle("uhf1_sql", 4, 0, "ON", "OFF")
add_cni_el("<INDEX", 12, 0, LARGE_FONT_CNI, "LeftCenter")
local scratchpad = add_cni_el(nil, 13, 0, LARGE_FONT_CNI, "LeftCenter", "cni_scratch", { "%s" })
scratchpad.name = "cni_scratchpad"
