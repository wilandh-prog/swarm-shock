extends Area3D
## Countermeasure flare. Drifts backward from player and attracts enemy missiles.

var _lifetime: float = 4.0
var _velocity: Vector3 = Vector3.ZERO

func _ready() -> void:
	add_to_group("flare")
	collision_layer = 0
	collision_mask = 0
	_build_visual()

func setup(vel: Vector3) -> void:
	_velocity = vel

func _process(delta: float) -> void:
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()
		return
	_velocity = _velocity.lerp(Vector3.ZERO, 2.0 * delta)
	_velocity.y -= 40.0 * delta
	global_position += _velocity * delta
	# Fade light near end
	if _lifetime < 1.0:
		scale = Vector3.ONE * (_lifetime)

func _build_visual() -> void:
	# Bright flare sphere
	var mesh_inst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 5.0
	sphere.height = 10.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.6, 0.1)
	mat.emission_energy_multiplier = 8.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = mat
	mesh_inst.mesh = sphere
	add_child(mesh_inst)

	# Spark trail
	var sparks := CPUParticles3D.new()
	sparks.amount = 20
	sparks.lifetime = 0.8
	sparks.one_shot = false
	sparks.direction = Vector3.ZERO
	sparks.spread = 180.0
	sparks.initial_velocity_min = 15.0
	sparks.initial_velocity_max = 50.0
	sparks.gravity = Vector3(0, -30, 0)
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 5.0
	sparks.color = Color(1.0, 0.7, 0.2)
	sparks.set_deferred("emitting", true)
	add_child(sparks)

	# Thick smoke trail — uses sphere mesh for visible 3D puffs
	var smoke := CPUParticles3D.new()
	smoke.amount = 30
	smoke.lifetime = 2.0
	smoke.one_shot = false
	smoke.explosiveness = 0.0
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 50.0
	smoke.initial_velocity_min = 15.0
	smoke.initial_velocity_max = 40.0
	smoke.gravity = Vector3(0, 20, 0)
	smoke.damping_min = 15.0
	smoke.damping_max = 30.0
	smoke.scale_amount_min = 8.0
	smoke.scale_amount_max = 18.0
	smoke.scale_amount_curve = Particles._create_fade_curve()

	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 3.0
	smoke_mesh.height = 6.0
	smoke_mesh.radial_segments = 8
	smoke_mesh.rings = 4
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.85, 0.82, 0.75, 0.7)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	smoke_mesh.material = smoke_mat
	smoke.mesh = smoke_mesh

	smoke.color = Color(0.9, 0.87, 0.8)
	smoke.color_ramp = Particles._create_fade_gradient(Color(0.85, 0.82, 0.75))
	smoke.set_deferred("emitting", true)
	add_child(smoke)

	# Glow light
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.1)
	light.light_energy = 3.0
	light.omni_range = 150.0
	add_child(light)
