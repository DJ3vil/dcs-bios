dofile(LockOn_Options.script_path .. "AMU_CNBP/definitions.lua")

-- the entry being edited is drawn a second time, on a box, and shown instead of the plain one
local point = amu_points[1]

local edited = CreateElement("ceStringPoly")
edited.name = create_guid_string()
edited.UseBackGround = true
edited.formats = { "<LEVEL %s" }
edited.init_pos = { point[1], point[2] }
edited.alignment = point[3]
Add(edited)

add_amu_page({ { { "<LEVEL %s%%", true } }, nil, nil, nil, "SET>", nil, nil, "MENU>" }, "EDIT PAGE")
