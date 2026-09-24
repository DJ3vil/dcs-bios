dofile(LockOn_Options.script_path .. "CNI_MU/definitions.lua")

local title = add_cni_el(nil, 0, 13, LARGE_FONT_CNI, "CenterCenter", "rte_title", { "%sRTE %d" })
title.name = "cni_title"
add_cni_el("ORIGIN", 1, 1, SMALL_FONT_CNI, "LeftCenter")
add_cni_el(nil, 2, 0, LARGE_FONT_CNI, "LeftCenter", "rte_origin", { "%s" })
add_cni_el("ERASE>", 12, 25, LARGE_FONT_CNI, "RightCenter")
