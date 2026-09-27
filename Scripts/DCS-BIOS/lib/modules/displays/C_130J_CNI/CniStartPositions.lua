module("CniStartPositions", package.seeall)

-- Where the CNI-MU's toggles are on a new aircraft, per page and toggle key: whether each field is
-- lit in that position. Neither the sim nor the module says which word of a toggle is lit, so
-- these were read off the cockpit by a crew correcting the highlights on the CDU (SP), and a
-- toggle nothing else has settled is taken to be in its position the first time it is seen. The
-- crew's own corrections, kept in C-130J-Highlights.lua, come first, and every switch in the
-- aircraft is followed from wherever the toggle started.

--- @type { [string]: { [string]: { [string]: boolean } } }
local CniStartPositions = {
	CAPS_ACFT = {
		["4R:caps_dsp"] = { caps_dsp_all = true, caps_dsp_sel = false },
	},
	CAPS_INDEX = {
		["1L:caps_freq"] = { caps_freq_a = true, caps_freq_b = false, caps_freq_c = false, caps_freq_d = false },
		["1R:caps_power"] = { caps_power_off = true, caps_power_on = false },
		["3L:caps_clock"] = { caps_clock_master = false, caps_clock_slave = true },
	},
	DEF_SYS_1 = {
		["1L:def_mst_pwr"] = { def_mst_pwr_off = false, def_mst_pwr_on = true },
	},
	ECB = {
		["1L:ecb_hdd"] = { ecb_hdd_off = true, ecb_hdd_on = false },
		["2L:ecb_md"] = { ecb_md_bus = false, ecb_md_open = true, ecb_md_sys = false },
	},
	IFF_1 = {
		["1L:iff"] = { iff_emerg = false },
		["1R:iff"] = { iff_power = true },
		["2L:iff_mode"] = { iff_mode_s = true },
		["2R:iff_md"] = { iff_md_1 = false, iff_md_2 = false, iff_md_stby = true },
		["4L:iff_mode"] = { iff_mode_c = true },
		["5L:iff_mode"] = { iff_mode_3 = true },
	},
	IFF_3 = {
		["1L:iff_atc"] = { iff_atc_reply = true },
		["2L:iff_dl"] = { iff_dl_data = true },
	},
	MSN_IDX = {
		["1L:msn_sel"] = { msn_sel_rt1 = true, msn_sel_rt2 = false },
	},
	NAV_CTRL_1 = {
		["1L:nav_ctrl_1_egi1_sol"] = { nav_ctrl_1_egi1_sol_p = true },
		["6L:nav_ctrl"] = { nav_ctrl_auto = true, nav_ctrl_man = false },
	},
	PA_CONTROL = {
		["4R:routing"] = { routing_all = true, routing_cgo = false, routing_fs = false },
	},
	PERF_INIT_WGT = {
		["3R:wgt_pct_var"] = { wgt_pct_var_0 = false, wgt_pct_var_10 = true, wgt_pct_var_15 = false, wgt_pct_var_5 = false },
	},
	ROUTE_GEN = {
		["5R:route"] = { route_cp = true, route_nom = false, route_pp = false },
	},
	TACPLOT = {
		["1L:tacplot"] = { tacplot_aaa = false, tacplot_ai = false, tacplot_sam = true },
	},
	WT_BAL_IDX = {
		["5L:wt_bal"] = { wt_bal_ldg = false, wt_bal_to = true },
		["6L:wt_bal"] = { wt_bal_arm = true, wt_bal_mom = false },
	},
	ZEROIZE_1 = {
		["6L:zero_record_inhibit"] = { zero_record_inhibit_off = true, zero_record_inhibit_on = false },
	},
}

return CniStartPositions
