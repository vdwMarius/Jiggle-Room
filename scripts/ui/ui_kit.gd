class_name UiKit
extends RefCounted
## Small helpers that build a touch-friendly theme and widgets in code.

const ACCENT := Color(1.0, 0.45, 0.62)
const INK := Color(0.2, 0.18, 0.28)
const PANEL_BG := Color(1.0, 0.98, 0.99, 0.94)
const BUTTON_H := 88.0
const FONT_SIZE := 26


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	t.set_stylebox("normal", "Button", _box(Color(1, 1, 1, 0.92), 22))
	t.set_stylebox("hover", "Button", _box(Color(1, 0.94, 0.97, 0.96), 22))
	t.set_stylebox("pressed", "Button", _box(ACCENT.lightened(0.55), 22))
	t.set_stylebox("disabled", "Button", _box(Color(0.9, 0.9, 0.92, 0.7), 22))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", INK)
	t.set_color("font_disabled_color", "Button", INK.lerp(Color.WHITE, 0.5))
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "CheckButton", INK)
	t.set_color("font_pressed_color", "CheckButton", INK)
	t.set_color("font_hover_color", "CheckButton", INK)
	t.set_stylebox("normal", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("hover_pressed", "CheckButton", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())

	t.set_stylebox("panel", "PanelContainer", _box(PANEL_BG, 30, 18))

	# Fat sliders with a big round grabber.
	var track := _box(Color(0.88, 0.85, 0.9), 12)
	track.content_margin_top = 10
	track.content_margin_bottom = 10
	t.set_stylebox("slider", "HSlider", track)
	var fill := _box(ACCENT.lightened(0.2), 12)
	fill.content_margin_top = 10
	fill.content_margin_bottom = 10
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var knob := _circle_texture(44, ACCENT)
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	t.set_constant("center_grabber", "HSlider", 1)
	return t


static func _box(c: Color, radius: int, margin: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin + 6
	sb.content_margin_right = margin + 6
	sb.content_margin_top = margin
	sb.content_margin_bottom = margin
	sb.shadow_color = Color(0.3, 0.1, 0.25, 0.12)
	sb.shadow_size = 4
	return sb


static func _circle_texture(size: int, c: Color) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var r := size * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			var col := c if d < r - 5.0 else Color.WHITE
			col.a = a
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func button(text: String, on_press: Callable, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, BUTTON_H)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	if on_press.is_valid():
		b.pressed.connect(on_press)
	return b


static func swatch(c: Color, on_press: Callable, size_px: float = 64.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(size_px, size_px)
	b.focus_mode = Control.FOCUS_NONE
	var sb := _box(c, int(size_px / 2), 0)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.border_color = ACCENT
	b.add_theme_stylebox_override("pressed", pressed)
	b.pressed.connect(on_press)
	return b


## Label + slider row. Returns the HSlider (set .step on it for coarser steps;
## steps >= 1 are shown as whole numbers).
static func slider(parent: Control, label: String, min_v: float, max_v: float, value: float,
		on_change: Callable) -> HSlider:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var l := Label.new()
	box.add_child(l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = 0.01
	s.value = value
	s.custom_minimum_size = Vector2(0, 56)
	s.focus_mode = Control.FOCUS_NONE
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.text = _slider_text(label, value, s.step)
	s.value_changed.connect(func(v: float) -> void:
		l.text = _slider_text(label, v, s.step)
		on_change.call(v))
	box.add_child(s)
	parent.add_child(box)
	return s


static func _slider_text(label: String, v: float, step: float) -> String:
	return "%s  %d" % [label, roundi(v)] if step >= 1.0 else "%s  %.2f" % [label, v]


static func toggle(parent: Control, label: String, value: bool, on_change: Callable) -> CheckButton:
	var c := CheckButton.new()
	c.text = label
	c.button_pressed = value
	c.custom_minimum_size = Vector2(0, 72)
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(on_change)
	parent.add_child(c)
	return c


static func heading(parent: Control, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 30)
	l.add_theme_color_override("font_color", ACCENT.darkened(0.25))
	parent.add_child(l)
	return l


static func flow(parent: Control, columns: int = 0) -> Container:
	var c: Container
	if columns > 0:
		var g := GridContainer.new()
		g.columns = columns
		g.add_theme_constant_override("h_separation", 10)
		g.add_theme_constant_override("v_separation", 10)
		c = g
	else:
		var h := HFlowContainer.new()
		h.add_theme_constant_override("h_separation", 10)
		h.add_theme_constant_override("v_separation", 10)
		c = h
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(c)
	return c
