# Pre-import browser assets using the native engine, including convex caches.
extends SceneTree
func _initialize():
	call_deferred("run")
func run():
	var database = root.get_node("AssetDB")
	database.start_importing()
	await database.completed
	if not database.get_error_dict().is_empty():
		push_error("Bundled asset preprocessing failed: " + str(database.get_error_dict()))
		quit(1)
		return
	var args = OS.get_cmdline_user_args()
	var target = args[args.find("--output") + 1]
	var file = FileAccess.open(target, FileAccess.WRITE)
	file.store_string(JSON.stringify({"user_directory": OS.get_user_data_dir()}))
	file.close()
	await process_frame
	quit()
