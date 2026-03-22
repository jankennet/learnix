extends Node3D
## Handles proprietary citadel level setup based on player karma

@export var good_karma_sky_color: Color = Color(0.1, 0.5, 1.0, 1.0)  # Bright blue
@export var bad_karma_env_color: Color = Color(0.3, 0.3, 0.4, 1.0)   # Dark gray/slate
@export var neutral_karma_sky_color: Color = Color(0.5, 0.5, 0.6, 1.0)  # Neutral gray

var world_environment: WorldEnvironment
var environment: Environment

func _ready() -> void:
	world_environment = get_node_or_null("WorldEnvironment")
	if world_environment:
		environment = world_environment.environment
	
	_apply_karma_sky()

func _apply_karma_sky() -> void:
	if not environment:
		return
	
	var karma = SceneManager.player_karma if SceneManager else "neutral"
	
	match karma:
		"good":
			_set_bright_blue_sky()
		"bad":
			_set_dark_sky()
		_:
			_set_neutral_sky()

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

func _set_neutral_sky() -> void:
	"""Set a neutral gray sky for neutral karma"""
	if not environment:
		return
	
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = neutral_karma_sky_color
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.8)
	environment.ambient_light_energy = 0.8
