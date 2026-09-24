-- A minimal stand-in for the C-130J CNI-MU page catalogue, used by the CNI-MU tests.
-- It mimics the structure the extractor expects; it is not taken from the module.

TEST_PAGE = 1
ROUTE = 2

page_subsets = {
	[TEST_PAGE] = LockOn_Options.script_path .. "CNI_MU/pages/test_page.lua",
	[ROUTE] = LockOn_Options.script_path .. "CNI_MU/pages/route.lua",
}
