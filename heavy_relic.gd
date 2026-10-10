class_name HeavyRelic
extends Node2D
## A heavy alien relic far out in the field, worth a fortune but too heavy for
## one diver. Players grab it with E; it only moves while TWO or more are
## holding on, and it drifts towards the middle of its carriers, so they have
## to agree on a direction ("left... no, YOUR left!"). Haul it into the station
## for a big team payout.
##
## Spawned identically on every peer by world.gd. The host simulates it and
## streams its position and carriers to everyone with sync_state.

const VALUE := 500
const GRAB_RANGE := 90.0             # how close you must be to grab it
const GRIP_RANGE := 220.0            # carriers further away than this lose their grip
const CARRIERS_NEEDED := 2
const CARRIER_SPEED_FACTOR := 0.5    # carriers fly at half speed
const RESPAWN_TIME := 90.0
const SYNC_INTERVAL := 0.05          # host sends state 20 times a second
const GLOW := Color(0.4, 1.0, 0.9)

var home := Vector2.ZERO
var active := true
var carriers := PackedInt32Array()   # peer ids of the players holding on
var _net_pos := Vector2.ZERO
var _sync_timer := 0.0


func _ready() -> void:
	add_to_group("relics")
	home = position
	_net_pos = position
	add_child(Station.make_light(Vector2.ZERO, 130.0, GLOW, 0.9))


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_simulate(delta)


func _process(delta: float) -> void:
	if not multiplayer.is_server():
		position = position.lerp(_net_pos, minf(1.0, delta * 12.0))
	visible = active
	queue_redraw()


func is_carried_by(peer_id: int) -> bool:
	return peer_id in carriers


func reset() -> void:
	active = true
	carriers.clear()
	position = home
	_net_pos = home


# --- Host side ---------------------------------------------------------------

func _simulate(delta: float) -> void:
	if active:
		_drop_lost_carriers()
		if carriers.size() >= CARRIERS_NEEDED:
			var center := Vector2.ZERO
			for id in carriers:
				center += _player(id).global_position
			center /= carriers.size()
			var speed := GameState.max_speed() * CARRIER_SPEED_FACTOR * 1.1
			position = position.move_toward(center, speed * delta)
			if absf(position.x) < Station.HALF_SIZE.x and absf(position.y) < Station.HALF_SIZE.y:
				_deliver()
	_sync_timer -= delta
	if _sync_timer <= 0.0:
		_sync_timer = SYNC_INTERVAL
		sync_state.rpc(position, carriers, active)


## Carriers who left the game, blacked out or drifted too far let go.
func _drop_lost_carriers() -> void:
	for id in carriers.duplicate():
		var player := _player(id)
		if player == null or player.is_blacked_out:
			_release(id)
		elif player.global_position.distance_to(position) > GRIP_RANGE:
			_release(id)
			GameState.announce.rpc("%s lost their grip on the relic!" % player.display_name)


func _deliver() -> void:
	var names := PackedStringArray()
	for id in carriers:
		names.append(_player(id).display_name)
	GameState.add_money(VALUE)
	GameState.announce.rpc("%s hauled home an alien relic! +$%d" % [" & ".join(names), VALUE])
	carriers.clear()
	active = false
	position = home
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(func() -> void: active = true)


func _release(peer_id: int) -> void:
	var index := carriers.find(peer_id)
	if index >= 0:
		carriers.remove_at(index)


@rpc("any_peer", "call_local", "reliable")
func request_grab() -> void:
	var id := multiplayer.get_remote_sender_id()
	var player := _player(id)
	if not multiplayer.is_server() or not active or player == null or is_carried_by(id):
		return
	if player.is_blacked_out or player.global_position.distance_to(position) > GRAB_RANGE + 30.0:
		return
	for relic: HeavyRelic in get_tree().get_nodes_in_group("relics"):
		relic._release(id)  # you can only hold one relic at a time
	carriers.append(id)
	if carriers.size() == CARRIERS_NEEDED:
		GameState.announce.rpc("The relic is moving! Haul it home together!")


@rpc("any_peer", "call_local", "reliable")
func request_release() -> void:
	if multiplayer.is_server():
		_release(multiplayer.get_remote_sender_id())


# --- Everyone ----------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered")
func sync_state(pos: Vector2, new_carriers: PackedInt32Array, is_active: bool) -> void:
	_net_pos = pos
	carriers = new_carriers
	active = is_active
	if position.distance_to(pos) > 400.0:
		position = pos  # it was delivered and reset: jump, don't glide


func _player(peer_id: int) -> Player:
	return get_node_or_null("../../Players/%d" % peer_id) as Player


func _draw() -> void:
	# Tether beams to everyone holding on.
	for id in carriers:
		var player := _player(id)
		if player:
			draw_line(Vector2.ZERO, to_local(player.global_position), Color(GLOW, 0.7), 2.0)

	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
	var frame := PackedVector2Array()
	for i in 8:
		frame.append(Vector2.from_angle(TAU * (i + 0.5) / 8.0) * 30.0)
	draw_colored_polygon(frame, Color(0.25, 0.27, 0.35))
	draw_polyline(frame + PackedVector2Array([frame[0]]), Color(0.5, 0.55, 0.65), 2.0)
	var crystal := PackedVector2Array([Vector2(0, -22), Vector2(14, 0), Vector2(0, 22), Vector2(-14, 0)])
	draw_colored_polygon(crystal, GLOW.darkened(1.0 - pulse))
	draw_colored_polygon(PackedVector2Array([Vector2(0, -22), Vector2(6, -4), Vector2(-4, 0)]), Color(1, 1, 1, 0.7))
	draw_arc(Vector2.ZERO, 40.0, 0.0, TAU, 40, Color(GLOW, 0.4 * pulse), 2.0)

	var font := ThemeDB.fallback_font
	var label := "HEAVY RELIC  %d/%d" % [mini(carriers.size(), CARRIERS_NEEDED), CARRIERS_NEEDED]
	draw_string(font, Vector2(-80, -48), label, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, GLOW)
	draw_string(font, Vector2(-80, 58), "$%d" % VALUE, HORIZONTAL_ALIGNMENT_CENTER, 160.0, 13, Color(1.0, 0.85, 0.3))
