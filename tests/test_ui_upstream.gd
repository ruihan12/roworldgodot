# godot --headless --path . -s res://tests/test_ui_upstream.gd
extends SceneTree
const NF := preload("res://ui_upstream/number_format.gd")
const TT := preload("res://ui_upstream/theme_tokens.gd")
func _init() -> void:
	var cases := {999.0: "999", 1234.0: "1.23K", 24567.0: "24.5K", 123456.0: "123K", 1259999.0: "1.25M", 25000000.0: "25.0M", 1999999999.0: "1.99B", -5.0: "0"}
	var fails := 0
	for k in cases:
		var got: String = NF.render_number(k)
		if got != cases[k]: fails += 1; print("FAIL render_number(%s) = %s want %s" % [k, got, cases[k]])
	if NF.render_troops(25000.0) != "2.50K": fails += 1
	if NF.fmt_time(3725.0) != "1:02:05" or NF.fmt_time(65.0) != "1:05": fails += 1
	if NF.fmt_cost(1500000.0) != "1.5M" or NF.fmt_cost(125000.0) != "125K": fails += 1
	if NF.fmt_pct(0.005) != "0.50%" or NF.fmt_pct(0.25) != "25.0%": fails += 1
	if NF.fmt_rate(0.2) != "±0/s" or NF.fmt_rate(1500.0) != "+1.5K/s": fails += 1
	if TT.AMBER.to_html(false) != "ffb547": fails += 1; print("AMBER ", TT.AMBER.to_html(false))
	var files := ["theme.json", "audio.json", "icons.json", "atlases.json", "catalog.json", "hotkeys.json", "number_format.json", "map_palette.json", "strings_by_screen.json"]
	for f in files:
		var d = JSON.parse_string(FileAccess.get_file_as_string("res://ui_upstream/" + f))
		if not (d is Dictionary): fails += 1; print("FAIL json ", f)
	print("UI_UPSTREAM_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
