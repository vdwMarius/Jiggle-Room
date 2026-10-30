@tool
class_name JellyData
extends Resource
## Everything needed to define one kind of jelly.
##
## To add a new jelly: export a glTF from Blender (see docs/BLENDER_WORKFLOW.md),
## create a new JellyData .tres in assets/jellies/, point `model_scene` (or `mesh`)
## at it and tune the numbers. No code changes needed: the jelly picker lists
## every .tres in assets/jellies/ automatically.

enum Shape { CUSTOM, BLOB, CUBE, STAR, DUCK, DOLPHIN, OCTOPUS, HEART }
enum Collision { AUTO_CONVEX, SPHERE, BOX, CAPSULE }

@export_group("Identity")
@export var id: StringName = &"blob"
@export var display_name: String = "Blob"
@export var sort_order: int = 0
## Unlock rule. Empty = unlocked from the start. Format "stat:amount",
## e.g. "pokes:50", "throws:20", "merges:3", "play_minutes:10".
@export var unlock_rule: String = ""

@export_group("Geometry")
## Built-in procedural shape, used when no mesh / model_scene is supplied.
@export var procedural_shape: Shape = Shape.BLOB
## A glTF/.glb scene from Blender. The first MeshInstance3D found is used.
@export var model_scene: PackedScene
## Or assign a Mesh resource directly (takes priority over model_scene).
@export var mesh: Mesh
## Final size of the jelly's longest half-extent in metres at scale 1.
@export_range(0.1, 2.0, 0.01) var base_radius: float = 0.45
@export var collision: Collision = Collision.AUTO_CONVEX

@export_group("Feel")
## How hard the jelly resists being deformed (0 = very soft, 1 = rubber).
## Scales how far grabs, lag and squash push the mesh.
@export_range(0.0, 1.0, 0.01) var stiffness: float = 0.45
## Damping ratio of every spring (0.05 = rings forever, 0.6 = barely wobbles).
## ~0.15-0.25 gives the 2-4 visible oscillations of a firm gelatin dessert.
@export_range(0.02, 1.0, 0.01) var damping: float = 0.2
## Natural frequency of the wobble in Hz.
@export_range(0.5, 10.0, 0.05) var wobble_frequency: float = 3.2
## Hard cap on any vertex's displacement, as a fraction of the jelly's radius.
@export_range(0.05, 0.5, 0.01) var max_deformation: float = 0.28
## Rigid-body mass in kg.
@export_range(0.05, 20.0, 0.05) var mass: float = 1.0
## Physics restitution (0 = dead thud, 1 = superball).
@export_range(0.0, 1.0, 0.01) var bounciness: float = 0.35
@export_range(0.0, 1.0, 0.01) var friction: float = 0.6

@export_group("Feel (advanced)")
## How strongly speed turns into stretch along the velocity direction.
@export_range(0.0, 0.2, 0.001) var stretch_per_speed: float = 0.035
## Multiplier on how far floppy parts (red vertex colour) trail behind.
@export_range(0.0, 3.0, 0.01) var lag_amount: float = 1.0
## Flattening per m/s of impact speed.
@export_range(0.0, 0.2, 0.001) var impact_squash_per_speed: float = 0.045
## Ripple height as a fraction of radius for a normal tap.
@export_range(0.0, 0.3, 0.005) var ripple_amplitude: float = 0.08
## Ripple fade-out speed (1/s).
@export_range(0.5, 10.0, 0.1) var ripple_decay: float = 3.0
## Ripple angular frequency multiplier relative to wobble_frequency.
@export_range(0.5, 6.0, 0.05) var ripple_frequency_scale: float = 2.5
## Ripple wavelength as a fraction of the radius.
@export_range(0.1, 2.0, 0.01) var ripple_wavelength: float = 0.55
## Weight given to fully black (rigid core) vertices. 0 = core never moves.
@export_range(0.0, 1.0, 0.01) var core_floppiness: float = 0.25

@export_group("Look")
@export var color: Color = Color(0.35, 0.8, 1.0)
@export var gradient_color: Color = Color(1.0, 0.45, 0.75)
@export_range(0.0, 1.0, 0.01) var gradient_amount: float = 0.0
## 0.1 - 1.0. Low = glassy, high = solid gummy.
@export_range(0.1, 1.0, 0.01) var opacity: float = 0.55
@export_range(0.0, 1.0, 0.01) var glitter: float = 0.0
@export_range(0.0, 1.0, 0.01) var glow_in_dark: float = 0.0


## Settings the player is allowed to customise and persist per jelly type.
const CUSTOM_KEYS: Array[String] = [
	"color", "gradient_color", "gradient_amount", "opacity", "glitter", "glow_in_dark",
	"stiffness", "damping", "wobble_frequency", "max_deformation", "mass", "bounciness",
]


## Returns a copy with the player's saved overrides applied.
func with_overrides(overrides: Dictionary) -> JellyData:
	var d: JellyData = duplicate()
	for key in overrides:
		if not CUSTOM_KEYS.has(key):
			continue
		var value = overrides[key]
		if get(key) is Color and value is String:
			value = Color.html(value)
		d.set(key, value)
	return d


func to_overrides() -> Dictionary:
	var out := {}
	for key in CUSTOM_KEYS:
		var value = get(key)
		out[key] = value.to_html() if value is Color else value
	return out
