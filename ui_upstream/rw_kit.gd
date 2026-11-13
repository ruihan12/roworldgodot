# RoWorld UI kit for the Godot port (2026-11-10): Godot equivalents of the upstream design system
# (src/client/UI/UITheme.luau, GlassPanel.luau, FillBar.luau, Widgets.pop_in). RoWorld's client is
# itself a port of Godot Controls on a 1600x900 canvas, so sizes here are the upstream logical px.
# Everything is static; preload it:  const RK := preload("res://ui_upstream/rw_kit.gd")
extends RefCounted

# --- colour tokens (UITheme.luau:147-173) ---
const GLASS := Color(0.051, 0.075, 0.149, 0.84)
const GLASS_SOLID := Color(0.043, 0.062, 0.125, 0.96)
const GLASS_RAISED := Color(0.1, 0.13, 0.24, 0.94)
const LINE := Color(1, 1, 1, 0.10)
const LINE_2 := Color(1, 1, 1, 0.18)
const FILL := Color(1, 1, 1, 0.06)
const FILL_2 := Color(1, 1, 1, 0.11)
const TEXT := Color(0.94, 0.955, 1.0)
const TEXT_2 := Color(0.68, 0.73, 0.86)
const TEXT_3 := Color(0.48, 0.53, 0.67)
const AMBER := Color(1.0, 0.71, 0.278)
const AMBER_HI := Color(1.0, 0.8, 0.47)
const AMBER_LO := Color(0.8, 0.49, 0.13)
const CYAN := Color(0.31, 0.82, 1.0)
const GREEN := Color(0.37, 0.89, 0.6)
const RED := Color(1.0, 0.33, 0.39)
const SURRENDER_RED := Color8(222, 48, 60)
const SURRENDER_RED_HI := Color8(240, 72, 82)
const SURRENDER_RED_LO := Color8(140, 20, 32)
const ORANGE := Color(1.0, 0.58, 0.36)
const VIOLET := Color(0.72, 0.62, 1.0)
const GOLD := Color(1.0, 0.84, 0.4)
const INK := Color(0.1, 0.066, 0.02)
const CLEAR := Color(0, 0, 0, 0)
# spacing / radii (:176-185)
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const R_SM := 6
const R_MD := 10
const R_LG := 14
const GLASS_BOOST := 0.08
const GLASS_SHEEN := 0.045
# Roblox top bar (Main.luau:31-42): 44 px circles RGB(18,18,21) @ 0.92 alpha, 36 px icon frames, 8 apart
const TOPBAR_BUTTON := 44.0
const TOPBAR_GAP := 8.0
const TOPBAR_FILL := Color8(18, 18, 21, 235)

const FONT_PATH := "res://assets/fonts/Rubik-VariableFont_wght.ttf"
static var _base: Font = null
static var _fonts := {}
static var _icons := {}

static func c(col: Color, a: float) -> Color:
	return Color(col.r, col.g, col.b, a)

# --- fonts: Rubik 100..900 (UITheme.font) ---
static func base_font() -> Font:
	if _base != null:
		return _base
	var f: Font = null
	if ResourceLoader.exists(FONT_PATH):
		f = load(FONT_PATH) as Font
	if f == null and FileAccess.file_exists(FONT_PATH):
		var ff := FontFile.new()
		if ff.load_dynamic_font(FONT_PATH) == OK:
			f = ff
	if f == null:
		f = ThemeDB.fallback_font
	if f is FontFile:
		(f as FontFile).antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		(f as FontFile).hinting = TextServer.HINTING_LIGHT
		(f as FontFile).subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO
	_base = f
	return f

static func font(weight := 500, spacing := 0.0) -> Font:
	var w := clampi(int((weight + 50) / 100) * 100, 100, 900)
	var key := "%d|%.2f" % [w, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = base_font()
	fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): w}
	if spacing != 0.0:
		fv.spacing_glyph = int(round(spacing))
	_fonts[key] = fv
	return fv

static func text_width(t: String, size: int, weight := 500, spacing := 0.0) -> float:
	return font(weight, spacing).get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x

# --- style factories (UITheme.flat / empty_box / shadow_box) ---
static func flat(bg: Color, radius := R_MD, border := CLEAR, bw := 0, mh := 0.0, mv := 0.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.corner_detail = 8 if radius < 20 else 12
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = mh; s.content_margin_right = mh
	s.content_margin_top = mv; s.content_margin_bottom = mv
	s.anti_aliasing = true
	return s

static func empty_box(mh := 0.0, mv := 0.0) -> StyleBoxEmpty:
	var s := StyleBoxEmpty.new()
	s.content_margin_left = mh; s.content_margin_right = mh
	s.content_margin_top = mv; s.content_margin_bottom = mv
	return s

# --- widgets (UITheme.label / caption / hbox / vbox / dividers / swatch / icon_rect) ---
static func label(t: String, size := 15, weight := 500, col := TEXT, spacing := 0.0) -> Label:
	var l := Label.new()
	l.text = t
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	style_label(l, size, weight, col, spacing)
	return l

static func style_label(l: Label, size: int, weight := 500, col := TEXT, spacing := 0.0) -> void:
	l.add_theme_font_override("font", font(weight, spacing))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("line_spacing", 0)

static func set_color(l: Control, col: Color) -> void:
	if l is Label:
		l.add_theme_color_override("font_color", col)
	elif l is TextureRect:
		l.modulate = col

static func caption(t: String, size := 11, col := TEXT_3) -> Label:
	return label(t.to_upper(), size, 700, col, 1)

static func fix_width(l: Label, w: float, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	l.clip_text = true
	l.custom_minimum_size.x = w
	l.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	l.horizontal_alignment = align
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS if align == HORIZONTAL_ALIGNMENT_LEFT else TextServer.OVERRUN_NO_TRIMMING

static func hbox(sep := S2) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func vbox(sep := S1) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b

static func spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func gap(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s

static func vdivider(h := 36.0) -> ColorRect:
	var d := ColorRect.new()
	d.color = LINE
	d.custom_minimum_size = Vector2(1, h)
	d.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

static func hdivider() -> ColorRect:
	var d := ColorRect.new()
	d.color = LINE
	d.custom_minimum_size = Vector2(0, 1)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return d

static func swatch(col: Color, px := 12.0, radius := 3) -> Panel:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(px, px)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", flat(col, radius, Color(1, 1, 1, 0.35), 1))
	return p

static func set_swatch(p: Panel, col: Color) -> void:
	var sb := p.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null or sb.bg_color != col:
		var radius: int = sb.corner_radius_top_left if sb else 3
		p.add_theme_stylebox_override("panel", flat(col, radius, Color(1, 1, 1, 0.35), 1))

# Icon masks (UITheme.icon): white 128 px masks, tinted at draw time.
const ICON_DIRS := ["ui_icons/", "ui/", "arsenal/ui/"]
static func icon_tex(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var t: Texture2D = null
	for d in ICON_DIRS:
		var p: String = "res://assets/" + d + name + ".png"
		if ResourceLoader.exists(p):
			t = load(p) as Texture2D
			if t: break
	_icons[name] = t
	return t

static func icon_rect(name: String, px: float, col := TEXT) -> TextureRect:
	var r := TextureRect.new()
	r.texture = icon_tex(name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.modulate = col
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return r

static func set_icon(r: TextureRect, name: String) -> void:
	r.texture = icon_tex(name)

# --- glass panel (GlassPanel.luau): navy tint + GLASS_BOOST, 1 px LINE border, top sheen and a soft
# 9-slice shadow (size 18, alpha 0.5, 6 px down). Content padding = pad_h x pad_v. ---
static func glass_style(tint := GLASS, radius := R_LG, border := LINE, shadow := 18, pad := Vector4(16, 12, 16, 12)) -> StyleBoxFlat:
	var a := tint.a
	if a < 0.97: a = clampf(a + GLASS_BOOST, 0.0, 0.97)
	var s := flat(Color(tint.r, tint.g, tint.b, a), radius, border, 1)
	s.content_margin_left = pad.x; s.content_margin_top = pad.y
	s.content_margin_right = pad.z; s.content_margin_bottom = pad.w
	if shadow > 0:
		s.shadow_color = Color(0, 0, 0, 0.32)
		s.shadow_size = int(shadow * 0.6)
		s.shadow_offset = Vector2(0, 6)
	return s

static func glass(pad_h := 16.0, pad_v := 12.0, radius := R_LG, shadow := 18, tint := GLASS) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.set_meta("rw_glass", {"tint": tint, "radius": radius, "border": LINE, "shadow": shadow, "pad": Vector4(pad_h, pad_v, pad_h, pad_v), "accent": CLEAR, "sheen": true})
	_restyle_glass(p)
	p.draw.connect(func(): _draw_sheen(p))
	return p

static func _restyle_glass(p: PanelContainer) -> void:
	var g: Dictionary = p.get_meta("rw_glass")
	p.add_theme_stylebox_override("panel", glass_style(g.tint, g.radius, g.border, g.shadow, g.pad))
	p.queue_redraw()

static func glass_set(p: PanelContainer, key: String, v) -> void:
	var g: Dictionary = p.get_meta("rw_glass")
	if g.get(key) == v: return
	g[key] = v
	_restyle_glass(p)

static func glass_padding(p: PanelContainer, l: float, t: float, r: float, b: float) -> void:
	glass_set(p, "pad", Vector4(l, t, r, b))

# Sheen: white top gradient (alpha GLASS_SHEEN fading out by 60 % of the height) + a 1 px line
# inset by the corner radius, brightest in the middle; optional 3 px left accent bar.
static func _draw_sheen(p: PanelContainer) -> void:
	var g: Dictionary = p.get_meta("rw_glass")
	var sz := p.size
	if sz.x <= 2 or sz.y <= 2: return
	var r: float = minf(float(g.radius), minf(sz.x, sz.y) * 0.5)
	if g.sheen:
		var h := sz.y * 0.6
		var steps := 6
		for i in steps:
			var y0 := h * i / steps
			var y1 := h * (i + 1) / steps
			var aa := GLASS_SHEEN * (1.0 - (float(i) + 0.5) / steps)
			var inset := 0.0
			if y0 < r:
				var dy := r - y0
				inset = r - sqrt(maxf(0.0, r * r - dy * dy))
			p.draw_rect(Rect2(inset + 1, y0 + 1, sz.x - 2 * inset - 2, y1 - y0), Color(1, 1, 1, aa))
		var lx := r
		if sz.x > lx * 2:
			var pts := PackedVector2Array([Vector2(lx, 1.0), Vector2(sz.x * 0.5, 1.0), Vector2(sz.x - lx, 1.0)])
			var cols := PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.2), Color(1, 1, 1, 0.0)])
			p.draw_polyline_colors(pts, cols, 1.0)
	var acc: Color = g.accent
	if acc.a > 0:
		var inset2 := minf(float(g.radius), sz.y * 0.5) * 0.55
		var ah := maxf(sz.y - inset2 * 2, 2)
		p.draw_rect(Rect2(1, inset2, 3, ah), acc)

# --- buttons (UITheme.theme variations) ---
static func _btn_styles(b: Button, n: Color, h: Color, pr: Color, border: Color, border_h: Color, fg: Color, weight: int, radius := R_MD, mh := 16.0, mv := 8.0) -> void:
	var bw := 1 if border.a > 0 else 0
	var bwh := 1 if border_h.a > 0 else 0
	b.add_theme_stylebox_override("normal", flat(n, radius, border, bw, mh, mv))
	b.add_theme_stylebox_override("hover", flat(h, radius, border_h, bwh, mh, mv))
	b.add_theme_stylebox_override("pressed", flat(pr, radius, border_h, bwh, mh, mv))
	b.add_theme_stylebox_override("hover_pressed", flat(pr, radius, border_h, bwh, mh, mv))
	b.add_theme_stylebox_override("disabled", flat(c(n, n.a * 0.5), radius, c(border, border.a * 0.5), bw, mh, mv))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", fg)
	for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, TEXT)
	b.add_theme_color_override("font_disabled_color", c(fg, 0.35))
	b.add_theme_color_override("icon_normal_color", fg)
	for k in ["icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(k, TEXT)
	b.add_theme_color_override("icon_disabled_color", c(fg, 0.35))
	b.add_theme_font_override("font", font(weight, 1))
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_constant_override("h_separation", 10)

static func button(t: String, variant := "GlassButton", icon := "", min_h := 44.0) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, min_h)
	b.set_meta("rw", true)
	match variant:
		"PrimaryButton", "SurrenderButton":
			var base := AMBER if variant == "PrimaryButton" else SURRENDER_RED
			var hi := AMBER_HI if variant == "PrimaryButton" else SURRENDER_RED_HI
			var lo := AMBER_LO if variant == "PrimaryButton" else SURRENDER_RED_LO
			var fg := INK if variant == "PrimaryButton" else Color.WHITE
			var pn := flat(base, R_MD, lo, 0, 22, 10); pn.border_width_bottom = 3
			var ph := flat(hi, R_MD, lo, 0, 22, 10); ph.border_width_bottom = 3
			var pp := flat(lo.lerp(base, 0.5), R_MD, CLEAR, 0, 22, 10); pp.content_margin_top = 12; pp.content_margin_bottom = 8
			var pd := flat(Color(1, 1, 1, 0.08), R_MD, LINE, 1, 22, 10)
			b.add_theme_stylebox_override("normal", pn); b.add_theme_stylebox_override("hover", ph)
			b.add_theme_stylebox_override("pressed", pp); b.add_theme_stylebox_override("hover_pressed", pp)
			b.add_theme_stylebox_override("disabled", pd); b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color", "icon_focus_color"]:
				b.add_theme_color_override(k, fg)
			b.add_theme_color_override("font_disabled_color", TEXT_3)
			b.add_theme_font_override("font", font(800, 2))
			b.add_theme_font_size_override("font_size", 17)
			b.add_theme_constant_override("h_separation", 10)
		"GhostButton":
			_btn_styles(b, Color(1, 1, 1, 0), FILL, Color(1, 1, 1, 0.03), CLEAR, CLEAR, TEXT_2, 600)
		"DangerButton":
			_btn_styles(b, c(RED, 0.14), c(RED, 0.26), c(RED, 0.08), c(RED, 0.45), c(RED, 0.8), Color(1.0, 0.78, 0.8), 700)
		"ChipButton":
			_btn_styles(b, Color(1, 1, 1, 0.04), FILL_2, c(AMBER, 0.2), LINE, LINE_2, TEXT_2, 600, 999, 14.0, 8.0)
			b.add_theme_stylebox_override("hover_pressed", flat(c(AMBER, 0.26), 999, AMBER, 1, 14, 6))
			b.add_theme_stylebox_override("pressed", flat(c(AMBER, 0.2), 999, c(AMBER, 0.9), 1, 14, 6))
			b.add_theme_color_override("font_pressed_color", AMBER_HI)
			b.add_theme_color_override("font_hover_pressed_color", AMBER_HI)
			b.add_theme_font_size_override("font_size", 13)
		_:
			_btn_styles(b, FILL, FILL_2, Color(1, 1, 1, 0.03), LINE, LINE_2, TEXT, 600)
	if icon != "":
		b.icon = icon_tex(icon)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 20)
	return b

# --- FillBar (FillBar.luau): rounded track, filled part + soft glow, optional goal line and markers ---
static func fill_bar(h := 4.0, col := CYAN) -> Control:
	var bar := Control.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(40, h)
	bar.set_meta("v", 0.0); bar.set_meta("target", 0.0); bar.set_meta("col", col); bar.set_meta("h", h)
	bar.set_meta("goal", -1.0); bar.set_meta("markers", []); bar.set_meta("glow", true)
	bar.draw.connect(func(): _draw_fill(bar))
	return bar

static func fill_set(bar: Control, v: float, instant := false) -> void:
	bar.set_meta("target", clampf(v, 0.0, 1.0))
	if instant: bar.set_meta("v", clampf(v, 0.0, 1.0))
	bar.queue_redraw()

static func fill_step(bar: Control, dt: float) -> void:
	var v: float = bar.get_meta("v"); var t: float = bar.get_meta("target")
	if absf(v - t) > 1e-6:
		v += (t - v) * (1.0 - exp(-dt * 6.0))
		if absf(v - t) < 0.0005: v = t
		bar.set_meta("v", v)
		bar.queue_redraw()

static func _draw_fill(bar: Control) -> void:
	var h: float = bar.get_meta("h")
	var w := bar.size.x
	var y := (bar.size.y - h) * 0.5
	var r := int(h * 0.5)
	bar.draw_style_box(flat(Color(1, 1, 1, 0.08), r), Rect2(0, y, w, h))
	var v: float = bar.get_meta("v")
	var fw := w * v
	var col: Color = bar.get_meta("col")
	if fw > 0.5:
		var frw := maxf(fw, h)
		if bar.get_meta("glow"):
			bar.draw_style_box(flat(c(col, 0.22), int(r + 1.5)), Rect2(-1.5, y - 1.5, frw + 3, h + 3))
		bar.draw_style_box(flat(col, r), Rect2(0, y, frw, h))
	var goal: float = bar.get_meta("goal")
	if goal >= 0:
		var gx := roundf(w * goal)
		bar.draw_rect(Rect2(gx - 1, y - 4, 2, h + 8), GOLD)
	for m in bar.get_meta("markers"):
		var mx := roundf(w * clampf(float(m.v), 0, 1))
		bar.draw_rect(Rect2(mx - 2, y - 3, 4, h + 6), Color(0, 0, 0, 0.6))
		bar.draw_rect(Rect2(mx - 1, y - 3, 2, h + 6), m.get("color", TEXT))

# --- animation (Widgets.pop_in): fade in over 0.8*dur (cubic out), scale from_scale -> 1 (back out) ---
static func pop_in(n: Control, delay := 0.0, from_scale := 0.96, dur := 0.4) -> void:
	n.visible = true
	n.modulate.a = 0.0
	n.pivot_offset = n.size * 0.5
	var t := n.create_tween()
	if delay > 0: t.tween_interval(delay)
	t.tween_callback(func(): n.pivot_offset = n.size * 0.5; n.scale = Vector2(from_scale, from_scale))
	t.set_parallel(true)
	t.tween_property(n, "modulate:a", 1.0, dur * 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(n, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

static func fade_out(n: CanvasItem, dur := 0.35, free := false) -> void:
	var t := n.create_tween()
	t.tween_property(n, "modulate:a", 0.0, dur)
	t.tween_callback(func():
		if free: n.queue_free()
		else: n.visible = false; n.modulate.a = 1.0)

# --- anchoring helpers (UDim2 anchors as in the upstream apply_layout functions) ---
static func anchor_top_center(c: Control, top: float, dx := 0.0) -> void:
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 0.0; c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH; c.grow_vertical = Control.GROW_DIRECTION_END
	c.offset_left = dx; c.offset_right = dx; c.offset_top = top; c.offset_bottom = top
	c.reset_size()

static func anchor_bottom_center(c: Control, bottom: float) -> void:
	c.anchor_left = 0.5; c.anchor_right = 0.5; c.anchor_top = 1.0; c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH; c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = 0; c.offset_right = 0; c.offset_top = -bottom; c.offset_bottom = -bottom
	c.reset_size()

static func anchor_top_right(c: Control, top: float, right: float) -> void:
	c.anchor_left = 1.0; c.anchor_right = 1.0; c.anchor_top = 0.0; c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN; c.grow_vertical = Control.GROW_DIRECTION_END
	c.offset_left = -right; c.offset_right = -right; c.offset_top = top; c.offset_bottom = top
	c.reset_size()

static func anchor_top_left(c: Control, top: float, left: float) -> void:
	c.anchor_left = 0.0; c.anchor_right = 0.0; c.anchor_top = 0.0; c.anchor_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_END; c.grow_vertical = Control.GROW_DIRECTION_END
	c.offset_left = left; c.offset_right = left; c.offset_top = top; c.offset_bottom = top
	c.reset_size()

static func anchor_bottom_left(c: Control, bottom: float, left: float) -> void:
	c.anchor_left = 0.0; c.anchor_right = 0.0; c.anchor_top = 1.0; c.anchor_bottom = 1.0
	c.grow_horizontal = Control.GROW_DIRECTION_END; c.grow_vertical = Control.GROW_DIRECTION_BEGIN
	c.offset_left = left; c.offset_right = left; c.offset_top = -bottom; c.offset_bottom = -bottom
	c.reset_size()

# UITheme.owner_ui_color: lift dark nation colours for UI use
static func owner_ui_color(col: Color) -> Color:
	var l := col.get_luminance()
	if l < 0.32:
		return col.lerp(Color.WHITE, 0.32 - l + 0.1)
	return col

# UITheme.fmt_pct
static func fmt_pct(share: float) -> String:
	var p := share * 100.0
	if p > 0.0 and p < 1.0: return "%.2f%%" % p
	return "%.1f%%" % p

static func fmt_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	if s >= 3600: return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
