extends Node
## Autoload "GameState": the team's shared money, upgrades and pod repair parts.
## The host owns this state. Peers send requests (add_money, buy_upgrade) to the
## host, which validates them and broadcasts the result with sync_state, so two
## players buying at once can never double-spend.

signal state_changed
signal message(text: String)
signal game_won
signal game_reset

## Balance knobs. Index = current level.
const OXYGEN_COSTS := [100, 250, 500]
const SPEED_COSTS := [100, 250, 500]
const PART_COSTS := [250, 400, 550, 700, 900]
const TETHER_COSTS := [100, 250, 500]
const TETHER_LENGTHS := [500.0, 700.0, 950.0, 1250.0]  # rope between teammates, px (10 px = 1 m)
const OXYGEN_CAPACITY := [25.0, 38.0, 55.0, 75.0]  # seconds of air outside the station
const THRUST := [520.0, 640.0, 780.0, 940.0]        # zero-g acceleration, px/s^2
const MAX_SPEED := [300.0, 360.0, 430.0, 520.0]     # px/s
const PARTS_NEEDED := 5

var money := 7000
var oxygen_level := 0
var speed_level := 0
var parts := 0
var tether_level := 0
var total_earned := 0
var _celebrated := false  # game_won fires once per round (the host bumps parts before syncing)


func _ready() -> void:
	_register_inputs()


func oxygen_capacity() -> float:
	return OXYGEN_CAPACITY[oxygen_level]


func thrust() -> float:
	return THRUST[speed_level]


func tether_length() -> float:
	return TETHER_LENGTHS[tether_level]


func max_speed() -> float:
	return MAX_SPEED[speed_level]


func has_won() -> bool:
	return parts >= PARTS_NEEDED


func level_of(kind: String) -> int:
	match kind:
		"oxygen": return oxygen_level
		"speed": return speed_level
		"part": return parts
		"tether": return tether_level
	return 0


## Cost of the next level of an upgrade, or -1 if it is maxed out.
func cost_of(kind: String) -> int:
	var costs: Array = []
	match kind:
		"oxygen": costs = OXYGEN_COSTS
		"speed": costs = SPEED_COSTS
		"part": costs = PART_COSTS
		"tether": costs = TETHER_COSTS
	var level := level_of(kind)
	return costs[level] if level < costs.size() else -1


func request_buy(kind: String) -> void:
	buy_upgrade.rpc_id(1, kind, NetworkManager.player_name)


func send_state_to(peer_id: int) -> void:
	sync_state.rpc_id(peer_id, money, oxygen_level, speed_level, parts, tether_level, total_earned)


func reset() -> void:
	money = 0
	oxygen_level = 0
	speed_level = 0
	parts = 0
	tether_level = 0
	total_earned = 0
	_celebrated = false


@rpc("any_peer", "call_local", "reliable")
func add_money(amount: int) -> void:
	if not multiplayer.is_server() or amount <= 0:
		return
	money += amount
	total_earned += amount
	_broadcast()


@rpc("any_peer", "call_local", "reliable")
func buy_upgrade(kind: String, buyer_name: String) -> void:
	if not multiplayer.is_server() or has_won():
		return
	var cost := cost_of(kind)
	if cost < 0 or cost > money:
		return
	money -= cost
	match kind:
		"oxygen":
			oxygen_level += 1
			announce.rpc("%s upgraded the oxygen tanks!" % buyer_name)
		"speed":
			speed_level += 1
			announce.rpc("%s upgraded the jetpacks!" % buyer_name)
		"part":
			parts += 1
			announce.rpc("%s fitted pod repair part %d/%d!" % [buyer_name, parts, PARTS_NEEDED])
		"tether":
			tether_level += 1
			announce.rpc("%s bought longer tethers!" % buyer_name)
	_broadcast()


@rpc("authority", "call_local", "reliable")
func sync_state(new_money: int, new_oxygen_level: int, new_speed_level: int, new_parts: int, new_tether_level: int, new_total: int) -> void:
	money = new_money
	oxygen_level = new_oxygen_level
	speed_level = new_speed_level
	parts = new_parts
	tether_level = new_tether_level
	total_earned = new_total
	print("[%s] team $%d  tank %d  jetpack %d  parts %d" % [NetworkManager.player_name, money, oxygen_level, speed_level, parts])
	state_changed.emit()
	if has_won() and not _celebrated:
		_celebrated = true
		game_won.emit()


@rpc("any_peer", "call_local", "reliable")
func announce(text: String) -> void:
	print("[%s] %s" % [NetworkManager.player_name, text])
	message.emit(text)


## Host only: start a fresh round with everyone still connected.
@rpc("authority", "call_local", "reliable")
func restart() -> void:
	reset()
	state_changed.emit()
	game_reset.emit()


func _broadcast() -> void:
	sync_state.rpc(money, oxygen_level, speed_level, parts, tether_level, total_earned)


func _register_inputs() -> void:
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("move_up", [KEY_W, KEY_UP, KEY_SPACE])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("interact", [KEY_E])
	_add_action("buy_oxygen", [KEY_1])
	_add_action("buy_speed", [KEY_2])
	_add_action("buy_part", [KEY_3])
	_add_action("buy_tether", [KEY_4])
	_add_action("radar", [KEY_R])


func _add_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)
