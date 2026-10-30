extends Node
## Persistent state: per-jelly customisations, room settings, stats & unlocks.
## Saved as JSON in user://jiggle_room.json (app-private storage on Android).

signal unlocked(kind: String, id: String, display_name: String)
signal settings_changed

const SAVE_PATH := "user://jiggle_room.json"
## v2: juicier default feel + furnished rooms (see _migrate).
const SAVE_VERSION := 2
const JELLY_DIR := "res://assets/jellies/"
const ROOM_DIR := "res://assets/rooms/"

var jelly_types: Array[JellyData] = []
var room_themes: Array[RoomTheme] = []

## jelly id -> Dictionary of JellyData overrides (colour, opacity, feel ...)
var jelly_overrides: Dictionary = {}
var room := {
	"theme": "living_room",
	"size": 1.0,
	"wall_color": "",      # "" = use theme default
	"floor_color": "",
	"ceiling_color": "",
	"light_color": "",
	"light_energy": 1.0,
	"props": true,
	"wall_mode": "normal", # normal | bouncy | sticky
	"slippery_floor": false,
}
var options := {
	"haptics": true,
	"sound": true,
	"volume": 0.8,
	"tilt_gravity": false,
	"shake": true,
	"last_jelly": "blob",
}
var stats := {"pokes": 0, "throws": 0, "merges": 0, "spawns": 0, "play_minutes": 0.0}
## ids unlocked by rewarded ads or other means beyond the stat rules.
var bonus_unlocks: Array = []

var _known_unlocks: Dictionary = {}
var _dirty := false
var _save_timer := 0.0


func _ready() -> void:
	jelly_types.assign(_load_resources(JELLY_DIR))
	jelly_types.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	room_themes.assign(_load_resources(ROOM_DIR))
	room_themes.sort_custom(func(a, b): return a.sort_order < b.sort_order)
	load_game()
	_known_unlocks = _unlocked_ids()


func _process(delta: float) -> void:
	stats.play_minutes += delta / 60.0 / maxf(Engine.time_scale, 0.01)
	_save_timer += delta
	if _save_timer > 20.0:
		_save_timer = 0.0
		_check_unlocks()
		if _dirty:
			save_game()


func _notification(what: int) -> void:
	# Android: app sent to background / closed.
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _load_resources(dir_path: String) -> Array:
	var out := []
	# ResourceLoader.list_directory is only in newer versions; DirAccess works
	# in exported builds as long as we strip the ".remap" suffix.
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("Missing folder " + dir_path)
		return out
	for f in dir.get_files():
		var file := f.trim_suffix(".remap")
		if not file.ends_with(".tres") and not file.ends_with(".res"):
			continue
		var res := load(dir_path + file)
		if res:
			out.append(res)
	return out


# ------------------------------------------------------------------ jellies

func get_jelly_type(id: StringName) -> JellyData:
	for j in jelly_types:
		if j.id == id:
			return j
	return jelly_types[0] if not jelly_types.is_empty() else null


## Base data merged with the player's saved customisations.
func get_custom_jelly(id: StringName) -> JellyData:
	var base := get_jelly_type(id)
	if base == null:
		return null
	return base.with_overrides(jelly_overrides.get(String(base.id), {}))


func save_jelly_custom(data: JellyData) -> void:
	jelly_overrides[String(data.id)] = data.to_overrides()
	mark_dirty()


func reset_jelly_custom(id: StringName) -> void:
	jelly_overrides.erase(String(id))
	mark_dirty()


func get_room_theme(id: String) -> RoomTheme:
	for t in room_themes:
		if String(t.id) == id:
			return t
	return room_themes[0] if not room_themes.is_empty() else null


# ------------------------------------------------------------------ unlocks

func is_unlocked(rule: String, id: String) -> bool:
	if rule.is_empty() or bonus_unlocks.has(id):
		return true
	var parts := rule.split(":")
	if parts.size() != 2:
		return true
	return float(stats.get(parts[0], 0.0)) >= float(parts[1])


func unlock_progress_text(rule: String) -> String:
	var parts := rule.split(":")
	if parts.size() != 2:
		return ""
	var have := int(stats.get(parts[0], 0.0))
	var label: String = {
		"pokes": "pokes", "throws": "throws", "merges": "merges",
		"spawns": "spawns", "play_minutes": "minutes played",
	}.get(parts[0], parts[0])
	return "%d / %s %s" % [mini(have, int(parts[1])), parts[1], label]


func grant_bonus_unlock(id: String) -> void:
	if not bonus_unlocks.has(id):
		bonus_unlocks.append(id)
		mark_dirty()
		_check_unlocks()
		settings_changed.emit()


func add_stat(stat: String, amount: float = 1.0) -> void:
	stats[stat] = stats.get(stat, 0.0) + amount
	mark_dirty()
	_check_unlocks()


## Emits `unlocked` for anything that became available since the last check.
func _check_unlocks() -> void:
	var now := _unlocked_ids()
	for key in now:
		if not _known_unlocks.has(key):
			var parts: PackedStringArray = key.split("|")
			unlocked.emit(parts[0], parts[1], now[key])
	_known_unlocks = now


func _unlocked_ids() -> Dictionary:
	var out := {}
	for j in jelly_types:
		if is_unlocked(j.unlock_rule, String(j.id)):
			out["jelly|" + String(j.id)] = j.display_name
	for t in room_themes:
		if is_unlocked(t.unlock_rule, String(t.id)):
			out["room|" + String(t.id)] = t.display_name
	return out


# ------------------------------------------------------------------ save/load

func mark_dirty() -> void:
	_dirty = true


func save_game() -> void:
	var payload := {
		"version": SAVE_VERSION,
		"jelly_overrides": jelly_overrides,
		"room": room,
		"options": options,
		"stats": stats,
		"bonus_unlocks": bonus_unlocks,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(payload, "\t"))
	_dirty = false


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		push_warning("Save file unreadable; starting fresh.")
		return
	jelly_overrides = parsed.get("jelly_overrides", {})
	room.merge(parsed.get("room", {}), true)
	options.merge(parsed.get("options", {}), true)
	stats.merge(parsed.get("stats", {}), true)
	bonus_unlocks = parsed.get("bonus_unlocks", [])
	_migrate(int(parsed.get("version", 1)))


func _migrate(from_version: int) -> void:
	if from_version < 2:
		# New, wobblier defaults: drop old saved feel values so they apply.
		for id in jelly_overrides:
			for key in ["stiffness", "damping", "wobble_frequency", "max_deformation"]:
				jelly_overrides[id].erase(key)
		# Rooms became furnished interiors with new ids.
		var renamed := {"cosy_lounge": "living_room"}
		room.theme = renamed.get(room.theme, room.theme)
		room.size = 1.0
		mark_dirty()
