class_name Player
extends CharacterBody2D
## A salvager. The node is named after its peer id and that peer has authority:
## movement, oxygen and cargo run locally (instant feel) and are replicated to
## everyone else through the MultiplayerSynchronizer.
##
## Inside the station there is gravity (walk, plus jetpack "rocket boots").
## Outside it is zero-g drift.

signal blackout_changed(is_out: bool)  ## Local player only; drives the HUD fade.

const STATION_GRAVITY := 900.0
const WALK_SPEED := 230.0
const WALK_ACCEL := 1800.0
const JETPACK_ACCEL := 1600.0     # upward boost inside the station
const JETPACK_MAX_RISE := 330.0
const SPACE_DRAG := 0.35          # fraction of speed lost per second while drifting
const CARRY_SLOWDOWN := 0.04      # speed lost per carried item...
const MIN_LOAD_FACTOR := 0.5      # ...down to half speed
const OXYGEN_REFILL_RATE := 30.0  # seconds of air restored per second inside
const LOW_OXYGEN := 0.3           # fraction of the tank where warnings start
const BLACKOUT_TIME := 1.6
const LIGHT_RADIUS := 240.0
const LAMP_ENERGY := 1.1
const CAMERA_ZOOM := 1.6
const PALETTE := [
	Color(0.3, 0.75, 1.0), Color(1.0, 0.45, 0.35), Color(0.45, 1.0, 0.45), Color(1.0, 0.85, 0.3),
	Color(0.85, 0.5, 1.0), Color(1.0, 0.6, 0.85), Color(0.35, 1.0, 0.9), Color(1.0, 0.65, 0.2),
]

# Replicated from the authority to everyone (see _setup_replication).
var net_pos := Vector2.ZERO
var oxygen := 25.0
var carried_value := 0
var carried_count := 0
var facing := 1
var thrust := Vector2.ZERO
var in_station := false  # the station's body_entered sets this on spawn
var is_blacked_out := false

var display_name := "Spacer"  # set by the spawn function on every peer
var color := Color.WHITE
var _shake := 0.0
var _lamp: PointLight2D

@onready var camera: Camera2D = $Camera2D


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	_setup_replication()


func _setup_replication() -> void:
	var config := SceneReplicationConfig.new()
	for property in ["net_pos", "oxygen", "carried_value", "carried_count", "facing", "thrust", "in_station", "is_blacked_out"]:
		var path := NodePath(".:" + property)
		config.add_property(path)
		config.property_set_spawn(path, false)
		config.property_set_replication_mode(path, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	$MultiplayerSynchronizer.replication_config = config


func _ready() -> void:
	add_to_group("players")
	collision_layer = 2  # players
	collision_mask = 1   # station deck (players pass through each other)
	z_index = 1
	color = PALETTE[absi(name.to_int()) % PALETTE.size()]

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 11.0
	capsule.height = 34.0
	shape.shape = capsule
	add_child(shape)
	_lamp = Station.make_light(Vector2(0, -8), LIGHT_RADIUS, Color(0.85, 0.92, 1.0), LAMP_ENERGY)
	add_child(_lamp)

	net_pos = global_position
	oxygen = GameState.oxygen_capacity()
	if is_multiplayer_authority():
		camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 8.0
		camera.enabled = true
		camera.make_current()
		GameState.game_reset.connect(_respawn)
		print("[%s] spawned" % display_name)


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or is_blacked_out:
		return
	var input := DevBot.steer(self) if NetworkManager.bot_mode else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if absf(input.x) > 0.1:
		facing = 1 if input.x > 0.0 else -1
	if in_station:
		_move_in_station(input, delta)
	else:
		_move_in_space(input, delta)
	move_and_slide()
	net_pos = global_position
	_update_oxygen(delta)
	if in_station and Input.is_action_just_pressed("interact"):
		sell()


func _process(delta: float) -> void:
	if not is_multiplayer_authority():
		# Glide towards the authority's position instead of snapping every packet.
		if global_position.distance_to(net_pos) > 300.0:
			global_position = net_pos
		else:
			global_position = global_position.lerp(net_pos, minf(1.0, delta * 15.0))
	elif _shake > 0.0:
		_shake -= delta
		camera.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 24.0 * maxf(_shake, 0.0)
	else:
		camera.offset = Vector2.ZERO
	# Helmet lamp dims indoors so it doesn't blow out the station's own light.
	_lamp.energy = move_toward(_lamp.energy, 0.15 if in_station else LAMP_ENERGY, delta * 2.0)
	queue_redraw()


func _move_in_station(input: Vector2, delta: float) -> void:
	velocity.x = move_toward(velocity.x, input.x * WALK_SPEED, WALK_ACCEL * delta)
	velocity.y = minf(velocity.y + STATION_GRAVITY * delta, 700.0)
	var boosting := input.y < -0.1
	if boosting:
		velocity.y = maxf(velocity.y - JETPACK_ACCEL * delta, -JETPACK_MAX_RISE)
	thrust = Vector2.UP if boosting else Vector2.ZERO


func _move_in_space(input: Vector2, delta: float) -> void:
	var load_factor := maxf(MIN_LOAD_FACTOR, 1.0 - CARRY_SLOWDOWN * carried_count)
	velocity += input * GameState.thrust() * load_factor * delta
	velocity = velocity.limit_length(GameState.max_speed() * load_factor)
	velocity *= maxf(0.0, 1.0 - SPACE_DRAG * delta)
	thrust = input


func _update_oxygen(delta: float) -> void:
	if in_station:
		oxygen = minf(GameState.oxygen_capacity(), oxygen + OXYGEN_REFILL_RATE * delta)
		return
	oxygen -= delta
	if oxygen <= 0.0:
		_black_out()


## Called by the station on every peer; only the authority's value counts.
func set_in_station(value: bool) -> void:
	if is_multiplayer_authority():
		in_station = value


func can_collect() -> bool:
	return not is_blacked_out


func add_cargo(value: int) -> void:
	carried_value += value
	carried_count += 1


func sell() -> void:
	if carried_value <= 0:
		return
	GameState.add_money.rpc_id(1, carried_value)
	GameState.announce.rpc("%s sold %d salvage for $%d" % [display_name, carried_count, carried_value])
	carried_value = 0
	carried_count = 0


func _black_out() -> void:
	is_blacked_out = true
	oxygen = 0.0
	velocity = Vector2.ZERO
	if carried_value > 0:
		GameState.announce.rpc("%s ran out of air and lost $%d of salvage!" % [display_name, carried_value])
	else:
		GameState.announce.rpc("%s ran out of air!" % display_name)
	carried_value = 0
	carried_count = 0
	_shake = 0.6
	blackout_changed.emit(true)
	get_tree().create_timer(BLACKOUT_TIME).timeout.connect(_respawn)


## Back to the station with a full tank and empty pockets (blackout or new round).
func _respawn() -> void:
	var station := get_tree().get_first_node_in_group("station") as Station
	global_position = station.spawn_point(name.to_int()) if station else Vector2.ZERO
	net_pos = global_position
	velocity = Vector2.ZERO
	oxygen = GameState.oxygen_capacity()
	carried_value = 0
	carried_count = 0
	is_blacked_out = false
	camera.reset_smoothing()
	blackout_changed.emit(false)


# Placeholder art: a side-on astronaut, drawn facing right and mirrored by `facing`.
func _draw() -> void:
	if is_blacked_out:
		return
	var suit := Color(0.92, 0.93, 0.97)
	var low_air := not in_station and oxygen < GameState.oxygen_capacity() * LOW_OXYGEN
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))

	# Jetpack flame, pointing away from the thrust direction.
	if thrust != Vector2.ZERO:
		var flame_dir := Vector2(-thrust.x * facing, -thrust.y).normalized()
		var nozzle := Vector2(-12.0, 6.0)
		var side := flame_dir.orthogonal() * 4.0
		var length := 14.0 + randf() * 9.0
		draw_colored_polygon(PackedVector2Array([nozzle + side, nozzle - side, nozzle + flame_dir * length]), Color(1.0, 0.5, 0.15))
		draw_colored_polygon(PackedVector2Array([nozzle + side * 0.5, nozzle - side * 0.5, nozzle + flame_dir * length * 0.6]), Color(1.0, 0.92, 0.45))

	# Loot sack on the back grows with cargo.
	if carried_count > 0:
		var sack_radius := 6.0 + minf(carried_count, 10.0) * 0.9
		var sack := Vector2(-16.0 - sack_radius * 0.5, 2.0)
		draw_circle(sack, sack_radius, Color(0.55, 0.38, 0.2))
		draw_circle(sack + Vector2(-2, -sack_radius * 0.6), 2.5, Color(1.0, 0.85, 0.3))

	draw_rect(Rect2(-15, -8, 7, 18), Color(0.6, 0.62, 0.7))  # air tank
	draw_rect(Rect2(-15, -8, 7, 3), color)
	draw_rect(Rect2(-7, 8, 6, 9), suit.darkened(0.1))  # legs
	draw_rect(Rect2(1, 8, 6, 9), suit.darkened(0.1))
	draw_rect(Rect2(-7, 14, 6, 3), Color(0.3, 0.3, 0.35))  # boots
	draw_rect(Rect2(1, 14, 6, 3), Color(0.3, 0.3, 0.35))
	draw_rect(Rect2(-8, -5, 16, 15), suit)  # body
	draw_rect(Rect2(-8, 3, 16, 3), color)   # belt in team colour
	draw_rect(Rect2(2, -2, 9, 5), suit.darkened(0.05))  # arm
	draw_circle(Vector2(0, -11), 9.5, suit)  # helmet
	var flashing := low_air and fmod(Time.get_ticks_msec() / 200.0, 2.0) < 1.0
	draw_circle(Vector2(3.5, -11), 6.0, Color(1.0, 0.2, 0.15) if flashing else color.darkened(0.25))
	draw_circle(Vector2(5.5, -13), 1.8, Color(1, 1, 1, 0.8))

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, -26), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12, color.lightened(0.3))
	if carried_value > 0:
		draw_string(font, Vector2(-60, 32), "$%d" % carried_value, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 11, Color(1.0, 0.85, 0.3))
