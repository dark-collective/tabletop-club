extends SceneTree

func _initialize():
	call_deferred("run")

func run():
	root.size = Vector2i(1152, 648)
	var splash = load("res://Scenes/SplashScreen.tscn").instantiate()
	root.add_child(splash)
	current_scene = splash
	root.get_node("Global")._current_scene = splash
	root.get_node("Global").start_importing_assets()
	for frame in range(3000):
		await process_frame
		if current_scene != null and current_scene.name == "MainMenu":
			break
	if current_scene == null or current_scene.name != "MainMenu":
		push_error("SMOKE: main menu did not load")
		quit(1)
		return
	print("SMOKE: main menu loaded")
	root.get_node("Global").start_game_singleplayer()
	for frame in range(600):
		await process_frame
		if current_scene != null and current_scene.name == "Game":
			break
	if current_scene == null or current_scene.name != "Game":
		push_error("SMOKE: singleplayer did not load")
		quit(1)
		return
	for frame in range(120): await process_frame
	print("SMOKE: singleplayer loaded")
	await exercise_game()
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var screenshot_path = ProjectSettings.globalize_path("res://../.artifacts/tests/singleplayer.png")
		DirAccess.make_dir_recursive_absolute(screenshot_path.get_base_dir())
		root.get_texture().get_image().save_png(screenshot_path)
	root.get_node("Global").start_main_menu()
	for frame in range(120): await process_frame
	current_scene.queue_free()
	for frame in range(3): await process_frame
	# Let the audio mixer release stopped streaming playback before shutdown.
	await create_timer(0.25).timeout
	print("SMOKE: all checks passed")
	quit()

func exercise_game():
	var game = current_scene
	var room = game.get_node("Room")
	assert(room.get_node("Table").get_child_count() >= 2, "Table mesh missing")
	assert(room.get_node("Table/HandPositions").get_child_count() > 0, "Hand positions missing")
	var database = root.get_node("AssetDB")
	assert(database.get_error_dict().is_empty(), "Asset import reported errors")
	var piece_count = room.get_node("Pieces").get_child_count()
	room.rpc_id(1, "request_add_piece", "TabletopClub/dice/d6/d6 (White)", Vector3(0, 8, 0))
	await process_frame
	assert(room.get_node("Pieces").get_child_count() == piece_count + 1, "Spawn failed")
	var die = room.get_node("Pieces").get_child(-1)
	die.rpc_id(1, "request_lock")
	assert(die.freeze, "Lock failed")
	die.rpc_id(1, "request_unlock")
	assert(not die.freeze, "Unlock failed")
	die.rpc_id(1, "request_set_albedo_color", Color.RED)
	assert(die.get_albedo_color().is_equal_approx(Color.RED), "Color failed")
	die.rpc_id(1, "request_impulse", Vector3.ZERO, Vector3(1, 4, 0))
	room.rpc_id(1, "request_add_stack_filled", Transform3D(Basis.IDENTITY, Vector3(10, 5, 0)), "TabletopClub/cards/52-Card Deck")
	await process_frame
	assert(room.get_node("Pieces").get_child_count() == piece_count + 2, "Stack spawn failed")
	var deck = room.get_node("Pieces").get_child(-1)
	assert(deck.has_method("get_piece_count") and deck.get_piece_count() == 52, "Deck contents failed")
	room.rpc_id(1, "request_pop_stack", str(deck.name), 1, false, 3.0)
	await process_frame
	assert(deck.get_piece_count() == 51, "Drawing a card failed")
	for name in ["Chess", "Dominoes", "Go", "Poker"]:
		var path = ProjectSettings.globalize_path("res://").path_join("../assets/TabletopClub/games/" + name + ".tc")
		var file = FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
		assert(file != null)
		var state = preload("res://Scripts/Runtime/TableStateFile.gd").read(file)
		assert(state is Dictionary, "Legacy save failed: " + name)
		room.rpc_id(1, "request_load_table_state", room.compress_state(state))
		for frame in range(3): await process_frame
		var actual = room.get_state(false, false)
		for kind in ["pieces", "containers", "speakers", "stacks", "timers"]:
			assert(actual[kind].size() == state[kind].size(), "Legacy object count mismatch: " + name + "/" + kind)
		assert(room.get_node("Pieces").get_child_count() > 0, "Empty legacy table: " + name)
		print("SMOKE: loaded legacy ", name)
	var state = room.get_state(true, false)
	var save_path = "user://smoke.tc"
	game.save_state(state, save_path)
	# Suppress the deferred screenshot during headless tests.
	game._save_screenshot_frames = -1
	var saved = FileAccess.open_compressed(save_path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	assert(preload("res://Scripts/Runtime/TableStateFile.gd").read(saved) == state, "Save round trip failed")
	saved.close()
	DirAccess.remove_absolute(save_path)
	var ui = game.get_node("GameUI")
	ui.popup_objects_dialog()
	for frame in range(10): await process_frame
	ui.get_node("CanvasLayer/ObjectsDialog").hide()
	print("SMOKE: gameplay and save checks passed")
