# Port of RoWorld src/shared/Core/SimColors.luau: OKLab colour distance, the human palette, and the
# minimal nudge that keeps a nation's authored colour apart from nearby capitals (so the 44 states of the
# United States map, all flag "us", don't share one colour). Colours are Godot Colors here.
class_name SimColors
extends RefCounted

const MIN_DE := 0.12
const NUDGE_BELOW := 0.08
const DLS := [0.0, 0.05, -0.05, 0.1, -0.1, 0.15, -0.15]
const DHS := [0.0, 0.26, -0.26, 0.52, -0.52, 0.79, -0.79, 1.05, -1.05]
static var _human: Array = []

static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)

static func _gamma(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * 12.92 if v <= 0.0031308 else 1.055 * pow(v, 1.0 / 2.4) - 0.055

static func oklab(c: Color) -> Vector3:
	var r := _lin(c.r); var g := _lin(c.g); var b := _lin(c.b)
	var l := pow(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b, 1.0 / 3.0)
	var m := pow(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b, 1.0 / 3.0)
	var s := pow(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b, 1.0 / 3.0)
	return Vector3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)

static func to_color(lab: Vector3) -> Color:
	var l_ := lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
	var m_ := lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
	var s_ := lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
	var l := l_ * l_ * l_; var m := m_ * m_ * m_; var s := s_ * s_ * s_
	return Color(_gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
		_gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
		_gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), 1.0)

static func min_de(lab: Vector3, refs: Array) -> float:
	var d := 10.0
	for r: Vector3 in refs: d = minf(d, lab.distance_to(r))
	return d

static func human_palette() -> Array:
	if not _human.is_empty(): return _human
	for i in 24:
		var h := TAU * i / 24.0
		for l in [0.64, 0.70, 0.76]:
			for c in [0.11, 0.155]:
				var deg := rad_to_deg(h)
				if deg > 75.0 and deg < 140.0 and l < 0.74: continue
				var lab := Vector3(l, cos(h) * c, sin(h) * c)
				var col := to_color(lab)
				if oklab(col).distance_to(lab) < 0.01: _human.append(col)
	return _human

# The candidate most distinct from `refs`, or a random one of those at least MIN_DE away.
static func pick(cands: Array, refs: Array, rng: RandomNumberGenerator = null) -> Color:
	var best: Color = cands[0]; var best_d := -1.0
	var good := []
	for c: Color in cands:
		var d := min_de(oklab(c), refs)
		if d >= MIN_DE: good.append(c)
		if d > best_d + 1e-4: best_d = d; best = c
	if rng != null and not good.is_empty(): return good[rng.randi() % good.size()]
	return best

# Authored colour unless a reference is too close; then the smallest lightness / hue shift that clears it.
static func nudge(c: Color, refs: Array) -> Color:
	if min_de(oklab(c), refs) >= NUDGE_BELOW: return c
	return shift(c, refs)

static func shift(c: Color, refs: Array) -> Color:
	var lab := oklab(c)
	var chroma := Vector2(lab.y, lab.z).length()
	var hue := atan2(lab.z, lab.y)
	var best := c; var best_cost := 1e9; var best_d := min_de(lab, refs)
	for dl: float in DLS:
		for dh: float in DHS:
			var h := hue + dh
			var lx := clampf(lab.x + dl, 0.35, 0.92)
			var rgb := to_color(Vector3(lx, cos(h) * chroma, sin(h) * chroma))
			var d := min_de(oklab(rgb), refs)
			var cost := absf(dl) * 2.0 + absf(dh) * maxf(chroma, 0.05)
			if d >= MIN_DE and (best_d < MIN_DE or cost < best_cost):
				best = rgb; best_cost = cost; best_d = d
			elif best_d < MIN_DE and d > best_d:
				best = rgb; best_d = d
	return best
