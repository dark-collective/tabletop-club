# Runtime asset loading for stock Godot 4; no editor modules are required.
# Copyright (c) 2026 Tabletop Club contributors. MIT license (see LICENSE).
extends RefCounted

const TEXTURE_EXTENSIONS = ["bmp", "dds", "exr", "hdr", "jpeg", "jpg", "png", "tga", "svg", "svgz", "webp"]
const RESOURCE_EXTENSIONS = TEXTURE_EXTENSIONS + ["ogg", "mp3", "wav", "obj", "gltf", "glb", "dae"]
const CACHE_SUFFIX = ".runtime.res"
var _web_bake = OS.get_cmdline_user_args().has("--web-assets")

func copy_file(from: String, to: String, force: bool = false) -> int:
	var err = DirAccess.make_dir_recursive_absolute(to.get_base_dir())
	if err != OK:
		return err
	if not force and FileAccess.file_exists(to):
		if FileAccess.get_md5(from) == FileAccess.get_md5(to):
			if not to.get_extension().to_lower() in RESOURCE_EXTENSIONS or FileAccess.file_exists(to + CACHE_SUFFIX):
				return ERR_ALREADY_EXISTS
	return DirAccess.copy_absolute(from, to)

func import(path: String) -> int:
	var resource: Resource
	var extension = path.get_extension().to_lower()
	if extension in TEXTURE_EXTENSIONS:
		var image = Image.load_from_file(path)
		if image == null or image.is_empty():
			return ERR_FILE_CORRUPT
		if _web_bake and not extension in ["svg", "svgz"]:
			_limit_image(image)
		image.generate_mipmaps()
		resource = ImageTexture.create_from_image(image)
	elif extension == "ogg":
		resource = AudioStreamOggVorbis.load_from_file(path)
	elif extension == "mp3":
		resource = AudioStreamMP3.load_from_file(path)
	elif extension == "wav":
		resource = AudioStreamWAV.load_from_file(path)
	elif extension in ["gltf", "glb"]:
		var document = GLTFDocument.new()
		var state = GLTFState.new()
		var err = document.append_from_file(path, state)
		if err != OK:
			return err
		var scene = document.generate_scene(state)
		if scene == null:
			return ERR_FILE_CORRUPT
		if _web_bake: _limit_scene_textures(scene)
		resource = _pack_scene(scene)
	elif extension == "obj":
		resource = _load_obj(path)
	else:
		push_error("Runtime import does not support '%s'. Convert Collada models to glTF first." % path)
		return ERR_UNAVAILABLE
	if resource == null:
		return ERR_FILE_CORRUPT
	return ResourceSaver.save(resource, path + CACHE_SUFFIX, ResourceSaver.FLAG_COMPRESS)

func _pack_scene(scene: Node) -> PackedScene:
	var packed = PackedScene.new()
	var err = packed.pack(scene)
	scene.free()
	return packed if err == OK else null

# The public runtime glTF loader does not accept Wavefront OBJ. Preserve the
# bundled OBJ assets with a small triangle/quad/polygon loader, including MTL.
func _load_obj(path: String) -> PackedScene:
	var vertices: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var materials: Dictionary = {}
	var surfaces: Dictionary = {}
	var material_name = ""
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	while not file.eof_reached():
		var fields = file.get_line().strip_edges().replace("\t", " ").split(" ", false)
		if fields.is_empty() or fields[0].begins_with("#"):
			continue
		match fields[0]:
			"v":
				if fields.size() < 4: return null
				vertices.append(Vector3(float(fields[1]), float(fields[2]), float(fields[3])))
			"vn":
				if fields.size() < 4: return null
				normals.append(Vector3(float(fields[1]), float(fields[2]), float(fields[3])))
			"vt":
				if fields.size() < 3: return null
				uvs.append(Vector2(float(fields[1]), 1.0 - float(fields[2])))
			"mtllib":
				var library = " ".join(fields.slice(1))
				if not library.is_absolute_path(): library = path.get_base_dir().path_join(library)
				materials.merge(_load_mtl(library), true)
			"usemtl":
				material_name = " ".join(fields.slice(1))
			"f":
				if fields.size() < 4: return null
				if not surfaces.has(material_name): surfaces[material_name] = []
				# Godot uses clockwise front faces; OBJ uses counterclockwise.
				for i in range(2, fields.size() - 1):
					for corner in [fields[1], fields[i + 1], fields[i]]:
						var indices = corner.split("/", true)
						var vi = _obj_index(indices[0], vertices.size())
						if vi < 0 or vi >= vertices.size(): return null
						var uv = Vector2.ZERO
						var normal = Vector3.ZERO
						if indices.size() > 1 and not indices[1].is_empty():
							var ti = _obj_index(indices[1], uvs.size())
							if ti < 0 or ti >= uvs.size(): return null
							uv = uvs[ti]
						if indices.size() > 2 and not indices[2].is_empty():
							var ni = _obj_index(indices[2], normals.size())
							if ni < 0 or ni >= normals.size(): return null
							normal = normals[ni]
						surfaces[material_name].append([vertices[vi], uv, normal])
	var mesh = ArrayMesh.new()
	for surface in surfaces:
		var tool = SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		var has_normals = true
		for vertex in surfaces[surface]:
			tool.set_uv(vertex[1])
			tool.set_normal(vertex[2])
			if vertex[2].is_zero_approx(): has_normals = false
			tool.add_vertex(vertex[0])
		if not has_normals: tool.generate_normals()
		tool.set_material(materials.get(surface, StandardMaterial3D.new()))
		tool.commit(mesh)
	if mesh.get_surface_count() == 0: return null
	var root = Node3D.new()
	root.name = path.get_file().get_basename().validate_node_name()
	var instance = MeshInstance3D.new()
	instance.name = "Mesh"
	instance.mesh = mesh
	root.add_child(instance)
	instance.owner = root
	return _pack_scene(root)

func _obj_index(value: String, count: int) -> int:
	var index = int(value)
	return index - 1 if index > 0 else count + index

func _load_mtl(path: String) -> Dictionary:
	var materials = {}
	var material: StandardMaterial3D
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null: return materials
	while not file.eof_reached():
		var fields = file.get_line().strip_edges().split(" ", false)
		if fields.is_empty(): continue
		if fields[0] == "newmtl":
			material = StandardMaterial3D.new()
			materials[" ".join(fields.slice(1))] = material
		elif material != null:
			match fields[0]:
				"Kd":
					if fields.size() >= 4:
						material.albedo_color = Color(float(fields[1]), float(fields[2]), float(fields[3]))
				"map_Kd":
					var texture_path = path.get_base_dir().path_join(" ".join(fields.slice(1)))
					var image = Image.load_from_file(texture_path)
					if image != null and not image.is_empty():
						if _web_bake: _limit_image(image)
						material.albedo_texture = ImageTexture.create_from_image(image)
	return materials

# Web assets retain all game content, with bounded raster texture resolution.
# SVG templates keep their original dimensions so textbox coordinates match.
func _limit_image(image: Image) -> void:
	var largest = max(image.get_width(), image.get_height())
	if largest > 1024:
		if image.is_compressed(): image.decompress()
		var factor = 1024.0 / largest
		image.resize(maxi(1, roundi(image.get_width() * factor)), maxi(1, roundi(image.get_height() * factor)), Image.INTERPOLATE_LANCZOS)

func _limit_scene_textures(scene: Node) -> void:
	var nodes = [scene]
	var scaled = {}
	while not nodes.is_empty():
		var node = nodes.pop_back()
		nodes.append_array(node.get_children())
		if not node is MeshInstance3D or node.mesh == null: continue
		for surface in range(node.mesh.get_surface_count()):
			var material = node.mesh.surface_get_material(surface)
			if material == null: continue
			for property in material.get_property_list():
				if not str(property.name).ends_with("_texture"): continue
				var texture = material.get(property.name)
				if not texture is Texture2D: continue
				var key = texture.get_instance_id()
				if not scaled.has(key):
					var image = texture.get_image()
					if image == null: continue
					_limit_image(image)
					image.generate_mipmaps()
					scaled[key] = ImageTexture.create_from_image(image)
				material.set(property.name, scaled[key])
