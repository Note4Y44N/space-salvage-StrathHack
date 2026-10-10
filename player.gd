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

# Sprites: "Spacers" by zwonky (CC0). Each sheet is 7 frames across and one
# suit colour per row (green, orange, red, blue); one sheet each for male/female.
const SHEETS := [preload("res://sprites/spacer_male.png"), preload("res://sprites/spacer_female.png")]
const SUIT_COLORS := [Color(0.64, 0.81, 0.15), Color(0.92, 0.54, 0.19), Color(0.88, 0.43, 0.55), Color(0.19, 0.64, 0.95)]
const LOOKS := 8  # 4 suit colours x 2 sheets
const SPRITE_SCALE := 2.5
enum Frame { IDLE, RUN_1, RUN_2, CLIMB, REACH, DEAD, FLOAT }

# Tethers (who is roped to whom: tethers.gd). Past its length a rope pulls you
# back; stretch it to Tethers.SNAP_STRETCH and it snaps and you black out.
const ROPE_STIFFNESS := 6.0    # pull strength per pixel of stretch...
const MAX_ROPE_PULL := 320.0   # ...capped below jetpack thrust, so pushing on can still snap it
const ROPE_DAMPING := 2.0      # how quickly moving-apart speed is soaked up
const REEL_SPEED := 90.0       # a new rope starts slack and reels in this fast (px/s)

# Health: with an empty tank you suffocate over about 5 seconds.
const MAX_HEALTH := 100.0
const SUFFOCATE_RATE := 20.0   # health lost per second with no air
const HEAL_RATE := 10.0        # health regained per second while breathing (5x in the station)

# Replicated from the authority to everyone (see _setup_replication).
var net_pos := Vector2.ZERO
var oxygen := 25.0
var carried_value := 0
var carried_count := 0
var facing := 1
var thrust := Vector2.ZERO
var in_station := false  # the station's body_entered sets this on spawn
var is_blacked_out := false
var health := MAX_HEALTH
var on_radar := false  # radar duty: sees the radar, not tethered

var display_name := "Spacer"  # set by the spawn function on every peer
var look := 0                 # which of the 8 sprite looks, also set by the spawn function
var color := Color.WHITE
var _shake := 0.0
var _lamp: PointLight2D
var _sprite: Sprite2D
var _exhaust: CPUParticles2D
var _last_pos := Vector2.ZERO
var _anim_time := 0.0
var _rope_rest := {}     # rope partner id (0 = station) -> current rope length
var rope_strain := 0.0  # how stretched our tightest rope is (1.0 = just taut), for the HUD

@onready var camera: Camera2D = $Camera2D


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())
	_setup_replication()


func _setup_replication() -> void:
	var config := SceneReplicationConfig.new()
	for property in ["net_pos", "oxygen", "carried_value", "carried_count", "facing", "thrust", "in_station", "is_blacked_out", "health", "on_radar"]:
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
	# Looks 0-3 alternate male/female across the four suit colours, so the
	# first four players all get different colours.
	var suit := look % 4
	color = SUIT_COLORS[suit]
	_sprite = Sprite2D.new()
	_sprite.texture = SHEETS[(look % 2 + look / 4) % 2]
	_sprite.hframes = 7
	_sprite.vframes = 4
	_sprite.frame = suit * 7
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.position = Vector2(0, -3)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # crisp pixel art
	add_child(_sprite)
	_last_pos = global_position

	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 11.0
	capsule.height = 34.0
	shape.shape = capsule
	add_child(shape)
	_lamp = Station.make_light(Vector2(0, -8), LIGHT_RADIUS, Color(0.85, 0.92, 1.0), LAMP_ENERGY)
	add_child(_lamp)
	_exhaust = Effects.thruster(Color(1.0, 0.55, 0.2))
	_exhaust.show_behind_parent = true
	add_child(_exhaust)

	net_pos = global_position
	oxygen = GameState.oxygen_capacity()
	if is_multiplayer_authority():
		camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
		camera.position_smoothing_enabled = true
		camera.position_smoothing_speed = 8.0
		camera.enabled = true
		camera.make_current()
		GameState.game_reset.connect(_respawn)
		GameState.game_won.connect(_on_game_won)
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
	_pull_ropes(delta)
	if is_blacked_out:
		return  # a rope snapped
	move_and_slide()
	net_pos = global_position
	_update_oxygen(delta)
	if Input.is_action_just_pressed("interact"):
		if in_station:
			sell()
		else:
			toggle_grab()
	if Input.is_action_just_pressed("radar") and in_station:
		set_on_radar(not on_radar)


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
	_animate(delta)
	# Jetpack exhaust, puffed out of our back, opposite to the way we thrust.
	_exhaust.emitting = thrust != Vector2.ZERO and not is_blacked_out
	_exhaust.position = Vector2(-10.0 * facing, 4.0)
	_exhaust.direction = -thrust
	queue_redraw()


## Picks the sprite frame. Runs on every peer, using only replicated state, so
## everyone sees the same animation.
func _animate(delta: float) -> void:
	var walk_speed := absf(global_position.x - _last_pos.x) / maxf(delta, 0.0001)
	_last_pos = global_position
	_anim_time += delta

	var pose: int = Frame.IDLE
	if is_blacked_out:
		pose = Frame.DEAD
	elif carried_relic():
		pose = Frame.REACH  # arms out, hauling the relic
	elif in_station:
		if thrust != Vector2.ZERO:
			pose = Frame.CLIMB  # jetpack boots
		elif walk_speed > 20.0:
			pose = Frame.RUN_1 if fmod(_anim_time, 0.3) < 0.15 else Frame.RUN_2
	else:
		pose = Frame.CLIMB if thrust != Vector2.ZERO else Frame.FLOAT

	_sprite.frame = (look % 4) * 7 + pose
	_sprite.flip_h = facing < 0
	var low_air := not in_station and oxygen < GameState.oxygen_capacity() * LOW_OXYGEN
	var flash_speed := 80.0 if oxygen <= 0.0 else 200.0  # faster when suffocating
	var flashing := low_air and fmod(Time.get_ticks_msec() / flash_speed, 2.0) < 1.0
	_sprite.modulate = Color(1.0, 0.45, 0.45) if flashing else Color.WHITE


func _move_in_station(input: Vector2, delta: float) -> void:
	velocity.x = move_toward(velocity.x, input.x * WALK_SPEED, WALK_ACCEL * delta)
	velocity.y = minf(velocity.y + STATION_GRAVITY * delta, 700.0)
	var boosting := input.y < -0.1
	if boosting:
		velocity.y = maxf(velocity.y - JETPACK_ACCEL * delta, -JETPACK_MAX_RISE)
	thrust = Vector2.UP if boosting else Vector2.ZERO


func _move_in_space(input: Vector2, delta: float) -> void:
	var load_factor := maxf(MIN_LOAD_FACTOR, 1.0 - CARRY_SLOWDOWN * carried_count)
	if carried_relic():
		load_factor = minf(load_factor, HeavyRelic.CARRIER_SPEED_FACTOR)
	velocity += input * GameState.thrust() * load_factor * delta
	velocity = velocity.limit_length(GameState.max_speed() * load_factor)
	velocity *= maxf(0.0, 1.0 - SPACE_DRAG * delta)
	thrust = input


## Air drains outside the station. With an empty tank you lose health instead,
## and black out when it runs out (about 5 seconds).
func _update_oxygen(delta: float) -> void:
	if in_station:
		oxygen = minf(GameState.oxygen_capacity(), oxygen + OXYGEN_REFILL_RATE * delta)
		health = minf(MAX_HEALTH, health + HEAL_RATE * 5.0 * delta)
		return
	oxygen = maxf(0.0, oxygen - delta)
	if oxygen > 0.0:
		health = minf(MAX_HEALTH, health + HEAL_RATE * delta)
		return
	health -= SUFFOCATE_RATE * delta
	if health <= 0.0:
		_black_out()


## Ropes pull us back when stretched past their length and snap (blacking us
## out) when stretched too far. Each player only moves itself; the partner's
## game does the same from its side, so both get pulled together.
func _pull_ropes(delta: float) -> void:
	rope_strain = 0.0
	var current := {}
	for link in Tethers.links_of(self):
		var other := Tethers.other_end(link, self)
		if other and other.is_blacked_out:
			continue
		var key := other.name.to_int() if other else 0
		var anchor := other.global_position if other else Tethers.STATION_ANCHOR
		var length := Tethers.rope_length(other == null)
		var offset := anchor - global_position
		var dist := offset.length()
		# A new rope starts as long as the gap and reels in, so being paired
		# with someone far away doesn't snap it straight away.
		var rest: float = _rope_rest.get(key, maxf(length, dist))
		rest = maxf(length, move_toward(rest, length, REEL_SPEED * delta))
		current[key] = rest
		rope_strain = maxf(rope_strain, dist / rest)
		if dist > rest * Tethers.SNAP_STRETCH:
			if other:
				other.rope_snapped.rpc_id(key)  # it's one rope: they go down too
			_black_out("%s's tether snapped" % display_name, "snap")
			return
		if dist > rest:
			var dir := offset / dist
			velocity += dir * minf((dist - rest) * ROPE_STIFFNESS, MAX_ROPE_PULL) * delta
			var moving_apart := -velocity.dot(dir)
			if moving_apart > 0.0:
				velocity += dir * moving_apart * minf(1.0, ROPE_DAMPING * delta)
	_rope_rest = current


## Sent by our rope partner's game when the rope between us snapped.
@rpc("any_peer", "call_remote", "reliable")
func rope_snapped() -> void:
	if is_multiplayer_authority() and not is_blacked_out:
		_black_out("%s's tether snapped" % display_name, "snap")


## R in the station: take the radar (and unclip your tether), or hand it back.
func set_on_radar(value: bool) -> void:
	if value == on_radar:
		return
	on_radar = value
	_rope_rest.clear()
	if on_radar:
		GameState.announce.rpc("%s is on the radar" % display_name)


## Called by the station on every peer; only the authority's value counts.
func set_in_station(value: bool) -> void:
	if is_multiplayer_authority():
		in_station = value
		if not value:
			set_on_radar(false)  # leaving the station means leaving the radar


func can_collect() -> bool:
	return not is_blacked_out


func add_cargo(value: int) -> void:
	carried_value += value
	carried_count += 1


## E outside the station: grab the nearest heavy relic, or let go of it.
func toggle_grab() -> void:
	var relic := carried_relic()
	if relic:
		relic.request_release.rpc_id(1)
		return
	relic = nearest_relic()
	if relic:
		relic.request_grab.rpc_id(1)


func carried_relic() -> HeavyRelic:
	for relic: HeavyRelic in get_tree().get_nodes_in_group("relics"):
		if relic.is_carried_by(name.to_int()):
			return relic
	return null


## The closest active relic within grabbing range, or null.
func nearest_relic() -> HeavyRelic:
	for relic: HeavyRelic in get_tree().get_nodes_in_group("relics"):
		if relic.active and global_position.distance_to(relic.global_position) <= HeavyRelic.GRAB_RANGE:
			return relic
	return null


func sell() -> void:
	if carried_value <= 0:
		return
	GameState.add_money.rpc_id(1, carried_value)
	GameState.announce.rpc("%s sold %d salvage for $%d" % [display_name, carried_count, carried_value])
	carried_value = 0
	carried_count = 0
	fx.rpc("sell")
	_shake = 0.15


## One-off visual effects on this player that everyone should see.
@rpc("authority", "call_local", "reliable")
func fx(kind: String) -> void:
	match kind:
		"sell":  # coin fountain
			Effects.burst(self, global_position, Color(1.0, 0.85, 0.3), 45, 240.0, 4.0, 0.9)
		"poof":  # last gasp of air
			Effects.burst(self, global_position, Color(0.7, 0.85, 1.0), 40, 170.0, 5.0, 0.8)
		"snap":  # bits of rope flying everywhere
			Effects.burst(self, global_position, Color(1.0, 0.3, 0.2), 30, 300.0, 3.0, 0.6)
			Effects.burst(self, global_position, Color(0.85, 0.8, 0.65), 20, 200.0, 2.0, 0.9)


## We won: zoom the camera out so everyone sees the escape pod launch.
func _on_game_won() -> void:
	create_tween().tween_property(camera, "zoom", Vector2(0.55, 0.55), 1.2).set_trans(Tween.TRANS_SINE)


func _black_out(reason := "", effect := "poof") -> void:
	fx.rpc(effect)
	is_blacked_out = true
	oxygen = 0.0
	health = 0.0
	velocity = Vector2.ZERO
	var what := reason if reason != "" else "%s ran out of air" % display_name
	if carried_value > 0:
		GameState.announce.rpc("%s and lost $%d of salvage!" % [what, carried_value])
	else:
		GameState.announce.rpc(what + "!")
	carried_value = 0
	carried_count = 0
	_shake = 0.6
	blackout_changed.emit(true)
	get_tree().create_timer(BLACKOUT_TIME).timeout.connect(_respawn)


## Back to the station with a full tank and empty pockets (blackout or new round).
func _respawn() -> void:
	var station := get_tree().get_first_node_in_group("station") as Station
	global_position = station.spawn_point(look) if station else Vector2.ZERO
	net_pos = global_position
	velocity = Vector2.ZERO
	oxygen = GameState.oxygen_capacity()
	health = MAX_HEALTH
	carried_value = 0
	carried_count = 0
	_rope_rest.clear()
	is_blacked_out = false
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.reset_smoothing()
	blackout_changed.emit(false)


# Drawn behind the sprite: ropes, jetpack flame and loot sack. Then the name tag.
func _draw() -> void:
	if not is_blacked_out:
		# Each rope is drawn once, by the first player on it.
		for link in Tethers.links_of(self):
			var other: Player = link[1]
			if link[0] == self and not (other and other.is_blacked_out):
				var end := to_local(other.global_position if other else Tethers.STATION_ANCHOR)
				_draw_rope(end, Tethers.rope_length(other == null))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2(facing, 1.0))  # mirror when facing left

		# Jetpack flame from the back, pointing away from the thrust direction.
		if thrust != Vector2.ZERO:
			var flame_dir := Vector2(-thrust.x * facing, -thrust.y).normalized()
			var nozzle := Vector2(-10.0, 4.0)
			var side := flame_dir.orthogonal() * 4.0
			var length := 14.0 + randf() * 9.0
			draw_colored_polygon(PackedVector2Array([nozzle + side, nozzle - side, nozzle + flame_dir * length]), Color(1.0, 0.5, 0.15))
			draw_colored_polygon(PackedVector2Array([nozzle + side * 0.5, nozzle - side * 0.5, nozzle + flame_dir * length * 0.6]), Color(1.0, 0.92, 0.45))

		# Loot sack on the back grows with cargo.
		if carried_count > 0:
			var sack_radius := 6.0 + minf(carried_count, 10.0) * 0.9
			var sack := Vector2(-14.0 - sack_radius * 0.5, 2.0)
			draw_circle(sack, sack_radius, Color(0.55, 0.38, 0.2))
			draw_circle(sack + Vector2(-2, -sack_radius * 0.6), 2.5, Color(1.0, 0.85, 0.3))

		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(-60, -30), display_name, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 12, color.lightened(0.3))
	if carried_value > 0:
		draw_string(font, Vector2(-60, 32), "$%d" % carried_value, HORIZONTAL_ALIGNMENT_CENTER, 120.0, 11, Color(1.0, 0.85, 0.3))


## A rope from us to `end`: wobbly when slack, turning red as it nears snapping.
func _draw_rope(end: Vector2, length: float) -> void:
	var strain := end.length() / length
	var color := Color(0.85, 0.8, 0.65)
	if strain > 1.0:
		color = color.lerp(Color(1.0, 0.2, 0.15), clampf((strain - 1.0) / (Tethers.SNAP_STRETCH - 1.0), 0.0, 1.0))
	var slack := clampf((length - end.length()) * 0.08, 0.0, 30.0)
	var normal := end.orthogonal().normalized()
	var wobble := sin(Time.get_ticks_msec() / 500.0)
	var points := PackedVector2Array()
	for i in 17:
		var t := i / 16.0
		points.append(end * t + normal * sin(t * PI) * slack * wobble)
	draw_polyline(points, color, 2.0)
