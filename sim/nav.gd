# Port of RoWorld src/shared/Core/SimNav.luau (AGPL-3.0, lukechatton/roworld @ae7a350): water pathfinding
# for transports, trade ships and warships.
#
# Same design as the source: the map is cut into 8 x 8 tile cells; inside each cell the water tiles are
# split into 4-connected regions; regions touching across a cell edge (or diagonally through a one-tile
# strait) are linked in a small graph (CSR). A query runs weighted A* (w 1.4) on that graph, stitches the
# regions with tiny in-region BFS walks through portal tiles, then string-pulls the result with
# line-of-sight checks. Paths never touch land (one-tile diagonal straits are allowed, as upstream).
#
# Port differences (speed in GDScript, no change in behaviour):
# - full-water cells are one region and are never flood-filled or stored per tile (cell_reg);
# - region-pair edges are gathered as sorted int64 keys instead of a table of lists;
# - region-path A* results and finished routes are cached; searches can be budgeted per sim tick
#   (begin_tick / budget_us), urgent queries (player orders) ignore the budget;
# - transports: nearest own coast found by a region BFS from the landing (nearest by sea, which keeps
#   boat targeting local: the landing tile itself is still chosen by the caller), not a Euclidean scan;
# - helpers return tile corners, pixel polylines (main.gd boats / trade ships) and a warship steering
#   step (sim/warships.gd).
# Water = body[t] > 0 (sim/naval.gd compute_bodies). Built once per map, after compute_bodies.
extends RefCounted
class_name SimNav

const CELL := 8
const HEURISTIC_W := 1.4
const PAIR_K := 1 << 20          # region ids stay below 2^20
const IDX_BITS := 23              # edge sample index bits in the sort key
const C_LAND := -2
const C_MIXED := -1

var ready := false
var W := 0
var H := 0
var N := 0
var CW := 0
var CH := 0
var body := PackedInt32Array()
var cell_reg := PackedInt32Array()   # region id of a full-water cell, C_MIXED, or C_LAND
var region := PackedInt32Array()     # per tile, only valid inside mixed cells (-1 land)
var reg_count := 0
var reg_body := PackedInt32Array()
var reg_tile := PackedInt32Array()
var reg_x := PackedFloat32Array()
var reg_y := PackedFloat32Array()
var reg_full := PackedByteArray()
var reg_n := PackedInt32Array()      # water tiles per region
var adj_off := PackedInt32Array()
var adj_to := PackedInt32Array()
var adj_cost := PackedFloat32Array()
var adj_pa := PackedInt32Array()
var adj_pb := PackedInt32Array()
# coarse level (coarse-to-fine): clusters = connected region groups inside 64 x 64 tile blocks
const SUPER := 8                     # cells per block side
const CORRIDOR_WIDEN := 0            # also allow clusters adjacent to the coarse path
var reg_clu := PackedInt32Array()
var clu_count := 0
var clu_x := PackedFloat32Array()
var clu_y := PackedFloat32Array()
var cadj_off := PackedInt32Array()
var cadj_to := PackedInt32Array()
var cadj_cost := PackedFloat32Array()
var _cg := PackedFloat32Array()
var _ccame := PackedInt32Array()
var _cseen := PackedInt32Array()
var _cclosed := PackedInt32Array()
var _cmark := PackedInt32Array()
var _cstamp := 0
var coast_off := PackedInt32Array()  # land tiles 4-adjacent to each region's water (CSR)
var coast_tiles := PackedInt32Array()

# A* scratch
var _g := PackedFloat32Array()
var _came := PackedInt32Array()
var _seen := PackedInt32Array()
var _closed := PackedInt32Array()
var _stamp := 0
var _hn := PackedInt32Array()
var _hf := PackedFloat32Array()
var _hs := 0
# in-region BFS scratch (<= 64 tiles)
var _lpar := PackedInt32Array()
var _lseen := PackedInt32Array()
var _lstamp := 0

# caches
var _reg_cache := {}
var _route_cache := {}
const REG_CACHE_MAX := 4096
const ROUTE_CACHE_MAX := 2048

# per-tick budget (microseconds of search time); begin_tick() resets it
var budget_us := 3000
var _spent_us := 0

# stats
var build_ms := 0.0
var searches := 0
var expanded := 0
var usec := 0
var usec_max := 0
var fails := 0
var cache_hits := 0
var deferred := 0
var last_deferred := false   # the last find_route returned [] only because the tick budget was spent
var usec_astar := 0
var usec_stitch := 0
var usec_smooth := 0

# ------------------------------------------------------------------------------------------------
# build
# ------------------------------------------------------------------------------------------------
func build(water_body: PackedInt32Array, w: int, h: int) -> void:
	var t0 := Time.get_ticks_usec()
	ready = false
	W = w; H = h; N = w * h
	body = water_body
	CW = (W + CELL - 1) / CELL
	CH = (H + CELL - 1) / CELL
	_reg_cache.clear(); _route_cache.clear()
	cell_reg = PackedInt32Array(); cell_reg.resize(CW * CH)
	region = PackedInt32Array(); region.resize(N); region.fill(-1)
	var rn := PackedInt32Array(); rn.resize(4096)
	var rb := PackedInt32Array(); var rt := PackedInt32Array()
	var rx := PackedFloat32Array(); var ry := PackedFloat32Array(); var rf := PackedByteArray()
	var cap := 4096
	rb.resize(cap); rt.resize(cap); rx.resize(cap); ry.resize(cap); rf.resize(cap)
	var co := PackedInt32Array(); co.resize(cap + 1); co[0] = 0
	var ct := PackedInt32Array(); var ctn := 0; ct.resize(65536)
	var rc := 0
	var stack := PackedInt32Array(); stack.resize(CELL * CELL)
	var members := PackedInt32Array(); members.resize(CELL * CELL)
	var cmark := {}
	# 1. regions
	for cy in CH:
		var y0 := cy * CELL
		var y1 := mini(y0 + CELL, H) - 1
		for cx in CW:
			var x0 := cx * CELL
			var x1 := mini(x0 + CELL, W) - 1
			var cw := x1 - x0 + 1
			var land := 0
			for yy in range(y0, y1 + 1):
				var s := yy * W + x0
				land += body.slice(s, s + cw).count(0)
			var c := cy * CW + cx
			var area := cw * (y1 - y0 + 1)
			if land == area:
				cell_reg[c] = C_LAND
				continue
			if rc + CELL * CELL + 1 >= cap:
				cap *= 2
				rb.resize(cap); rt.resize(cap); rx.resize(cap); ry.resize(cap); rf.resize(cap); co.resize(cap + 1); rn.resize(cap)
			if land == 0:
				var mx := mini(x0 + CELL / 2, x1); var my := mini(y0 + CELL / 2, y1)
				rb[rc] = body[my * W + mx]; rt[rc] = my * W + mx
				rx[rc] = (x0 + x1) * 0.5; ry[rc] = (y0 + y1) * 0.5
				rf[rc] = 1 if area == CELL * CELL else 0
				rn[rc] = area
				cell_reg[c] = rc
				# land just outside the cell = this region's coast
				if ctn + 4 * CELL + 4 >= ct.size(): ct.resize(ct.size() * 2)
				if y0 > 0:
					var s0 := (y0 - 1) * W + x0
					if body.slice(s0, s0 + cw).count(0) > 0:
						for xx in range(x0, x1 + 1):
							if body[s0 + xx - x0] == 0: ct[ctn] = s0 + xx - x0; ctn += 1
				if y1 < H - 1:
					var s1 := (y1 + 1) * W + x0
					if body.slice(s1, s1 + cw).count(0) > 0:
						for xx in range(x0, x1 + 1):
							if body[s1 + xx - x0] == 0: ct[ctn] = s1 + xx - x0; ctn += 1
				if x0 > 0:
					for yy in range(y0, y1 + 1):
						if body[yy * W + x0 - 1] == 0: ct[ctn] = yy * W + x0 - 1; ctn += 1
				if x1 < W - 1:
					for yy in range(y0, y1 + 1):
						if body[yy * W + x1 + 1] == 0: ct[ctn] = yy * W + x1 + 1; ctn += 1
				co[rc + 1] = ctn
				rc += 1
				continue
			cell_reg[c] = C_MIXED
			for yy in range(y0, y1 + 1):
				for xx in range(x0, x1 + 1):
					var ts := yy * W + xx
					var b: int = body[ts]
					if b == 0 or region[ts] != -1: continue
					var r := rc
					region[ts] = r
					var sn := 1; stack[0] = ts
					var mn := 0
					var fx := 0.0; var fy := 0.0
					cmark.clear()
					while sn > 0:
						sn -= 1
						var t: int = stack[sn]
						members[mn] = t; mn += 1
						var tx := t % W; var ty := t / W
						fx += tx; fy += ty
						# west
						if tx > 0:
							var j := t - 1
							var bj: int = body[j]
							if bj == 0: cmark[j] = true
							elif tx > x0 and region[j] == -1: region[j] = r; stack[sn] = j; sn += 1
						if tx < W - 1:
							var j := t + 1
							var bj: int = body[j]
							if bj == 0: cmark[j] = true
							elif tx < x1 and region[j] == -1: region[j] = r; stack[sn] = j; sn += 1
						if ty > 0:
							var j := t - W
							var bj: int = body[j]
							if bj == 0: cmark[j] = true
							elif ty > y0 and region[j] == -1: region[j] = r; stack[sn] = j; sn += 1
						if ty < H - 1:
							var j := t + W
							var bj: int = body[j]
							if bj == 0: cmark[j] = true
							elif ty < y1 and region[j] == -1: region[j] = r; stack[sn] = j; sn += 1
					fx /= mn; fy /= mn
					var best: int = members[0]; var bd := 1e20
					for m in mn:
						var t: int = members[m]
						var ddx := (t % W) - fx; var ddy := (t / W) - fy
						var dd := ddx * ddx + ddy * ddy
						if dd < bd: bd = dd; best = t
					rb[rc] = b; rt[rc] = best; rx[rc] = fx; ry[rc] = fy; rf[rc] = 0; rn[rc] = mn
					for k in cmark:
						if ctn >= ct.size(): ct.resize(ct.size() * 2)
						ct[ctn] = k; ctn += 1
					co[rc + 1] = ctn
					rc += 1
	reg_count = rc
	rb.resize(maxi(rc, 1)); rt.resize(maxi(rc, 1)); rx.resize(maxi(rc, 1)); ry.resize(maxi(rc, 1)); rf.resize(maxi(rc, 1))
	co.resize(rc + 1); ct.resize(ctn)
	rn.resize(maxi(rc, 1))
	reg_body = rb; reg_tile = rt; reg_x = rx; reg_y = ry; reg_full = rf; reg_n = rn
	coast_off = co; coast_tiles = ct
	assert(rc < PAIR_K, "SimNav: too many regions")
	# 2. edges: every region pair that touches (4-adjacent, or diagonal through a one-tile strait)
	var keys := PackedInt64Array()
	var eta := PackedInt32Array()
	var etb := PackedInt32Array()
	var en := [0]
	var ecap := 1 << 16
	keys.resize(ecap); eta.resize(ecap); etb.resize(ecap)
	var ne := 0
	for cy in CH:
		var y0 := cy * CELL
		var y1 := mini(y0 + CELL, H) - 1
		for cx in CW:
			var c := cy * CW + cx
			var cr: int = cell_reg[c]
			if cr == C_LAND: continue
			var x0 := cx * CELL
			var x1 := mini(x0 + CELL, W) - 1
			if ne + 4 * CELL * CELL + 64 >= ecap:
				ecap *= 2; keys.resize(ecap); eta.resize(ecap); etb.resize(ecap)
			# right neighbour
			if cx + 1 < CW:
				var rr: int = cell_reg[c + 1]
				if rr != C_LAND:
					if cr >= 0 and rr >= 0:
						var tm := ((y0 + y1) / 2) * W + x1
						ne = _add(keys, eta, etb, ne, cr, rr, tm, tm + 1)
					else:
						for y in range(y0, y1 + 1):
							var t := y * W + x1
							var a := region_of(t)
							var e := t + 1
							if a >= 0:
								var b2 := region_of(e)
								if b2 >= 0 and b2 != a: ne = _add(keys, eta, etb, ne, a, b2, t, e)
							if y < y1:
								# t -> south-east (crosses the vertical edge)
								var se := e + W
								if a >= 0:
									var b3 := region_of(se)
									if b3 >= 0 and b3 != a and region_of(e) < 0 and region_of(t + W) < 0:
										ne = _add(keys, eta, etb, ne, a, b3, t, se)
								# e -> south-west
								var a2 := region_of(e)
								if a2 >= 0:
									var sw := t + W
									var b4 := region_of(sw)
									if b4 >= 0 and b4 != a2 and a < 0 and region_of(e + W) < 0:
										ne = _add(keys, eta, etb, ne, a2, b4, e, sw)
			# lower neighbour (incl. both corners)
			if cy + 1 < CH:
				var dr: int = cell_reg[c + CW]
				if not (cr >= 0 and dr >= 0):
					for x in range(x0, x1 + 1):
						var t := y1 * W + x
						var a := region_of(t)
						if a < 0: continue
						var s := t + W
						var bs := region_of(s)
						if bs >= 0 and bs != a: ne = _add(keys, eta, etb, ne, a, bs, t, s)
						if x < W - 1 and bs < 0 and region_of(t + 1) < 0:
							var b3 := region_of(s + 1)
							if b3 >= 0 and b3 != a: ne = _add(keys, eta, etb, ne, a, b3, t, s + 1)
						if x > 0 and bs < 0 and region_of(t - 1) < 0:
							var b4 := region_of(s - 1)
							if b4 >= 0 and b4 != a: ne = _add(keys, eta, etb, ne, a, b4, t, s - 1)
				elif dr != cr:
					var tm2 := y1 * W + (x0 + x1) / 2
					ne = _add(keys, eta, etb, ne, cr, dr, tm2, tm2 + W)
			# interior diagonals of a mixed cell
			if cr == C_MIXED:
				for y in range(y0, y1):
					for x in range(x0, x1 + 1):
						var t := y * W + x
						var a: int = region[t]
						if a < 0: continue
						var s := t + W
						if region[s] >= 0: continue
						if x < x1 and region[t + 1] < 0:
							var b3: int = region[s + 1]
							if b3 >= 0 and b3 != a: ne = _add(keys, eta, etb, ne, a, b3, t, s + 1)
						if x > x0 and region[t - 1] < 0:
							var b4: int = region[s - 1]
							if b4 >= 0 and b4 != a: ne = _add(keys, eta, etb, ne, a, b4, t, s - 1)
	keys.resize(ne)
	keys.sort()
	# 3. CSR adjacency, portal = middle sample of each pair
	var ga := PackedInt32Array(); var gb := PackedInt32Array(); var gpa := PackedInt32Array(); var gpb := PackedInt32Array()
	var deg := PackedInt32Array(); deg.resize(rc + 1); deg.fill(0)
	var i := 0
	var mask := (1 << IDX_BITS) - 1
	while i < ne:
		var k: int = keys[i] >> IDX_BITS
		var j := i
		while j < ne and (keys[j] >> IDX_BITS) == k: j += 1
		var mid: int = keys[i + (j - i) / 2] & mask
		var a := k / PAIR_K; var b := k % PAIR_K
		ga.append(a); gb.append(b); gpa.append(eta[mid]); gpb.append(etb[mid])
		deg[a] += 1; deg[b] += 1
		i = j
	adj_off = PackedInt32Array(); adj_off.resize(rc + 1)
	var acc := 0
	for r in rc:
		adj_off[r] = acc; acc += deg[r]
	adj_off[rc] = acc
	adj_to = PackedInt32Array(); adj_to.resize(maxi(acc, 1))
	adj_cost = PackedFloat32Array(); adj_cost.resize(maxi(acc, 1))
	adj_pa = PackedInt32Array(); adj_pa.resize(maxi(acc, 1))
	adj_pb = PackedInt32Array(); adj_pb.resize(maxi(acc, 1))
	var fill := PackedInt32Array(); fill.resize(rc + 1); fill.fill(0)
	for q in ga.size():
		var a: int = ga[q]; var b: int = gb[q]
		var cost := Vector2(rx[a] - rx[b], ry[a] - ry[b]).length()
		var ia: int = adj_off[a] + fill[a]; fill[a] += 1
		adj_to[ia] = b; adj_cost[ia] = cost; adj_pa[ia] = gpa[q]; adj_pb[ia] = gpb[q]
		var ib: int = adj_off[b] + fill[b]; fill[b] += 1
		adj_to[ib] = a; adj_cost[ib] = cost; adj_pa[ib] = gpb[q]; adj_pb[ib] = gpa[q]
	_build_clusters()
	# scratch
	var n1 := maxi(rc, 1)
	_g.resize(n1); _came.resize(n1); _seen.resize(n1); _seen.fill(0); _closed.resize(n1); _closed.fill(0)
	_stamp = 0
	_lpar.resize(CELL * CELL); _lseen.resize(CELL * CELL); _lseen.fill(0); _lstamp = 0
	searches = 0; expanded = 0; usec = 0; usec_max = 0; fails = 0; cache_hits = 0; deferred = 0
	build_ms = (Time.get_ticks_usec() - t0) / 1000.0
	ready = true

func _build_clusters() -> void:
	var rc := reg_count
	var SW := (CW + SUPER - 1) / SUPER
	var sup := PackedInt32Array(); sup.resize(maxi(rc, 1))
	for r in rc:
		var t: int = reg_tile[r]
		sup[r] = ((t / W) / CELL / SUPER) * SW + ((t % W) / CELL) / SUPER
	var par := PackedInt32Array(); par.resize(maxi(rc, 1))
	for r in rc: par[r] = r
	for r in rc:
		for k in range(adj_off[r], adj_off[r + 1]):
			var n: int = adj_to[k]
			if n <= r or sup[n] != sup[r]: continue
			var a := r
			while par[a] != a: par[a] = par[par[a]]; a = par[a]
			var b := n
			while par[b] != b: par[b] = par[par[b]]; b = par[b]
			if a != b: par[maxi(a, b)] = mini(a, b)
	reg_clu = PackedInt32Array(); reg_clu.resize(maxi(rc, 1))
	var cid := PackedInt32Array(); cid.resize(maxi(rc, 1)); cid.fill(-1)
	var cc := 0
	var sx := PackedFloat32Array(); var sy := PackedFloat32Array(); var sn := PackedInt32Array()
	for r in rc:
		var a := r
		while par[a] != a: a = par[a]
		if cid[a] < 0:
			cid[a] = cc; cc += 1; sx.append(0.0); sy.append(0.0); sn.append(0)
		var c: int = cid[a]
		reg_clu[r] = c
		sx[c] += reg_x[r]; sy[c] += reg_y[r]; sn[c] += 1
	clu_count = cc
	for c in cc:
		sx[c] /= sn[c]; sy[c] /= sn[c]
	clu_x = sx; clu_y = sy
	var keys := PackedInt64Array()
	for r in rc:
		var a: int = reg_clu[r]
		for k in range(adj_off[r], adj_off[r + 1]):
			var b: int = reg_clu[adj_to[k]]
			if b > a: keys.append(a * PAIR_K + b)
	keys.sort()
	var ga := PackedInt32Array(); var gb := PackedInt32Array()
	var deg := PackedInt32Array(); deg.resize(cc + 1); deg.fill(0)
	var prev := -1
	for k in keys:
		if k == prev: continue
		prev = k
		var a := k / PAIR_K; var b := k % PAIR_K
		ga.append(a); gb.append(b); deg[a] += 1; deg[b] += 1
	cadj_off = PackedInt32Array(); cadj_off.resize(cc + 1)
	var acc := 0
	for c in cc:
		cadj_off[c] = acc; acc += deg[c]
	cadj_off[cc] = acc
	cadj_to = PackedInt32Array(); cadj_to.resize(maxi(acc, 1))
	cadj_cost = PackedFloat32Array(); cadj_cost.resize(maxi(acc, 1))
	var fill := PackedInt32Array(); fill.resize(cc + 1); fill.fill(0)
	for q in ga.size():
		var a: int = ga[q]; var b: int = gb[q]
		var cost := Vector2(sx[a] - sx[b], sy[a] - sy[b]).length()
		var ia: int = cadj_off[a] + fill[a]; fill[a] += 1
		cadj_to[ia] = b; cadj_cost[ia] = cost
		var ib: int = cadj_off[b] + fill[b]; fill[b] += 1
		cadj_to[ib] = a; cadj_cost[ib] = cost
	var n1 := maxi(cc, 1)
	_cg.resize(n1); _ccame.resize(n1); _cseen.resize(n1); _cseen.fill(0); _cclosed.resize(n1); _cclosed.fill(0)
	_cmark.resize(n1); _cmark.fill(0); _cstamp = 0

func _cluster_path(ca: int, cb: int) -> PackedInt32Array:
	_stamp += 1
	var st := _stamp
	_hs = 0
	_cg[ca] = 0.0; _ccame[ca] = -1; _cseen[ca] = st
	var gx: float = clu_x[cb]; var gy: float = clu_y[cb]
	_push(ca, 0.0)
	var found := false
	while _hs > 0:
		var c := _pop()
		if _cclosed[c] == st: continue
		_cclosed[c] = st
		if c == cb: found = true; break
		var gc: float = _cg[c]
		for k in range(cadj_off[c], cadj_off[c + 1]):
			var n: int = cadj_to[k]
			if _cclosed[n] == st: continue
			var ng: float = gc + cadj_cost[k]
			if _cseen[n] != st or ng < _cg[n]:
				_cseen[n] = st; _cg[n] = ng; _ccame[n] = c
				_push(n, ng + Vector2(clu_x[n] - gx, clu_y[n] - gy).length() * HEURISTIC_W)
	var out := PackedInt32Array()
	if found:
		var c := cb
		while c != -1:
			out.append(c); c = _ccame[c]
	return out

func _add(keys: PackedInt64Array, eta: PackedInt32Array, etb: PackedInt32Array, ne: int, a: int, b: int, ta: int, tb: int) -> int:
	if a > b:
		var tmp := a; a = b; b = tmp
		tmp = ta; ta = tb; tb = tmp
	keys[ne] = ((a * PAIR_K + b) << IDX_BITS) | ne
	eta[ne] = ta; etb[ne] = tb
	return ne + 1

# ------------------------------------------------------------------------------------------------
# queries on tiles
# ------------------------------------------------------------------------------------------------
func is_water(t: int) -> bool:
	return t >= 0 and t < N and body[t] > 0

func body_of(t: int) -> int:
	return body[t] if t >= 0 and t < N else 0

func region_of(t: int) -> int:
	if t < 0 or t >= N: return -1
	var cr: int = cell_reg[(t / W / CELL) * CW + (t % W) / CELL]
	if cr >= 0: return cr
	if cr == C_LAND: return -1
	return region[t]

# A water tile of `wb` (any body if wb <= 0) 4/8-adjacent to tile t (-1 if none). Order: W, E, N, NW,
# NE, S, SW, SE (source order).
func water_next_to(t: int, wb := 0) -> int:
	var x := t % W
	var hw := x > 0; var he := x < W - 1
	var cands := []
	if hw: cands.append(t - 1)
	if he: cands.append(t + 1)
	if t >= W:
		cands.append(t - W)
		if hw: cands.append(t - W - 1)
		if he: cands.append(t - W + 1)
	if t < N - W:
		cands.append(t + W)
		if hw: cands.append(t + W - 1)
		if he: cands.append(t + W + 1)
	for c in cands:
		var b: int = body[c]
		if b > 0 and (wb <= 0 or b == wb): return c
	return -1

# Water body a coastal land tile touches (first of W, E, N, S), 0 if none.
func coast_body(t: int) -> int:
	var w := water_next_to(t)
	return body[w] if w >= 0 else 0

# ------------------------------------------------------------------------------------------------
# budget
# ------------------------------------------------------------------------------------------------
func begin_tick() -> void:
	_spent_us = 0

func budget_left() -> bool:
	return _spent_us < budget_us

# ------------------------------------------------------------------------------------------------
# paths
# ------------------------------------------------------------------------------------------------
# Corner tiles (string-pulled) of a water route src -> dst (both water, same body); [] if none.
# Consecutive corners are joined by straight water lines (see raster()). urgent ignores the budget.
func find_route(src: int, dst: int, urgent := true) -> PackedInt32Array:
	last_deferred = false
	if not ready or src < 0 or dst < 0 or src >= N or dst >= N: return PackedInt32Array()
	var b: int = body[src]
	if b == 0 or body[dst] != b: return PackedInt32Array()
	var key := src * N + dst
	if _route_cache.has(key):
		cache_hits += 1
		return _route_cache[key]
	if src == dst: return PackedInt32Array([src])
	if los_strict(src, dst, b):
		var straight := PackedInt32Array([src, dst])
		_cache_route(key, straight)
		return straight
	if not urgent and _spent_us >= budget_us:
		deferred += 1
		last_deferred = true
		return PackedInt32Array()
	var t0 := Time.get_ticks_usec()
	var out := PackedInt32Array()
	var ra := region_of(src); var rb := region_of(dst)
	if ra >= 0 and rb >= 0:
		var regs := _region_path(ra, rb)
		var t1 := Time.get_ticks_usec(); usec_astar += t1 - t0
		if regs.size() > 0:
			var raw := _stitch(src, dst, regs)
			var t2 := Time.get_ticks_usec(); usec_stitch += t2 - t1
			if raw.size() > 0: out = _smooth(raw, b)
			usec_smooth += Time.get_ticks_usec() - t2
	var dt := Time.get_ticks_usec() - t0
	_spent_us += dt; usec += dt; usec_max = maxi(usec_max, dt)
	if out.is_empty(): fails += 1
	_cache_route(key, out)
	return out

func _cache_route(key: int, r: PackedInt32Array) -> void:
	if _route_cache.size() >= ROUTE_CACHE_MAX: _route_cache.clear()
	_route_cache[key] = r

# Dense tile path (every step a 4/8-neighbour) for a corner list.
func dense(corners: PackedInt32Array) -> PackedInt32Array:
	if corners.is_empty(): return corners
	var out := PackedInt32Array([corners[0]])
	for i in range(1, corners.size()): supercover(corners[i - 1], corners[i], out)
	return out

# Tiles touched by the centre-to-centre segment a -> bt (excluding a), 4/8-connected (corner = diagonal).
func supercover(a: int, bt: int, out: PackedInt32Array) -> void:
	var x := a % W; var y := a / W
	var dx := bt % W - x; var dy := bt / W - y
	var nx := absi(dx); var ny := absi(dy)
	var sx := 1 if dx > 0 else -1
	var sy := 1 if dy > 0 else -1
	var ix := 0; var iy := 0
	while ix < nx or iy < ny:
		var dec := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if dec == 0: x += sx; y += sy; ix += 1; iy += 1
		elif dec < 0: x += sx; ix += 1
		else: y += sy; iy += 1
		out.append(y * W + x)

func _region_path(ra: int, rb: int) -> PackedInt32Array:
	var key := ra * PAIR_K + rb
	if _reg_cache.has(key): return _reg_cache[key]
	var rkey := rb * PAIR_K + ra
	if _reg_cache.has(rkey):
		var rv: PackedInt32Array = _reg_cache[rkey].duplicate(); rv.reverse()
		return rv
	searches += 1
	var corridor := false
	if clu_count > 0 and reg_clu[ra] != reg_clu[rb]:
		var cp := _cluster_path(reg_clu[ra], reg_clu[rb])
		if cp.is_empty():
			_reg_cache[key] = PackedInt32Array()
			return PackedInt32Array()
		_cstamp += 1
		for c in cp:
			_cmark[c] = _cstamp
		for _w in CORRIDOR_WIDEN:
			var ring := PackedInt32Array()
			for c in cp:
				for k in range(cadj_off[c], cadj_off[c + 1]):
					var n: int = cadj_to[k]
					if _cmark[n] != _cstamp: ring.append(n)
			for n in ring: _cmark[n] = _cstamp
			cp.append_array(ring)
		corridor = true
	var res := _astar_regions(ra, rb, corridor)
	if res.is_empty() and corridor: res = _astar_regions(ra, rb, false)
	if _reg_cache.size() >= REG_CACHE_MAX: _reg_cache.clear()
	_reg_cache[key] = res
	return res

func _astar_regions(ra: int, rb: int, corridor: bool) -> PackedInt32Array:
	var cs := _cstamp
	_stamp += 1
	var st := _stamp
	_hs = 0
	_g[ra] = 0.0; _came[ra] = -1; _seen[ra] = st
	var gx: float = reg_x[rb]; var gy: float = reg_y[rb]
	_push(ra, Vector2(reg_x[ra] - gx, reg_y[ra] - gy).length() * HEURISTIC_W)
	var found := false
	var ex := 0
	while _hs > 0:
		var r := _pop()
		if _closed[r] == st: continue
		_closed[r] = st
		ex += 1
		if r == rb: found = true; break
		var gr: float = _g[r]
		for k in range(adj_off[r], adj_off[r + 1]):
			var n: int = adj_to[k]
			if _closed[n] == st: continue
			if corridor and _cmark[reg_clu[n]] != cs: continue
			var ng: float = gr + adj_cost[k]
			if _seen[n] != st or ng < _g[n]:
				_seen[n] = st; _g[n] = ng; _came[n] = r
				_push(n, ng + Vector2(reg_x[n] - gx, reg_y[n] - gy).length() * HEURISTIC_W)
	expanded += ex
	var out := PackedInt32Array()
	if found:
		var c := rb
		while c != -1:
			out.append(c); c = _came[c]
		out.reverse()
	return out

func _push(n: int, f: float) -> void:
	if _hs >= _hn.size():
		_hn.resize(maxi(64, _hs * 2)); _hf.resize(maxi(64, _hs * 2))
	var i := _hs
	_hs += 1
	while i > 0:
		var p := (i - 1) >> 1
		if _hf[p] <= f: break
		_hn[i] = _hn[p]; _hf[i] = _hf[p]
		i = p
	_hn[i] = n; _hf[i] = f

func _pop() -> int:
	var top: int = _hn[0]
	_hs -= 1
	var size := _hs
	if size == 0: return top
	var ln: int = _hn[size]; var lf: float = _hf[size]
	var i := 0
	while true:
		var c := i * 2 + 1
		if c >= size: break
		if c + 1 < size and _hf[c + 1] < _hf[c]: c += 1
		if _hf[c] >= lf: break
		_hn[i] = _hn[c]; _hf[i] = _hf[c]
		i = c
	_hn[i] = ln; _hf[i] = lf
	return top

func _portal(r: int, r2: int) -> Vector2i:
	for k in range(adj_off[r], adj_off[r + 1]):
		if adj_to[k] == r2: return Vector2i(adj_pa[k], adj_pb[k])
	return Vector2i(-1, -1)

func _stitch(src: int, dst: int, regs: PackedInt32Array) -> PackedInt32Array:
	var raw := PackedInt32Array([src])
	var cur := src
	for i in regs.size() - 1:
		var p := _portal(regs[i], regs[i + 1])
		if p.x < 0: return PackedInt32Array()
		if p.x != cur and los_strict(cur, p.x, body[cur]): raw.append(p.x)   # sparse: smoothing only needs visible hops
		elif not _bfs_append(cur, p.x, regs[i], raw): return PackedInt32Array()
		raw.append(p.y)
		cur = p.y
	if dst != cur and los_strict(cur, dst, body[cur]): raw.append(dst)
	elif not _bfs_append(cur, dst, regs[regs.size() - 1], raw): return PackedInt32Array()
	return raw

# BFS inside region r from a to b; appends the tiles after a up to and including b.
func _bfs_append(a: int, b: int, r: int, out: PackedInt32Array) -> bool:
	if a == b: return true
	if reg_full[r] == 1 or cell_reg[(a / W / CELL) * CW + (a % W) / CELL] >= 0:
		raster(a, b, out)
		return true
	var x0 := ((a % W) / CELL) * CELL; var y0 := ((a / W) / CELL) * CELL
	if (b % W) / CELL * CELL != x0 or (b / W) / CELL * CELL != y0:
		out.append(b)   # diagonal strait jump across a cell edge
		return region_of(b) == r or region_of(a) == r
	_lstamp += 1
	var ls := _lstamp
	var q := PackedInt32Array([a])
	var la := ((a / W) - y0) * CELL + (a % W) - x0
	_lseen[la] = ls; _lpar[la] = -1
	var head := 0
	var found := false
	while head < q.size():
		var t: int = q[head]; head += 1
		if t == b: found = true; break
		var x := t % W; var y := t / W
		for k in 4:
			var n := -1
			if k == 0:
				if x == x0 or x == 0: continue
				n = t - 1
			elif k == 1:
				if x == x0 + CELL - 1 or x == W - 1: continue
				n = t + 1
			elif k == 2:
				if y == y0 or y == 0: continue
				n = t - W
			else:
				if y == y0 + CELL - 1 or y == H - 1: continue
				n = t + W
			if region[n] != r: continue
			var ln := ((n / W) - y0) * CELL + (n % W) - x0
			if _lseen[ln] == ls: continue
			_lseen[ln] = ls; _lpar[ln] = t
			q.append(n)
	if not found:
		out.append(b)
		return region_of(b) == r or region_of(a) == r
	var seg := PackedInt32Array()
	var c := b
	while c != a:
		seg.append(c)
		c = _lpar[((c / W) - y0) * CELL + (c % W) - x0]
	seg.reverse()
	out.append_array(seg)
	return true

# String pulling: exponential probe + binary search for the farthest visible raw tile (source).
# Returns the corner tiles only.
func _smooth(raw: PackedInt32Array, b: int) -> PackedInt32Array:
	var n := raw.size()
	if n <= 2: return raw
	var out := PackedInt32Array([raw[0]])
	var i := 0
	while i < n - 1:
		var good := i + 1
		var stride := 2
		var bad := -1
		while true:
			var j := mini(i + stride, n - 1)
			if los_strict(raw[i], raw[j], b):
				good = j
				if j == n - 1 or stride >= 256: break
				stride *= 2
			else:
				bad = j; break
		if bad > 0:
			var lo := good; var hi := bad
			while hi - lo > 1:
				var mid := (lo + hi) / 2
				if los_strict(raw[i], raw[mid], b): lo = mid
				else: hi = mid
			good = lo
		out.append(raw[good])
		i = good
	return out

# True when the tile line a -> bt stays on water of body b without cutting land corners.
func los(a: int, bt: int, b: int) -> bool:
	var x0 := a % W; var y0 := a / W
	var x1 := bt % W; var y1 := bt / W
	var dx := x1 - x0; var dy := y1 - y0
	var sx := 1 if dx > 0 else -1
	var sy := 1 if dy > 0 else -1
	var ax := absi(dx); var ay := absi(dy)
	var err := ax - ay
	var x := x0; var y := y0
	var steps := ax + ay
	var k := 0
	while k < steps:
		var e2 := err * 2
		var nx := x; var ny := y
		if e2 > -ay: err -= ay; nx = x + sx
		if e2 < ax: err += ax; ny = y + sy
		if nx != x and ny != y:
			if body[y * W + nx] != b and body[ny * W + x] != b: return false
			k += 1
		x = nx; y = ny
		if body[y * W + x] != b: return false
		k += 1
	return true

# Stricter than los(): every tile the continuous centre-to-centre segment touches is water of body b
# (supercover; a segment through a tile corner needs both side tiles). Used for string pulling so the
# drawn polylines (main.gd boats, trade ships) never graze land. Port choice; the source uses los().
func los_strict(a: int, bt: int, b: int) -> bool:
	var x := a % W; var y := a / W
	var dx := bt % W - x; var dy := bt / W - y
	var nx := absi(dx); var ny := absi(dy)
	var sx := 1 if dx > 0 else -1
	var sy := 1 if dy > 0 else -1
	var ix := 0; var iy := 0
	while ix < nx or iy < ny:
		var dec := (1 + 2 * ix) * ny - (1 + 2 * iy) * nx
		if dec == 0:
			if body[y * W + x + sx] != b or body[(y + sy) * W + x] != b: return false
			x += sx; y += sy; ix += 1; iy += 1
		elif dec < 0:
			x += sx; ix += 1
		else:
			y += sy; iy += 1
		if body[y * W + x] != b: return false
	return true

# Tiles of the line a -> bt (excluding a), appended to out (source line_tiles).
func raster(a: int, bt: int, out: PackedInt32Array) -> void:
	var x0 := a % W; var y0 := a / W
	var x1 := bt % W; var y1 := bt / W
	var dx := x1 - x0; var dy := y1 - y0
	var sx := 1 if dx > 0 else -1
	var sy := 1 if dy > 0 else -1
	var ax := absi(dx); var ay := absi(dy)
	var err := ax - ay
	var x := x0; var y := y0
	while x != x1 or y != y1:
		var e2 := err * 2
		if e2 > -ay: err -= ay; x += sx
		if e2 < ax: err += ax; y += sy
		out.append(y * W + x)

# ------------------------------------------------------------------------------------------------
# game helpers
# ------------------------------------------------------------------------------------------------
# Nearest coastal land tile of owner `a` by sea from water tile `wd` (region BFS over wd's body).
# Returns [coast_tile, region path from that coast's region to wd's region] or [] if none.
# max_tiles caps the water searched (sum of visited region sizes), like the old BFS max_nodes.
func nearest_own_coast(owner_map: PackedInt32Array, a: int, wd: int, max_tiles := 1 << 30) -> Array:
	var r0 := region_of(wd)
	if r0 < 0: return []
	_stamp += 1
	var st := _stamp
	var q := PackedInt32Array([r0])
	_seen[r0] = st; _came[r0] = -1
	var head := 0
	var seen_tiles := 0
	while head < q.size() and seen_tiles < max_tiles:
		var r: int = q[head]; head += 1
		seen_tiles += reg_n[r]
		for k in range(coast_off[r], coast_off[r + 1]):
			var c: int = coast_tiles[k]
			if owner_map[c] == a:
				var regs := PackedInt32Array()
				var x := r
				while x != -1:
					regs.append(x); x = _came[x]
				return [c, regs]
		for k in range(adj_off[r], adj_off[r + 1]):
			var n: int = adj_to[k]
			if _seen[n] == st: continue
			_seen[n] = st; _came[n] = r
			q.append(n)
	return []

# Transport route for owner `a` to the land tile `dest` (chosen by the caller, local to the click):
# corner tiles from a water tile next to a's nearest coast (by sea) to a water tile next to dest.
# max_tiles caps the sea search like the old BFS max_nodes (water tiles searched from the landing), so
# AI transports (12000 nodes) stay as local as before.
func boat_route(owner_map: PackedInt32Array, a: int, dest: int, max_tiles := 1 << 30) -> PackedInt32Array:
	if not ready or dest < 0 or dest >= N: return PackedInt32Array()
	var t0 := Time.get_ticks_usec()
	var out := PackedInt32Array()
	var tried := []
	var x := dest % W
	for wd in [dest - 1 if x > 0 else -1, dest + 1 if x < W - 1 else -1, dest - W, dest + W]:
		if wd < 0 or wd >= N or body[wd] == 0 or body[wd] in tried: continue
		tried.append(body[wd])
		out = _boat_route_body(owner_map, a, wd, max_tiles)
		if not out.is_empty(): break
	var dt := Time.get_ticks_usec() - t0
	usec += dt; usec_max = maxi(usec_max, dt); _spent_us += dt
	if out.is_empty(): fails += 1
	return out

func _boat_route_body(owner_map: PackedInt32Array, a: int, wd: int, max_tiles: int) -> PackedInt32Array:
	var hit := nearest_own_coast(owner_map, a, wd, max_tiles)
	if hit.is_empty(): return PackedInt32Array()
	var c: int = hit[0]
	var regs: PackedInt32Array = hit[1]
	var b: int = body[wd]
	var ws := -1
	var r0: int = regs[0]
	var x := c % W
	for j in [c - 1 if x > 0 else -1, c + 1 if x < W - 1 else -1, c - W, c + W]:
		if j >= 0 and j < N and region_of(j) == r0: ws = j; break
	if ws < 0: ws = water_next_to(c, b)
	if ws < 0: return PackedInt32Array()
	var key := ws * N + wd
	if _route_cache.has(key):
		cache_hits += 1
		return _route_cache[key]
	var out := PackedInt32Array()
	if los_strict(ws, wd, b):
		out = PackedInt32Array([ws, wd])
	else:
		var raw := _stitch(ws, wd, regs)
		if raw.size() > 0: out = _smooth(raw, b)
	_cache_route(key, out)
	return out

# Pixel polyline (tile centres * ts) for corners, ending at land tile end_tile when >= 0 (main.gd's
# boats/trade ships end on the coast tile). Corners are rounded off (Chaikin) only where the cut stays
# on water, so the curve never crosses land.
func to_points(corners: PackedInt32Array, end_tile: int, ts: float, rounds := 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for t in corners: pts.append(Vector2(t % W + 0.5, t / W + 0.5))
	if end_tile >= 0: pts.append(Vector2(end_tile % W + 0.5, end_tile / W + 0.5))
	var last := pts.size() - (1 if end_tile >= 0 else 0)   # the landing leg is not rounded
	for _it in rounds:
		if last < 3: break
		var np := PackedVector2Array([pts[0]])
		for m in range(1, last - 1):
			var a: Vector2 = pts[m - 1]; var p: Vector2 = pts[m]; var c: Vector2 = pts[m + 1]
			var q1 := p.lerp(a, 0.25); var q2 := p.lerp(c, 0.25)
			if seg_water(q1, q2): np.append(q1); np.append(q2)
			else: np.append(p)
		for m in range(last - 1, pts.size()): np.append(pts[m])
		var nlast := np.size() - (1 if end_tile >= 0 else 0)
		var ok := true
		for m in range(1, nlast):
			if not seg_water(np[m - 1], np[m]): ok = false; break
		if not ok: break   # keep the previous (valid) polyline
		last = nlast
		pts = np
	for m in pts.size(): pts[m] *= ts
	return pts

# Float-coordinate segment test (tile units): every sample lies inside a water tile; a sample exactly on
# a tile edge or corner (touching land only along a border, or a one-tile diagonal strait) is accepted
# when a water tile shares that border.
func seg_water(p0: Vector2, p1: Vector2) -> bool:
	var n := int(p0.distance_to(p1) * 4.0) + 1
	for s in n + 1:
		var p := p0.lerp(p1, float(s) / n)
		var x := int(p.x); var y := int(p.y)
		if x < 0 or y < 0 or x >= W or y >= H: return false
		if body[y * W + x] != 0: continue
		var ex := absf(p.x - roundf(p.x)) < 1e-4
		var ey := absf(p.y - roundf(p.y)) < 1e-4
		if not ex and not ey: return false
		var ok := false
		var xs := [x - 1, x] if ex else [x]
		var ys := [y - 1, y] if ey else [y]
		for yy in ys:
			for xx in xs:
				if xx >= 0 and yy >= 0 and xx < W and yy < H and body[yy * W + xx] != 0: ok = true
		if not ok: return false
	return true

# Drop-in for main.gd _water_path(from_tile, to_tile): pixel route between two coastal tiles (trade).
func water_path_px(from_tile: int, to_tile: int, ts: float, urgent := true) -> PackedVector2Array:
	var wa := water_next_to(from_tile) if body_of(from_tile) == 0 else from_tile
	if wa < 0: return PackedVector2Array()
	var wb := water_next_to(to_tile, body[wa]) if body_of(to_tile) == 0 else to_tile
	if wb < 0: return PackedVector2Array()
	var r := find_route(wa, wb, urgent)
	if r.is_empty(): return PackedVector2Array()
	# like the old BFS route: starts on the water next to from_tile, ends on to_tile's centre
	return to_points(r, to_tile if body_of(to_tile) == 0 else -1, ts)

# Warship steering (tile units, ws.pos / ws.tgt as in sim/warships.gd). Moves ws.pos up to `step`
# along a water route to ws.tgt, re-planning when the target drifts > 3 tiles. Returns false when no
# route is available this tick (caller falls back to its straight-line step).
func steer(ws: Dictionary, step: float) -> bool:
	if not ready: return false
	var pos: Vector2 = ws.pos; var tgt: Vector2 = ws.tgt
	var pt := clampi(int(pos.y), 0, H - 1) * W + clampi(int(pos.x), 0, W - 1)
	var b: int = body[pt]
	if b == 0: return false
	var route: PackedVector2Array = ws.get("nav_r", PackedVector2Array())
	var rt: Vector2 = ws.get("nav_t", Vector2(-1e9, -1e9))
	var ri: int = ws.get("nav_i", 0)
	if route.is_empty() or rt.distance_to(tgt) > 3.0 or (ri >= route.size() and pos.distance_to(tgt) > 0.01):
		var tt := clampi(int(tgt.y), 0, H - 1) * W + clampi(int(tgt.x), 0, W - 1)
		if body[tt] != b:
			var alt := water_next_to(tt, b)
			if alt < 0: return false
			tt = alt; tgt = Vector2(tt % W + 0.5, tt / W + 0.5); ws.tgt = tgt
		var corners := find_route(pt, tt, false)
		if corners.is_empty(): return false
		route = PackedVector2Array()
		for m in corners.size(): route.append(Vector2(corners[m] % W + 0.5, corners[m] / W + 0.5))
		route.append(tgt)
		ws["nav_r"] = route; ws["nav_t"] = tgt; ws["nav_i"] = 0
	var i: int = ws.get("nav_i", 0)
	var left := step
	while left > 0.0 and i < route.size():
		var wp: Vector2 = tgt if i == route.size() - 1 else route[i]
		var d := pos.distance_to(wp)
		if d <= left:
			if body[clampi(int(wp.y), 0, H - 1) * W + clampi(int(wp.x), 0, W - 1)] != b: break
			pos = wp; left -= d; i += 1
		else:
			var np := pos + (wp - pos) / d * left
			if body[clampi(int(np.y), 0, H - 1) * W + clampi(int(np.x), 0, W - 1)] != b:
				ws.erase("nav_r"); break
			pos = np; left = 0.0
	ws.pos = pos; ws["nav_i"] = i
	return true
