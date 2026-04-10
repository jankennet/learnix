extends RefCounted
class_name PuzzleIntelLibrary

static func get_objective_lines(enemy_id: String, puzzle_data, dependency_objective_active: bool) -> Array[String]:
	if dependency_objective_active:
		return [
			"STATUS: PUZZLE_MODE",
			"TRACE INFO: dependency graph has unresolved conflicts",
			"ACTIVE GOAL: REPAIR_PATH_INTEGRITY",
			"INVESTIGATION LOOP: SCAN -> ANALYZE -> EXECUTE",
			"TUX COMM:",
		]

	if puzzle_data == null or not ("custom_data" in puzzle_data):
		return [
			"STATUS: PUZZLE_MODE",
			"TRACE INFO: awaiting puzzle telemetry",
			"ACTIVE GOAL: INVESTIGATE_SYSTEM_ANOMALY",
			"INVESTIGATION LOOP: SCAN -> ANALYZE -> EXECUTE",
			"TUX COMM:",
		]

	var custom: Dictionary = puzzle_data.custom_data
	if custom.has("required_fragments"):
		return _lost_file_objective_lines(custom)

	if custom.has("expected_sequence"):
		var expected: Array = custom.get("expected_sequence", [])
		var total := expected.size()
		var index := clampi(int(custom.get("current_index", 0)), 0, maxi(0, total - 1))
		return [
			"STATUS: PUZZLE_MODE | PROGRESS %d/%d" % [index + 1, maxi(1, total)],
			"TRACE INFO: %s" % _sequence_trace_info(enemy_id, index),
			"ACTIVE GOAL: %s" % _active_goal(enemy_id),
			"INVESTIGATION LOOP: SCAN -> ANALYZE -> EXECUTE",
			"TUX COMM:",
		]

	return [
		"STATUS: PUZZLE_MODE",
		"TRACE INFO: puzzle state loaded",
		"ACTIVE GOAL: INVESTIGATE_SYSTEM_ANOMALY",
		"INVESTIGATION LOOP: SCAN -> ANALYZE -> EXECUTE",
		"TUX COMM:",
	]

static func get_status_snapshot(enemy_id: String, puzzle_data) -> String:
	if puzzle_data == null or not ("custom_data" in puzzle_data):
		return "TUX // STATUS: puzzle telemetry not loaded. Start with SCAN phase."

	var custom: Dictionary = puzzle_data.custom_data
	if custom.has("required_fragments"):
		var required: Array = custom.get("required_fragments", [])
		var found: Array = custom.get("fragments_found", [])
		var restored: Array = custom.get("fragments_restored", [])
		var decrypted: Array = custom.get("fragments_decrypted", [])
		return "TUX // STATUS: ORPHAN_BLOCKS %d | FOUND %d/%d | RESTORED %d/%d | DECRYPTED %d" % [required.size(), found.size(), required.size(), restored.size(), required.size(), decrypted.size()]

	if custom.has("expected_sequence"):
		var expected: Array = custom.get("expected_sequence", [])
		var total := expected.size()
		var index := clampi(int(custom.get("current_index", 0)), 0, maxi(0, total - 1))
		return "TUX // STATUS: STEP %d/%d | TRACE: %s" % [index + 1, maxi(1, total), _sequence_trace_info(enemy_id, index)]

	return "TUX // STATUS: run SCAN, then ANALYZE, then EXECUTE."

static func get_tux_doc_summary(enemy_id: String, puzzle_data) -> String:
	if puzzle_data == null:
		return "TUX DOCS // No puzzle data yet. Use LS, then SCAN, then act on the clue noun."
	return "TUX DOCS // %s\nUse LS for nouns. Use SCAN for verb family. Then execute one step." % _active_goal(enemy_id)

static func get_tux_doc_suggestions(enemy_id: String, puzzle_data) -> Array[Dictionary]:
	var phase := _current_phase(enemy_id, puzzle_data)
	var noun_hint := _noun_hint(enemy_id, puzzle_data)
	var suggestions: Array[Dictionary] = []
	suggestions.append({
		"label": "Start here",
		"detail": "Quick beginner path.",
		"message": _beginner_quickstart(enemy_id, puzzle_data),
	})
	suggestions.append({
		"label": "How do I scan?",
		"detail": "Get current phase and valid verb family.",
		"message": _scan_doc(enemy_id, phase, noun_hint),
	})
	suggestions.append({
		"label": "How do I analyze?",
		"detail": "Interpret clue noun and symptom.",
		"message": _analyze_doc(enemy_id, phase, noun_hint),
	})
	suggestions.append({
		"label": "How do I execute?",
		"detail": "Apply one safe action.",
		"message": _execute_doc(enemy_id, phase, noun_hint),
	})
	suggestions.append({
		"label": "Show clue notes",
		"detail": "Intercepted logs with environmental hints and file nouns.",
		"message": get_terminal_history(enemy_id, puzzle_data),
	})
	return suggestions

static func get_terminal_history(enemy_id: String, puzzle_data) -> String:
	var lines := _history_lines(enemy_id)
	if puzzle_data != null and "custom_data" in puzzle_data:
		var custom: Dictionary = puzzle_data.custom_data
		if custom.has("expected_sequence"):
			var total := (custom.get("expected_sequence", []) as Array).size()
			var index := int(custom.get("current_index", 0))
			lines.append("LOG_ENTRY 99: Sequence checkpoint %d/%d. Toolchain state persisted." % [index + 1, maxi(1, total)])
		elif custom.has("required_fragments"):
			var restored := (custom.get("fragments_restored", []) as Array).size()
			lines.append("LOG_ENTRY 99: Recovery daemon reports %d fragments restored." % restored)

	return "INTERCEPTED LOGS:\n- %s" % "\n- ".join(lines)

static func get_context_help_lines(enemy_id: String, puzzle_data) -> Array[String]:
	var noun_hint := _noun_hint(enemy_id, puzzle_data)
	return [
		"start      - ls -> scan -> act",
		"loop       - scan -> analyze -> execute",
		"symptom    - %s" % _short_symptom(enemy_id, puzzle_data),
		"noun       - %s" % noun_hint,
		"scan       - returns valid verb family now",
		"fight      - return to combat",
	]

static func _lost_file_objective_lines(custom: Dictionary) -> Array[String]:
	var required: Array = custom.get("required_fragments", [])
	var found: Array = custom.get("fragments_found", [])
	var restored: Array = custom.get("fragments_restored", [])
	var decrypted: Array = custom.get("fragments_decrypted", [])
	return [
		"STATUS: PUZZLE_MODE | RECOVERY_PIPELINE",
		"TRACE INFO: SYSTEM_REPORT: %d orphaned blocks detected. Sector flags: '.fragment'" % required.size(),
		"TRACE INFO: RECOVERY_STATE: FOUND %d/%d | RESTORED %d/%d | DECRYPTED %d" % [found.size(), required.size(), restored.size(), required.size(), decrypted.size()],
		"ACTIVE GOAL: RECOVER_FRAGMENT_DATA",
		"TUX COMM:",
	]

static func _sequence_trace_info(enemy_id: String, step_index: int) -> String:
	var traces := {
		"broken_link": [
			"SYMLINK_STATUS: BROKEN_POINTER | CLUE_NOUN: stub",
			"PATH_AUDIT: POINTER_DESTINATION_UNRESOLVED | CLUE_NOUN: target_note",
			"LINK_BINDING: STALE_REFERENCE_ATTACHED",
			"LINK_BINDING: NEW_POINTER_REQUIRED",
			"ACL_STATE: LINK_TABLE_WRITE_LOCKED | CLUE_NOUN: link_table",
			"MAPPING_STATE: LINK_TABLE_OUT_OF_SYNC | CLUE_NOUN: link_table",
			"TRACE_PATH: stub -> [MISSING]",
			"BUILD_STATE: LINK_MAP_REINDEX_REQUIRED",
		],
		"hardware_ghost": [
			"BUS_LOG: LEGACY_INTERRUPT_STORM | CLUE_NOUN: legacy_bus.log",
			"DRIVER_INDEX: LEGACY_PATH_UNRESOLVED | CLUE_NOUN: driver_table",
			"ECHO_LOG: RECURSIVE_SIGNAL_LOOP | CLUE_NOUN: ghost_echo.log",
			"ACL_STATE: DRIVER_TABLE_WRITE_LOCKED | CLUE_NOUN: driver_table",
			"BUILD_STATE: DRIVER_MAP_RECONCILE_PENDING",
		],
		"driver_remnant": [
			"PROC_STATE: ROGUE_DRIVER_SIGNATURE_ACTIVE | CLUE_NOUN: remnant.sig",
			"IRQ_TRACE: INTERRUPT_LINE_NOT_MAPPED | CLUE_NOUN: irq_line",
			"THREAD_STATE: REMNANT_PROCESS_NOT_TERMINATED",
			"IRQ_LINK: STALE_INTERRUPT_REFERENCE_PRESENT",
			"ACL_STATE: INTERRUPT_TABLE_WRITE_LOCKED | CLUE_NOUN: interrupt_table",
			"BUILD_STATE: STABILITY_MAP_REGEN_PENDING",
		],
		"printer_beast": [
			"QUEUE_STATUS: SPOOL_ENTRIES_BACKLOGGED | CLUE_NOUN: spool",
			"PATH_AUDIT: JAM_LOCATION_UNVERIFIED | CLUE_NOUN: jam_page",
			"SPOOL_STATE: CORRUPTED_PAGE_MARKED_ACTIVE",
			"ACL_STATE: SPOOL_WRITE_LOCKED | CLUE_NOUN: spool",
			"INDEX_STATE: SPOOL_INDEX_DESYNC | CLUE_NOUN: spool_index",
			"BUILD_STATE: PRINT_QUEUE_REBUILD_PENDING",
		],
		"evil_tux": [
			"KERNEL_ALERT: CORE_ROUTE_TAINTED",
			"PATH_CHECK: APP_ROUTE_FRAGMENTED",
			"SECURITY_STATE: ELEVATED_RULES_CONFLICT",
			"BUILD_STATE: CORE_RECOMPILE_REQUIRED",
		],
	}

	var enemy_traces: Array = traces.get(enemy_id, ["SYSTEM_TRACE: ANALYZE CURRENT TELEMETRY"])
	if enemy_traces.is_empty():
		return "SYSTEM_TRACE: ANALYZE CURRENT TELEMETRY"
	var safe_index := clampi(step_index, 0, enemy_traces.size() - 1)
	return str(enemy_traces[safe_index])

static func _active_goal(enemy_id: String) -> String:
	match enemy_id:
		"broken_link":
			return "REPAIR_PATH_INTEGRITY"
		"hardware_ghost":
			return "STABILIZE_LEGACY_BUS"
		"driver_remnant":
			return "ISOLATE_INTERRUPT_ANOMALY"
		"printer_beast":
			return "RESTORE_SPOOL_STABILITY"
		"lost_file":
			return "RECOVER_FRAGMENT_DATA"
		"evil_tux":
			return "REBUILD_CORE_ROUTE"
		_:
			return "INVESTIGATE_SYSTEM_ANOMALY"

static func _current_phase(enemy_id: String, puzzle_data) -> String:
	if puzzle_data == null or not ("custom_data" in puzzle_data):
		return "scan"
	var custom: Dictionary = puzzle_data.custom_data

	if custom.has("required_fragments"):
		var required: Array = custom.get("required_fragments", [])
		var found: Array = custom.get("fragments_found", [])
		var restored: Array = custom.get("fragments_restored", [])
		if found.size() < required.size():
			return "scan"
		if restored.size() < required.size():
			return "analyze"
		return "execute"

	if custom.has("expected_sequence"):
		var expected: Array = custom.get("expected_sequence", [])
		var index := int(custom.get("current_index", 0))
		if index <= 1:
			return "scan"
		if index <= maxi(1, expected.size() - 2):
			return "analyze"
		return "execute"

	if enemy_id == "evil_tux":
		return "execute"

	return "scan"

static func _scan_doc(_enemy_id: String, phase: String, noun_hint: String) -> String:
	var scan_lines: Array[String] = []
	scan_lines.append("TUX // SCAN")
	scan_lines.append("Phase: %s" % phase.to_upper())
	scan_lines.append("Noun: %s" % noun_hint)
	scan_lines.append("Use LS to view files. Use CAT/FIND to inspect clues.")
	return "\n".join(scan_lines)

static func _beginner_quickstart(enemy_id: String, puzzle_data) -> String:
	var noun_hint := _noun_hint(enemy_id, puzzle_data)
	var _unused_enemy_id := enemy_id
	return "TUX // BEGINNER PATH\n1) Type LS\n2) Read the clue noun (%s)\n3) Type SCAN for the valid verb family" % noun_hint

static func _analyze_doc(enemy_id: String, phase: String, noun_hint: String) -> String:
	var _unused_enemy_id := enemy_id
	var lines: Array[String] = []
	lines.append("TUX // ANALYZE")
	lines.append("Phase: %s" % phase.to_upper())
	lines.append("Focus noun: %s" % noun_hint)
	lines.append("Identify one blocker before executing.")
	return "\n".join(lines)

static func _execute_doc(enemy_id: String, phase: String, noun_hint: String) -> String:
	var _unused_enemy_id := enemy_id
	var lines: Array[String] = []
	lines.append("TUX // EXECUTE")
	lines.append("Target noun: %s" % noun_hint)
	if phase != "execute":
		lines.append("You are early. Finish SCAN/ANALYZE first.")
	else:
		lines.append("Apply one action, validate output, continue.")
	return "\n".join(lines)

static func _noun_hint(enemy_id: String, puzzle_data) -> String:
	if puzzle_data != null and "custom_data" in puzzle_data:
		var custom: Dictionary = puzzle_data.custom_data
		if custom.has("required_fragments"):
			return "fragment files"
		if custom.has("expected_sequence"):
			match enemy_id:
				"broken_link":
					return "stub and target_note"
				"hardware_ghost":
					return "legacy logs and driver_table"
				"driver_remnant":
					return "remnant signature and irq_line"
				"printer_beast":
					return "spool, jam_page, and queue index"
	return "the current clue noun"

static func _history_lines(enemy_id: String) -> Array[String]:
	match enemy_id:
		"broken_link":
			return [
				"LOG_ENTRY 04: System Admin moved all /bin assets to /archive/temp to save space.",
				"LOG_ENTRY 05: Pointer table was not updated after migration.",
			]
		"lost_file":
			return [
				"LOG_ENTRY 12: Orphaned sectors tagged '.fragment' after abrupt power loss.",
				"LOG_ENTRY 13: One block remained encrypted in hidden cache.",
			]
		"hardware_ghost":
			return [
				"LOG_ENTRY 21: Legacy bus logs loop every boot; driver map stale since rollback.",
				"LOG_ENTRY 22: Echo stream references legacy_driver.log snapshots.",
			]
		"driver_remnant":
			return [
				"LOG_ENTRY 31: Rogue thread persisted after interrupted uninstall.",
				"LOG_ENTRY 32: IRQ pointer still bound to deprecated remnant node.",
			]
		"printer_beast":
			return [
				"LOG_ENTRY 41: Spool queue jam detected in spool.queue.",
				"LOG_ENTRY 42: Queue index left stale after emergency stop.",
			]
		"evil_tux":
			return [
				"LOG_ENTRY 51: Core route policy overwritten by hostile ruleset.",
				"LOG_ENTRY 52: App path integrity degraded after privilege escalation.",
			]
		_:
			return ["LOG_ENTRY 01: System anomaly detected. Collect more telemetry before intervention."]

static func _short_symptom(enemy_id: String, puzzle_data) -> String:
	if puzzle_data != null and "custom_data" in puzzle_data and puzzle_data.custom_data.has("expected_sequence"):
		var idx := int(puzzle_data.custom_data.get("current_index", 0))
		return _sequence_trace_info(enemy_id, idx)
	if enemy_id == "lost_file":
		return "SYSTEM_REPORT: orphaned fragment blocks detected"
	return "SYSTEM_REPORT: operational anomaly requires investigation"
