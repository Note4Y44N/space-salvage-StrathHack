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

## The "Discord game" twist: space is dark, divers only see their helmet light,
## and whoever is in the station gets the radar. Turn off to make it easy.
const DARKNESS_ENABLED := true
const DARKNESS_COLOR := Color(0.07, 0.07, 0.11)

@onready var players: Node2D = $Players
@onready var spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var station: Station = $Station

var loot_root: Node2D
var _stars: Node2D
var _star_data: Array[Vector3] = []  # x, y in 0..1 screen space, z = depth


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.01, 0.01, 0.03))
	spawner.spawn_path = spawner.get_path_to(players)
	spawner.spawn_function = _spawn_player
	_spawn_loot()
	_build_sky()

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


func _process(_delta: float) -> void:
	_stars.queue_redraw()


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
		spawner.spawn({"id": id, "name": player_name})


## Runs on every peer (host and clients) with the same data.
func _spawn_player(data: Variant) -> Node:
	var id: int = data["id"]
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(id)
	player.display_name = data["name"]
	player.position = station.spawn_point(id)
	return player


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	var player := players.get_node_or_null(str(id)) as Player
	if player:
		GameState.announce.rpc("%s left" % player.display_name)
		player.queue_free()


func _on_connection_failed() -> void:
	NetworkManager.leave("Could not connect to %s." % NetworkManager.join_ip)


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


# --- Sky and darkness --------------------------------------------------------

func _build_sky() -> void:
	# Stars live on their own canvas layer so the darkness doesn't hide them.
	var sky := CanvasLayer.new()
	sky.layer = -10
	add_child(sky)
	_stars = Node2D.new()
	_stars.draw.connect(_draw_sky)
	sky.add_child(_stars)
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	for i in 220:
		_star_data.append(Vector3(rng.randf(), rng.randf(), rng.randf()))

	if DARKNESS_ENABLED:
		var darkness := CanvasModulate.new()
		darkness.color = DARKNESS_COLOR
		add_child(darkness)


func _draw_sky() -> void:
	var size := get_viewport_rect().size
	var camera_offset := get_viewport().get_canvas_transform().origin
	# A distant planet that barely moves.
	var planet := Vector2(size.x * 0.9, size.y * 0.86) + camera_offset * 0.01
	_stars.draw_circle(planet, 64.0, Color(0.22, 0.13, 0.3))
	_stars.draw_circle(planet + Vector2(-12, -12), 50.0, Color(0.3, 0.18, 0.38))
	_stars.draw_arc(planet, 96.0, PI * 0.9, PI * 2.1, 48, Color(0.5, 0.4, 0.6, 0.5), 3.0)
	# Parallax stars: nearer (higher z) stars move faster and shine brighter.
	for star in _star_data:
		var parallax := 0.05 + star.z * 0.25
		var pos := Vector2(
			fposmod(star.x * size.x + camera_offset.x * parallax, size.x),
			fposmod(star.y * size.y + camera_offset.y * parallax, size.y))
		var star_size := 1.0 + floorf(star.z * 2.5)
		_stars.draw_rect(Rect2(pos, Vector2(star_size, star_size)), Color(1, 1, 1, 0.25 + star.z * 0.75))
