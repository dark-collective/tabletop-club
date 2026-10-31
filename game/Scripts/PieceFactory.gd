# tabletop-club
# Copyright (c) 2020-2026 Benjamin 'drwhut' Beddows.
# Copyright (c) 2021-2026 Tabletop Club contributors (see game/CREDITS.tres).
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

extends Node

signal finished(order, piece)

# Any orders that come in are stored here.
var _order_list = []
var _order_list_mutex = Mutex.new()
var _next_order_id = 0

# The last order that was accepted - if a piece is not accepted when it is
# finished, then it is freed from memory.
var _last_accepted_order = -1

# Finished pieces are placed here ready to be emitted.
var _finished_list = []
var _finished_list_mutex = Mutex.new()

# Pieces that were requested, but have not been accepted.
var _neglected_list = []
var _neglected_list_mutex = Mutex.new()

# Build previews on the main thread, one piece per frame.
var _building = false
var _stop_flag = false
var _stop_flag_mutex = Mutex.new()

# Accept a finished piece created by the factory.
# NOTE: If the piece is not accepted, it is immediately freed from memory.
# order: The order to accept.
func accept(order: int) -> void:
	assert(order >= 0)
	assert(order < _next_order_id)
	
	_last_accepted_order = order

# Stop an order from being built by the factory.
# NOTE: This only applies to pieces that are still in the request queue, not
# orders that are currently being built.
# order: The order to cancel.
func cancel(order: int) -> void:
	assert(order >= 0)
	assert(order < _next_order_id)
	
	_order_list_mutex.lock()
	for index in range(_order_list.size() - 1, -1, -1):
		var order_item: Dictionary = _order_list[index]
		var current_order: int = order_item["order"]
		if order == current_order:
			_order_list.remove_at(index)
	_order_list_mutex.unlock()

# Make a request to the factory to build a piece.
# Returns: The order number - the same number is given when "finished" is
# emitted. Used to take your order and register it as accepted.
# piece_entry: The AssetDB entry of the piece to build.
func request(piece_entry: Dictionary) -> int:
	var order_id = _next_order_id
	_next_order_id += 1
	
	_order_list_mutex.lock()
	_order_list.push_back({
		"order": order_id,
		"piece_entry": piece_entry
	})
	_order_list_mutex.unlock()
	
	if not _building:
		_building = true
		call_deferred("_build")
	
	return order_id

func _ready():
	connect("tree_exiting", Callable(self, "_on_tree_exiting"))

func _process(_delta):
	_finished_list_mutex.lock()
	while not _finished_list.is_empty():
		var finished_item: Dictionary = _finished_list.pop_front()
		var order: int = finished_item["order"]
		var piece: Piece = finished_item["piece"]
		
		emit_signal("finished", order, piece)
		
		# If the piece has not been accepted by whoever ordered it, then free
		# it from memory when everything else in the queue has been processed.
		if _last_accepted_order != order:
			ResourceManager.queue_free_object(piece)

	_finished_list_mutex.unlock()

# Drain the preview construction queue.
func _build() -> void:
	# Take the first item out of the list.
	var order_item = {}
	_order_list_mutex.lock()
	if not _order_list.is_empty():
		order_item = _order_list.pop_front()
	_order_list_mutex.unlock()
	
	while not order_item.is_empty():
		_stop_flag_mutex.lock()
		var stop = _stop_flag
		_stop_flag_mutex.unlock()
		
		if stop:
			break
		
		var order: int = order_item["order"]
		var piece_entry: Dictionary = order_item["piece_entry"]
		
		var piece: Piece = null
		
		# Build or load the preview without touching nodes from a worker thread.
		if piece_entry.has("entry_names"):
			if piece_entry["scene_path"] == "res://Pieces/Card.tscn":
				piece = preload("res://Pieces/StackSandwich.tscn").instantiate()
			else:
				piece = preload("res://Pieces/StackLasagne.tscn").instantiate()
			PieceBuilder.fill_stack(piece, piece_entry)
		elif PieceCache.should_cache(piece_entry):
			var thumbnail_cache = PieceCache.new(piece_entry["entry_path"], true)
			var maybe_piece = thumbnail_cache.get_scene()
			if maybe_piece != null and maybe_piece is Piece:
				piece = maybe_piece
			else:
				if maybe_piece != null:
					ResourceManager.free_object(maybe_piece)
				
				piece = PieceBuilder.build_piece(piece_entry, false)
		else:
			piece = PieceBuilder.build_piece(piece_entry, false)
		
		if piece != null:
			_finished_list_mutex.lock()
			_finished_list.push_back({
				"order": order,
				"piece": piece
			})
			_finished_list_mutex.unlock()
		
		await get_tree().process_frame
		if _stop_flag:
			break

		# Take the first item out of the list.
		order_item = {}
		_order_list_mutex.lock()
		if not _order_list.is_empty():
			order_item = _order_list.pop_front()
		_order_list_mutex.unlock()
	
	_building = false

	# After building everything in the queue, take any items
	# that were neglected (not accepted after they were requested)... and
	# throw them in the nearest available bin.
	_neglected_list_mutex.lock()
	for neglected_item in _neglected_list:
		ResourceManager.queue_free_object(neglected_item)
	_neglected_list.clear()
	_neglected_list_mutex.unlock()

func _on_tree_exiting():
	_stop_flag_mutex.lock()
	_stop_flag = true
	_stop_flag_mutex.unlock()
	
	
	_finished_list_mutex.lock()
	while not _finished_list.is_empty():
		var finished_item: Dictionary = _finished_list.pop_back()
		var piece: Piece = finished_item["piece"]
		ResourceManager.free_object(piece)
	_finished_list_mutex.unlock()
