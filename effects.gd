class_name Effects
extends RefCounted
## Particle effects. burst() fires a one-off puff of glowing pixels that deletes
## itself when done; thruster() makes the looping jetpack exhaust. Both glow
## (unshaded + additive), so they show up even in the dark.


## A one-off burst of particles at a world position.
static func burst(from: Node, pos: Vector2, color: Color, amount := 24, speed := 140.0, size := 3.0, lifetime := 0.7) -> void:
	var particles := CPUParticles2D.new()
	particles.position = pos
	particles.z_index = 5
	particles.material = _glow()
	particles.one_shot = true
	particles.explosiveness = 0.9
	particles.amount = amount
	particles.lifetime = lifetime
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = speed * 0.3
	particles.initial_velocity_max = speed
	particles.damping_min = speed * 0.5
	particles.damping_max = speed
	particles.scale_amount_min = size * 0.5
	particles.scale_amount_max = size
	particles.color_ramp = _fade(color)
	from.get_tree().current_scene.add_child(particles)
	particles.emitting = true
	particles.finished.connect(particles.queue_free)


## A looping exhaust stream. Turn it on and off with `emitting` and aim it with
## `direction`. Particles stay where they were puffed out, leaving a trail.
static func thruster(color: Color, size := 3.0) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.material = _glow()
	particles.local_coords = false
	particles.emitting = false
	particles.amount = 40
	particles.lifetime = 0.45
	particles.spread = 18.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 60.0
	particles.initial_velocity_max = 130.0
	particles.scale_amount_min = size * 0.5
	particles.scale_amount_max = size
	particles.color_ramp = _fade(color)
	return particles


## Bright colour fading to transparent over the particle's life.
static func _fade(color: Color) -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, color.lightened(0.3))
	gradient.set_color(1, Color(color, 0.0))
	return gradient


static func _glow() -> CanvasItemMaterial:
	var material := CanvasItemMaterial.new()
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return material
