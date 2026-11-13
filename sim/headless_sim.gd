# Headless entry to the live port Sim (main.gd), for tests that need a running match.
#   var hs = load("res://sim/headless_sim.gd").new(self)   # self: a SceneTree script (godot -s ...)
#   await hs.ready_async()                                   # one frame so main._ready's deferred calls run
#   var st = hs.start(0, 0, Vector2(0.5, 0.38), 60, 5e8)     # World, player blob r60, 500M gold
#   hs.step(300); hs.m.launch_nuke(hs.m.PLAYER, 7, tile) ...
# hs.m is the main node: owner_map, nations, structs, missiles, warships, boats, traders, attacks, allies,
# ally_requests, sim_rules (SimRules), sim_ars (SimArsenal), sim_ws (SimWarships), sim_naval, sim_atk.
extends RefCounted

var m: Node
var tree: SceneTree

func _init(t: SceneTree) -> void:
	tree = t
	m = load("res://main.tscn").instantiate()
	tree.root.add_child(m)

func ready_async() -> void:
	await tree.process_frame
	await tree.process_frame

func start(tab := 0, idx := 0, at := Vector2(0.5, 0.38), claim_r := 0, gold := -1.0) -> int:
	return m.sim_start(tab, idx, at, claim_r, gold)

func step(n := 1) -> void:
	m.sim_step(n)

func tick() -> int:
	return m.sim_tick()

func owner(tile: int) -> int:
	return m.owner_map[tile]

func nation(id: int) -> Dictionary:
	return m.nations[id]

func free() -> void:
	if is_instance_valid(m): m.queue_free()
