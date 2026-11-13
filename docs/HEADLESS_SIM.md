# Headless Sim entry (for tests/upstream live cases)

`sim/headless_sim.gd` wraps a live main.gd match without the menu:

```gdscript
extends SceneTree
func _initialize(): _run()
func _run():
	var hs = load("res://sim/headless_sim.gd").new(self)
	await hs.ready_async()                                 # let main._ready finish
	var st: int = hs.start(0, 0, Vector2(0.5, 0.38), 60, 5e8)  # tab 0 real maps / 1 random / 2 RoWorld; spawn fraction; blob r; gold
	hs.step(300)                                           # 300 sim ticks (10/s)
	var m = hs.m                                           # main node
	m.try_build(5, tile)            # build (k = build id: 0 city 1 port 2 factory 3 defense 4 SAM 5 silo 10 artillery 14 airfield 15 railgun)
	m.launch_nuke(m.PLAYER, 7, tile)  # 7 atom 8 H 9 MIRV 11 mega 12 scatter
	m.sim_ars.launch_strike(m.PLAYER, SimRules.N_AIRSTRIKE, tile)
	m.propose_alliance(a, b); m.has_request(a, b); m.ally_reply(id, target, accept); m.request_cooldown_left(a, b)
	quit()
```

State: m.owner_map, m.nations[id] (troops, gold, land, alive, grudge_<id>), m.structs (k, tile, o, level, bt, shots, hp),
m.missiles, m.warships, m.boats, m.traders, m.attacks, m.allies, m.ally_requests, m.mirvs_launched,
m.sim_rules (SimRules, per-map k_lin), m.sim_ars (SimArsenal: ready_missiles, damage_struct, stats),
m.sim_ws (SimWarships: init_ship, stats), m.sim_naval, m.sim_atk.tick. Arsenal items are gated by
m.save.unlocked (ids: mega scatter reinf art air rail reload). main.gd --porttest is a worked example.
