# Compile every game script, including scripts not loaded by the splash scene.
extends SceneTree
var failures = 0
func _initialize():
	call_deferred("check_all")
func check_all():
	check_dir("res://Scripts")
	if failures == 0:
		print("SCRIPTS: all game scripts compile")
	quit(1 if failures else 0)
func check_dir(path: String):
	var dir = DirAccess.open(path)
	for file in dir.get_files():
		if file.ends_with(".gd"):
			var resource = load(path.path_join(file))
			if resource == null or not resource.can_instantiate():
				failures += 1
	for subdir in dir.get_directories():
		# These are editor templates with deliberate placeholders.
		if subdir != "Templates":
			check_dir(path.path_join(subdir))
