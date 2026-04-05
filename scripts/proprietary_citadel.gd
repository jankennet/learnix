extends Node3D
## Handles proprietary citadel level setup based on player karma

@export var good_karma_sky_color: Color = Color(0.1, 0.5, 1.0, 1.0)  # Bright blue
@export var bad_karma_env_color: Color = Color(0.3, 0.3, 0.4, 1.0)   # Dark gray/slate

var world_environment: WorldEnvironment
var environment: Environment
var directional_light: DirectionalLight3D
var _base_light_color: Color = Color.WHITE
var _base_light_energy: float = 1.0

func _ready() -> void:
	world_environment = get_node_or_null("WorldEnvironment")
	if world_environment:
		environment = world_environment.environment

	directional_light = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if directional_light:
		_base_light_color = directional_light.light_color
		_base_light_energy = directional_light.light_energy
	
	_apply_karma_sky()

func _apply_karma_sky() -> void:
	if not environment:
		return
	
	var karma = SceneManager.player_karma if SceneManager else "neutral"

	# Proprietary Citadel has two intended moods in this arc:
	# high karma => sunny; anything else => dark/genocide tone.
	if karma == "good":
		_set_bright_blue_sky()
	else:
		_set_dark_sky()

func _set_bright_blue_sky() -> void:
	"""Set a bright blue sky for good karma"""
	if not environment:
		return
	
	# Change background to a solid color
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = good_karma_sky_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 1.0
	if directional_light:
		directional_light.light_color = _base_light_color
		directional_light.light_energy = _base_light_energy

func _set_dark_sky() -> void:
	"""Set a dark sky with reduced lighting for bad karma"""
	if not environment:
		return
	
	# Change background to a solid dark color
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = bad_karma_env_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	environment.ambient_light_energy = 0.6
	if directional_light:
		directional_light.light_color = Color(0.5, 0.54, 0.65, 1.0)
		directional_light.light_energy = maxf(0.15, _base_light_energy * 0.35)

