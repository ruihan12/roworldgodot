# The owner console opens with F2 (owner request 2026-11-28: "Make the console open via the F keys if possible";
# F2 is one that Edge and Chrome leave to the page) and still with Esc then Tab, only for the owner. This run has
# no owner token and no --console arg, so neither key opens it; then it runs itself again with the local
# --console arg (the owner stand-in offline), where F2 opens and closes it, Esc then Tab opens it, a lone Tab
# doesn't, and F2 does nothing on the title screen. A lone Tab toggles the leaderboard in a match (upstream
# UIInteract, owner request 2026-11-28 "Yes, match upstream"), for everyone, and Esc then Tab leaves it alone.
#   godot --headless --path . -s res://tests/test_console_keys.gd
extends SceneTree

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("  ok   " if ok else "  FAIL ") + what)


func _initialize() -> void:
	_run()


func _key(m, code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	m.get_viewport().push_input(ev)
	var up := InputEventKey.new()
	up.keycode = code
	up.physical_keycode = code
	up.pressed = false
	m.get_viewport().push_input(up)


func _board(m) -> bool:
	var hud = m.client
	return hud != null and hud.board != null and hud.board.expanded


func _run() -> void:
	var owner_run := "--console" in OS.get_cmdline_user_args()
	var hs = load("res://sim/headless_sim.gd").new(self)
	await hs.ready_async()
	var m = hs.m
	var who := "owner (--console)" if owner_run else "not the owner"
	if owner_run:
		_check(m.state != "play" and m.state != "pick", "the title screen is up first (state %s)" % m.state)
		_key(m, KEY_F2)
		_check(not m.console_panel.visible, "%s: F2 on the title screen opens nothing" % who)
		var t0: bool = _board(m)
		_key(m, KEY_TAB)
		_check(_board(m) == t0, "%s: Tab on the title screen leaves the leaderboard alone" % who)
	hs.start(0, 0, Vector2(0.5, 0.38), 0, -1.0)
	await process_frame
	_check(m.state == "play" or m.state == "pick", "a match is running (state %s)" % m.state)
	m._esc_msec = -100000
	var b0: bool = _board(m)
	_key(m, KEY_TAB)
	_check(_board(m) != b0 and not m.console_panel.visible, "%s: a lone Tab toggles the leaderboard (%s to %s)" % [who, b0, _board(m)])
	_key(m, KEY_TAB)
	_check(_board(m) == b0, "%s: Tab again toggles it back" % who)
	_check(m.console_panel != null and not m.console_panel.visible, "%s: the console starts closed" % who)
	_key(m, KEY_F2)
	if owner_run:
		_check(m.console_panel.visible, "%s: F2 opens the console" % who)
		_key(m, KEY_F2)
		_check(not m.console_panel.visible, "%s: F2 again closes it" % who)
		m._esc_msec = -100000
		_key(m, KEY_TAB)
		_check(not m.console_panel.visible, "%s: a lone Tab doesn't open it" % who)
		var b1: bool = _board(m)
		_key(m, KEY_ESCAPE)
		_key(m, KEY_TAB)
		_check(m.console_panel.visible, "%s: Esc then Tab still opens it" % who)
		_check(_board(m) == b1, "%s: Esc then Tab leaves the leaderboard alone" % who)
		_key(m, KEY_ESCAPE)
		_check(not m.console_panel.visible, "%s: Esc closes it" % who)
	else:
		_check(not m.console_panel.visible, "%s: F2 doesn't open the console" % who)
		_key(m, KEY_ESCAPE)
		_key(m, KEY_TAB)
		_check(not m.console_panel.visible, "%s: Esc then Tab doesn't open it" % who)
	m.queue_free()
	await process_frame
	if not owner_run:
		# the owner half, in a second run with the local --console arg
		var out := []
		var rc := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", "res://tests/test_console_keys.gd", "--", "--console"], out, true)
		var text := "\n".join(out)
		for line in text.split("\n"):
			if line.begins_with("  ok") or line.begins_with("  FAIL"):
				print(line)
		_check(rc == 0 and text.find("CONSOLE_KEYS_TEST PASS") >= 0, "the owner run passes (rc %d)" % rc)
	print("CONSOLE_KEYS_TEST %s fails=%d" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails else 0)
