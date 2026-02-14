class_name Particles
## Factory for creating various CPUParticles3D effects.
## All methods return a ready-to-add CPUParticles3D node.

static func enemy_death(pos: Vector3, color: Color, size: float = 14.0) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.4
	p.explosiveness = 0.95
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 80.0
	p.initial_velocity_max = 200.0
	p.gravity = Vector3.ZERO
	p.damping_min = 100.0
	p.damping_max = 200.0
	p.scale_amount_min = size * 0.1
	p.scale_amount_max = size * 0.25
	p.scale_amount_curve = _create_fade_curve()
	p.color = color
	p.color_ramp = _create_fade_gradient(color)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.set_deferred("emitting", true)
	return p

static func chain_spark(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 10
	p.lifetime = 0.25
	p.explosiveness = 0.9
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector3.ZERO
	p.damping_min = 150.0
	p.damping_max = 250.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	p.color = Color(0.5, 0.85, 1.0)
	p.color_ramp = _create_fade_gradient(Color(0.5, 0.85, 1.0))
	p.position = pos
	p.finished.connect(p.queue_free)
	p.set_deferred("emitting", true)
	return p

static func pickup_collect(pos: Vector3, color: Color) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 8
	p.lifetime = 0.3
	p.explosiveness = 0.9
	p.direction = Vector3(0, 1, 0)
	p.spread = 60.0
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector3(0, -100, 0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	p.color_ramp = _create_fade_gradient(color)
	p.position = pos
	p.finished.connect(p.queue_free)
	p.set_deferred("emitting", true)
	return p

static func player_hit(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 16
	p.lifetime = 0.3
	p.explosiveness = 0.95
	p.direction = Vector3.ZERO
	p.spread = 180.0
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 250.0
	p.gravity = Vector3.ZERO
	p.damping_min = 200.0
	p.damping_max = 300.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	p.color = Color(1.0, 0.3, 0.3)
	p.color_ramp = _create_fade_gradient(Color(1.0, 0.3, 0.3))
	p.position = pos
	p.finished.connect(p.queue_free)
	p.set_deferred("emitting", true)
	return p

static func level_up_burst(pos: Vector3) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = 40
	p.lifetime = 0.8
	p.explosiveness = 0.85
	p.direction = Vector3(0, 1, 0)
	p.spread = 180.0
	p.initial_velocity_min = 100.0
	p.initial_velocity_max = 300.0
	p.gravity = Vector3(0, -200, 0)
	p.damping_min = 50.0
	p.damping_max = 100.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	p.color = Color(0.3, 0.7, 1.0)
	p.color_ramp = _create_rainbow_gradient()
	p.position = pos
	p.finished.connect(p.queue_free)
	p.set_deferred("emitting", true)
	return p

static func ambient_float() -> CPUParticles3D:
	## Continuous ambient floating particles. Add as child, not one-shot.
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = 4.0
	p.explosiveness = 0.0
	p.randomness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(1000, 2, 600)
	p.direction = Vector3(0, 1, 0)
	p.spread = 30.0
	p.initial_velocity_min = 10.0
	p.initial_velocity_max = 30.0
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	p.color = Color(0.3, 0.5, 0.8, 0.15)
	p.color_ramp = _create_fade_gradient(Color(0.3, 0.5, 0.8, 0.15))
	return p

# --- Gradient helpers ---

static func _create_fade_gradient(color: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(color, 1.0))
	g.add_point(0.5, Color(color, 0.6))
	g.set_color(1, Color(color, 0.0))
	return g

static func _create_rainbow_gradient() -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(0.3, 0.7, 1.0))
	g.add_point(0.3, Color(0.5, 0.3, 1.0))
	g.add_point(0.6, Color(1.0, 0.5, 0.3))
	g.set_color(1, Color(1.0, 0.9, 0.2, 0.0))
	return g

static func _create_fade_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c
