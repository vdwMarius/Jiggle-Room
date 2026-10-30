class_name PhotoMode
extends Node
## Freeze the scene, orbit the camera, save PNG screenshots or short GIF clips.

signal status(message: String)
signal recording_changed(active: bool)

const PHOTO_DIR := "user://photos/"
const GIF_SECONDS := 2.5
const GIF_FPS := 12
const GIF_WIDTH := 240

var active := false
var recording := false
var camera: CameraRig
## Nodes hidden while capturing (the HUD).
var hide_during_capture: Array[CanvasItem] = []

var _thread: Thread


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func enter(focus: Vector3) -> void:
	active = true
	get_tree().paused = true
	camera.begin_orbit(focus)


func exit() -> void:
	active = false
	get_tree().paused = false
	camera.end_orbit()


func toggle_freeze() -> bool:
	get_tree().paused = not get_tree().paused
	return get_tree().paused


func take_screenshot() -> void:
	var img: Image = await _grab_frame()
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var path := PHOTO_DIR + "jiggle_%s.png" % _stamp()
	img.save_png(path)
	Feedback.vibrate(15, 0.4)
	status.emit("Saved " + _export_copy(path, img))


## Records GIF_SECONDS of live motion (unfreezes while recording).
func record_gif() -> void:
	if recording:
		return
	recording = true
	recording_changed.emit(true)
	var was_paused := get_tree().paused
	get_tree().paused = false
	var frames: Array[Image] = []
	var total := int(GIF_SECONDS * GIF_FPS)
	status.emit("Recording…")
	_set_ui_visible(false)
	for i in total:
		var img: Image = await _grab_frame(false)
		var h := int(GIF_WIDTH * float(img.get_height()) / img.get_width())
		img.resize(GIF_WIDTH, h, Image.INTERPOLATE_BILINEAR)
		img.convert(Image.FORMAT_RGB8)
		frames.append(img)
		await get_tree().create_timer(1.0 / GIF_FPS, true, false, true).timeout
	_set_ui_visible(true)
	get_tree().paused = was_paused
	status.emit("Encoding GIF…")
	_thread = Thread.new()
	_thread.start(_encode_job.bind(frames, int(100.0 / GIF_FPS)))
	while _thread.is_alive():
		await get_tree().process_frame
	var bytes: PackedByteArray = _thread.wait_to_finish()
	_thread = null
	DirAccess.make_dir_recursive_absolute(PHOTO_DIR)
	var path := PHOTO_DIR + "jiggle_%s.gif" % _stamp()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	recording = false
	recording_changed.emit(false)
	status.emit("Saved " + _export_copy(path, null))


func _encode_job(frames: Array[Image], delay_cs: int) -> PackedByteArray:
	return GifEncoder.encode(frames, delay_cs)


func _grab_frame(toggle_ui: bool = true) -> Image:
	if toggle_ui:
		_set_ui_visible(false)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if toggle_ui:
		_set_ui_visible(true)
	return img


func _set_ui_visible(v: bool) -> void:
	for c in hide_during_capture:
		c.visible = v


func _stamp() -> String:
	return Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")


## Also try to copy into the device's Pictures folder. On Android 10+ scoped
## storage usually blocks this without a media/share plugin, in which case the
## file stays in app storage (see docs/ANDROID_EXPORT.md).
func _export_copy(user_path: String, _img: Image) -> String:
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics.is_empty():
		return ProjectSettings.globalize_path(user_path)
	var dest_dir := pics.path_join("JiggleRoom")
	if DirAccess.make_dir_recursive_absolute(dest_dir) == OK:
		var dest := dest_dir.path_join(user_path.get_file())
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(user_path), dest) == OK:
			return dest
	return ProjectSettings.globalize_path(user_path)
