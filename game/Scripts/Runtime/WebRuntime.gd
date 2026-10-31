# Browser storage and the narrow JavaScript bridge used by Matrix widgets.
# Copyright (c) 2026 Tabletop Club contributors. MIT license (see LICENSE).
extends Node

var _callback: JavaScriptObject
var _lobby: Node
var _preparing = false
var _prepared = false
var _commands: Array = []
var _shell
var _ready_scene = ""
var _participants = -1

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	_shell = JavaScriptBridge.get_interface("tabletopWidget")
	if _shell != null:
		_callback = JavaScriptBridge.create_callback(_on_command)
		_shell.registerGame(_callback)

func is_widget() -> bool:
	return OS.has_feature("web") and _shell != null and bool(_shell.isWidget)

func multiplayer_available() -> bool:
	return not OS.has_feature("web") or (_shell != null and bool(_shell.multiplayerReady))

func player_name() -> String:
	return str(_shell.displayName) if is_widget() else ""

func ice_servers() -> Array:
	if is_widget():
		var parsed = JSON.parse_string(str(_shell.iceServersJSON))
		if parsed is Array and not parsed.is_empty():
			return parsed
	return [{"urls": ["stun:stun.l.google.com:19302"]}]

func open_lobby(lobby: Node, code: String) -> void:
	_lobby = lobby
	_send({"action": "connect", "code": code})

func close_lobby(lobby: Node) -> void:
	if _lobby == lobby:
		_lobby = null
		_send({"action": "disconnect"})

func send_lobby(action: String, data: Dictionary = {}) -> void:
	data["action"] = action
	_send(data)

func _send(data: Dictionary) -> void:
	if _shell != null:
		_shell.fromGame(JSON.stringify(data))

func _on_command(arguments: Array) -> void:
	if arguments.is_empty(): return
	var data = JSON.parse_string(str(arguments[0]))
	if data is Dictionary:
		_commands.append(data)

func _process(_delta: float) -> void:
	if not OS.has_feature("web"): return
	while not _commands.is_empty():
		var command = _commands.pop_front()
		if command.get("action") == "lobby" and is_instance_valid(_lobby):
			_lobby.handle_matrix_event(command)
		elif command.get("action") == "export_save":
			_export_save()
		elif command.get("action") == "import_save":
			_import_save(str(command.get("data", "")))
		elif command.get("action") == "start_singleplayer":
			Global.start_game_singleplayer()
		elif command.get("action") == "host":
			Global.start_game_as_server()
		elif command.get("action") == "join":
			Global.start_game_as_client(str(command.get("code", "")))
	var scene = get_tree().current_scene
	if scene != null and str(scene.name) != _ready_scene:
		_ready_scene = str(scene.name)
		_send({"action": "scene", "name": _ready_scene})
	if scene != null and str(scene.name) == "Game":
		var count = scene.multiplayer.get_peers().size() + 1
		if count != _participants:
			_participants = count
			_send({"action": "participants", "count": count})

# Sources and prebuilt resource caches live in a ZIP so the exporter cannot
# replace source images with import remaps. Extract into the browser userfs.
func prepare_assets() -> bool:
	if _prepared: return true
	if _preparing:
		while _preparing: await get_tree().process_frame
		return _prepared
	_preparing = true
	var archive = ZIPReader.new()
	var err = archive.open("res://web_assets.zip")
	if err != OK:
		push_error("Could not open the bundled assets (error %d)." % err)
		_preparing = false
		return false
	var version = FileAccess.get_file_as_string("res://web_assets.sha256").strip_edges()
	var stamp_path = "user://bundled/version.txt"
	if not FileAccess.file_exists(stamp_path) or FileAccess.get_file_as_string(stamp_path) != version:
		# Remove obsolete bundled sources after upgrades; keep user saves intact.
		_remove_bundle_directory("user://bundled/assets")
		var files = archive.get_files()
		for index in range(files.size()):
			var name = files[index]
			if name.ends_with("/"): continue
			if name.is_absolute_path() or ".." in name.split("/"):
				push_error("Invalid path in the bundled assets.")
				_preparing = false
				return false
			var path = "user://" + name.trim_prefix("cache/") if name.begins_with("cache/assets/") else "user://bundled/" + name
			err = DirAccess.make_dir_recursive_absolute(path.get_base_dir())
			var file = FileAccess.open(path, FileAccess.WRITE) if err == OK else null
			if file == null:
				push_error("Could not unpack the bundled assets.")
				_preparing = false
				return false
			file.store_buffer(archive.read_file(name))
			file.close()
			if index % 8 == 0:
				_send({"action": "loading", "message": "Unpacking game assets…", "progress": float(index) / files.size()})
				await get_tree().process_frame
		var stamp = FileAccess.open(stamp_path, FileAccess.WRITE)
		if stamp == null:
			_preparing = false
			return false
		stamp.store_string(version)
		stamp.close()
	archive.close()
	_preparing = false
	_prepared = true
	return true

func _remove_bundle_directory(path: String) -> void:
	var directory = DirAccess.open(path)
	if directory == null: return
	for name in directory.get_files():
		directory.remove(name)
	for name in directory.get_directories():
		_remove_bundle_directory(path.path_join(name))
	DirAccess.remove_absolute(path)

func _export_save() -> void:
	var game = get_tree().current_scene
	if game == null or str(game.name) != "Game": return
	var path = "user://browser-export.tc"
	var file = FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null: return
	file.store_var(game.get_node("Room").get_state(false, false))
	file.close()
	JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(path), "tabletop-club.tc", "application/octet-stream")

func _import_save(encoded: String) -> void:
	var game = get_tree().current_scene
	if game == null or str(game.name) != "Game" or not game.multiplayer.is_server(): return
	if encoded.length() > 24 * 1024 * 1024: return
	var bytes = Marshalls.base64_to_raw(encoded)
	var path = "user://browser-import.tc"
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_buffer(bytes)
	file.close()
	game.load_state(path)
