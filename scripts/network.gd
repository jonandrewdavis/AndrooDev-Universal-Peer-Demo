extends Node

const PLAYER = preload("uid://dbcqeo103wau6")

var peer_selected: PEERS = PEERS.EnetLocal: set = set_peer

# TODO: Icons
enum PEERS { 
	None,
	EnetLocal,
	EnetRelay,
	WebRTC,
	Websockets,
	GodotSteam,
	Epic,
	SpacetimeDB,
	GodotFusion
}

#region Peer Init

var enet_peer := ENetMultiplayerPeer.new()
var PORT := 9999
var IP_ADDRESS := '127.0.0.1'

var node_peer: NodeTunnelPeer
var node_tunnel_address := 'us_east.nodetunnel.io:8080'
var node_tunnel_id := 'vki6jrs3ezr133x'

var tube_client := TubeClient.new() #WebRTC
const TUBE_CONTEXT = preload("uid://chqw3jdoon6c1")

# TODO: FreeMP
var websockets_peer

# TODO: Steam
var steam_peer: SteamMultiplayerPeer

# TODO: Epic Online Service
#@onready var peer: EOSGMultiplayerPeer = EOSGMultiplayerPeer.new()
var eos

#endregion

var current_session_id
var host_function: Callable
var join_function: Callable

signal signal_error_raised

func set_peer(new_value: PEERS):
	peer_selected = new_value 
	
	# TODO: Assure reset
	reset_all_peers()
	
	match new_value:	
		PEERS.EnetLocal:
			host_function = start_server
			join_function = join_server
		PEERS.EnetRelay:
			node_peer = NodeTunnelPeer.new()
			node_peer.authenticated.connect(handle_node_tunnel_ready)
			node_peer.room_connected.connect(handle_room_ready)
			node_peer.error.connect(handle_error_raised)
			node_peer.connect_to_relay(node_tunnel_address, node_tunnel_id)
			host_function = start_node # TODO: These could be in a map or something to reduce repetition
			join_function = join_node
			multiplayer.multiplayer_peer = node_peer
		PEERS.WebRTC:
			tube_client.context = TUBE_CONTEXT
			get_tree().root.add_child.call_deferred(tube_client)
			host_function = start_tube
			join_function = join_tube
			tube_client._session_initiated.connect(func(): current_session_id = tube_client.session_id)
			tube_client.error_raised.connect(handle_error_raised)
		PEERS.GodotSteam:
			var is_steam_initilaized = Steam.steamInit(480, true) # "Spacewars"
			if is_steam_initilaized == false:
				push_warning('Steam not initialized')
				prints("Steam not initialized. Did you forget to sign in? Result:", is_steam_initilaized)
			else:
				prints("Steam initialized:", is_steam_initilaized)
				host_function = start_steam
				join_function = join_steam
				Steam.initRelayNetworkAccess()
				steam_peer = SteamMultiplayerPeer.new()
				steam_peer.server_relay = true

# Bind?
func host():
	multiplayer.peer_connected.connect(add_player)
	multiplayer.peer_disconnected.connect(remove_player)
	host_function.call()

func join(session_id: String = ''):
	multiplayer.peer_connected.connect(add_player) 
	multiplayer.peer_disconnected.connect(remove_player)
	multiplayer.connected_to_server.connect(add_player_self)
	join_function.call(session_id)

#region Peer Implementations

func start_server():
	enet_peer.create_server(PORT)
	multiplayer.multiplayer_peer = enet_peer
	add_player(1)

func join_server(_session_id: String = ''):
	enet_peer.create_client(IP_ADDRESS, PORT)
	multiplayer.multiplayer_peer = enet_peer

func start_tube():
	tube_client.create_session()
	add_player(1)

func join_tube(session_id: String):
	tube_client.join_session(session_id)

func start_node():
	node_peer.host_room(true, "")
	node_peer.room_connected.connect(add_player_self)

func join_node(session_id: String):
	node_peer.join_room(session_id)

func start_steam():
	Steam.createLobby(Steam.LobbyType.LOBBY_TYPE_PUBLIC, 16)
	Steam.lobby_created.connect(on_steam_created)
	
func join_steam(lobby_id: String):
	Steam.joinLobby(lobby_id.to_int())
	Steam.lobby_joined.connect(on_steam_joined)

func on_steam_created(result: int, lobby_id: int):
	if result == Steam.Result.RESULT_OK:
		prints("DEBUG:", lobby_id)
		current_session_id = str(lobby_id)
		steam_peer.create_host()
		multiplayer.multiplayer_peer = steam_peer
		add_player(1)

func on_steam_joined(lobby_id: int, _permissions: int, _locked: bool, _response: int):
	current_session_id = str(lobby_id)
	steam_peer.create_client(Steam.getLobbyOwner(lobby_id))
	multiplayer.multiplayer_peer = steam_peer

#region

func add_player_self():
	add_player(multiplayer.get_unique_id())

func add_player(peer_id: int):
	var new_player = PLAYER.instantiate()
	new_player.name = str(peer_id)

	var rand_x = randf_range(-5.0, 5.0)
	var rand_z = randf_range(-5.0, 5.0)

	new_player.position = Vector3(rand_x, 1.0, rand_z)
	get_tree().current_scene.add_child(new_player, true)

func remove_player(peer_id):
	if peer_id == 1:
		leave_server()
		return
	
	var players: Array[Node] = get_tree().get_nodes_in_group('Players')
	var player_to_remove = players.find_custom(func(item): return item.name == str(peer_id))
	if player_to_remove != -1:
		players[player_to_remove].queue_free()

func leave_server():
	if peer_selected == PEERS.WebRTC:
		tube_client.leave_session()

	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	clean_up_signals()
	get_tree().reload_current_scene()
	
func clean_up_signals():
	if multiplayer.peer_connected.is_connected(add_player):
		multiplayer.peer_connected.disconnect(add_player) 
	if multiplayer.peer_disconnected.is_connected(remove_player):
		multiplayer.peer_disconnected.disconnect(remove_player)
	if multiplayer.connected_to_server.is_connected(add_player_self):
		multiplayer.connected_to_server.disconnect(add_player_self)

func _exit_tree() -> void:
	if peer_selected == PEERS.WebRTC:
		tube_client.leave_session()

func handle_node_tunnel_ready():
	print("NODE TUNNEL READY")

func handle_room_ready():
	current_session_id = node_peer.room_id
	DisplayServer.clipboard_set(node_peer.room_id)

func handle_error_raised(..._args):
	clean_up_signals()
	signal_error_raised.emit()

func reset_all_peers():
	pass
