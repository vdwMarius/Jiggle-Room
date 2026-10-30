class_name Hud
extends CanvasLayer
## Touch-first UI, built in code. Toolbar sits at the bottom in portrait and on
## the right in landscape; one sliding panel is open at a time above/beside it.

const PRESETS := [
	Color(0.35, 0.8, 1.0), Color(1.0, 0.4, 0.55), Color(0.55, 0.95, 0.45),
	Color(1.0, 0.8, 0.25), Color(0.7, 0.45, 1.0), Color(1.0, 0.55, 0.25),
	Color(0.3, 0.95, 0.85), Color(0.95, 0.95, 1.0),
]
const ROOM_SWATCHES := [
	Color(0.95, 0.86, 0.78), Color(0.98, 0.78, 0.82), Color(0.75, 0.88, 0.98),
	Color(0.8, 0.95, 0.8), Color(0.98, 0.95, 0.75), Color(0.85, 0.78, 0.95),
	Color(0.35, 0.35, 0.42), Color(0.15, 0.18, 0.3), Color(0.55, 0.38, 0.28),
]
const GRAVITY_LABELS := ["Gravity", "Zero-G", "Flipped"]

var main   # main.gd (untyped: methods are called dynamically)

var _root: Control
var _toolbar: Container
var _toolbar_holder: PanelContainer
var _panel: PanelContainer
var _panel_scroll: ScrollContainer
var _panel_body: VBoxContainer
var _open_panel := ""
var _toast: Label
var _toast_tween: Tween
var _photo_bar: PanelContainer
var _gravity_button: Button
var _slow_button: Button
var _merge_button: Button
var _freeze_button: Button
var _gif_button: Button
var _selected: JellyObject
var _landscape := false


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.make_theme()
	add_child(_root)

	_toolbar_holder = PanelContainer.new()
	_root.add_child(_toolbar_holder)

	_panel = PanelContainer.new()
	_panel.visible = false
	_root.add_child(_panel)
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(_panel_scroll)
	_panel_body = VBoxContainer.new()
	_panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_body.add_theme_constant_override("separation", 14)
	_panel_scroll.add_child(_panel_body)

	_photo_bar = PanelContainer.new()
	_photo_bar.visible = false
	_root.add_child(_photo_bar)
	var pb := HBoxContainer.new()
	pb.add_theme_constant_override("separation", 10)
	_photo_bar.add_child(pb)
	_freeze_button = UiKit.button("Play", _on_freeze)
	pb.add_child(_freeze_button)
	pb.add_child(UiKit.button("Snap", func() -> void: main.photo.take_screenshot()))
	_gif_button = UiKit.button("GIF", func() -> void: main.photo.record_gif())
	pb.add_child(_gif_button)
	pb.add_child(UiKit.button("Done", func() -> void: main.set_photo_mode(false)))

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_color_override("font_color", Color.WHITE)
	_toast.add_theme_color_override("font_outline_color", Color(0.25, 0.1, 0.25))
	_toast.add_theme_constant_override("outline_size", 10)
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	_root.add_child(_toast)

	_build_toolbar()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _build_toolbar() -> void:
	for c in _toolbar_holder.get_children():
		c.queue_free()
	if _landscape:
		_toolbar = VBoxContainer.new()
		_toolbar.add_theme_constant_override("separation", 8)
	else:
		# Two rows in portrait so every label stays big and readable.
		var grid := GridContainer.new()
		grid.columns = 4
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		_toolbar = grid
	_toolbar_holder.add_child(_toolbar)
	_toolbar.add_child(UiKit.button("Jelly", _toggle_panel.bind("jelly")))
	_toolbar.add_child(UiKit.button("Colour", _toggle_panel.bind("look")))
	_toolbar.add_child(UiKit.button("Room", _toggle_panel.bind("room")))
	_gravity_button = UiKit.button(GRAVITY_LABELS[main.motion.mode], func() -> void: main.cycle_gravity())
	_toolbar.add_child(_gravity_button)
	_slow_button = UiKit.button("Slow", func() -> void: main.toggle_slow_motion())
	_slow_button.toggle_mode = true
	_slow_button.button_pressed = Engine.time_scale < 1.0
	_toolbar.add_child(_slow_button)
	_toolbar.add_child(UiKit.button("Photo", func() -> void: main.set_photo_mode(true)))
	_toolbar.add_child(UiKit.button("More", _toggle_panel.bind("more")))


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var landscape := size.x > size.y
	if landscape != _landscape:
		_landscape = landscape
		_build_toolbar()
	var m := 16.0
	var safe := _safe_margins()
	if _landscape:
		var bar_w := 190.0
		_toolbar_holder.position = Vector2(size.x - bar_w - m - safe.z, m + safe.y)
		_toolbar_holder.size = Vector2(bar_w, size.y - 2 * m - safe.y - safe.w)
		var pw := minf(size.x * 0.45, 640.0)
		_panel.position = Vector2(size.x - bar_w - pw - 2 * m - safe.z, m + safe.y)
		_panel.size = Vector2(pw, size.y - 2 * m - safe.y - safe.w)
	else:
		var bar_h := UiKit.BUTTON_H * 2.0 + 48.0
		_toolbar_holder.position = Vector2(m + safe.x, size.y - bar_h - m - safe.w)
		_toolbar_holder.size = Vector2(size.x - 2 * m - safe.x - safe.z, bar_h)
		var ph := size.y * 0.42
		_panel.position = Vector2(m + safe.x, size.y - bar_h - ph - 2 * m - safe.w)
		_panel.size = Vector2(size.x - 2 * m - safe.x - safe.z, ph)
	_photo_bar.size = Vector2(minf(size.x - 2 * m, 720.0), UiKit.BUTTON_H + 40.0)
	_photo_bar.position = Vector2((size.x - _photo_bar.size.x) * 0.5, size.y - _photo_bar.size.y - m - safe.w)
	_toast.size = Vector2(size.x - 4 * m, 120)
	_toast.position = Vector2(2 * m, m + safe.y + 40)


## Notch / gesture-bar insets (left, top, right, bottom) in viewport pixels.
func _safe_margins() -> Vector4:
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	var vp := get_viewport().get_visible_rect().size
	if screen.x <= 0 or safe.size.x <= 0:
		return Vector4.ZERO
	var k := vp.x / float(screen.x)
	return Vector4(safe.position.x * k, safe.position.y * k,
		(screen.x - safe.end.x) * k, (screen.y - safe.end.y) * k)


func is_point_over_ui(p: Vector2) -> bool:
	for c in [_toolbar_holder, _panel, _photo_bar]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false


func set_photo_mode(on: bool) -> void:
	_toolbar_holder.visible = not on
	_photo_bar.visible = on
	if on:
		_close_panel()
	_freeze_button.text = "Play" if get_tree().paused else "Freeze"


func set_gravity_mode(mode: int) -> void:
	_gravity_button.text = GRAVITY_LABELS[mode]


func set_slow_motion(on: bool) -> void:
	_slow_button.set_pressed_no_signal(on)


func set_selected(j: JellyObject) -> void:
	_selected = j
	if _open_panel == "look":
		_rebuild_panel()


func set_recording(on: bool) -> void:
	_gif_button.disabled = on
	_gif_button.text = "Rec…" if on else "GIF"


func toast(text: String, seconds: float = 2.2) -> void:
	_toast.text = text
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)


func _on_freeze() -> void:
	var paused: bool = main.photo.toggle_freeze()
	_freeze_button.text = "Play" if paused else "Freeze"


# ------------------------------------------------------------------ panels

func _toggle_panel(which: String) -> void:
	if _open_panel == which:
		_close_panel()
		return
	_open_panel = which
	_panel.visible = true
	_rebuild_panel()
	_panel_scroll.scroll_vertical = 0


func _close_panel() -> void:
	_open_panel = ""
	_panel.visible = false


func refresh() -> void:
	if _open_panel != "":
		_rebuild_panel()


func _rebuild_panel() -> void:
	var keep_scroll := _panel_scroll.scroll_vertical
	for c in _panel_body.get_children():
		c.queue_free()
	match _open_panel:
		"jelly":
			_build_jelly_panel()
		"look":
			_build_look_panel()
		"room":
			_build_room_panel()
		"more":
			_build_more_panel()
	_panel_body.add_child(UiKit.button("Close", _close_panel))
	await get_tree().process_frame
	_panel_scroll.scroll_vertical = keep_scroll


func _build_jelly_panel() -> void:
	UiKit.heading(_panel_body, "Tap to add a jelly")
	var grid := UiKit.flow(_panel_body, 2)
	for jd in GameState.jelly_types:
		var unlocked := GameState.is_unlocked(jd.unlock_rule, String(jd.id))
		if unlocked:
			grid.add_child(UiKit.button(jd.display_name, main.spawn_jelly.bind(jd.id)))
		else:
			var box := VBoxContainer.new()
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var b := UiKit.button("Locked: " + jd.display_name, Callable())
			b.disabled = true
			box.add_child(b)
			var l := Label.new()
			l.text = GameState.unlock_progress_text(jd.unlock_rule)
			l.add_theme_font_size_override("font_size", 20)
			box.add_child(l)
			if AdsService.is_available():
				box.add_child(UiKit.button("Watch ad to unlock", _watch_ad.bind(String(jd.id))))
			grid.add_child(box)
	var row := UiKit.flow(_panel_body, 2)
	_merge_button = UiKit.button("Merge: " + ("On" if main.merge_mode else "Off"), func() -> void:
		main.merge_mode = not main.merge_mode
		_merge_button.text = "Merge: " + ("On" if main.merge_mode else "Off")
		if main.merge_mode:
			toast("Merge on: drag one jelly into another"))
	row.add_child(_merge_button)
	row.add_child(UiKit.button("Remove last touched", func() -> void: main.remove_selected()))
	row.add_child(UiKit.button("Clear all", func() -> void: main.clear_jellies()))
	row.add_child(UiKit.button("Drop from top", func() -> void: main.respawn_selected()))
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Tap = poke · Drag = stretch · Flick = throw · Pinch = resize · Shake phone = shake"
	hint.add_theme_font_size_override("font_size", 20)
	_panel_body.add_child(hint)


func _watch_ad(id: String) -> void:
	toast("Loading ad…")
	AdsService.show_rewarded(id)


func _build_look_panel() -> void:
	var j := _selected
	if j == null or not is_instance_valid(j):
		UiKit.heading(_panel_body, "Touch a jelly first")
		return
	var d := j.data
	UiKit.heading(_panel_body, d.display_name + " – colour")
	var presets := UiKit.flow(_panel_body)
	for c in PRESETS:
		presets.add_child(UiKit.swatch(c, func() -> void:
			d.color = c
			_look_changed(j)
			_rebuild_panel()))
	var hsv := [d.color.h, d.color.s, d.color.v]
	UiKit.slider(_panel_body, "Hue", 0.0, 1.0, hsv[0], func(v: float) -> void:
		d.color = Color.from_hsv(v, d.color.s, d.color.v)
		_look_changed(j))
	UiKit.slider(_panel_body, "Saturation", 0.0, 1.0, hsv[1], func(v: float) -> void:
		d.color = Color.from_hsv(d.color.h, v, d.color.v)
		_look_changed(j))
	UiKit.slider(_panel_body, "Brightness", 0.15, 1.0, hsv[2], func(v: float) -> void:
		d.color = Color.from_hsv(d.color.h, d.color.s, v)
		_look_changed(j))
	# 10% = nearly solid gummy, 100% = clear glass (opacity 0.1).
	var transparency := UiKit.slider(_panel_body, "Transparency %", 10.0, 100.0, (1.0 - d.opacity) * 100.0 + 10.0, func(v: float) -> void:
		d.opacity = clampf(1.0 - (v - 10.0) / 100.0, 0.1, 1.0)
		_look_changed(j))
	transparency.step = 1.0
	UiKit.heading(_panel_body, "Extras")
	UiKit.slider(_panel_body, "Gradient", 0.0, 1.0, d.gradient_amount, func(v: float) -> void:
		d.gradient_amount = v
		_look_changed(j))
	UiKit.slider(_panel_body, "Gradient hue", 0.0, 1.0, d.gradient_color.h, func(v: float) -> void:
		d.gradient_color = Color.from_hsv(v, 0.6, 1.0)
		_look_changed(j))
	UiKit.slider(_panel_body, "Glitter", 0.0, 1.0, d.glitter, func(v: float) -> void:
		d.glitter = v
		_look_changed(j))
	UiKit.slider(_panel_body, "Glow in the dark", 0.0, 1.0, d.glow_in_dark, func(v: float) -> void:
		d.glow_in_dark = v
		_look_changed(j))

	UiKit.heading(_panel_body, "Feel")
	UiKit.slider(_panel_body, "Stiffness", 0.0, 1.0, d.stiffness, func(v: float) -> void:
		d.stiffness = v
		_feel_changed(j))
	UiKit.slider(_panel_body, "Damping", 0.05, 0.8, d.damping, func(v: float) -> void:
		d.damping = v
		_feel_changed(j))
	UiKit.slider(_panel_body, "Wobble Hz", 1.0, 8.0, d.wobble_frequency, func(v: float) -> void:
		d.wobble_frequency = v
		_feel_changed(j))
	UiKit.slider(_panel_body, "Max squish", 0.1, 0.35, d.max_deformation, func(v: float) -> void:
		d.max_deformation = v
		_feel_changed(j))
	UiKit.slider(_panel_body, "Mass", 0.2, 5.0, d.mass, func(v: float) -> void:
		d.mass = v
		_feel_changed(j))
	UiKit.slider(_panel_body, "Bounciness", 0.0, 0.95, d.bounciness, func(v: float) -> void:
		d.bounciness = v
		_feel_changed(j))
	var row := UiKit.flow(_panel_body, 2)
	row.add_child(UiKit.button("Test wobble", func() -> void: j.jolt(Vector3.UP * 2.5)))
	row.add_child(UiKit.button("Reset to default", func() -> void:
		GameState.reset_jelly_custom(d.id)
		j.setup(GameState.get_custom_jelly(d.id), j.size)
		_rebuild_panel()))


func _look_changed(j: JellyObject) -> void:
	if is_instance_valid(j):
		j.apply_look()
		GameState.save_jelly_custom(j.data)


func _feel_changed(j: JellyObject) -> void:
	if is_instance_valid(j):
		j.apply_feel()
		GameState.save_jelly_custom(j.data)


func _build_room_panel() -> void:
	var r: Dictionary = GameState.room
	UiKit.heading(_panel_body, "Theme")
	var themes := UiKit.flow(_panel_body, 2)
	for t in GameState.room_themes:
		if GameState.is_unlocked(t.unlock_rule, String(t.id)):
			var b := UiKit.button(t.display_name, func() -> void:
				r.theme = String(t.id)
				r.wall_color = ""
				r.floor_color = ""
				r.ceiling_color = ""
				r.light_color = ""
				main.apply_room()
				_rebuild_panel())
			b.toggle_mode = true
			b.button_pressed = r.theme == String(t.id)
			themes.add_child(b)
		else:
			var b := UiKit.button("Locked: %s\n%s" % [t.display_name, GameState.unlock_progress_text(t.unlock_rule)], Callable())
			b.disabled = true
			b.custom_minimum_size.y = UiKit.BUTTON_H * 1.3
			themes.add_child(b)
			if AdsService.is_available():
				themes.add_child(UiKit.button("Ad: unlock " + t.display_name, _watch_ad.bind(String(t.id))))
	UiKit.slider(_panel_body, "Room size", 0.7, 1.6, float(r.size), func(v: float) -> void:
		r.size = v
		main.apply_room(true))
	for key in [["wall_color", "Walls"], ["floor_color", "Floor"], ["ceiling_color", "Ceiling"]]:
		UiKit.heading(_panel_body, key[1])
		var sw := UiKit.flow(_panel_body)
		var reset_surface := UiKit.button("Theme", func() -> void:
			r[key[0]] = ""
			main.apply_room())
		reset_surface.custom_minimum_size.x = 120.0
		sw.add_child(reset_surface)
		for c in ROOM_SWATCHES:
			sw.add_child(UiKit.swatch(c, func() -> void:
				r[key[0]] = c.to_html(false)
				main.apply_room()))
	UiKit.heading(_panel_body, "Lighting")
	var lights := UiKit.flow(_panel_body)
	var reset_light := UiKit.button("Theme", func() -> void:
		r.light_color = ""
		main.apply_room())
	reset_light.custom_minimum_size.x = 120.0
	lights.add_child(reset_light)
	for c in [Color(1, 0.9, 0.75), Color(1, 1, 1), Color(0.7, 0.85, 1), Color(1, 0.7, 0.85), Color(0.75, 1, 0.8), Color(0.8, 0.7, 1)]:
		lights.add_child(UiKit.swatch(c, func() -> void:
			r.light_color = c.to_html(false)
			main.apply_room()))
	UiKit.slider(_panel_body, "Brightness", 0.1, 1.6, float(r.light_energy), func(v: float) -> void:
		r.light_energy = v
		main.apply_room())
	UiKit.heading(_panel_body, "Walls & floor")
	var modes := UiKit.flow(_panel_body, 3)
	for mode in ["normal", "bouncy", "sticky"]:
		var b := UiKit.button(mode.capitalize(), func() -> void:
			r.wall_mode = mode
			main.apply_room()
			_rebuild_panel())
		b.toggle_mode = true
		b.button_pressed = r.wall_mode == mode
		modes.add_child(b)
	UiKit.toggle(_panel_body, "Slippery floor", bool(r.slippery_floor), func(on: bool) -> void:
		r.slippery_floor = on
		main.apply_room())
	UiKit.toggle(_panel_body, "Furniture & props", bool(r.props), func(on: bool) -> void:
		r.props = on
		main.apply_room())


func _build_more_panel() -> void:
	var o: Dictionary = GameState.options
	UiKit.heading(_panel_body, "Motion")
	UiKit.toggle(_panel_body, "Tilt phone to steer gravity", bool(o.tilt_gravity), func(on: bool) -> void:
		o.tilt_gravity = on
		main.apply_options())
	UiKit.toggle(_panel_body, "Shake phone to shake jellies", bool(o.shake), func(on: bool) -> void:
		o.shake = on
		main.apply_options())
	UiKit.heading(_panel_body, "Feedback")
	UiKit.toggle(_panel_body, "Vibration", bool(o.haptics), func(on: bool) -> void:
		o.haptics = on
		GameState.mark_dirty())
	UiKit.toggle(_panel_body, "Sounds", bool(o.sound), func(on: bool) -> void:
		o.sound = on
		GameState.mark_dirty())
	UiKit.slider(_panel_body, "Volume", 0.0, 1.0, float(o.volume), func(v: float) -> void:
		o.volume = v
		GameState.mark_dirty())
	UiKit.heading(_panel_body, "Your stats")
	var s: Dictionary = GameState.stats
	var l := Label.new()
	l.text = "Pokes: %d\nThrows: %d\nMerges: %d\nMinutes played: %d" % [s.pokes, s.throws, s.merges, int(s.play_minutes)]
	_panel_body.add_child(l)
