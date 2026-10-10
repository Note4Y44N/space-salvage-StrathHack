class_name DevBot
extends RefCounted
## Autopilot for testing, enabled with `--bot` on the command line. It chases
## the nearest loot, heads home when full or low on air, sells, and buys
## whatever the team can afford. Handy for solo testing and headless runs.

const CARGO_TARGET := 3

static var _last_buy_msec := 0


static func steer(p: Player) -> Vector2:
	var capacity := GameState.oxygen_capacity()
	if p.in_station:
		if p.carried_value > 0:
			p.sell()
		_try_buy()
		if p.oxygen < capacity - 0.5:
			return Vector2.ZERO  # catch our breath
	var going_home := p.carried_count >= CARGO_TARGET or p.oxygen < capacity * 0.5
	if going_home:
		return Vector2.ZERO if p.in_station else _steer_to(p, Vector2.ZERO)

	var target := _nearest_loot(p)
	if target == null:
		return Vector2.ZERO
	if p.in_station:
		# Fly out of the roof or walk out of the nearest airlock.
		if target.global_position.y < -Station.HALF_SIZE.y:
			return Vector2.UP
		return Vector2.RIGHT if target.global_position.x >= 0.0 else Vector2.LEFT
	return _steer_to(p, target.global_position)


static func _steer_to(p: Player, target: Vector2) -> Vector2:
	var desired := p.global_position.direction_to(target) * GameState.max_speed()
	var correction := desired - p.velocity
	return correction.normalized() if correction.length() > 10.0 else Vector2.ZERO


static func _nearest_loot(p: Player) -> Loot:
	var best: Loot = null
	var best_dist := INF
	for loot: Loot in p.get_tree().get_nodes_in_group("loot"):
		var dist := p.global_position.distance_squared_to(loot.global_position)
		if loot.active and dist < best_dist:
			best = loot
			best_dist = dist
	return best


static func _try_buy() -> void:
	if Time.get_ticks_msec() - _last_buy_msec < 500:
		return
	for kind in ["oxygen", "speed", "part"]:
		var cost := GameState.cost_of(kind)
		if cost >= 0 and cost <= GameState.money:
			_last_buy_msec = Time.get_ticks_msec()
			GameState.request_buy(kind)
			return
