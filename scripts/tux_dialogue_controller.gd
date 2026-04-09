extends Node

const DialogueResourceRes = preload("res://addons/dialogue_manager/dialogue_resource.gd")
const DMConstantsRes = preload("res://addons/dialogue_manager/constants.gd")
const HUD_DIALOGUE_PATH := "res://dialogues/TuxHUD.dialogue"
const FALLBACK_HAMLET_SCENE_PATH := "res://Scenes/Levels/fallback_hamlet.tscn"
const POST_ENDING_HAMLET_GREETING_META_KEY := "post_ending_hamlet_greeting_shown"

var dm: Node = null
var sm: Node = null

var _prev_npc_states: Dictionary = {}
var _prev_player_karma: String = ""
var _prev_defeated_flags: Dictionary = {}
var _prev_item_flags: Dictionary = {}
var _sage_quiz_announced: bool = false
var _ready_check_prompted: Dictionary = {}
var _tux_line_queue: Array[String] = []
var _draining_tux_lines: bool = false
var _hud_dialogue_resource: Resource = null
var _hud_dialogue_busy: bool = false
var _hud_selected_topic: String = ""
var _last_scene_path_seen: String = ""
var _post_ending_greeting_shown_for_scene: bool = false
var _recent_tux_lines: Dictionary = {}

const TUX_LINE_GAP_SECONDS := 1.25
const TUX_LINE_DEDUP_WINDOW_SECONDS := 6.0

const ITEM_FLAGS: Array[String] = [
	"gatekeeper_pass_granted",
	"sudo_token_driver_remnant",
	"proficiency_key_forest",
	"proficiency_key_printer",
	"broken_link_fragmented_key",
]

const DEFEAT_FLAGS: Array[String] = [
	"broken_link_defeated",
	"driver_remnant_defeated",
	"printer_beast_defeated",
	"deleted_lost_file",
	"hardware_ghost_defeated",
]

const NPC_TEMPLATES: Dictionary = {
	"default": {
		"first_meet": "You met %s. Pay attention — they might teach you something.",
		"helped": "Nice work helping %s! That should make things easier.",
		"killed_good": "You killed %s? Are you sure that was necessary?",
		"killed_neutral": "What happened to %s? Why?",
		"killed_evil": "You killed %s. That... feels wrong. Why did you do it?",
	},
	"Lost File": {
		"first_meet": "Lost File... they told me about fragments. Scattered, broken, searching for home. Listen with empathy.",
		"helped": "You restored %s. Their fragments are whole now. That took real compassion.",
		"killed_good": "You destroyed %s? Even after they reached out? I... didn't expect that.",
		"killed_neutral": "What happened to %s? I thought you understood their pain.",
		"killed_evil": "You erased %s. Just like the script that broke them in the first place. Why?",
	},
	"Messy Directory": {
		"first_meet": "Messy Directory... protective, searching for her child. She carries a mother's worry. Hear her out.",
		"helped": "You helped %s care for her lost one. That's what compassion looks like.",
	},
	"Broken Installer": {
		"first_meet": "Broken Installer... corrupted systems, incomplete installations. Remember, even broken things have stories.",
	},
	"Hardware Ghost": {
		"first_meet": "Hardware Ghost... old technology given life. Ancient hardware holds ancient secrets. Be respectful.",
		"helped": "You freed %s from their digital prison. That's honorable.",
		"killed_good": "You destroyed %s? Even after they showed you their memories?",
		"killed_neutral": "What happened to %s? Why end such an ancient being?",
		"killed_evil": "You erased %s. Thousands of years of existence, gone. Just like that.",
	},
	"Driver Remnant": {
		"first_meet": "Driver Remnant... a fragment of system power. They're dangerous, but they have a choice. So do you.",
		"helped": "You convinced %s to help. Power channeled for good. That matters.",
		"killed_good": "You stopped %s. Necessary, but not without cost.",
		"killed_neutral": "What happened to %s? Did they push too hard?",
		"killed_evil": "You hunted down %s for their power. Now look what you've become.",
	},
	"Printer Boss": {
		"first_meet": "Printer Boss... madness given form. They're dangerous and unpredictable. Stay sharp.",
		"helped": "You calmed the chaos of %s. That took serious skill.",
		"killed_good": "You stopped %s. They were beyond saving anyway.",
		"killed_neutral": "What happened to %s? Did their chaos consume them?",
		"killed_evil": "You destroyed %s. One less threat, one more sin.",
	},
	"Gatekeeper": {
		"first_meet": "Gatekeeper... guardian of passage. They decide who goes forward. Earn their respect.",
		"helped": "You earned %s's pass. You did it the right way.",
		"killed_good": "You killed %s? Even after they offered you a path?",
		"killed_neutral": "What happened to %s? You sealed your own fate.",
		"killed_evil": "You murdered %s for passage. Now everyone will remember that.",
	},
	"Elder Shell": {
		"first_meet": "Elder Shell... ancient wisdom in digital form. They've seen systems rise and fall. Listen.",
		"helped": "You helped %s share their knowledge. Wisdom matters.",
	},
	"Broken Link": {
		"first_meet": "Broken Link... fragmented, jittering connections. They might be salvageable if you approach carefully.",
		"helped": "You patched %s's link. That should restore some connectivity.",
		"killed_good": "You destroyed %s to stop the corruption. Hard choices.",
		"killed_neutral": "What happened to %s? Was there no other way?",
		"killed_evil": "You crushed %s. Connections aren't easily mended after that.",
	},
}

func _ready() -> void:
	dm = get_node_or_null("/root/DialogueManager")
	sm = get_node_or_null("/root/SceneManager")

	if sm:
		refresh_state_snapshot()
			
		if sm.has_signal("npc_first_interacted"):
			sm.npc_first_interacted.connect(_on_npc_first_interacted)

	if dm:
		# FIXED: Godot 4 syntax for signal checking
		var dialogue_ended_callable := Callable(self, "_on_dialogue_ended")
		if not dm.dialogue_ended.is_connected(dialogue_ended_callable):
			dm.dialogue_ended.connect(dialogue_ended_callable)
	
	# Check NPC states periodically to catch state changes from puzzle solving
	var check_timer = Timer.new()
	check_timer.wait_time = 0.5
	check_timer.timeout.connect(_check_state_changes_periodic)
	add_child(check_timer)
	check_timer.start()

func refresh_state_snapshot(clear_pending_lines: bool = false) -> void:
	if sm == null:
		sm = get_node_or_null("/root/SceneManager")
	if sm == null:
		return

	_prev_npc_states = sm.npc_states.duplicate(true) if sm.npc_states != null else {}
	_prev_player_karma = str(sm.player_karma)

	_prev_item_flags.clear()
	for flag in ITEM_FLAGS:
		_prev_item_flags[flag] = sm.get(flag) if sm.get(flag) != null else false

	_prev_defeated_flags.clear()
	for flag in DEFEAT_FLAGS:
		_prev_defeated_flags[flag] = sm.get(flag) if sm.get(flag) != null else false

	_ready_check_prompted.clear()
	for quest_id in sm.quest_manager.quests.keys() if sm.quest_manager else []:
		var qid := String(quest_id)
		_ready_check_prompted[qid] = _is_quest_ready_to_check(qid)

	if clear_pending_lines:
		_tux_line_queue.clear()

func _on_npc_first_interacted(npc_name: String) -> void:
	# Just show status in inventory UI when met; don't open file explorer
	var tpl: Dictionary = NPC_TEMPLATES.get(npc_name, NPC_TEMPLATES["default"])
	var template: String = tpl.get("first_meet", NPC_TEMPLATES["default"]["first_meet"])
	var text: String = template
	if "%" in template:
		text = template % npc_name

	var pause_menu = get_node_or_null("/root/PauseMenu")
	if pause_menu:
		if pause_menu.has_method("_show_status"):
			pause_menu.call("_show_status", text)

# Called by pause_menu when an NPC file is double-clicked (activated)
func show_npc_file_dialogue(npc_name: String) -> void:
	var tpl: Dictionary = NPC_TEMPLATES.get(npc_name, NPC_TEMPLATES["default"])
	var template: String = tpl.get("first_meet", NPC_TEMPLATES["default"]["first_meet"])
	var text: String = template
	if "%" in template:
		text = template % npc_name
	_show_tux_line(text)

func _on_dialogue_ended(_resource: Resource) -> void:
	if sm == null: return

	# 1. Check NPC State Changes
	var curr_states: Dictionary = sm.npc_states.duplicate(true) if sm.npc_states else {}
	for npc_key in curr_states.keys():
		var old_val = _prev_npc_states.get(npc_key)
		var new_val = curr_states[npc_key]
		if old_val != new_val:
			_handle_npc_state_change(npc_key, old_val, new_val)
	_prev_npc_states = curr_states

	# 2. Check Karma
	_prev_player_karma = str(sm.player_karma)

	# 3. Check Flags (Items & Defeats)
	_check_boolean_flags(ITEM_FLAGS, _prev_item_flags, _handle_item_granted)
	_check_boolean_flags(DEFEAT_FLAGS, _prev_defeated_flags, _handle_npc_defeated)
	_maybe_prompt_ready_quest_check()

# Periodically check NPC states to catch state changes from puzzle solving
func _check_state_changes_periodic() -> void:
	if sm == null: return

	var current_scene := get_tree().current_scene
	var current_scene_path := String(current_scene.scene_file_path) if current_scene else ""
	if current_scene_path != _last_scene_path_seen:
		_last_scene_path_seen = current_scene_path
		_post_ending_greeting_shown_for_scene = false
	_maybe_show_post_ending_greeting(current_scene_path)
	
	var curr_states: Dictionary = sm.npc_states.duplicate(true) if sm.npc_states else {}
	for npc_key in curr_states.keys():
		var old_val = _prev_npc_states.get(npc_key)
		var new_val = curr_states[npc_key]
		if old_val != new_val:
			print("[TuxDialogueController] NPC state changed: %s from %s to %s" % [npc_key, old_val, new_val])
			_handle_npc_state_change(npc_key, old_val, new_val)
	_prev_npc_states = curr_states
	_maybe_prompt_ready_quest_check()

func _maybe_show_post_ending_greeting(scene_path: String) -> void:
	if _post_ending_greeting_shown_for_scene:
		return
	if scene_path != FALLBACK_HAMLET_SCENE_PATH:
		return
	if sm == null:
		return
	if bool(sm.get_meta(POST_ENDING_HAMLET_GREETING_META_KEY, false)):
		_post_ending_greeting_shown_for_scene = true
		return
	if not bool(sm.get_meta("evil_tux_boss_cleared", false)):
		return
	if bool(sm.get_meta("hide_all_npcs_post_evil_tux", false)):
		return
	if str(sm.player_karma) != "good":
		return
	if not bool(sm.bios_vault_sage_quiz_passed) and not bool(sm.bios_vault_sage_defeated):
		return

	_post_ending_greeting_shown_for_scene = true
	sm.set_meta(POST_ENDING_HAMLET_GREETING_META_KEY, true)
	_show_tux_line("Hey there, savior. Good to see you back in Fallback Hamlet.")

# Helper to reduce code duplication for flag checking
func _check_boolean_flags(flag_list: Array[String], storage: Dictionary, callback: Callable) -> void:
	for flag in flag_list:
		var flag_result = sm.get(flag)
		var current_val: bool = flag_result if flag_result != null else false
		var prev_val: bool = storage.get(flag, false)
		
		if current_val and not prev_val:
			print("[TuxDialogueController] Flag changed from false to true: %s" % flag)
			callback.call(flag)
		storage[flag] = current_val

func _handle_npc_state_change(npc_name: String, old_state: Variant, new_state: Variant) -> void:
	if str(new_state) == "helped" and str(old_state) != "helped":
		var tpl: Dictionary = NPC_TEMPLATES.get(npc_name, NPC_TEMPLATES["default"])
		var template: String = tpl.get("helped", NPC_TEMPLATES["default"]["helped"])
		var text: String = template
		if "%" in template:
			text = template % npc_name
		
		# Add delay before showing Tux dialogue
		await get_tree().create_timer(2.0).timeout
		_show_tux_line(text)

func _handle_npc_defeated(defeat_flag: String) -> void:
	var name_map := {
		"deleted_lost_file": "Lost File",
		"driver_remnant_defeated": "Driver Remnant",
		"printer_beast_defeated": "Printer Boss",
		"broken_link_defeated": "Broken Link",
		"hardware_ghost_defeated": "Hardware Ghost",
	}
	
	var npc_name: String = name_map.get(defeat_flag, "Unknown")
	var current_state: String = ""
	if sm and sm.npc_states != null:
		current_state = str(sm.npc_states.get(npc_name, ""))

	if current_state == "helped":
		# Helped state text is handled by _handle_npc_state_change().
		# Do not enqueue a second line from defeat flag transitions.
		print("[TuxDialogueController] Defeat flag %s ignored because %s is helped" % [defeat_flag, npc_name])
		return

	var karma: String = str(sm.player_karma) if sm else "neutral"
	var tpl: Dictionary = NPC_TEMPLATES.get(npc_name, NPC_TEMPLATES["default"])

	var msg_key := "killed_neutral"
	match karma:
		"evil": msg_key = "killed_evil"
		"good": msg_key = "killed_good"

	# Use default template if NPC template doesn't have this key
	if not tpl.has(msg_key):
		tpl = NPC_TEMPLATES["default"]

	var template: String = tpl.get(msg_key, "You defeated %s.")
	print("[TuxDialogueController] Defeated flag: %s -> NPC: %s, Karma: %s, Template key: %s" % [defeat_flag, npc_name, karma, msg_key])
	var text: String = template
	if "%" in template:
		text = template % npc_name

	# Add delay before showing Tux dialogue
	await get_tree().create_timer(2.0).timeout
	_show_tux_line(text)

func _handle_item_granted(flag: String) -> void:
	var item_messages := {
		"gatekeeper_pass_granted": "You received the Gatekeeper Pass. Use it at the Gate to proceed.",
		"sudo_token_driver_remnant": "You were given a Sudo Token. Try it on special doors or consoles.",
		"proficiency_key_forest": "Forest Proficiency Key acquired — this unlocks forest systems.",
		"proficiency_key_printer": "Printer Proficiency Key acquired — useful in printer zones.",
		"broken_link_fragmented_key": "You found a fragmented link piece. It might restore access somewhere."
	}
	_show_tux_line(item_messages.get(flag, "You received something new. Check your inventory."))
	_maybe_prompt_ready_quest_check()

func _get_quest_manager() -> QuestManager:
	if sm == null:
		return null
	return sm.quest_manager if sm.quest_manager else null

func _is_quest_ready_to_check(quest_id: String) -> bool:
	var qm := _get_quest_manager()
	if qm == null:
		return false
	if not qm.has_method("is_quest_ready_to_check"):
		return false
	return bool(qm.call("is_quest_ready_to_check", quest_id))

func _quest_display_name(quest_id: String) -> String:
	var qm := _get_quest_manager()
	if qm == null:
		return quest_id
	var quest := qm.get_quest(quest_id)
	return quest.quest_name if quest else quest_id

func _maybe_prompt_ready_quest_check() -> void:
	var qm := _get_quest_manager()
	if qm == null:
		return

	for quest_id in qm.get_active_quests():
		var qid := String(quest_id)
		if bool(_ready_check_prompted.get(qid, false)):
			continue
		if not _is_quest_ready_to_check(qid):
			continue
		_ready_check_prompted[qid] = true
		var quest_name := _quest_display_name(qid)
		await get_tree().create_timer(1.0).timeout
		_show_tux_line("Quest ready: %s. Open your Quest tab and press CHECK COMPLETE." % quest_name)
		return

func on_quest_checked_complete(quest_id: String) -> void:
	_ready_check_prompted[String(quest_id)] = true
	match quest_id:
		"find_lost_file":
			_show_tux_line("Quest confirmed. Return to Messy Directory in Fallback Hamlet for your next lead.")
		"broken_link_puzzle":
			_show_tux_line("Quest confirmed. Report to the Gate Keeper and keep building your proficiency path.")
		"drivers_den_cleanup":
			_show_tux_line("Quest confirmed. Talk to Hardware Ghost, then prepare for the next zone unlock.")
		"gatekeeper_proficiency":
			_show_tux_line("Great work. You proved your proficiency. Head back to the Gate Keeper in Fallback Hamlet to unlock the BIOS Vault.")
		_:
			_show_tux_line("Quest confirmed. Nice work. Check your map and continue to the next objective.")

func show_world_hint_from_hud() -> void:
	if _hud_dialogue_busy:
		return

	if sm == null:
		sm = get_node_or_null("/root/SceneManager")
	if dm == null:
		dm = get_node_or_null("/root/DialogueManager")

	var dialogue := _get_hud_dialogue_resource()
	if dm == null or dialogue == null:
		_show_tux_line("I am online. Explore Linuxia and check your active quests for your next move.")
		return

	if _is_bios_vault_scene_active():
		_hud_dialogue_busy = true
		call_deferred("_run_bios_vault_missing_tux_dialogue")
		return

	if _is_post_evil_tux_bad_route_state():
		_hud_dialogue_busy = true
		call_deferred("_run_post_evil_tux_tux_icon_offline_dialogue")
		return

	if _is_proprietary_citadel_scene_active():
		_hud_dialogue_busy = true
		call_deferred("_run_proprietary_tux_ahead_dialogue")
		return

	_hud_dialogue_busy = true
	call_deferred("_run_hud_dialogue_session")

func _run_bios_vault_missing_tux_dialogue() -> void:
	var dialogue := _get_hud_dialogue_resource()
	if dm == null or dialogue == null:
		_hud_dialogue_busy = false
		return

	dm.show_dialogue_balloon(dialogue, "hud_bios_tux_missing", [self])
	if dm.has_signal("dialogue_ended"):
		await dm.dialogue_ended

	_hud_dialogue_busy = false

func _run_proprietary_tux_ahead_dialogue() -> void:
	var dialogue := _get_hud_dialogue_resource()
	if dm == null or dialogue == null:
		_hud_dialogue_busy = false
		return

	dm.show_dialogue_balloon(dialogue, "hud_proprietary_tux_ahead", [self])
	if dm.has_signal("dialogue_ended"):
		await dm.dialogue_ended

	_hud_dialogue_busy = false

func _run_post_evil_tux_tux_icon_offline_dialogue() -> void:
	var dialogue := _get_hud_dialogue_resource()
	if dm == null or dialogue == null:
		_hud_dialogue_busy = false
		return

	dm.show_dialogue_balloon(dialogue, "hud_post_evil_tux_icon_offline", [self])
	if dm.has_signal("dialogue_ended"):
		await dm.dialogue_ended

	_hud_dialogue_busy = false

func _is_post_evil_tux_bad_route_state() -> bool:
	if sm == null:
		return false

	return bool(sm.get_meta("evil_tux_boss_cleared", false)) and bool(sm.get_meta("hide_all_npcs_post_evil_tux", false))

func _is_bios_vault_scene_active() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var scene_path := String(current_scene.scene_file_path)
	return scene_path == "res://Scenes/Levels/bios_vault.tscn" or scene_path == "res://Scenes/Levels/bios_vault_.tscn"

func _is_proprietary_citadel_scene_active() -> bool:
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return false

	var scene_path := String(current_scene.scene_file_path)
	return scene_path == "res://Scenes/Levels/proprietary_citadel.tscn"

func _get_hud_dialogue_resource() -> Resource:
	if _hud_dialogue_resource != null:
		return _hud_dialogue_resource
	_hud_dialogue_resource = load(HUD_DIALOGUE_PATH)
	if _hud_dialogue_resource == null:
		push_warning("HUD Tux dialogue not found: " + HUD_DIALOGUE_PATH)
	return _hud_dialogue_resource

func _run_hud_dialogue_session() -> void:
	var dialogue := _get_hud_dialogue_resource()
	if dm == null or dialogue == null:
		_hud_dialogue_busy = false
		return

	_hud_selected_topic = ""
	dm.show_dialogue_balloon(dialogue, "hud_menu", [self])
	if dm.has_signal("dialogue_ended"):
		await dm.dialogue_ended

	var topic := _hud_selected_topic.strip_edges().to_lower()
	var titles: Array[String] = []

	if topic == "location":
		titles.append(_pick_label(_location_dialogue_titles(), "hud_location_unknown_a"))
	elif topic == "objective":
		titles.append(_pick_label(_objective_dialogue_titles(), "hud_objective_no_tracker_a"))
	elif topic == "world":
		titles.append(_pick_label(_world_state_dialogue_titles(), "hud_world_default_a"))
	elif topic == "tone":
		titles.append(_pick_label(_tone_dialogue_titles(), "hud_tone_neutral_a"))
	elif topic == "shop":
		titles.append(_pick_label(_shop_dialogue_titles(), "hud_shop_hint_a"))
	elif topic == "full":
		titles = [
			_pick_label(_location_dialogue_titles(), "hud_location_unknown_a"),
			_pick_label(_objective_dialogue_titles(), "hud_objective_no_tracker_a"),
			_pick_label(_world_state_dialogue_titles(), "hud_world_default_a"),
			_pick_label(_tone_dialogue_titles(), "hud_tone_neutral_a"),
			_pick_label(_shop_dialogue_titles(), "hud_shop_hint_a"),
		]
	else:
		titles.append("hud_exit")

	for title in titles:
		dm.show_dialogue_balloon(dialogue, title, [self])
		if dm.has_signal("dialogue_ended"):
			await dm.dialogue_ended

	_hud_dialogue_busy = false

func choose_hud_topic_location() -> void:
	_hud_selected_topic = "location"

func choose_hud_topic_objective() -> void:
	_hud_selected_topic = "objective"

func choose_hud_topic_world() -> void:
	_hud_selected_topic = "world"

func choose_hud_topic_tone() -> void:
	_hud_selected_topic = "tone"

func choose_hud_topic_shop() -> void:
	_hud_selected_topic = "shop"

func choose_hud_topic_full() -> void:
	_hud_selected_topic = "full"

func choose_hud_topic_exit() -> void:
	_hud_selected_topic = "exit"

func _location_dialogue_titles() -> Array[String]:
	var current_scene := get_tree().current_scene
	var scene_path := ""
	if current_scene != null:
		scene_path = String(current_scene.scene_file_path)

	match scene_path:
		"res://Scenes/Levels/tutorial - Copy.tscn":
			return ["hud_location_tutorial_a", "hud_location_tutorial_b"]
		"res://Scenes/Levels/fallback_hamlet.tscn":
			return ["hud_location_hamlet_a", "hud_location_hamlet_b"]
		"res://Scenes/Levels/file_system_forest.tscn":
			return ["hud_location_forest_a", "hud_location_forest_b"]
		"res://Scenes/Levels/deamon_depths.tscn":
			return ["hud_location_depths_a", "hud_location_depths_b"]
		"res://Scenes/Levels/bios_vault.tscn", "res://Scenes/Levels/bios_vault_.tscn":
			return ["hud_location_vault_a", "hud_location_vault_b"]
		_:
			return ["hud_location_unknown_a", "hud_location_unknown_b"]

func _objective_dialogue_titles() -> Array[String]:
	var qm := _get_quest_manager()
	if qm == null:
		return ["hud_objective_no_tracker_a", "hud_objective_no_tracker_b"]

	var active := qm.get_active_quests()
	if active.is_empty():
		return ["hud_objective_no_active_a", "hud_objective_no_active_b"]

	var quest_id := String(active[0])
	if _is_quest_ready_to_check(quest_id):
		return ["hud_objective_ready_a", "hud_objective_ready_b"]

	return ["hud_objective_active_a", "hud_objective_active_b"]

func _world_state_dialogue_titles() -> Array[String]:
	if sm == null:
		return ["hud_world_default_a", "hud_world_default_b"]

	if bool(sm.get("printer_beast_defeated")) and bool(sm.get("gatekeeper_pass_granted")):
		return ["hud_world_momentum_a", "hud_world_momentum_b"]

	if bool(sm.get("proficiency_key_forest")) and not bool(sm.get("broken_link_fragmented_key")):
		return ["hud_world_forest_key_a", "hud_world_forest_key_b"]

	if bool(sm.get("gatekeeper_pass_granted")) and not bool(sm.get("deamon_depths_boss_door_unlocked")):
		return ["hud_world_gatepass_a", "hud_world_gatepass_b"]

	return ["hud_world_default_a", "hud_world_default_b"]

func _tone_dialogue_titles() -> Array[String]:
	if sm == null:
		return ["hud_tone_neutral_a", "hud_tone_neutral_b"]

	var karma := str(sm.player_karma)
	match karma:
		"good":
			return ["hud_tone_good_a", "hud_tone_good_b"]
		"evil":
			return ["hud_tone_evil_a", "hud_tone_evil_b"]
		_:
			return ["hud_tone_neutral_a", "hud_tone_neutral_b"]

func _shop_dialogue_titles() -> Array[String]:
	if sm == null:
		return ["hud_shop_hint_a", "hud_shop_hint_b"]

	if bool(sm.get("file_explorer_unlocked")) and bool(sm.get("cli_history_unlocked")):
		return ["hud_shop_ready_a", "hud_shop_ready_b"]

	return ["hud_shop_hint_a", "hud_shop_hint_b"]

func _pick_label(options: Array[String], fallback: String) -> String:
	if options.is_empty():
		return fallback
	return options[randi() % options.size()]

func _show_tux_line(text: String) -> void:
	if dm == null:
		dm = get_node_or_null("/root/DialogueManager")
	if dm == null:
		push_warning("Tux: DialogueManager not found. Text: %s" % text)
		return
	if text.strip_edges().is_empty():
		return
	if _is_recent_duplicate_tux_line(text):
		return

	_tux_line_queue.append(text)
	if _draining_tux_lines:
		return
	_draining_tux_lines = true
	call_deferred("_drain_tux_line_queue")

func _is_recent_duplicate_tux_line(text: String) -> bool:
	var normalized := text.strip_edges().to_lower()
	if normalized.is_empty():
		return true

	var now_seconds := Time.get_ticks_msec() / 1000.0
	var last_seen := float(_recent_tux_lines.get(normalized, -1000.0))
	_recent_tux_lines[normalized] = now_seconds

	# Clean stale entries so dictionary doesn't grow forever.
	var stale_keys: Array[String] = []
	for key in _recent_tux_lines.keys():
		if now_seconds - float(_recent_tux_lines[key]) > (TUX_LINE_DEDUP_WINDOW_SECONDS * 4.0):
			stale_keys.append(String(key))
	for key in stale_keys:
		_recent_tux_lines.erase(key)

	return (now_seconds - last_seen) < TUX_LINE_DEDUP_WINDOW_SECONDS

func _drain_tux_line_queue() -> void:
	while not _tux_line_queue.is_empty():
		var text := String(_tux_line_queue.pop_front())
		print("[TuxDialogueController] Showing Tux line: %s" % text)

		var resource := DialogueResourceRes.new()
		resource.lines = {
			"start": {
				"id": "start",
				"type": DMConstantsRes.TYPE_DIALOGUE,
				"character": "Tux",
				"text": text,
				"next_id": DMConstantsRes.ID_END
			}
		}
		dm.show_dialogue_balloon(resource, "start")

		if dm.has_signal("dialogue_ended"):
			await dm.dialogue_ended
		await get_tree().create_timer(TUX_LINE_GAP_SECONDS).timeout

	_draining_tux_lines = false

func on_sage_quiz_passed() -> void:
	if _sage_quiz_announced:
		return
	_sage_quiz_announced = true
	await get_tree().create_timer(1.0).timeout
	_show_tux_line("You passed Sage's assessment. Clean commands, clear thinking. Keep that discipline.")
