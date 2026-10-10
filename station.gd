class_name Station
extends Area2D
## The home station, drawn side-on like a Terraria house and centred on the
## origin. Inside the pressurised hab there is gravity, air refills, and the
## shop and radar open. Calls set_in_station(true/false) on players.

const HALF_SIZE := Vector2(320.0, 150.0)  # pressurised interior; the deck is the bottom edge
const AIRLOCK_HEIGHT := 110.0
const WALL := 16.0
const BEACON_POS := Vector2(270.0, -276.0)

var _beacon: PointLight2D


func _ready() -> void:
	add_to_group("station")
	z_index = -1
	collision_layer = 0
	collision_mask = 2  # players

	var area_shape := CollisionShape2D.new()
	var area_rect := RectangleShape2D.new()
	area_rect.size = HALF_SIZE * 2.0
	area_shape.shape = area_rect
	add_child(area_shape)

	# The deck is one-way, so you can jetpack up through it from underneath.
	var deck := StaticBody2D.new()
	deck.collision_layer = 1
	deck.collision_mask = 0
	var deck_shape := CollisionShape2D.new()
	var deck_rect := RectangleShape2D.new()
	deck_rect.size = Vector2(HALF_SIZE.x * 2.0, 16.0)
	deck_shape.shape = deck_rect
	deck_shape.position = Vector2(0.0, HALF_SIZE.y + 8.0)
	deck_shape.one_way_collision = true
	deck.add_child(deck_shape)
	add_child(deck)

	add_child(make_light(Vector2(0, -20), 560.0, Color(1.0, 0.93, 0.8), 0.9))
	_beacon = make_light(BEACON_POS, 170.0, Color(1.0, 0.25, 0.2), 1.0)
	add_child(_beacon)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _process(_delta: float) -> void:
	_beacon.energy = 0.4 + 0.8 * absf(sin(Time.get_ticks_msec() / 400.0))
	queue_redraw()


func spawn_point(slot: int) -> Vector2:
	return Vector2(-160.0 + float(absi(slot) % 8) * 45.0, HALF_SIZE.y - 30.0)


func _on_body_entered(body: Node2D) -> void:
	if body.has_method("set_in_station"):
		body.set_in_station(true)


func _on_body_exited(body: Node2D) -> void:
	if body.has_method("set_in_station"):
		body.set_in_station(false)


## Soft round PointLight2D. Used by the station and by players' helmet lamps.
static func make_light(pos: Vector2, radius: float, color: Color, energy: float) -> PointLight2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color.BLACK)
	gradient.add_point(0.45, Color(0.75, 0.75, 0.75))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	texture.width = 256
	texture.height = 256
	var light := PointLight2D.new()
	light.texture = texture
	light.texture_scale = radius * 2.0 / 256.0
	light.color = color
	light.energy = energy
	light.position = pos
	return light


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var hx := HALF_SIZE.x
	var hy := HALF_SIZE.y
	var hull := Color(0.33, 0.36, 0.43)
	var hull_dark := Color(0.2, 0.22, 0.28)
	var wall := Color(0.56, 0.59, 0.66)

	# Solar panel wings.
	for side in [-1.0, 1.0]:
		var root_x: float = side * (hx + WALL)
		draw_rect(Rect2(minf(root_x, root_x + side * 230.0), -74.0, 230.0, 8.0), hull_dark)
		for i in 3:
			var px: float = root_x + side * (40.0 + i * 64.0)
			var panel := Rect2(px - 28.0, -130.0, 56.0, 120.0)
			draw_rect(panel, Color(0.12, 0.2, 0.45))
			for j in 4:
				draw_line(Vector2(panel.position.x, panel.position.y + j * 30.0), Vector2(panel.end.x, panel.position.y + j * 30.0), Color(0.3, 0.45, 0.8), 1.0)
			draw_rect(panel, Color(0.4, 0.5, 0.75), false, 2.0)

	# Hull and interior back wall.
	draw_rect(Rect2(-hx - WALL, -hy - WALL, (hx + WALL) * 2.0, (hy + WALL) * 2.0 + 16.0), hull)
	draw_rect(Rect2(-hx, -hy, hx * 2.0, hy * 2.0), wall)
	for x in range(-int(hx) + 80, int(hx), 80):
		draw_line(Vector2(x, -hy), Vector2(x, hy), wall.darkened(0.12), 2.0)
	draw_rect(Rect2(-hx, -12.0, hx * 2.0, 6.0), wall.darkened(0.2))

	# Portholes.
	for x in [-110.0, 0.0, 110.0]:
		var c := Vector2(x, -75.0)
		draw_circle(c, 27.0, hull_dark)
		draw_circle(c, 21.0, Color(0.02, 0.03, 0.09))
		draw_circle(c + Vector2(-7, -5), 1.5, Color.WHITE)
		draw_circle(c + Vector2(8, 6), 1.0, Color.WHITE)

	# Airlocks: openings in the side walls next to the deck.
	for side in [-1.0, 1.0]:
		var x: float = -hx - WALL if side < 0.0 else hx
		draw_rect(Rect2(x, hy - AIRLOCK_HEIGHT, WALL, AIRLOCK_HEIGHT), Color(0.03, 0.03, 0.06))
		for k in 4:
			var stripe := Color(0.95, 0.75, 0.1) if k % 2 == 0 else Color(0.1, 0.1, 0.1)
			draw_rect(Rect2(x + k * 4.0, hy - AIRLOCK_HEIGHT - 8.0, 4.0, 8.0), stripe)

	# Deck.
	draw_rect(Rect2(-hx - WALL, hy, (hx + WALL) * 2.0, 16.0), Color(0.24, 0.26, 0.3))
	for x in range(-int(hx), int(hx), 40):
		draw_rect(Rect2(x, hy, 20.0, 4.0), Color(0.95, 0.75, 0.1, 0.5))

	# Shop terminal (left) and radar console (right).
	_draw_console(Vector2(-225.0, hy), Color(1.0, 0.82, 0.3), "SHOP", font)
	_draw_console(Vector2(225.0, hy), Color(0.3, 1.0, 0.5), "RADAR", font)

	# Escape pod docked on the roof, with one light per repair part.
	var pod := Rect2(-80.0, -hy - WALL - 64.0, 160.0, 64.0)
	draw_circle(Vector2(pod.position.x, pod.get_center().y), 32.0, Color(0.85, 0.85, 0.9))
	draw_circle(Vector2(pod.end.x, pod.get_center().y), 32.0, Color(0.85, 0.85, 0.9))
	draw_rect(pod, Color(0.85, 0.85, 0.9))
	draw_circle(Vector2(pod.end.x + 6.0, pod.get_center().y - 6.0), 14.0, Color(0.2, 0.45, 0.7))
	for i in GameState.PARTS_NEEDED:
		var lit := i < GameState.parts
		draw_circle(Vector2(-48.0 + i * 24.0, pod.get_center().y + 10.0), 7.0, Color(0.3, 1.0, 0.4) if lit else Color(0.45, 0.1, 0.1))
	draw_string(font, Vector2(-100.0, pod.position.y - 40.0), "ESCAPE POD %d/%d" % [GameState.parts, GameState.PARTS_NEEDED], HORIZONTAL_ALIGNMENT_CENTER, 200.0, 18, Color.WHITE)

	# Antenna with a blinking beacon.
	draw_line(Vector2(BEACON_POS.x, -hy - WALL), BEACON_POS, hull_dark, 4.0)
	draw_circle(BEACON_POS, 7.0, Color(1.0, 0.3, 0.25).lerp(Color(0.4, 0.05, 0.05), 1.0 - _beacon.energy / 1.2))


func _draw_console(base: Vector2, screen_color: Color, label: String, font: Font) -> void:
	draw_rect(Rect2(base.x - 40.0, base.y - 60.0, 80.0, 60.0), Color(0.25, 0.27, 0.32))
	draw_rect(Rect2(base.x - 32.0, base.y - 104.0, 64.0, 44.0), Color(0.15, 0.16, 0.2))
	draw_rect(Rect2(base.x - 27.0, base.y - 99.0, 54.0, 34.0), screen_color.darkened(0.6))
	draw_string(font, Vector2(base.x - 40.0, base.y - 76.0), label, HORIZONTAL_ALIGNMENT_CENTER, 80.0, 14, screen_color)
