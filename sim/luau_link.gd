class_name LuauLink
extends RefCounted
## Keeps Luau's world state (luau/sim/Core/SimState.luau) equal to the GDScript one while the sim is half ported
## (docs/LUAU_PORT.md, Steps 4 and 5), and runs the Luau sim modules' calls.
## The match's GDScript side records every owner / fallout change it makes (map.gd _set_owner and
## sim/arsenal.gd nuke_blast append (tile, value) pairs to luau_dirty / luau_fdirty). flush() sends them to Luau,
## which replays them through its own set_owner (land counts, bounding boxes, border sets follow, in order).
## apply() writes back what a Luau call did, in the order it did it: owner changes through the game's own
## _set_owner (borders, land / pop / bounding box, structure capture, net replication and the fallout clear all
## follow, and the border dicts end in the order Luau's lists have), fallout like nuke_blast sets it, events
## (viewer events, attacked_tick / grudges, conquests), then the troops of every nation the call changed.
## lcall() = flush -> the Luau function -> apply, so writes of both sides land in the order they happened.
## sync() = flush + pull runs at the end of each tick, so at every tick boundary both copies hold the same state.
## A new map (sim_epoch) starts Luau from full copies. Without the extension the link stays off and the sim runs
## in GDScript as before.

const STATE := "Core/SimState"
const MODULES := ["Core/SimState", "Core/SimAttacks", "Core/SimStructures", "Core/SimArsenal", "Core/SimRails"]
const EV_VIEWER_ATTACK := 1
const EV_HOSTILE := 2
const EV_CONQUEST := 3

var vm: LuauVM = null
var on := false
var epoch := -1
var error := ""
## ops applied by the last apply (tests)
var applied_owner := 0
var applied_fall := 0
var applied_ev := 0


func _init() -> void:
	_start()
	# one line per game in the log / browser console: which sim runs (docs/LUAU_PORT.md Step 6)
	if not on: print("Luau sim: off, GDScript fallback (%s)" % error)
	elif OS.has_environment("NO_LUAU_SIM"): print("Luau sim: off, GDScript fallback (NO_LUAU_SIM)")
	else: print("Luau sim: on")


func _start() -> void:
	if not LuauVM.available():
		error = "Luau extension not loaded"
		return
	vm = LuauVM.new()
	if not vm.boot():
		error = vm.last_error
		vm = null
		return
	for m in MODULES:
		if not vm.require_module(m):
			error = vm.last_error
			vm = null
			return
	on = true


## At the end of every tick (game/audio.gd _sim_tick_end).
func sync(g) -> void:
	if flush(g): pull(g)


## GDScript's changes since the last flush -> Luau (a new map: full copies first). False when the link is off.
func flush(g) -> bool:
	if not on: return false
	if epoch != g.sim_epoch or not g.luau_rec:
		_begin(g)
		return on
	if g.luau_dirty.is_empty() and g.luau_fdirty.is_empty(): return true
	var ok: Variant = vm.call_fn(STATE, "push", [g.luau_dirty.to_byte_array(), g.luau_fdirty.to_byte_array(), g.nations.size()])
	g.luau_dirty.clear()
	g.luau_fdirty.clear()
	if ok == null:
		_fail(g, vm.last_error)
		return false
	return true


## Luau modules' changes since the last take -> GDScript.
func pull(g) -> void:
	if not on: return
	var out: Variant = vm.call_fn(STATE, "take", [])
	if out == null:
		_fail(g, vm.last_error)
		return
	apply(g, out)


## flush -> module.fn(args) -> apply. Returns the call's result table (a Dictionary), null when the link failed.
func lcall(g, module: String, fn: String, args: Array) -> Variant:
	if not flush(g): return null
	var out: Variant = vm.call_fn(module, fn, args)
	if out == null:
		_fail(g, vm.last_error)
		return null
	apply(g, out)
	return out


## A Luau call's result -> GDScript, in stream order (see SimState.take). Owner recording is off meanwhile (Luau
## has those values); a fallout clear _set_owner makes is recorded and goes to Luau with the next flush.
func apply(g, out: Dictionary) -> void:
	var oi: PackedInt32Array = (out.ops as PackedByteArray).to_int32_array()
	var ev: PackedFloat64Array = (out.evs as PackedByteArray).to_float64_array()
	applied_owner = 0
	applied_fall = 0
	applied_ev = 0
	if not oi.is_empty():
		g.luau_rec = false
		for k in range(0, oi.size(), 2):
			var i: int = oi[k]
			var v: int = oi[k + 1]
			if i >= 0:
				g._set_owner(i, v)
				applied_owner += 1
			elif i == -1:
				_event(g, ev, v * 5)
				applied_ev += 1
			else:
				var t: int = -2 - i
				g.fallout[t] = v
				if v == 1: g.fallout_list[t] = true
				else: g.fallout_list.erase(t)
				applied_fall += 1
		g.luau_rec = true
	var tr: PackedFloat64Array = (out.troops as PackedByteArray).to_float64_array()
	if not tr.is_empty():
		var nats: Array = g.nations
		for k in range(0, tr.size(), 2):
			nats[int(tr[k])].troops = tr[k + 1]
	if out.has("rhi"):
		var hi: int = int(out.rhi)
		if hi >= 0x80000000: hi -= 0x100000000
		g.rng.state = hi * 0x100000000 + int(out.rlo)
	if out.has("pf_atk") and int(out.pf_atk) > 0:
		g._pf_add("tiles", float(out.pf_tiles)); g._pf_add("atk_n", float(out.pf_atk))


func _event(g, ev: PackedFloat64Array, k: int) -> void:
	var kind := int(ev[k])
	var a := int(ev[k + 1])
	var b := int(ev[k + 2])
	match kind:
		EV_VIEWER_ATTACK:
			g._viewer_event({"type": "attack", "actor": a, "target": b}, [b])
		EV_HOSTILE:
			var n: Dictionary = g.nations[a]
			n["attacked_tick"] = int(ev[k + 3])
			var gk: String = "grudge_" + str(b)
			n[gk] = maxi(int(n.get(gk, 0)), int(ev[k + 4]))  # add_grudge keeps the later expiry
		EV_CONQUEST:
			var taken: float = ev[k + 3]
			var nv: Dictionary = g.nations[a]
			g.nations[b].gold += taken
			nv.gold = 0.0
			nv["conq_sent"] = true  # (Sim._conquest_sent: the elimination payout after this one is silent)
			if g.has_method("_on_conquest"): g._on_conquest(a, b, taken)  # (the view: a victory flag)
			nv["last_by"] = b
			nv["killer"] = b
		_:
			if kind >= 10: g.sim_ars.on_luau_event(ev, k)  # SimArsenal (sim/arsenal.gd)


## The rng state of the sim (shared by the attack pass and the AI) as two uint32 halves for Luau.
static func rng_args(g) -> Array:
	var s: int = g.rng.state
	return [(s >> 32) & 0xFFFFFFFF, s & 0xFFFFFFFF]


func _begin(g) -> void:
	g.luau_dirty.clear()
	g.luau_fdirty.clear()
	var nats: Array = g.nations
	var nn := nats.size()
	var land := PackedInt32Array(); land.resize(nn)
	var bb := PackedInt32Array(); bb.resize(nn * 4)
	var lb := PackedInt32Array(); lb.resize(nn)
	var borders := PackedInt32Array()
	var bd: Array = g.border
	for id in nn:
		var n: Dictionary = nats[id]
		land[id] = int(n.get("land", 0))
		var r: Rect2i = n.get("bb", Rect2i())
		bb[id * 4] = r.position.x; bb[id * 4 + 1] = r.position.y; bb[id * 4 + 2] = r.size.x; bb[id * 4 + 3] = r.size.y
		lb[id] = int(n.get("last_by", 0))
		if id < bd.size():
			var keys := PackedInt32Array(bd[id].keys())
			borders.append(keys.size())
			borders.append_array(keys)
		else:
			borders.append(0)
	var mt: PackedByteArray = g.mtn if g.mtn.size() == g.W * g.H else PackedByteArray()
	var ok: Variant = vm.call_fn(STATE, "begin", [g.W, g.H, g.owner_map.to_byte_array(), g.fallout, mt,
		nn, land.to_byte_array(), bb.to_byte_array(), lb.to_byte_array(), borders.to_byte_array()])
	if ok == null:
		_fail(g, vm.last_error)
		return
	ok = vm.call_fn("Core/SimAttacks", "reset", [])
	if ok == null:
		_fail(g, vm.last_error)
		return
	if g.get("sim_atk") != null: g.sim_atk.luau_reset()
	ok = vm.call_fn("Core/SimArsenal", "reset", [])
	if ok == null:
		_fail(g, vm.last_error)
		return
	if g.get("sim_ars") != null: g.sim_ars.luau_reset()
	ok = vm.call_fn("Core/SimRails", "reset", [])
	if ok == null:
		_fail(g, vm.last_error)
		return
	if g.get("sim_rails") != null: g.sim_rails.luau_reset()
	epoch = g.sim_epoch
	g.luau_rec = true
	g.luau_frec = true


## Empties every list Luau keeps for a match (attacks, missiles and munitions, rails and trains, structures) and
## the GDScript mirrors of them, and makes the next flush send the whole world again. main's _clear_world_view
## calls it when the title screen starts and when an attract sim starts, so nothing of the last match survives
## in Luau until the next map's first flush.
func reset_world(g) -> void:
	if not on: return
	for m in ["Core/SimAttacks", "Core/SimArsenal", "Core/SimRails", "Core/SimStructures"]:
		if vm.call_fn(m, "reset", []) == null:
			_fail(g, vm.last_error)
			return
	if g.get("sim_atk") != null: g.sim_atk.luau_reset()
	if g.get("sim_ars") != null: g.sim_ars.luau_reset()
	if g.get("sim_rails") != null: g.sim_rails.luau_reset()
	g.luau_dirty.clear()
	g.luau_fdirty.clear()
	epoch = -1


func _fail(g, msg: String) -> void:
	error = msg
	on = false
	g.luau_rec = false
	g.luau_frec = false
	push_error("Luau link off: " + msg)
