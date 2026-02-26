extends CanvasLayer
## A styled dialogue balloon for Learnix game.

const DialogueManagerConstants = preload("res://addons/dialogue_manager/constants.gd")
const UI_BASE_RESOLUTION := Vector2(1280.0, 720.0)
const UI_MIN_SCALE := 1.0
const UI_MAX_SCALE := 1.8
const CHARACTER_FONT_BASE := 16
const DIALOGUE_FONT_BASE := 14
const RESPONSE_FONT_BASE := 12

## The dialogue resource
@export var dialogue_resource: DialogueResource

## Start from a given title when using balloon as a [Node] in a scene.
@export var start_from_title: String = ""

## If running as a [Node] in a scene then auto start the dialogue.
@export var auto_start: bool = false

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"

## Dictionary mapping character names to portrait textures
@export var character_portraits: Dictionary = {}

const DIALOGUE_PORTRAITS_BASE := {
	"Broken Installer": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_broken_installer.png",
	"Elder Shell": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_elder_shell.png",
	"Gate Keeper": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_mount_whisperer.png",
	"Mount Whisperer": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_mount_whisperer.png"
}

const DIALOGUE_PORTRAITS_VARIANTS := {
	"Broken Link": {
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_broken_link.png",
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_broken_link.png"
	},
	"Driver Remnant": {
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_driver_remnant.png",
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_driver_remnant.png"
	},
	"Hardware Ghost": {
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_hardware_ghost.png",
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_hardware_ghost.png"
	},
	"Lost File": {
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_lost_file.png",
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_lost_file.png"
	},
	"Messy Directory": {
		"good": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_good_messy_directory.png",
		"bad": "res://Assets/characterSpriteSheets/ss_dialouge/dialouge_bad_messy_directory.png"
	}
}

## A sound player for voice lines (if they exist).
@onready var audio_stream_player: AudioStreamPlayer = %AudioStreamPlayer

## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		else:
			# The dialogue has finished so close the balloon
			_unlock_player_controls()
			if owner == null:
				queue_free()
			else:
				hide()
	get:
		return dialogue_line

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

## The base balloon anchor
@onready var balloon: Control = %Balloon
@onready var margin_container: MarginContainer = $Balloon/MarginContainer
@onready var hbox_container: HBoxContainer = $Balloon/MarginContainer/PanelContainer/HBoxContainer
@onready var vbox_container: VBoxContainer = $Balloon/MarginContainer/PanelContainer/HBoxContainer/VBoxContainer

## The label showing the name of the currently speaking character
@onready var character_label: RichTextLabel = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu

## Indicator to show that player can progress dialogue.
@onready var progress: Polygon2D = %Progress

## The portrait panel and image
@onready var portrait_panel: PanelContainer = %PortraitPanel
@onready var portrait: TextureRect = %Portrait


func _ready() -> void:
	balloon.hide()
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)
	if not get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.connect(_on_viewport_resized)
	call_deferred("_apply_responsive_ui")

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)

	if auto_start:
		if not is_instance_valid(dialogue_resource):
			assert(false, DialogueManagerConstants.get_error_message(DialogueManagerConstants.ERR_MISSING_RESOURCE_FOR_AUTOSTART))
		start()


func _on_viewport_resized() -> void:
	_apply_responsive_ui()


func _get_ui_scale_factor() -> float:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return 1.0
	var width_ratio := viewport_size.x / UI_BASE_RESOLUTION.x
	var height_ratio := viewport_size.y / UI_BASE_RESOLUTION.y
	return clamp(min(width_ratio, height_ratio), UI_MIN_SCALE, UI_MAX_SCALE)


func _apply_responsive_ui() -> void:
	var scale_factor := _get_ui_scale_factor()
	character_label.add_theme_font_size_override("normal_font_size", roundi(CHARACTER_FONT_BASE * scale_factor))
	dialogue_label.add_theme_font_size_override("normal_font_size", roundi(DIALOGUE_FONT_BASE * scale_factor))

	var response_font_size := roundi(RESPONSE_FONT_BASE * scale_factor)
	for child in responses_menu.get_children():
		if child is Button:
			(child as Button).add_theme_font_size_override("font_size", response_font_size)

	margin_container.offset_left = 40.0 * scale_factor
	margin_container.offset_right = -40.0 * scale_factor
	margin_container.offset_top = -180.0 * scale_factor
	margin_container.offset_bottom = -40.0 * scale_factor

	portrait_panel.custom_minimum_size = Vector2(100.0, 100.0) * scale_factor
	hbox_container.add_theme_constant_override("separation", roundi(15.0 * scale_factor))
	vbox_container.add_theme_constant_override("separation", roundi(8.0 * scale_factor))
	progress.scale = Vector2.ONE * max(1.0, scale_factor * 0.9)


func _process(_delta: float) -> void:
	if is_instance_valid(dialogue_line):
		progress.visible = not dialogue_label.is_typing and dialogue_line.responses.size() == 0 and not dialogue_line.has_tag("voice")
		# Position the arrow at the bottom-right of the panel
		if progress.visible:
			var panel = balloon.get_node("MarginContainer/PanelContainer")
			progress.position = Vector2(panel.size.x - 30, panel.size.y - 20)


func _unhandled_input(event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()
	
	# Handle space bar as next action
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		if dialogue_label.is_typing:
			dialogue_label.skip_typing()
		elif is_waiting_for_input and dialogue_line.responses.size() == 0:
			next(dialogue_line.next_id)


func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio = dialogue_label.visible_ratio
		dialogue_line = await dialogue_resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()


## Lock player movement controls
func _lock_player_controls() -> void:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		scene_manager.input_locked = true


## Unlock player movement controls
## ONLY if no other system (like combat UI) has locked input
func _unlock_player_controls() -> void:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		# Check if combat UI is open - don't unlock if it is
		var combat_ui = get_tree().get_root().find_child("CombatTerminalUI", true, false)
		if combat_ui and combat_ui.visible:
			print("[DialogueBalloon] Combat UI is open, NOT unlocking input")
			return
		scene_manager.input_locked = false


## Start some dialogue
func start(with_dialogue_resource: DialogueResource = null, title: String = "", extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	_lock_player_controls()
	if is_instance_valid(with_dialogue_resource):
		dialogue_resource = with_dialogue_resource
	if not title.is_empty():
		start_from_title = title
	dialogue_line = await dialogue_resource.get_next_dialogue_line(start_from_title, temporary_game_states)
	show()


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	progress.hide()
	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()
	character_label.text = tr(dialogue_line.character, "dialogue")
	
	# Update portrait based on character
	_update_portrait(dialogue_line.character)

	dialogue_label.visible_characters = 0
	dialogue_label.dialogue_line = dialogue_line
	dialogue_label.visible_characters = 0
	dialogue_label.modulate = Color(1, 1, 1, 1)

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# Show our balloon
	balloon.show()
	will_hide_balloon = false
	if not dialogue_line.text.is_empty():
		dialogue_label.visible_characters = 0
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	# Wait for next line
	if dialogue_line.has_tag("voice"):
		audio_stream_player.stream = load(dialogue_line.get_tag_value("voice"))
		audio_stream_player.play()
		await audio_stream_player.finished
		next(dialogue_line.next_id)
	elif dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## Update the portrait based on character name
func _update_portrait(character_name: String) -> void:
	var resolved_texture := _resolve_character_portrait(character_name)
	if resolved_texture:
		portrait.texture = resolved_texture
	portrait_panel.show()


func _resolve_character_portrait(character_name: String) -> Texture2D:
	if character_portraits.has(character_name):
		return character_portraits[character_name]

	var variant := _get_character_alignment_variant(character_name)
	if variant != "" and DIALOGUE_PORTRAITS_VARIANTS.has(character_name):
		var variant_path: String = DIALOGUE_PORTRAITS_VARIANTS[character_name].get(variant, "")
		if variant_path != "" and ResourceLoader.exists(variant_path):
			return load(variant_path) as Texture2D

	if DIALOGUE_PORTRAITS_BASE.has(character_name):
		var base_path: String = DIALOGUE_PORTRAITS_BASE[character_name]
		if ResourceLoader.exists(base_path):
			return load(base_path) as Texture2D

	return null


func _get_character_alignment_variant(character_name: String) -> String:
	var scene_manager = get_node_or_null("/root/SceneManager")
	if scene_manager:
		if scene_manager.npc_states.has(character_name):
			var npc_state: String = str(scene_manager.npc_states[character_name])
			if npc_state in ["helped", "solved", "good", "peaceful"]:
				return "good"
			if npc_state in ["hostile", "bad", "fled_combat", "defeated"]:
				return "bad"

		var player_karma: String = str(scene_manager.player_karma)
		if player_karma in ["good", "bad"]:
			return player_karma

	return ""


## Set a portrait for a character (can be called from dialogue or externally)
func set_character_portrait(character_name: String, texture: Texture2D) -> void:
	character_portraits[character_name] = texture


## Go to the next line
func next(next_id: String) -> void:
	dialogue_line = await dialogue_resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()


func _on_mutated(_mutation: Dictionary) -> void:
	if not _mutation.is_inline:
		is_waiting_for_input = false
		will_hide_balloon = true
		mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
