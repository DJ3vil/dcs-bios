dofile(LockOn_Options.script_path .. "AMU_CNBP/definitions.lua")

add_amu_page({
	"PILOT/COPILOT",
	{ { "BARO" }, { "IN/MB" } },
	"MAG / TRUE / GRID",
	{ { "SOURCE" }, { "%s", true } },
	{ { "2/1" }, { "REF UNIT" } },
	nil,
	nil,
	"MENU>",
}, "TEST DISPLAY")
