# Optional end-to-end check against a locally running upstream signaling server.
extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	root.size = Vector2i(1152, 648)
	var args = OS.get_cmdline_user_args()
	var host = args.has("--session-host")
	var transfer = args.has("--session-transfer")
	var shared_path = args[args.find("--session-file") + 1]
	var splash = load("res://Scenes/SplashScreen.tscn").instantiate()
	root.add_child(splash)
	current_scene = splash
	root.get_node("Global")._current_scene = splash
	root.get_node("Global").start_importing_assets()
	for frame in range(3000):
		await process_frame
		if current_scene.name == "MainMenu": break
	assert(current_scene.name == "MainMenu")
	if host:
		root.get_node("Global").start_game_as_server()
	else:
		for frame in range(3000):
			await process_frame
			if FileAccess.file_exists(shared_path): break
		assert(FileAccess.file_exists(shared_path), "Host did not publish room code")
		root.get_node("Global").start_game_as_client(FileAccess.get_file_as_string(shared_path))
	for frame in range(600):
		await process_frame
		if current_scene.name == "Game": break
	assert(current_scene.name == "Game")
	var game = current_scene
	if host:
		for frame in range(3000):
			await process_frame
			var code = game.get_node("MasterServer").room_code
			if not code.is_empty():
				var file = FileAccess.open(shared_path, FileAccess.WRITE)
				file.store_string(code)
				file.close()
				break
		var room = game.get_node("Room")
		room.rpc_id(1, "request_add_piece", "MigrationTest/tokens/cube/Test" if transfer else "TabletopClub/dice/d6/d6 (White)", Vector3(0, 5, 0))
		for frame in range(6000):
			await process_frame
			if FileAccess.file_exists(shared_path + ".done"): break
		assert(FileAccess.file_exists(shared_path + ".done"), "Client did not finish syncing")
	else:
		var room = game.get_node("Room")
		for frame in range(6000):
			await process_frame
			if transfer and game.get_node("MissingAssetsDialog").visible:
				game._on_MissingYesButton_pressed()
			if transfer and game.get_node("DownloadAssetsConfirmDialog").visible:
				game._on_DownloadAssetsConfirmDialog_confirmed()
			if game._cln_compared_schemas and root.get_node("Lobby").get_player_list().size() == 2 and room.get_node("Pieces").get_child_count() == 1:
				break
		if transfer:
			assert(root.get_node("AssetDB").search_path("MigrationTest/tokens/cube/Test").size() > 0, "Downloaded asset not registered")
			assert(FileAccess.file_exists("user://assets/MigrationTest/tokens/cube/Test.png.runtime.res"), "Runtime import did not finish")
		assert(game._cln_compared_schemas, "Asset schemas were not compared")
		assert(room.get_node("Pieces").get_child_count() == 1, "Room state did not sync")
		room.get_node("Pieces").get_child(0).rpc_id(1, "request_lock")
		for frame in range(60): await process_frame
		assert(room.get_node("Pieces").get_child(0).freeze, "Gameplay did not replicate")
		var file = FileAccess.open(shared_path + ".done", FileAccess.WRITE)
		file.store_string("ok")
		file.close()
	root.get_node("Global").start_main_menu()
	for frame in range(600):
		await process_frame
		if current_scene.name == "MainMenu": break
	assert(current_scene.name == "MainMenu")
	for frame in range(120): await process_frame
	current_scene.queue_free()
	for frame in range(3): await process_frame
	# Let the audio mixer release stopped streaming playback before shutdown.
	await create_timer(0.25).timeout
	print("SESSION: ", "host" if host else "client", " passed")
	quit()
