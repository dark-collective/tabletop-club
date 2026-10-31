# Exercise the migrated RPCs over real local WebRTC data channels.
extends SceneTree
var host_connection: WebRTCPeerConnection
var client_connection: WebRTCPeerConnection
var host_peer: WebRTCMultiplayerPeer
var client_peer: WebRTCMultiplayerPeer

func _initialize():
	call_deferred("run")

func run():
	var host = _make_endpoint("Host")
	var client = _make_endpoint("Client")
	var host_api = SceneMultiplayer.new()
	var client_api = SceneMultiplayer.new()
	set_multiplayer(host_api, host.get_path())
	set_multiplayer(client_api, client.get_path())
	host_peer = WebRTCMultiplayerPeer.new()
	client_peer = WebRTCMultiplayerPeer.new()
	assert(host_peer.create_server() == OK)
	assert(client_peer.create_client(2) == OK)
	host_connection = WebRTCPeerConnection.new()
	client_connection = WebRTCPeerConnection.new()
	assert(host_connection.initialize({}) == OK, "Install the Godot 4 WebRTC extension for desktop tests")
	assert(client_connection.initialize({}) == OK)
	host_connection.session_description_created.connect(_host_description)
	client_connection.session_description_created.connect(_client_description)
	host_connection.ice_candidate_created.connect(func(mid, index, sdp): client_connection.add_ice_candidate(mid, index, sdp))
	client_connection.ice_candidate_created.connect(func(mid, index, sdp): host_connection.add_ice_candidate(mid, index, sdp))
	assert(host_peer.add_peer(host_connection, 2) == OK)
	assert(client_peer.add_peer(client_connection, 1) == OK)
	host_api.multiplayer_peer = host_peer
	client_api.multiplayer_peer = client_peer
	assert(host_connection.create_offer() == OK)
	for frame in range(1800):
		await process_frame
		if client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED and host_api.get_peers().size() == 1:
			break
	assert(client_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, "WebRTC connection timed out")
	assert(host_api.get_peers().size() == 1, "Host did not see client")
	client.get_node("Lobby").rpc_id(1, "request_add_self", "Client", Color.BLUE)
	for frame in range(120): await process_frame
	assert(host.get_node("Lobby").player_exists(2), "Client request did not reach host")
	assert(client.get_node("Lobby").player_exists(2), "Host lobby update did not reach client")
	client.get_node("Piece").rpc_id(1, "request_lock")
	for frame in range(120): await process_frame
	assert(host.get_node("Piece").freeze and client.get_node("Piece").freeze, "Piece lock did not replicate")
	client.get_node("Piece").rpc_id(1, "request_unlock")
	for frame in range(120): await process_frame
	assert(not host.get_node("Piece").freeze and not client.get_node("Piece").freeze, "Piece unlock did not replicate")
	var before = host.get_node("Piece").position
	client.get_node("Piece").rpc_id(1, "sync_position", Vector3(100, 100, 100))
	for frame in range(120): await process_frame
	assert(host.get_node("Piece").position == before, "Client bypassed host authority")
	host_peer.close()
	client_peer.close()
	host.queue_free()
	client.queue_free()
	await process_frame
	print("MULTIPLAYER: WebRTC lobby, piece replication, and authority checks passed")
	quit()

func _make_endpoint(endpoint_name: String) -> Node:
	var node = Node.new()
	node.name = endpoint_name
	root.add_child(node)
	var lobby = load("res://Scripts/Lobby.gd").new()
	lobby.name = "Lobby"
	node.add_child(lobby)
	var piece = load("res://Pieces/Tokens/Cube.tscn").instantiate()
	piece.name = "Piece"
	piece.gravity_scale = 0
	node.add_child(piece)
	return node

func _host_description(type: String, sdp: String):
	host_connection.set_local_description(type, sdp)
	client_connection.set_remote_description(type, sdp)

func _client_description(type: String, sdp: String):
	client_connection.set_local_description(type, sdp)
	host_connection.set_remote_description(type, sdp)
