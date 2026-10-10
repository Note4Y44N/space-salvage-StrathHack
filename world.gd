extends Node2D
## Root of world.tscn. Starts networking, spawns players (host only, through the
## MultiplayerSpawner), lays out the loot field and builds the sky and darkness.
##
## The scene loads *before* we connect, so a joining client always has the
## spawner ready when the host's spawn messages arrive.

const PLAYER_SCENE := preload("res://player.tscn")
const LOOT_SCENE := preload("res://loot.tscn")

const LOOT_SEED := 12345
const LOOT_COUNT := 160
const LOOT_MIN_DIST := 450.0
const LOOT_MAX_DIST := 3400.0
const RELIC_DISTANCES := [1500.0, 2100.0, 2700.0]  # one heavy relic at each distance
const JOIN_TIMEOUT := 10.0  # seconds before a join attempt gives up

## The "Discord game" twist: space is dark, divers only see their helmet light,
## and whoever is in the station gets the radar. Turn off to make it easy.
const DARKNESS_ENABLED := true
const DARKNESS_COLOR := Color(0.07, 0.07, 0.11)

@onready var players: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var station: Station = $Station

var loot_root: Node2D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.01, 0.01, 0.03))
	spawner.spawn_path = spawner.get_path_to(players)
	spawner.spawn_function = _spawn_player
	_spawn_loot()
	_spawn_relics()
	var music := Sounds.loop("music", -14.0)
	add_child(music)
	music.play()
	add_child(SpaceBackground.new())
	if DARKNESS_ENABLED:
		var darkness := CanvasModulate.new()
		darkness.color = DARKNESS_COLOR
		add_child(darkness)

	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	GameState.game_reset.connect(_on_game_reset)

	var err := NetworkManager.host() if NetworkManager.want_host else NetworkManager.join(NetworkManager.join_ip)
	if err != OK:
		NetworkManager.leave(NetworkManager.last_error)
		return
	if multiplayer.is_server():
		_add_player(1, NetworkManager.player_name)
		if NetworkManager.dev_money > 0:
			GameState.add_money(NetworkManager.dev_money)
	else:
		# ENet can take ~30 s to give up on a wrong address; fail faster and clearer.
		get_tree().create_timer(JOIN_TIMEOUT).timeout.connect(_on_join_timeout)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		NetworkManager.leave()


# --- Players -----------------------------------------------------------------

func _on_connected_to_server() -> void:
	print("[%s] connected as peer %d" % [NetworkManager.player_name, multiplayer.get_unique_id()])
	register_player.rpc_id(1, NetworkManager.player_name)


## Client -> host: "I'm loaded, spawn me".
@rpc("any_peer", "reliable")
func register_player(player_name: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	GameState.send_state_to(id)
	_send_loot_state(id)
	_add_player(id, player_name.left(16))
	GameState.announce.rpc("%s joined the crew" % player_name)


func _add_player(id: int, player_name: String) -> void:
	if not players.has_node(str(id)):
		spawner.spawn({"id": id, "name": player_name, "look": _free_look()})


## The first sprite look nobody is wearing yet (wraps around past 8 players).
func _free_look() -> int:
	var taken := []
	for player: Player in players.get_children():
		taken.append(player.look)
	for look in Player.LOOKS:
		if look not in taken:
			return look
	return players.get_child_count() % Player.LOOKS


## Runs on every peer (host and clients) with the same data.
func _spawn_player(data: Variant) -> Node:
	var id: int = data["id"]
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.display_name = data["name"]
	player.look = data["look"]
	player.position = station.spawn_point(player.look)
	return player


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var player := players.get_node_or_null(str(id)) as Player
	if player:
		GameState.announce.rpc("%s left" % player.display_name)
		player.queue_free()


func _on_connection_failed() -> void:
	NetworkManager.leave(_join_help())


func _on_join_timeout() -> void:
	if multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		NetworkManager.leave(_join_help())


func _join_help() -> String:
	return "Couldn't reach %s. Check the join code, that you're on the same Wi-Fi as the host, and that the host allowed Godot through the firewall." % NetworkManager.join_ip


func _on_server_disconnected() -> void:
	NetworkManager.leave("Lost connection to the host.")


# --- Loot --------------------------------------------------------------------

## Same seed and same node names on every peer, so loot itself needs no syncing.
func _spawn_loot() -> void:
	loot_root = Node2D.new()
	loot_root.name = "Loot"
	add_child(loot_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = LOOT_SEED
	for i in LOOT_COUNT:
		var loot: Loot = LOOT_SCENE.instantiate()
		loot.name = "Loot%d" % i
		var dist := rng.randf_range(LOOT_MIN_DIST, LOOT_MAX_DIST)
		loot.position = Vector2.from_angle(rng.randf() * TAU) * dist
		loot.setup(dist)
		loot_root.add_child(loot)


## Heavy relics: also deterministic, but the host streams their position.
func _spawn_relics() -> void:
	var relic_root := Node2D.new()
	relic_root.name = "Relics"
	add_child(relic_root)
	var rng := RandomNumberGenerator.new()
	rng.seed = LOOT_SEED + 1
	for i in RELIC_DISTANCES.size():
		var relic := HeavyRelic.new()
		relic.name = "Relic%d" % i
		relic.position = Vector2.from_angle(rng.randf() * TAU) * RELIC_DISTANCES[i]
		relic_root.add_child(relic)


## Tell a late joiner which loot is already gone.
func _send_loot_state(peer_id: int) -> void:
	var taken := PackedStringArray()
	for loot: Loot in get_tree().get_nodes_in_group("loot"):
		if not loot.active:
			taken.append(loot.name)
	if not taken.is_empty():
		sync_loot.rpc_id(peer_id, taken)


@rpc("authority", "reliable")
func sync_loot(taken: PackedStringArray) -> void:
	for loot_name in taken:
		var loot := loot_root.get_node_or_null(NodePath(loot_name)) as Loot
		if loot:
			loot.set_collected()


func _on_game_reset() -> void:
	for loot: Loot in get_tree().get_nodes_in_group("loot"):
		loot.reset()
	for relic: HeavyRelic in get_tree().get_nodes_in_group("relics"):
		relic.reset()
