-- A minimal stand-in for the C-130J AMU page catalogue, used by the AMU tests.
-- It mimics the structure the extractor expects; it is not taken from the module.

BASE = 0
MENU = 1
DISPLAY = 2
RANGE_PAGE = 3
DISPLAY_COPY = 4
EDIT = 5

page_subsets = {
	[BASE] = LockOn_Options.script_path .. "AMU_CNBP/pages/base.lua",
	[MENU] = LockOn_Options.script_path .. "AMU_CNBP/pages/menu.lua",
	[DISPLAY] = LockOn_Options.script_path .. "AMU_CNBP/pages/display.lua",
	[RANGE_PAGE] = LockOn_Options.script_path .. "AMU_CNBP/pages/range.lua",
	-- a second page drawn by the same file
	[DISPLAY_COPY] = LockOn_Options.script_path .. "AMU_CNBP/pages/display.lua",
	[EDIT] = LockOn_Options.script_path .. "AMU_CNBP/pages/edit.lua",
}
