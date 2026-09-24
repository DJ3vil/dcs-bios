dofile(LockOn_Options.script_path .. "AMU_CNBP/definitions.lua")

-- drawn over each other beside the first right key: the label and the range filled in
local point = amu_points[5]

local label = CreateElement("ceStringPoly")
label.name = create_guid_string()
label.formats = { "RANGE  %s>" }
label.init_pos = { point[1], point[2] }
label.alignment = point[3]
Add(label)

local range = CreateElement("ceStringPoly")
range.name = create_guid_string()
range.formats = { "%0.0f>" }
range.init_pos = { point[1], point[2] }
range.alignment = point[3]
Add(range)

add_amu_page({ "TEST RANGE", nil, nil, nil, nil, nil, nil, "MENU>" }, "RANGE PAGE")
