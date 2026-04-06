extends Node

const SETTINGS_FILE_PATH := "user://graphics_settings.cfg"
const SETTINGS_SECTION := "graphics"
const QUALITY_KEY := "quality"

const QUALITY_LOW := 0
const QUALITY_MEDIUM := 1
const QUALITY_HIGH := 2

const QUALITY_SCALES := [0.67, 0.85, 1.0]
const PARTICLE_RATIO := [0.45, 0.7, 1.0]

var _quality_index: int = QUALITY_LOW
var _last_scene: Node = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_quality_index = _load_quality_index()
	set_process(true)
	call_deferred("apply_current_profile")

func _process(_delta: float) -> void:
	var current_scene := get_tree().current_scene
	if current_scene != _last_scene:
		_last_scene = current_scene
		apply_current_profile()

func get_quality_index() -> int:
	return _quality_index

func set_quality_index(index: int, save_to_disk: bool = true) -> void:
	_quality_index = clampi(index, QUALITY_LOW, QUALITY_HIGH)
	if save_to_disk:
		_save_quality_index(_quality_index)
	apply_current_profile()

func apply_current_profile() -> void:
	_apply_to_viewport()
	var scene := get_tree().current_scene
	if scene:
		_apply_to_scene(scene)

func _apply_to_viewport() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return

	match _quality_index:
		QUALITY_LOW:
			viewport.msaa_3d = Viewport.MSAA_DISABLED
		QUALITY_MEDIUM:
			viewport.msaa_3d = Viewport.MSAA_2X
		QUALITY_HIGH:
			viewport.msaa_3d = Viewport.MSAA_4X

	if _has_property(viewport, "scaling_3d_scale"):
		viewport.set("scaling_3d_scale", QUALITY_SCALES[_quality_index])

func _apply_to_scene(scene: Node) -> void:
	for node in scene.find_children("*", "WorldEnvironment", true, false):
		var env_node := node as WorldEnvironment
		if env_node == null or env_node.environment == null:
			continue
		_apply_world_environment(env_node)

	for node in scene.find_children("*", "DirectionalLight3D", true, false):
		var light := node as DirectionalLight3D
		if light:
			_apply_directional_light(light)

	for node in scene.find_children("*", "OmniLight3D", true, false):
		var light := node as OmniLight3D
		if light:
			_apply_local_light(light)

	for node in scene.find_children("*", "SpotLight3D", true, false):
		var light := node as SpotLight3D
		if light:
			_apply_local_light(light)

	for node in scene.find_children("*", "GPUParticles3D", true, false):
		var particles := node as GPUParticles3D
		if particles:
			_apply_particles(particles)

func _apply_world_environment(world_env: WorldEnvironment) -> void:
	var env := world_env.environment
	_capture_original(world_env, "glow_enabled", env.glow_enabled)
	_capture_original(world_env, "volumetric_fog_enabled", env.volumetric_fog_enabled)

	var original_glow: bool = bool(_get_original(world_env, "glow_enabled", env.glow_enabled))
	var original_volumetric: bool = bool(_get_original(world_env, "volumetric_fog_enabled", env.volumetric_fog_enabled))

	match _quality_index:
		QUALITY_LOW:
			env.glow_enabled = false
			env.volumetric_fog_enabled = false
		QUALITY_MEDIUM:
			env.glow_enabled = false
			env.volumetric_fog_enabled = original_volumetric
		QUALITY_HIGH:
			env.glow_enabled = original_glow
			env.volumetric_fog_enabled = original_volumetric

func _apply_directional_light(light: DirectionalLight3D) -> void:
	_capture_original(light, "shadow_enabled", light.shadow_enabled)
	_capture_original(light, "shadow_distance", light.directional_shadow_max_distance)

	var original_shadow_enabled: bool = bool(_get_original(light, "shadow_enabled", light.shadow_enabled))
	var original_distance: float = float(_get_original(light, "shadow_distance", light.directional_shadow_max_distance))

	match _quality_index:
		QUALITY_LOW:
			light.shadow_enabled = original_shadow_enabled
			light.directional_shadow_max_distance = maxf(1.0, original_distance * 0.6)
		QUALITY_MEDIUM:
			light.shadow_enabled = original_shadow_enabled
			light.directional_shadow_max_distance = maxf(1.0, original_distance * 0.85)
		QUALITY_HIGH:
			light.shadow_enabled = original_shadow_enabled
			light.directional_shadow_max_distance = original_distance

func _apply_local_light(light: Light3D) -> void:
	_capture_original(light, "shadow_enabled", light.shadow_enabled)
	var original_shadow_enabled: bool = bool(_get_original(light, "shadow_enabled", light.shadow_enabled))

	match _quality_index:
		QUALITY_LOW:
			light.shadow_enabled = false
		QUALITY_MEDIUM:
			light.shadow_enabled = false
		QUALITY_HIGH:
			light.shadow_enabled = original_shadow_enabled

func _apply_particles(particles: GPUParticles3D) -> void:
	_capture_original(particles, "amount_ratio", particles.amount_ratio)
	var base_ratio: float = float(_get_original(particles, "amount_ratio", particles.amount_ratio))

	match _quality_index:
		QUALITY_LOW:
			particles.amount_ratio = clampf(base_ratio * PARTICLE_RATIO[QUALITY_LOW], 0.0, 1.0)
		QUALITY_MEDIUM:
			particles.amount_ratio = clampf(base_ratio * PARTICLE_RATIO[QUALITY_MEDIUM], 0.0, 1.0)
		QUALITY_HIGH:
			particles.amount_ratio = clampf(base_ratio, 0.0, 1.0)

func _capture_original(node: Object, key: String, value: Variant) -> void:
	var meta_key := "_perf_orig_%s" % key
	if not node.has_meta(meta_key):
		node.set_meta(meta_key, value)

func _get_original(node: Object, key: String, fallback: Variant) -> Variant:
	var meta_key := "_perf_orig_%s" % key
	return node.get_meta(meta_key, fallback)

func _load_quality_index() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_FILE_PATH) != OK:
		return QUALITY_LOW
	return clampi(int(cfg.get_value(SETTINGS_SECTION, QUALITY_KEY, QUALITY_LOW)), QUALITY_LOW, QUALITY_HIGH)

func _save_quality_index(index: int) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SETTINGS_SECTION, QUALITY_KEY, clampi(index, QUALITY_LOW, QUALITY_HIGH))
	cfg.save(SETTINGS_FILE_PATH)

func _has_property(target: Object, property_name: String) -> bool:
	for info in target.get_property_list():
		if str(info.name) == property_name:
			return true
	return false
