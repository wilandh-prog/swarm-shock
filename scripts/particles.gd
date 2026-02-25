class_name Particles
## Factory for creating various CPUParticles3D effects.
## All methods return a ready-to-add CPUParticles3D node.

static var _fireball_shader: Shader
static var _soft_circle: ImageTexture
static var _smoke_mesh: Mesh
static var _fire_quad: QuadMesh

static func _get_fireball_shader() -> Shader:
	if not _fireball_shader:
		_fireball_shader = load("res://shaders/fireball.gdshader")
	return _fireball_shader

static func _get_soft_circle() -> ImageTexture:
	if not _soft_circle:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var d := Vector2(x - 31.5, y - 31.5).length() / 31.5
				var a := clampf(exp(-d * d * 3.5), 0.0, 1.0) if d <= 1.0 else 0.0
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a))
		_soft_circle = ImageTexture.create_from_image(img)
	return _soft_circle

static func _get_smoke_mesh() -> Mesh:
	if not _smoke_mesh:
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material = mat
		_smoke_mesh = mesh
	return _smoke_mesh

static func _get_fire_quad() -> QuadMesh:
	if not _fire_quad:
		_fire_quad = QuadMesh.new()
		_fire_quad.size = Vector2(2.0, 2.0)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.vertex_color_use_as_albedo = true
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.albedo_texture = _get_soft_circle()
		_fire_quad.material = mat
	return _fire_quad

static func explosion(pos: Vector3, radius: float = 50.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var s: float = radius / 50.0

	# 1) Fireball shader sphere — ONE sphere, sized to final size
	var fireball := MeshInstance3D.new()
	var fb_mesh := SphereMesh.new()
	fb_mesh.radius = radius * 1.5
	fb_mesh.height = radius * 3.0
	fb_mesh.radial_segments = 32
	fb_mesh.rings = 16
	var fb_mat := ShaderMaterial.new()
	fb_mat.shader = _get_fireball_shader()
	fb_mat.set_shader_parameter("emission_strength", 8.0)
	fb_mat.set_shader_parameter("dissolve", 0.0)
	fb_mesh.material = fb_mat
	fireball.mesh = fb_mesh
	root.add_child(fireball)

	# 2) Fire particles around the fireball (soft additive quads)
	var fire := CPUParticles3D.new()
	fire.emitting = false
	fire.one_shot = true
	fire.amount = 40
	fire.lifetime = 0.9
	fire.explosiveness = 0.93
	fire.direction = Vector3(0, 1, 0)
	fire.spread = 140.0
	fire.initial_velocity_min = 50.0 * s
	fire.initial_velocity_max = 200.0 * s
	fire.gravity = Vector3(0, 70, 0)
	fire.damping_min = 50.0
	fire.damping_max = 100.0
	fire.scale_amount_min = 18.0 * s
	fire.scale_amount_max = 45.0 * s
	fire.scale_amount_curve = _create_explosion_scale_curve()
	var fire_grad := Gradient.new()
	fire_grad.set_color(0, Color(1.0, 1.0, 0.85, 1.0))
	fire_grad.add_point(0.15, Color(1.0, 0.8, 0.2, 1.0))
	fire_grad.add_point(0.4, Color(1.0, 0.4, 0.05, 0.85))
	fire_grad.add_point(0.7, Color(0.5, 0.1, 0.01, 0.4))
	fire_grad.set_color(1, Color(0.15, 0.03, 0.01, 0.0))
	fire.color_ramp = fire_grad
	fire.mesh = _get_fire_quad()
	root.add_child(fire)
	fire.set_deferred("emitting", true)

	# 3) Sparks
	var sparks := CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 40
	sparks.lifetime = 0.7
	sparks.explosiveness = 0.98
	sparks.direction = Vector3.ZERO
	sparks.spread = 180.0
	sparks.initial_velocity_min = 200.0 * s
	sparks.initial_velocity_max = 600.0 * s
	sparks.gravity = Vector3(0, -300, 0)
	sparks.damping_min = 80.0
	sparks.damping_max = 150.0
	sparks.scale_amount_min = 1.5 * s
	sparks.scale_amount_max = 4.0 * s
	sparks.scale_amount_curve = _create_fade_curve()
	var spark_grad := Gradient.new()
	spark_grad.set_color(0, Color(1.0, 1.0, 0.7, 1.0))
	spark_grad.add_point(0.2, Color(1.0, 0.7, 0.2, 0.9))
	spark_grad.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	sparks.color_ramp = spark_grad
	root.add_child(sparks)
	sparks.set_deferred("emitting", true)

	# 4) Smoke (single unified system — soft quad billboards)
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.one_shot = true
	smoke.amount = 40
	smoke.lifetime = 3.5
	smoke.explosiveness = 0.7
	smoke.randomness = 0.4
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 120.0
	smoke.initial_velocity_min = 60.0 * s
	smoke.initial_velocity_max = 250.0 * s
	smoke.gravity = Vector3(0, 35, 0)
	smoke.damping_min = 10.0
	smoke.damping_max = 40.0
	smoke.scale_amount_min = 50.0 * s
	smoke.scale_amount_max = 130.0 * s
	smoke.scale_amount_curve = _create_grow_fade_curve()
	var smoke_grad := Gradient.new()
	smoke_grad.set_color(0, Color(0.12, 0.10, 0.08, 0.6))
	smoke_grad.add_point(0.15, Color(0.10, 0.08, 0.06, 0.5))
	smoke_grad.add_point(0.4, Color(0.13, 0.10, 0.08, 0.3))
	smoke_grad.add_point(0.7, Color(0.15, 0.12, 0.10, 0.1))
	smoke_grad.set_color(1, Color(0.18, 0.15, 0.12, 0.0))
	smoke.color_ramp = smoke_grad
	smoke.mesh = _get_smoke_mesh()
	root.add_child(smoke)
	smoke.set_deferred("emitting", true)

	# 5) Shockwave ring
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = radius * 0.4
	ring_mesh.outer_radius = radius * 0.55
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 16
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.8, 0.3, 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.6, 0.2)
	ring_mat.emission_energy_multiplier = 5.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mesh.material = ring_mat
	ring.mesh = ring_mesh
	ring.rotation.x = deg_to_rad(90.0)
	root.add_child(ring)

	# 6) OmniLight
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 15.0
	light.omni_range = 150.0 * s
	root.add_child(light)

	root.ready.connect(func():
		# Fireball: quick scale up from 0.4 → 1.0, then dissolve
		fireball.scale = Vector3.ONE * 0.4
		var tw := root.create_tween()
		tw.tween_property(fireball, "scale", Vector3.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(fb_mat, "shader_parameter/dissolve", 1.0, 0.6).set_ease(Tween.EASE_IN)
		tw.tween_callback(fireball.queue_free)

		# Ring expand
		var tw_ring := root.create_tween().set_parallel(true)
		tw_ring.tween_property(ring, "scale", Vector3.ONE * 5.0, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw_ring.tween_property(ring_mat, "albedo_color:a", 0.0, 0.4)
		tw_ring.chain().tween_callback(ring.queue_free)

		# Light fade
		var tw_light := root.create_tween()
		tw_light.tween_property(light, "light_energy", 0.0, 0.6)
		tw_light.tween_callback(light.queue_free)

		root.create_tween().tween_callback(root.queue_free).set_delay(4.0)
	)

	return root

static func enemy_death(pos: Vector3, color: Color, size: float = 14.0) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var s: float = size / 14.0  # normalize to default enemy size

	# 1) Flash — bright white sphere that scales up and fades fast
	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 8.0 * s
	flash_mesh.height = 16.0 * s
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	var flash_mat := StandardMaterial3D.new()
	flash_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.9)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.9, 0.6)
	flash_mat.emission_energy_multiplier = 8.0
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash_mesh.material = flash_mat
	flash.mesh = flash_mesh
	root.add_child(flash)

	# 2) Fireball core — soft additive fire quads
	var fireball := CPUParticles3D.new()
	fireball.emitting = false
	fireball.one_shot = true
	fireball.amount = 35
	fireball.lifetime = 0.8
	fireball.explosiveness = 0.95
	fireball.direction = Vector3.ZERO
	fireball.spread = 180.0
	fireball.initial_velocity_min = 60.0 * s
	fireball.initial_velocity_max = 180.0 * s
	fireball.gravity = Vector3(0, 60, 0)
	fireball.damping_min = 60.0
	fireball.damping_max = 120.0
	fireball.scale_amount_min = 12.0 * s
	fireball.scale_amount_max = 30.0 * s
	fireball.scale_amount_curve = _create_fade_curve()
	var fire_grad := Gradient.new()
	fire_grad.set_color(0, Color(1.0, 1.0, 0.8, 1.0))
	fire_grad.add_point(0.15, Color(1.0, 0.8, 0.2, 1.0))
	fire_grad.add_point(0.4, Color(1.0, 0.4, 0.05, 0.8))
	fire_grad.add_point(0.7, Color(0.6, 0.15, 0.02, 0.5))
	fire_grad.set_color(1, Color(0.2, 0.05, 0.02, 0.0))
	fireball.color_ramp = fire_grad
	fireball.mesh = _get_fire_quad()
	root.add_child(fireball)
	fireball.set_deferred("emitting", true)

	# 3) Sparks/debris — fast bright streaks
	var sparks := CPUParticles3D.new()
	sparks.emitting = false
	sparks.one_shot = true
	sparks.amount = 40
	sparks.lifetime = 0.7
	sparks.explosiveness = 0.98
	sparks.direction = Vector3.ZERO
	sparks.spread = 180.0
	sparks.initial_velocity_min = 200.0 * s
	sparks.initial_velocity_max = 600.0 * s
	sparks.gravity = Vector3(0, -300, 0)
	sparks.damping_min = 80.0
	sparks.damping_max = 150.0
	sparks.scale_amount_min = 1.5 * s
	sparks.scale_amount_max = 4.0 * s
	sparks.scale_amount_curve = _create_fade_curve()
	var spark_grad := Gradient.new()
	spark_grad.set_color(0, Color(1.0, 1.0, 0.7, 1.0))
	spark_grad.add_point(0.2, Color(1.0, 0.7, 0.2, 0.9))
	spark_grad.set_color(1, Color(1.0, 0.3, 0.1, 0.0))
	sparks.color_ramp = spark_grad
	root.add_child(sparks)
	sparks.set_deferred("emitting", true)

	# 4) Smoke (single unified system — soft quad billboards)
	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.one_shot = true
	smoke.amount = 50
	smoke.lifetime = 4.0
	smoke.explosiveness = 0.5
	smoke.randomness = 0.5
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 100.0
	smoke.initial_velocity_min = 30.0 * s
	smoke.initial_velocity_max = 250.0 * s
	smoke.gravity = Vector3(0, 35, 0)
	smoke.damping_min = 5.0
	smoke.damping_max = 35.0
	smoke.scale_amount_min = 60.0 * s
	smoke.scale_amount_max = 160.0 * s
	smoke.scale_amount_curve = _create_grow_fade_curve()
	var smoke_grad := Gradient.new()
	smoke_grad.set_color(0, Color(0.12, 0.10, 0.08, 0.6))
	smoke_grad.add_point(0.15, Color(0.10, 0.08, 0.06, 0.5))
	smoke_grad.add_point(0.4, Color(0.13, 0.10, 0.08, 0.3))
	smoke_grad.add_point(0.7, Color(0.15, 0.12, 0.10, 0.1))
	smoke_grad.set_color(1, Color(0.18, 0.15, 0.12, 0.0))
	smoke.color_ramp = smoke_grad
	smoke.mesh = _get_smoke_mesh()
	root.add_child(smoke)
	smoke.set_deferred("emitting", true)

	# 5) Shockwave ring — expanding torus
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 6.0 * s
	ring_mesh.outer_radius = 10.0 * s
	ring_mesh.rings = 12
	ring_mesh.ring_segments = 12
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(1.0, 0.7, 0.3, 0.7)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(1.0, 0.5, 0.2)
	ring_mat.emission_energy_multiplier = 4.0
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mesh.material = ring_mat
	ring.mesh = ring_mesh
	ring.rotation.x = deg_to_rad(90.0)
	root.add_child(ring)

	# Light flash — brighter, larger
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.2)
	light.light_energy = 15.0
	light.omni_range = 150.0 * s
	root.add_child(light)

	# Animate after added to scene tree
	root.ready.connect(func():
		var tween := root.create_tween()
		tween.tween_property(flash, "scale", Vector3.ONE * 4.0, 0.08)
		tween.parallel().tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
		tween.parallel().tween_property(ring, "scale", Vector3.ONE * 8.0, 0.5).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.5)
		tween.parallel().tween_property(light, "light_energy", 0.0, 0.6)
		tween.tween_callback(root.queue_free).set_delay(4.5)
	)

	return root

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

static func _create_grow_fade_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(0.6, 0.5))
	c.add_point(Vector2(1.0, 0.0))
	return c

static func _create_explosion_scale_curve() -> Curve:
	## Fast grow, hold big, then shrink — makes fireball blobs feel chunky
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.2))
	c.add_point(Vector2(0.15, 1.0))
	c.add_point(Vector2(0.5, 0.9))
	c.add_point(Vector2(1.0, 0.0))
	return c
