extends CanvasLayer

signal animation_finished

@onready var rect = $ColorRect
@onready var label = $Label

const CORE_LOCATIONS := [
	"fallback_hamlet",
	"filesystem_forest",
	"deamon_depths",
	"bios_vault",
	"proprietary_citadel",
]

const CHARACTER_LIST := [
	"elder_shell",
	"broken_installer",
	"lost_file",
	"gate_keeper",
	"driver_remnant",
	"printer_beast",
]

var _is_animating := false
var _last_reported_bucket := -1
var _target_location := "fallback_hamlet"
var _area_lines: Array[String] = []
var _area_line_index := 0
var _resource_stream_completed := false

func fade_in(scene_path: String = "", spawn_name: String = ""):
	if _is_animating:
		return
	_is_animating = true

	show()
	rect.modulate.a = 0.0
	var intro_tween := create_tween()
	intro_tween.tween_property(rect, "modulate:a", 1.0, 0.25).set_trans(Tween.TRANS_SINE)
	await intro_tween.finished

	_target_location = _resolve_location_name(scene_path)
	_area_lines = _build_area_specific_lines(_target_location)
	_area_line_index = 0
	_last_reported_bucket = -1
	_resource_stream_completed = false

	label.text = "SYSTEM LOG v5.1 -- %s\n" % Time.get_datetime_string_from_system()
	await _append_lines(_build_boot_lines(spawn_name), 0.045)

	_is_animating = false
	emit_signal("animation_finished")

func fade_out():
	if not _resource_stream_completed:
		set_loading_progress(1.0)

	var outro_tween := create_tween()
	outro_tween.tween_property(rect, "modulate:a", 0.0, 0.2).set_trans(Tween.TRANS_SINE)
	await outro_tween.finished
	hide()
	label.text = ""
	_last_reported_bucket = -1
	_area_lines.clear()
	_area_line_index = 0
	_resource_stream_completed = false
	emit_signal("animation_finished")

func _input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()

func _unhandled_input(_event: InputEvent) -> void:
	if visible:
		get_viewport().set_input_as_handled()

func set_loading_progress(progress: float) -> void:
	var clamped_progress: float = clampf(progress, 0.0, 1.0)
	var bucket := int(floor(clamped_progress * 10.0))
	if bucket > _last_reported_bucket:
		_last_reported_bucket = bucket
		label.text += "[LOAD] RESOURCE STREAM: %d%%\n" % int(round(clamped_progress * 100.0))
		_try_append_area_line(clamped_progress)

	if clamped_progress >= 1.0 and not _resource_stream_completed:
		_resource_stream_completed = true
		label.text += "[OK] RESOURCE STREAM COMPLETE\n"

func _try_append_area_line(progress: float) -> void:
	if _area_line_index >= _area_lines.size():
		return

	var threshold := float(_area_line_index + 1) / float(_area_lines.size() + 1)
	if progress >= threshold:
		label.text += _area_lines[_area_line_index] + "\n"
		_area_line_index += 1

func _append_lines(lines: Array[String], step_seconds: float) -> void:
	for entry in lines:
		label.text += entry + "\n"
		await get_tree().create_timer(step_seconds).timeout

func _build_boot_lines(spawn_name: String) -> Array[String]:
	var lines: Array[String] = []
	var target_location := _target_location

	lines.append("[OK] USER \"NOVA\" LOGGED IN SUCCESSFULLY")
	lines.append("[OK] INITIALIZING WORLD LOADER")
	lines.append("[OK] SCANNING REGIONS: " + ", ".join(CORE_LOCATIONS))
	lines.append("[OK] MOUNT POINT ACTIVE: " + target_location)

	if spawn_name.strip_edges() != "":
		lines.append("[OK] TARGET ENTRY NODE: " + spawn_name)

	lines.append("[OK] VERIFYING CHARACTER INSTANCES")
	for character in CHARACTER_LIST:
		lines.append("[OK] CHARACTER READY: " + character)

	lines.append("[OK] RESOLVING SHADERS AND COLLISION MAPS")
	lines.append("[OK] SYNCHRONIZING QUEST FLAGS")
	lines.append("[OK] PREPARING RESOURCE STREAM")
	return lines

func _build_area_specific_lines(location_name: String) -> Array[String]:
	match location_name:
		"fallback_hamlet":
			return [
				"[AREA:fallback_hamlet] VALIDATING WELL DISTRICT NAVMESH",
				"[AREA:fallback_hamlet] LINKING VILLAGER DIALOGUE REGISTRY",
				"[AREA:fallback_hamlet] ENABLING HOME INSTANCE SHARDS",
			]
		"filesystem_forest":
			return [
				"[AREA:filesystem_forest] INDEXING DIRECTORY CANOPY CLUSTERS",
				"[AREA:filesystem_forest] REPAIRING SYMLINK PATHS",
				"[AREA:filesystem_forest] ACTIVATING LOST_FILE TRACKERS",
			]
		"deamon_depths":
			return [
				"[AREA:deamon_depths] MOUNTING KERNEL CHASM SECTORS",
				"[AREA:deamon_depths] AUTHENTICATING BOSS DOOR TOKEN",
				"[AREA:deamon_depths] WAKING PRINT SPOOLER SENTINELS",
			]
		"bios_vault":
			return [
				"[AREA:bios_vault] READING FIRMWARE MEMORY PAGES",
				"[AREA:bios_vault] LOCKING CAMERA STAGING CHANNEL",
				"[AREA:bios_vault] PATCHING LEGACY BOOT FLAGS",
			]
		"proprietary_citadel":
			return [
				"[AREA:proprietary_citadel] DECRYPTING VENDOR GATE LIST",
				"[AREA:proprietary_citadel] SYNCING ACCESS CONTROL MATRICES",
				"[AREA:proprietary_citadel] INITIALIZING CITADEL CORE SERVICES",
			]
		_:
			return [
				"[AREA:%s] VALIDATING SCENE DEPENDENCIES" % location_name,
				"[AREA:%s] STREAMING WORLD SEGMENTS" % location_name,
				"[AREA:%s] FINALIZING RUNTIME BINDINGS" % location_name,
			]

func _resolve_location_name(scene_path: String) -> String:
	if scene_path.is_empty():
		return "fallback_hamlet"

	var file_name := scene_path.get_file().trim_suffix(".tscn")
	match file_name:
		"file_system_forest":
			return "filesystem_forest"
		"fallback_hamlet":
			return "fallback_hamlet"
		"deamon_depths":
			return "deamon_depths"
		"bios_vault", "bios_vault_":
			return "bios_vault"
		_:
			if file_name.find("citadel") != -1:
				return "proprietary_citadel"
			return file_name
