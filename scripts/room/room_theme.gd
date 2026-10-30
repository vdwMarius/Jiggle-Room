@tool
class_name RoomTheme
extends Resource
## A furnished room. Drop a new .tres into assets/rooms/ to add one; pick an
## existing `layout` (furniture arrangement) and recolour it.

enum Pattern { PLAIN, STRIPES, CHECKER, PLANKS, CAUSTICS, PANELS, STARS, DOTS, TILES, CARPET }
enum Layout { LIVING_ROOM, BEDROOM, KITCHEN, PLAYROOM, AQUARIUM, SPACE }

@export var id: StringName = &"living_room"
@export var display_name: String = "Living Room"
@export var sort_order: int = 0
## Same format as JellyData.unlock_rule ("pokes:50" etc). Empty = free.
@export var unlock_rule: String = ""

@export_group("Room")
@export var layout: Layout = Layout.LIVING_ROOM
## Width (x), height (y), depth (z) in metres at room-size 1.0.
@export var room_size: Vector3 = Vector3(6.0, 2.8, 5.0)

@export_group("Surfaces")
@export var wall_color: Color = Color(0.95, 0.86, 0.78)
@export var wall_color_b: Color = Color(0.91, 0.8, 0.72)
@export var wall_pattern: Pattern = Pattern.STRIPES
## Optional image instead of a procedural pattern (tinted by wall_color).
@export var wall_texture: Texture2D
@export var floor_color: Color = Color(0.62, 0.42, 0.3)
@export var floor_color_b: Color = Color(0.52, 0.34, 0.24)
@export var floor_pattern: Pattern = Pattern.PLANKS
@export var floor_texture: Texture2D
@export var ceiling_color: Color = Color(0.98, 0.95, 0.9)
@export var pattern_scale: float = 1.0

@export_group("Furnishing")
## Sofa / bed linen / main soft furnishing colour.
@export var fabric_color: Color = Color(0.45, 0.55, 0.7)
@export var wood_color: Color = Color(0.6, 0.42, 0.28)
## Rug, cushions, small accents.
@export var accent_color: Color = Color(0.9, 0.55, 0.45)
## What you see through the windows (unshaded).
@export var sky_color: Color = Color(0.65, 0.85, 1.0)

@export_group("Lighting")
@export var light_color: Color = Color(1.0, 0.9, 0.78)
@export var light_energy: float = 1.0
@export var ambient_color: Color = Color(0.7, 0.62, 0.6)
@export var ambient_energy: float = 0.6
@export var glow: bool = false
