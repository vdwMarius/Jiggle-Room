extends Node
## Optional rewarded ads - the only kind of ad in Jiggle Room.
##
## This is a thin wrapper so the game never depends on an ad SDK. Out of the box
## no ad plugin is installed and `is_available()` returns false, so the
## "Watch an ad to unlock" buttons are hidden. In debug builds a fake ad is
## shown (2 s wait) so the flow can be tested.
##
## To ship real ads, install an AdMob plugin for Godot 4 Android (see
## docs/ANDROID_EXPORT.md) and fill in `_show_plugin_ad` below.

signal reward_granted(reward_id: String)
signal ad_failed(reward_id: String)

var _plugin: Object = null


func _ready() -> void:
	# Example: a Godot Android plugin exposed as a singleton named "AdMob".
	if Engine.has_singleton("AdMob"):
		_plugin = Engine.get_singleton("AdMob")


func is_available() -> bool:
	return _plugin != null or OS.is_debug_build()


## Show a rewarded ad. `reward_id` comes back with `reward_granted` only if the
## player watched to the end. Never call this without the player tapping a
## clearly-labelled button.
func show_rewarded(reward_id: String) -> void:
	if _plugin != null:
		_show_plugin_ad(reward_id)
	elif OS.is_debug_build():
		await get_tree().create_timer(2.0, true, false, true).timeout
		reward_granted.emit(reward_id)
	else:
		ad_failed.emit(reward_id)


func _show_plugin_ad(reward_id: String) -> void:
	# Wire your plugin here, e.g.:
	#   _plugin.show_rewarded_ad()
	#   _plugin.connect("rewarded", func(_t, _a): reward_granted.emit(reward_id))
	#   _plugin.connect("rewarded_ad_failed_to_load", func(_e): ad_failed.emit(reward_id))
	ad_failed.emit(reward_id)
