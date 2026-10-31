# Bridge Godot 4's public Logger API to the in-game error console.
# Copyright (c) 2026 Tabletop Club contributors. MIT license (see LICENSE).
extends Logger

signal error_received(function: String, file: String, line: int, error: String, expression: String)
signal warning_received(function: String, file: String, line: int, error: String, expression: String)

func _log_error(function: String, file: String, line: int, code: String,
		rationale: String, _editor_notify: bool, error_type: int,
		_script_backtraces: Array[ScriptBacktrace]) -> void:
	# Engine errors can arrive from worker threads. Deliver to UI on the next
	# main-thread turn, outside the engine's logger callback.
	var event = "warning_received" if error_type == ERROR_TYPE_WARNING else "error_received"
	call_deferred("emit_signal", event, function, file, line,
		rationale if not rationale.is_empty() else code, code)
