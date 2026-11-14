# Upstream RoWorld maps (World, Africa, Asia, Europe, North America, South America, Mediterranean,
# Middle East, Oceania, United States + the two test
# fixtures Pangaea and Onion), decoded from the Luau data modules (MapCodec: base64 -> zstd -> tile
# bytes) and converted to 1792x1600 by tools/convert_upstream_maps.py. Data: res://maps/upstream/.
#   <id>.codes.bin  zlib, W*H u8: 0 water 1 plains 2 highland 3 mountain 4 snow (same as RealMaps b64
#                   payload plus code 4: Antarctica on World; plains rules, drawn white - see docs/HOOKS.md)
#   <id>.tiles.bin  zlib, W*H u8 upstream WorldMap tile byte: bit7 land, bit6 shore, bit5 ocean,
#                   bits0-4 magnitude (land elevation 0-30; water ceil(dist to coast / 2), cap 31)
#   <id>.json       meta: name, k_lin, scale, crop, nations [{name, flag, x, y}], notes
#   index.json      map list, nation colour table (Data/Nations.luau), tribe names (Data/Tribes.luau)
# Antarctica is ordinary land (code 4 snow); no impassable / ice (0x9F) tiles remain. Usage: const UpstreamMaps := preload(...)
extends RefCounted

const DIR := "res://maps/upstream/"
const W := 1792
const H := 1600
const T_WATER := 0
const T_PLAINS := 1
const T_HIGHLAND := 2
const T_MOUNTAIN := 3
const T_SNOW := 4  # passable, conquerable land treated as plains; only its colour differs
const SNOW_COLOR := Color8(0xF4, 0xF7, 0xFA)
# Menu order (the game's maps first, then the two upstream test fixtures). Edit to hide fixtures.
const ORDER := ["world", "europe", "asia", "northamerica", "southamerica", "africa", "mediterranean", "middleeast",
	"oceania", "unitedstates", "pangaea", "onion"]

static var _index := {}
static var _meta := {}
static var _codes := {}
static var _tiles := {}
static var _real := {}

static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("UpstreamMaps: cannot open %s (%d)" % [path, FileAccess.get_open_error()])
		return null
	return JSON.parse_string(f.get_as_text())

static func _read_zlib(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("UpstreamMaps: cannot open %s" % path)
		return PackedByteArray()
	var raw := f.get_buffer(f.get_length())
	var out := raw.decompress(W * H, FileAccess.COMPRESSION_DEFLATE)
	if out.size() != W * H:
		push_error("UpstreamMaps: %s decoded to %d bytes, expected %d" % [path, out.size(), W * H])
		return PackedByteArray()
	return out

static func index() -> Dictionary:
	if _index.is_empty():
		var d = _read_json(DIR + "index.json")
		if d is Dictionary: _index = d
	return _index

static func ids() -> Array:
	return ORDER.duplicate()

static func count() -> int:
	return ORDER.size()

static func id_at(k: int) -> String:
	return ORDER[clampi(k, 0, ORDER.size() - 1)]

static func meta(id: String) -> Dictionary:
	if not _meta.has(id):
		var d = _read_json(DIR + id + ".json")
		_meta[id] = d if d is Dictionary else {}
	return _meta[id]

# W*H terrain codes (0 water, 1 plains, 2 highland, 3 mountain, 4 snow).
static func codes(id: String) -> PackedByteArray:
	if not _codes.has(id): _codes[id] = _read_zlib(DIR + id + ".codes.bin")
	return _codes[id]

static func codes_at(k: int) -> PackedByteArray:
	return codes(id_at(k))

# W*H full upstream tile bytes (elevation magnitude, shore/ocean bits, water depth).
static func tiles(id: String) -> PackedByteArray:
	if not _tiles.has(id): _tiles[id] = _read_zlib(DIR + id + ".tiles.bin")
	return _tiles[id]

static func is_snow(code: int) -> bool:
	return code == T_SNOW

static func is_lake(tb: int) -> bool:
	return tb < 128 and (tb & 0x20) == 0

static func elevation(tb: int) -> int:
	return tb & 0x1F if tb >= 128 else -1

# Nations as main.gd expects them: [name, flag, x, y].
static func nations(id: String) -> Array:
	var out := []
	for n in meta(id).get("nations", []):
		out.append([str(n.name), str(n.flag), int(n.x), int(n.y)])
	return out

# A dictionary shaped like a RealMaps.MAPS entry ({id, name, k_lin, b64, nations, land}), so main.gd
# paths that read RealMaps entries work unchanged. b64 is base64(zlib(codes)), as in real_maps.gd.
static func as_real_map(id: String) -> Dictionary:
	if _real.has(id): return _real[id]
	var m := meta(id)
	if m.is_empty(): return {}
	var f := FileAccess.open(DIR + id + ".codes.bin", FileAccess.READ)
	if f == null: return {}
	var e := {"id": id, "name": str(m.name), "k_lin": float(m.k_lin),
		"b64": Marshalls.raw_to_base64(f.get_buffer(f.get_length())),
		"nations": nations(id), "land": int(m.land_tiles), "upstream": true}
	_real[id] = e
	return e

static func real_map_at(k: int) -> Dictionary:
	return as_real_map(id_at(k))

# Menu rows shaped like main.gd MAPS entries: [name, seed, 0.0, 200].
static func menu_entries() -> Array:
	var out := []
	for k in ORDER.size():
		out.append([str(meta(ORDER[k]).get("name", ORDER[k])), 12001 + k * 97, 0.0, 200])
	return out

# Upstream nation colours by lowercase flag code ("us" -> "#719bfa"), from Data/Nations.luau.
static func nation_colors() -> Dictionary:
	var out := {}
	for n in index().get("nation_table", []):
		out[str(n.code).to_lower()] = str(n.color)
	return out

static func tribe_names() -> Array:
	return index().get("tribe_names", [])

# Card thumbnail in the in-game terrain palette (MapSurface.luau colours).
static func preview_image(id: String, pw: int, ph: int) -> Image:
	var tb := tiles(id)
	var cd := codes(id)
	var im := Image.create(pw, ph, false, Image.FORMAT_RGBA8)
	if tb.size() != W * H: return im
	for py in ph:
		var sy := clampi(int((py + 0.5) * H / ph), 0, H - 1)
		for px in pw:
			var sx := clampi(int((px + 0.5) * W / pw), 0, W - 1)
			var b: int = tb[sy * W + sx]
			var c: Color
			if cd.size() == W * H and cd[sy * W + sx] == T_SNOW:
				c = SNOW_COLOR
			elif b >= 128:
				var m := b & 0x1F
				if (b & 0x40) != 0: c = Color8(0xCC, 0xCB, 0x9E)
				elif m < 10: c = Color8(0xBE, 0xDC - 2 * m, 0x8A)
				elif m < 20: c = Color8(0xDC + 2 * (m - 10), 0xCB + 2 * (m - 10), 0x9E + 2 * (m - 10))
				else: c = Color8(mini(255, 0xE6 + m / 2), mini(255, 0xE6 + m / 2), mini(255, 0xE6 + m / 2))
			else:
				var d := mini(b & 0x1F, 10)
				c = Color8(0x47 - d, 0x85 - d, 0xB5 - d)
			im.set_pixel(px, py, c)
	return im

static func preview_texture(id: String, pw: int, ph: int) -> ImageTexture:
	return ImageTexture.create_from_image(preview_image(id, pw, ph))
