class_name SpaceBackground
extends CanvasLayer
## The background: a pixel-art nebula shader, parallax stars and a planet.
## It sits on its own canvas layer behind the world, so the darkness
## (CanvasModulate in world.gd) doesn't affect it.
##
## The further the local player drifts from the station, the more the nebula
## shifts from calm blues to an ominous red ("danger" in nebula.gdshader).

const NEBULA_SHADER := preload("res://nebula.gdshader")
const SAFE_DISTANCE := 600.0     # no danger tint closer than this to the station
const DANGER_DISTANCE := 3000.0  # full danger tint this far out
const PARALLAX := 0.00025        # how fast the nebula scrolls as the camera moves
const COLOR_CHANGE_SPEED := 1.5  # how quickly the tint catches up (higher = snappier)

const CALM_COLORS := [Color(0.07, 0.06, 0.18), Color(0.14, 0.11, 0.32), Color(0.22, 0.2, 0.5), Color(0.3, 0.42, 0.7), Color(0.5, 0.75, 0.9)]
const DANGER_COLORS := [Color(0.12, 0.03, 0.05), Color(0.28, 0.05, 0.09), Color(0.5, 0.1, 0.1), Color(0.8, 0.32, 0.14), Color(1.0, 0.68, 0.3)]

var _nebula: ColorRect
var _material: ShaderMaterial
var _stars: Node2D
var _star_data: Array[Vector3] = []  # x, y in 0..1 screen space, z = depth
var _danger := 0.0


func _ready() -> void:
	layer = -10

	_material = ShaderMaterial.new()
	_material.shader = NEBULA_SHADER
	_material.set_shader_parameter("colors_calm", _gradient(CALM_COLORS))
	_material.set_shader_parameter("colors_danger", _gradient(DANGER_COLORS))
	_nebula = ColorRect.new()
	_nebula.material = _material
	_nebula.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_nebula)

	_stars = Node2D.new()
	_stars.draw.connect(_draw_stars)
	add_child(_stars)
	var rng := RandomNumberGenerator.new()
	rng.seed = 999
	for i in 220:
		_star_data.append(Vector3(rng.randf(), rng.randf(), rng.randf()))


func _process(delta: float) -> void:
	var size := get_viewport().get_visible_rect().size
	var camera_offset := get_viewport().get_canvas_transform().origin

	# How far out is the local player? 0 near the station, 1 in deep space.
	var target := 0.0
	var me := _local_player()
	if me:
		target = clampf((me.global_position.length() - SAFE_DISTANCE) / (DANGER_DISTANCE - SAFE_DISTANCE), 0.0, 1.0)
	_danger = lerpf(_danger, target, minf(1.0, delta * COLOR_CHANGE_SPEED))

	_nebula.size = size  # cover the whole screen, even after a window resize
	_material.set_shader_parameter("danger", _danger)
	_material.set_shader_parameter("offset", -camera_offset * PARALLAX)
	_material.set_shader_parameter("aspect", size.x / size.y)
	_stars.queue_redraw()


func _local_player() -> Player:
	for player: Player in get_tree().get_nodes_in_group("players"):
		if player.is_multiplayer_authority():
			return player
	return null


## Turns a list of colours into a texture the shader can look colours up in.
func _gradient(colors: Array) -> GradientTexture1D:
	var offsets := PackedFloat32Array()
	var packed_colors := PackedColorArray()
	for i in colors.size():
		offsets.append(float(i) / colors.size())
		packed_colors.append(colors[i])
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT  # hard pixel-art bands
	gradient.offsets = offsets
	gradient.colors = packed_colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _draw_stars() -> void:
	var size := get_viewport().get_visible_rect().size
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
