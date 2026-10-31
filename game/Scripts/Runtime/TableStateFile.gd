# Read data-only .tc saves from both Godot 3 and Godot 4.
# Copyright (c) 2026 Tabletop Club contributors. MIT license (see LICENSE).
# Godot 3's wire layout: godotengine/godot, 3.6, core/io/marshalls.cpp.
extends RefCounted

const MAX_BYTES = 256 * 1024 * 1024
var _data: PackedByteArray
var _offset = 0
var _valid = true

static func read(file: FileAccess):
	if file.get_length() < 8 or file.get_length() > MAX_BYTES:
		return null
	var size = file.get_32()
	if size < 4 or size > file.get_length() - 4:
		return null
	var bytes = file.get_buffer(size)
	# The root must be a Dictionary. Its type ID changed from 18 to 27.
	if bytes.decode_u32(0) == TYPE_DICTIONARY:
		return bytes_to_var(bytes)
	if bytes.decode_u32(0) != 18:
		return null
	var decoder = new()
	decoder._data = bytes
	var result = decoder._decode(0)
	return result if decoder._valid and decoder._offset == bytes.size() else null

func _take(size: int) -> int:
	var start = _offset
	if size < 0 or size > _data.size() - _offset:
		_valid = false
		return -1
	_offset += size
	return start

func _u32() -> int:
	var at = _take(4)
	return _data.decode_u32(at) if at >= 0 else 0

func _real() -> float:
	var at = _take(4)
	return _data.decode_float(at) if at >= 0 else 0.0

func _vec2() -> Vector2:
	var x = _real()
	var y = _real()
	return Vector2(x, y)

func _vec3() -> Vector3:
	var x = _real()
	var y = _real()
	var z = _real()
	return Vector3(x, y, z)

func _color() -> Color:
	var r = _real()
	var g = _real()
	var b = _real()
	var a = _real()
	return Color(r, g, b, a)

func _basis() -> Basis:
	# Godot 3 encodes rows, while Basis constructors take columns.
	var x = _vec3()
	var y = _vec3()
	var z = _vec3()
	return Basis(x, y, z).transposed()

func _string() -> String:
	var size = _u32()
	var at = _take(size)
	if at < 0: return ""
	var text = _data.slice(at, at + size).get_string_from_utf8()
	_take((4 - size % 4) % 4)
	return text

func _decode(depth: int):
	if not _valid or depth > 64:
		_valid = false
		return null
	var header = _u32()
	var type = header & 0xFFFF
	var wide = (header & 0x10000) != 0
	match type:
		0: return null
		1: return _u32() != 0
		2:
			var at = _take(8 if wide else 4)
			if at < 0: return null
			return _data.decode_s64(at) if wide else _data.decode_s32(at)
		3:
			if not wide: return _real()
			var at = _take(8)
			return _data.decode_double(at) if at >= 0 else 0.0
		4: return _string()
		5: return _vec2()
		6:
			var position = _vec2()
			var size = _vec2()
			return Rect2(position, size)
		7: return _vec3()
		8:
			var x = _vec2()
			var y = _vec2()
			var origin = _vec2()
			return Transform2D(x, y, origin)
		9:
			var normal = _vec3()
			var distance = _real()
			return Plane(normal, distance)
		10:
			var xyz = _vec3()
			var w = _real()
			return Quaternion(xyz.x, xyz.y, xyz.z, w)
		11:
			var position = _vec3()
			var size = _vec3()
			return AABB(position, size)
		12: return _basis()
		13:
			var basis = _basis()
			var origin = _vec3()
			return Transform3D(basis, origin)
		14: return _color()
		18, 19:
			var count = _u32() & 0x7FFFFFFF
			if count > (_data.size() - _offset) / (8 if type == 18 else 4):
				_valid = false
				return null
			if type == 18:
				var dictionary = {}
				for i in range(count):
					var key = _decode(depth + 1)
					var value = _decode(depth + 1)
					if not _valid or not (key is String or key is int):
						_valid = false
						return null
					dictionary[key] = value
				return dictionary
			var array = []
			for i in range(count):
				array.append(_decode(depth + 1))
				if not _valid: return null
			return array
		20:
			var size = _u32()
			var at = _take(size)
			if at < 0: return null
			var bytes = _data.slice(at, at + size)
			_take((4 - size % 4) % 4)
			return bytes
		21, 22, 23, 24, 25, 26:
			var count = _u32()
			if count > (_data.size() - _offset) / 4:
				_valid = false
				return null
			var values = []
			for i in range(count):
				match type:
					21:
						var at = _take(4)
						values.append(_data.decode_s32(at) if at >= 0 else 0)
					22: values.append(_real())
					23: values.append(_string())
					24: values.append(_vec2())
					25: values.append(_vec3())
					26: values.append(_color())
				if not _valid: return null
			match type:
				21: return PackedInt32Array(values)
				22: return PackedFloat32Array(values)
				23: return PackedStringArray(values)
				24: return PackedVector2Array(values)
				25: return PackedVector3Array(values)
				26: return PackedColorArray(values)
		_:
			# Reject objects, resources, node paths and unknown types.
			_valid = false
	return null
