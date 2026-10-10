extends CanvasLayer
## HUD, built in code: team money, oxygen, cargo and distance; the shop and the
## radar (only while inside the station); the event feed; the blackout fade;
## and the win screen.

const RADAR_SIZE := 320.0
const RADAR_RANGE := 3600.0  # world distance shown at the radar's edge
const PX_PER_METRE := 10.0
const SHOP := [
	{"kind": "oxygen", "name": "Oxygen Tank", "key": "1", "action": "buy_oxygen"},
	{"kind": "speed", "name": "Jetpack", "key": "2", "action": "buy_speed"},
	{"kind": "part", "name": "Pod Repair Part", "key": "3", "action": "buy_part"},
	{"kind": "tether", "name": "Longer Tether", "key": "4", "action": "buy_tether"},
]
const GOLD := Color(1.0, 0.85, 0.3)
const RADAR_GREEN := Color(0.3, 1.0, 0.5)

var world: Node2D
var player: Player

var money_label: Label
var stats_label: Label
var depth_label: Label
var oxygen_bar: ProgressBar
var oxygen_fill: StyleBoxFlat
var health_bar: ProgressBar
var arrow: Control
var crew_label: Label
var hint_label: Label
var ip_label: Label
var shop_panel: PanelContainer
var shop_buttons := {}
var radar: Control
var feed: VBoxContainer
var fade: ColorRect
var win_panel: ColorRect
var win_stats: Label
var restart_button: Button
var waiting_label: Label
var vignette: ShaderMaterial
var confetti: CPUParticles2D
var _upgrades_seen := 0  # to play a sound whenever anyone buys something

## Red glow around the screen edges; `strength` 0..1 is set every frame.
const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float edge = smoothstep(0.3, 0.75, distance(UV, vec2(0.5)));
	COLOR = vec4(0.85, 0.05, 0.05, edge * strength);
}
"""


func _ready() -> void:
	world = get_parent()
	_build_ui()
	GameState.state_changed.connect(_refresh_shop)
	GameState.message.connect(show_message)
	GameState.game_won.connect(_on_game_won)
	GameState.game_reset.connect(_on_game_reset)
	_refresh_shop()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = world.get_node_or_null("Players/%d" % multiplayer.get_unique_id()) as Player
		if player == null:
			hint_label.text = "Connecting..."
			return
		player.blackout_changed.connect(_on_blackout)
		if multiplayer.is_server() and not NetworkManager.local_ips().is_empty():
			ip_label.text = "Join code: %s   (if that fails: %s)" % [NetworkManager.my_code(), NetworkManager.my_code(2)]

	var ratio := clampf(player.oxygen / GameState.oxygen_capacity(), 0.0, 1.0)
	var low_air := ratio < Player.LOW_OXYGEN and not player.in_station
	oxygen_bar.value = ratio
	oxygen_fill.bg_color = Color(1.0, 0.3, 0.25) if low_air else Color(0.35, 0.8, 1.0)
	health_bar.value = player.health / Player.MAX_HEALTH
	money_label.text = "TEAM $%d" % GameState.money
	stats_label.text = "Cargo: %d  ($%d)\nTank %d/3   Jetpack %d/3   Tether %d/3   Pod %d/%d" % [
		player.carried_count, player.carried_value, GameState.oxygen_level, GameState.speed_level,
		GameState.tether_level, GameState.parts, GameState.PARTS_NEEDED]
	depth_label.text = "Distance from station: %d m" % int(player.global_position.length() / PX_PER_METRE)

	shop_panel.visible = player.in_station
	radar.visible = player.on_radar
	arrow.queue_redraw()
	if radar.visible:
		radar.queue_redraw()
	crew_label.text = _crew_status()
	hint_label.text = _hint(low_air)
	var urgent := low_air or player.rope_strain > 1.1
	# Pulse the red vignette when you're suffocating or your rope is about to snap.
	var danger := 1.0 if player.oxygen <= 0.0 and not player.in_station else (0.6 if player.rope_strain > 1.1 else 0.0)
	var pulse := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)
	vignette.set_shader_parameter("strength", 0.0 if player.is_blacked_out else danger * pulse)
	hint_label.modulate.a = 0.55 + 0.45 * sin(Time.get_ticks_msec() / 90.0) if urgent else 1.0

	if player.in_station and not player.is_blacked_out:
		for item in SHOP:
			if Input.is_action_just_pressed(item["action"]):
				_buy(item["kind"])


func show_message(text: String) -> void:
	var label := _label(feed, 16, Color.WHITE)
	label.text = text
	if feed.get_child_count() > 6:
		feed.get_child(0).queue_free()
	var tween := label.create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)


func _buy(kind: String) -> void:
	if is_instance_valid(player) and player.in_station and not GameState.has_won():
		GameState.request_buy(kind)


func _refresh_shop() -> void:
	var upgrades := GameState.oxygen_level + GameState.speed_level + GameState.tether_level + GameState.parts
	if upgrades > _upgrades_seen and is_instance_valid(player):
		Sounds.play(self, "buy", -4.0)
	_upgrades_seen = upgrades
	for item in SHOP:
		var button: Button = shop_buttons[item["kind"]]
		var cost := GameState.cost_of(item["kind"])
		var level := GameState.level_of(item["kind"])
		if cost < 0:
			button.text = "%s - MAXED" % item["name"]
			button.disabled = true
			continue
		var next := "%d/%d" % [level + 1, GameState.PARTS_NEEDED] if item["kind"] == "part" else "Lv %d" % (level + 1)
		button.text = "[%s] %s %s   $%d" % [item["key"], item["name"], next, cost]
		button.disabled = cost > GameState.money


func _crew_status() -> String:
	if player.on_radar:
		return "You're on the radar: talk your divers to the gold and back!"
	var spotters := PackedStringArray()
	for other: Player in get_tree().get_nodes_in_group("players"):
		if other != player and other.on_radar:
			spotters.append(other.display_name)
	if spotters.is_empty():
		return "Nobody is on the radar. You're flying blind!"
	return "On the radar: " + ", ".join(spotters)


func _hint(low_air: bool) -> String:
	if player.is_blacked_out:
		return ""
	if player.in_station:
		if player.carried_value > 0:
			return "Press E to sell your cargo ($%d)" % player.carried_value
		if player.on_radar:
			return "R: leave the radar and clip back onto a tether"
		return "R: take the radar (unclips your tether)   or walk out an airlock to dive"
	if player.oxygen <= 0.0:
		return "OUT OF AIR - YOU'RE SUFFOCATING!"
	if player.rope_strain > 1.1:
		return "TETHER STRAINING - STAY TOGETHER OR IT SNAPS!"
	if low_air:
		return "LOW OXYGEN - GET BACK TO THE STATION!"
	var relic := player.carried_relic()
	if relic:
		if relic.carriers.size() < HeavyRelic.CARRIERS_NEEDED:
			return "Too heavy! Get a crewmate to grab it too  (E: let go)"
		return "Haul it home together!  (E: let go)"
	if player.nearest_relic():
		return "E: grab the heavy relic (needs %d crew)" % HeavyRelic.CARRIERS_NEEDED
	return _rope_status()


func _rope_status() -> String:
	var names := PackedStringArray()
	for link in Tethers.links_of(player):
		var other := Tethers.other_end(link, player)
		names.append(other.display_name if other else "the station")
	return "Tethered to " + " & ".join(names) if not names.is_empty() else ""


## Arrow next to the player pointing home: big when close, smaller further out.
func _draw_arrow() -> void:
	if not is_instance_valid(player) or player.in_station or player.is_blacked_out:
		return
	var dist := player.global_position.length()
	var size := lerpf(1.0, 0.35, clampf(dist / 3000.0, 0.0, 1.0))
	var dir := -player.global_position.normalized()
	var center := player.get_global_transform_with_canvas().origin + dir * 70.0
	var side := dir.orthogonal()
	var points := PackedVector2Array([
		center + dir * 26.0 * size,
		center - dir * 14.0 * size + side * 18.0 * size,
		center - dir * 6.0 * size,
		center - dir * 14.0 * size - side * 18.0 * size,
	])
	arrow.draw_colored_polygon(points, Color(GOLD, 0.9))
	arrow.draw_polyline(points + PackedVector2Array([points[0]]), Color(0, 0, 0, 0.8), 2.0)


func _on_blackout(is_out: bool) -> void:
	var tween := create_tween()
	tween.tween_property(fade, "modulate:a", 1.0 if is_out else 0.0, 0.3 if is_out else 0.6)


func _on_game_won() -> void:
	# Let everyone watch the escape pod launch first (station.gd), then celebrate.
	await get_tree().create_timer(Station.POD_LAUNCH_TIME).timeout
	if not GameState.has_won():
		return  # the host restarted in the meantime
	win_panel.visible = true
	confetti.emitting = true
	Sounds.play(self, "win")
	win_stats.text = "All %d repair parts fitted. The escape pod blasts off!\nTeam salvage sold: $%d" % [GameState.PARTS_NEEDED, GameState.total_earned]
	restart_button.visible = multiplayer.is_server()
	waiting_label.visible = not multiplayer.is_server()


func _on_game_reset() -> void:
	win_panel.visible = false
	confetti.emitting = false
	_refresh_shop()


# --- Radar -------------------------------------------------------------------

func _draw_radar() -> void:
	var font := ThemeDB.fallback_font
	var r := RADAR_SIZE * 0.5
	var c := Vector2(r, r + 28.0)
	radar.draw_string(font, Vector2(0, 18), "STATION RADAR", HORIZONTAL_ALIGNMENT_CENTER, RADAR_SIZE, 18, RADAR_GREEN)
	radar.draw_circle(c, r, Color(0.02, 0.1, 0.05, 0.88))
	for ring in [1000.0, 2000.0, 3000.0]:
		radar.draw_arc(c, ring / RADAR_RANGE * r, 0.0, TAU, 64, Color(RADAR_GREEN, 0.2), 1.0)
		radar.draw_string(font, c + Vector2(3, -ring / RADAR_RANGE * r + 11), "%dm" % int(ring / PX_PER_METRE), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(RADAR_GREEN, 0.45))
	var sweep := fmod(Time.get_ticks_msec() / 700.0, TAU)
	radar.draw_line(c, c + Vector2.from_angle(sweep) * r, Color(RADAR_GREEN, 0.35), 2.0)

	for loot: Loot in get_tree().get_nodes_in_group("loot"):
		if loot.active:
			radar.draw_circle(_radar_point(loot.position, c, r), 1.5 + loot.tier, Loot.TIER_COLORS[loot.tier])
	for relic: HeavyRelic in get_tree().get_nodes_in_group("relics"):
		if relic.active:
			var p := _radar_point(relic.position, c, r)
			radar.draw_colored_polygon(PackedVector2Array([p + Vector2(0, -7), p + Vector2(6, 0), p + Vector2(0, 7), p + Vector2(-6, 0)]), HeavyRelic.GLOW)
			radar.draw_string(font, p + Vector2(8, 4), "$%d" % HeavyRelic.VALUE, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HeavyRelic.GLOW)
	radar.draw_rect(Rect2(c - Vector2(7, 4), Vector2(14, 8)), Color.WHITE)

	# Tethers between divers (or to the station).
	for link in Tethers.links(get_tree()):
		var a: Player = link[0]
		var b: Player = link[1]
		var end := _radar_point(b.global_position, c, r) if b else c
		radar.draw_line(_radar_point(a.global_position, c, r), end, Color(0.85, 0.8, 0.65, 0.7), 1.5)

	for other: Player in get_tree().get_nodes_in_group("players"):
		if other.is_blacked_out:
			continue
		var pos := _radar_point(other.global_position, c, r)
		var air := int(100.0 * other.oxygen / GameState.oxygen_capacity())
		radar.draw_circle(pos, 4.5, other.color)
		radar.draw_string(font, pos + Vector2(7, 4), "%s %d%%" % [other.display_name, air], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
			Color(1.0, 0.35, 0.3) if air < Player.LOW_OXYGEN * 100.0 else Color.WHITE)
	radar.draw_arc(c, r, 0.0, TAU, 96, Color(RADAR_GREEN, 0.8), 2.0)

	var legend_y := c.y + r + 20.0
	for tier in Loot.TIER_NAMES.size():
		var x := 10.0 + tier * 75.0
		radar.draw_circle(Vector2(x, legend_y - 4.0), 2.5 + tier, Loot.TIER_COLORS[tier])
		radar.draw_string(font, Vector2(x + 8.0, legend_y), Loot.TIER_NAMES[tier], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(RADAR_GREEN, 0.8))
	var heavy := Vector2(235.0, legend_y - 4.0)
	radar.draw_colored_polygon(PackedVector2Array([heavy + Vector2(0, -6), heavy + Vector2(5, 0), heavy + Vector2(0, 6), heavy + Vector2(-5, 0)]), HeavyRelic.GLOW)
	radar.draw_string(font, heavy + Vector2(8, 4), "2-crew", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(RADAR_GREEN, 0.8))


func _radar_point(world_pos: Vector2, center: Vector2, radius: float) -> Vector2:
	var offset := world_pos / RADAR_RANGE * radius
	return center + offset.limit_length(radius - 4.0)


#  Building the UI 

func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vignette_rect := ColorRect.new()
	vignette_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	var vignette_shader := Shader.new()
	vignette_shader.code = VIGNETTE_SHADER
	vignette = ShaderMaterial.new()
	vignette.shader = vignette_shader
	vignette_rect.material = vignette
	root.add_child(vignette_rect)

	# Top left: team money, oxygen, cargo and distance.
	var stats := VBoxContainer.new()
	stats.position = Vector2(16, 10)
	root.add_child(stats)
	money_label = _label(stats, 30, GOLD)
	var air_row := HBoxContainer.new()
	stats.add_child(air_row)
	_label(air_row, 16, Color.WHITE).text = "O2 "
	oxygen_bar = ProgressBar.new()
	oxygen_bar.custom_minimum_size = Vector2(240, 18)
	oxygen_bar.max_value = 1.0
	oxygen_bar.step = 0.0
	oxygen_bar.show_percentage = false
	oxygen_fill = StyleBoxFlat.new()
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.6)
	oxygen_bar.add_theme_stylebox_override("fill", oxygen_fill)
	oxygen_bar.add_theme_stylebox_override("background", bar_bg)
	air_row.add_child(oxygen_bar)
	var health_row := HBoxContainer.new()
	stats.add_child(health_row)
	_label(health_row, 16, Color.WHITE).text = "HP "
	health_bar = ProgressBar.new()
	health_bar.custom_minimum_size = Vector2(240, 12)
	health_bar.max_value = 1.0
	health_bar.step = 0.0
	health_bar.show_percentage = false
	var health_fill := StyleBoxFlat.new()
	health_fill.bg_color = Color(0.9, 0.25, 0.3)
	health_bar.add_theme_stylebox_override("fill", health_fill)
	health_bar.add_theme_stylebox_override("background", bar_bg)
	health_row.add_child(health_bar)
	stats_label = _label(stats, 16, Color.WHITE)
	depth_label = _label(stats, 16, Color(0.6, 0.9, 1.0))

	crew_label = _label(root, 16, RADAR_GREEN)
	crew_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	crew_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	crew_label.offset_top = 12.0

	hint_label = _label(root, 22, Color.WHITE)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -64.0
	hint_label.offset_bottom = -28.0
	ip_label = _label(root, 22, Color(1.0, 0.85, 0.3))
	ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ip_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	ip_label.offset_top = -34.0
	ip_label.offset_bottom = -6.0
	ip_label.offset_right = -16.0

	# Left: the shop (only inside the station).
	shop_panel = PanelContainer.new()
	shop_panel.position = Vector2(16, 175)
	root.add_child(shop_panel)
	var shop_box := VBoxContainer.new()
	shop_panel.add_child(shop_box)
	_label(shop_box, 18, GOLD).text = "STATION SHOP"
	for item in SHOP:
		var button := Button.new()
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(290, 34)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_buy.bind(item["kind"]))
		shop_box.add_child(button)
		shop_buttons[item["kind"]] = button
	_label(shop_box, 13, Color(0.8, 0.8, 0.8)).text = "E: sell cargo    1 / 2 / 3 / 4: buy"

	# Right: the radar (only inside the station).
	radar = Control.new()
	radar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	radar.draw.connect(_draw_radar)
	root.add_child(radar)
	radar.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	radar.offset_left = -RADAR_SIZE - 16.0
	radar.offset_right = -16.0
	radar.offset_top = 10.0
	radar.offset_bottom = 10.0 + RADAR_SIZE + 60.0

	# Arrow pointing home (only outside the station).
	arrow = Control.new()
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	arrow.draw.connect(_draw_arrow)
	root.add_child(arrow)

	# Bottom left: event feed.
	feed = VBoxContainer.new()
	feed.alignment = BoxContainer.ALIGNMENT_END
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(feed)
	feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	feed.offset_left = 16.0
	feed.offset_right = 640.0
	feed.offset_top = -280.0
	feed.offset_bottom = -72.0

	# Blackout fade.
	fade = ColorRect.new()
	fade.color = Color.BLACK
	fade.modulate.a = 0.0
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fade)
	var out_label := _label(fade, 44, Color(1.0, 0.3, 0.25))
	out_label.text = "OUT OF OXYGEN"
	out_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	out_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	out_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# Win screen.
	win_panel = ColorRect.new()
	win_panel.color = Color(0.02, 0.02, 0.08, 0.88)
	win_panel.visible = false
	win_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(win_panel)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	win_panel.add_child(center)
	var win_box := VBoxContainer.new()
	win_box.add_theme_constant_override("separation", 14)
	center.add_child(win_box)
	var title := _label(win_box, 60, GOLD)
	title.text = "YOU MADE IT HOME!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	win_stats = _label(win_box, 20, Color.WHITE)
	win_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_button = Button.new()
	restart_button.text = "Play again"
	restart_button.custom_minimum_size = Vector2(0, 44)
	restart_button.pressed.connect(func() -> void: GameState.restart.rpc())
	win_box.add_child(restart_button)
	waiting_label = _label(win_box, 16, Color(0.7, 0.75, 0.85))
	waiting_label.text = "Waiting for the host to start another round..."
	waiting_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var menu_button := Button.new()
	menu_button.text = "Back to menu"
	menu_button.custom_minimum_size = Vector2(0, 44)
	menu_button.pressed.connect(func() -> void: NetworkManager.leave())
	win_box.add_child(menu_button)

	# Confetti falling across the whole win screen.
	confetti = CPUParticles2D.new()
	confetti.emitting = false
	confetti.amount = 160
	confetti.lifetime = 5.0
	confetti.position = Vector2(get_viewport().get_visible_rect().size.x / 2.0, -20.0)
	confetti.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	confetti.emission_rect_extents = Vector2(get_viewport().get_visible_rect().size.x / 2.0, 1.0)
	confetti.direction = Vector2.DOWN
	confetti.spread = 25.0
	confetti.gravity = Vector2(0.0, 120.0)
	confetti.initial_velocity_min = 40.0
	confetti.initial_velocity_max = 140.0
	confetti.angular_velocity_min = -360.0
	confetti.angular_velocity_max = 360.0
	confetti.scale_amount_min = 4.0
	confetti.scale_amount_max = 8.0
	var confetti_colors := Gradient.new()
	confetti_colors.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	confetti_colors.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8])
	confetti_colors.colors = PackedColorArray([GOLD, RADAR_GREEN, Color(0.3, 0.7, 1.0), Color(1.0, 0.4, 0.6), Color(0.8, 0.5, 1.0)])
	confetti.color_initial_ramp = confetti_colors
	win_panel.add_child(confetti)


func _label(parent: Control, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	return label
