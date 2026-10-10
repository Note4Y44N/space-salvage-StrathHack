class_name Loot
extends Area2D
## A piece of floating salvage, worth more the further it is from the station.
## Every peer spawns the same loot (same seed, same names), so only pickups are
## networked: the touching player asks the host, and the host decides who got
## it first and confirms to everyone.

const RESPAWN_TIME := 60.0
const TIER_NAMES := ["scrap", "gold bar", "relic"]
const TIER_COLORS := [Color(0.95, 0.78, 0.25), Color(1.0, 0.6, 0.1), Color(0.8, 0.45, 1.0)]

var value := 10
var tier := 0
var active := true
var _pending := false
var _home := Vector2.ZERO
var _phase := 0.0
var _time := 0.0


func setup(distance: float) -> void:
	tier = 0 if distance < 1400.0 else (1 if distance < 2400.0 else 2)
	value = int(10.0 + pow(distance / 100.0, 1.35))


func _ready() -> void:
	add_to_group("loot")
	collision_layer = 0
	collision_mask = 2  # players
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0 + tier * 4.0
	shape.shape = circle
	add_child(shape)
	body_entered.connect(_on_body_entered)
	_home = position
	_phase = position.x * 0.013 + position.y * 0.007


func _process(delta: float) -> void:
	if not active:
		return
	_time += delta
	position = _home + Vector2(0.0, sin(_time * 1.3 + _phase) * 6.0)
	rotation = sin(_time * 0.7 + _phase) * 0.5


func _on_body_entered(body: Node2D) -> void:
	var player := body as Player
	if active and not _pending and player and player.is_multiplayer_authority() and player.can_collect():
		_pending = true
		request_collect.rpc_id(1)
		get_tree().create_timer(1.0).timeout.connect(func() -> void: _pending = false)


## Runs on the host. First request wins; later ones are ignored.
@rpc("any_peer", "call_local", "reliable")
func request_collect() -> void:
	if multiplayer.is_server() and active:
		confirm.rpc(multiplayer.get_remote_sender_id())


@rpc("authority", "call_local", "reliable")
func confirm(collector_id: int) -> void:
	Effects.burst(self, global_position, TIER_COLORS[tier], 16 + tier * 12, 120.0 + tier * 60.0)
	set_collected()
	if collector_id == multiplayer.get_unique_id():
		var player := get_node_or_null("../../Players/%d" % collector_id) as Player
		if player:
			player.add_cargo(value)
			print("[%s] picked up %s (%s) worth $%d" % [player.display_name, TIER_NAMES[tier], name, value])
			_show_popup()


func set_collected() -> void:
	if not active:
		return
	active = false
	_pending = false
	visible = false
	set_deferred("monitoring", false)
	get_tree().create_timer(RESPAWN_TIME).timeout.connect(reset)


func reset() -> void:
	active = true
	visible = true
	set_deferred("monitoring", true)


func _show_popup() -> void:
	var label := Label.new()
	label.text = "+$%d" % value
	label.z_index = 5
	label.position = position + Vector2(-24.0, -36.0)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", TIER_COLORS[tier])
	get_parent().add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.9)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.9)
	tween.tween_callback(label.queue_free)


func _draw() -> void:
	var main: Color = TIER_COLORS[tier]
	var shine := main.lightened(0.45)
	match tier:
		0:  # gold scrap nugget
			draw_colored_polygon(PackedVector2Array([Vector2(-8, -3), Vector2(-3, -9), Vector2(6, -7), Vector2(9, 1), Vector2(3, 8), Vector2(-6, 6)]), main)
			draw_colored_polygon(PackedVector2Array([Vector2(-4, -3), Vector2(-1, -6), Vector2(3, -4), Vector2(0, -1)]), shine)
		1:  # gold bar
			draw_colored_polygon(PackedVector2Array([Vector2(-14, 7), Vector2(14, 7), Vector2(10, -6), Vector2(-10, -6)]), main)
			draw_colored_polygon(PackedVector2Array([Vector2(-10, -6), Vector2(10, -6), Vector2(8, -2), Vector2(-8, -2)]), shine)
		2:  # alien relic chest
			draw_arc(Vector2.ZERO, 21.0, 0.0, TAU, 32, Color(main, 0.5), 2.0)
			draw_rect(Rect2(-14, -10, 28, 20), Color(0.45, 0.3, 0.18))
			draw_rect(Rect2(-14, -3, 28, 4), Color(1.0, 0.8, 0.3))
			draw_circle(Vector2(0, -1), 5.0, main)
			draw_circle(Vector2(-1.5, -2.5), 1.5, shine)
