@tool
class_name RoomTheme
extends Resource
## A room look. Drop a new .tres into assets/rooms/ to add a theme.

enum Pattern { PLAIN, STRIPES, CHECKER, PLANKS, CAUSTICS, PANELS, STARS, DOTS }
enum Props { NONE, LOUNGE, AQUARIUM, SPACE, PLAYROOM }

@export var id: StringName = &"cosy_lounge"
@export var display_name: String = "Cosy Lounge"
@export var sort_order: int = 0
## Same format as JellyData.unlock_rule ("pokes:50" etc). Empty = free.
@export var unlock_rule: String = ""

@export_group("Surfaces")
@export var wall_color: Color = Color(0.95, 0.86, 0.78)
@export var wall_color_b: Color = Color(0.9, 0.78, 0.7)
@export var wall_pattern: Pattern = Pattern.STRIPES
## Optional image instead of a procedural pattern (tinted by wall_color).
@export var wall_texture: Texture2D
@export var floor_color: Color = Color(0.62, 0.42, 0.3)
@export var floor_color_b: Color = Color(0.52, 0.34, 0.24)
@export var floor_pattern: Pattern = Pattern.PLANKS
@export var floor_texture: Texture2D
@export var ceiling_color: Color = Color(0.98, 0.95, 0.9)
@export var pattern_scale: float = 1.0

@export_group("Lighting")
@export var light_color: Color = Color(1.0, 0.9, 0.78)
@export var light_energy: float = 1.0
@export var ambient_color: Color = Color(0.7, 0.62, 0.6)
@export var ambient_energy: float = 0.6
@export var glow: bool = false

@export_group("Props")
@export var props: Props = Props.LOUNGE
