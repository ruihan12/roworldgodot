# Port of RoWorld src/shared/Core/NumberFormat.luau (render_number / render_troops) and the UITheme
# formatters (src/client/UI/UITheme.luau:1890-1953). Reference only: the live HUD keeps its own
# K/M/B/T/Qd/Qt formatter. Upstream stops at B.
extends RefCounted

static func _fixed(v: float, d: int) -> String:
	return ("%." + str(d) + "f") % v

# Floored, never rounded: 1234 -> "1.23K", 123456 -> "123K", 1259999 -> "1.25M".
static func render_number(num: float) -> String:
	if is_nan(num): num = 0.0
	num = maxf(num, 0.0)
	if num >= 10_000_000_000.0: return _fixed(floorf(num / 100000000.0) / 10.0, 1) + "B"
	if num >= 1_000_000_000.0: return _fixed(floorf(num / 10000000.0) / 100.0, 2) + "B"
	if num >= 10_000_000.0: return _fixed(floorf(num / 100000.0) / 10.0, 1) + "M"
	if num >= 1_000_000.0: return _fixed(floorf(num / 10000.0) / 100.0, 2) + "M"
	if num >= 100000.0: return str(int(floorf(num / 1000.0))) + "K"
	if num >= 10000.0: return _fixed(floorf(num / 100.0) / 10.0, 1) + "K"
	if num >= 1000.0: return _fixed(floorf(num / 10.0) / 100.0, 2) + "K"
	return str(int(floorf(num)))

# Upstream shows troops as the internal count / 10.
static func render_troops(troops: float) -> String:
	return render_number(troops / 10.0)

# UITheme format_troops / fmt_num (gold and other numbers): rounded printf, sign kept.
static func fmt_num(value: float) -> String:
	var v := absf(value)
	var s: String
	if v >= 1000000.0:
		s = ("%.2fM" % (v / 1000000.0)) if v < 10000000.0 else ("%.1fM" % (v / 1000000.0))
	elif v >= 1000.0:
		s = ("%.1fK" % (v / 1000.0)) if v < 100000.0 else ("%dK" % int(floorf(v / 1000.0)))
	else:
		s = str(int(floorf(v)))
	return ("-" if value < 0 else "") + s

static func fmt_cost(v: float) -> String:
	if v >= 1000000.0:
		var m := v / 1000000.0
		return ("%dM" % roundi(m)) if absf(m - roundf(m)) < 0.05 else ("%.1fM" % m)
	if v >= 1000.0:
		var k := v / 1000.0
		return ("%dK" % roundi(k)) if (k >= 10.0 or absf(k - roundf(k)) < 0.05) else ("%.1fK" % k)
	return str(int(floorf(v)))

static func fmt_pct(share: float) -> String:
	var p := share * 100.0
	if p >= 10.0: return "%.1f%%" % p
	return ("%.2f%%" % p) if (p > 0.0 and p < 1.0) else ("%.1f%%" % p)

static func fmt_time(seconds: float) -> String:
	var s := maxi(0, int(floorf(seconds)))
	if s >= 3600: return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]

static func fmt_rate(v: float) -> String:
	if absf(v) < 0.5: return "±0/s"
	return ("+" if v > 0 else "−") + fmt_num(absf(v)) + "/s"
