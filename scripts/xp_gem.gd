extends Area3D
## XP gem. Attracted to player, gives XP on collection. 3D mesh with glow.

var xp_value: int = 1
var _attracted: bool = false
var _attract_speed: float = 400.0
var _target: Node3D = null
var _bob_time: float = 0.0
var _color: Color = Color(0.2, 1.0, 0.5)
var _spawn_scale: float = 0.0
var _body_mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	set_deferred("monitorable", true)

	var shape := SphereShape3D.new()
	shape.radius = 8.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.set_deferred("disabled", false)
	add_child(col)

	_bob_time = randf() * TAU

	# Diamond mesh (rotated box)
	_body_mesh = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(8, 8, 8)
	_body_mesh.mesh = mesh
	_body_mesh.rotation_degrees = Vector3(0, 45, 45)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mesh.material_override = mat
	_body_mesh.scale = Vector3.ZERO
	add_child(_body_mesh)

	# Pop-in animation
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "_spawn_scale", 1.0, 0.2)

func setup(value: int) -> void:
	xp_value = value
	if value >= 3:
		_color = Color(0.2, 0.5, 1.0)
	elif value >= 2:
		_color = Color(0.2, 0.8, 0.8)
	if _body_mesh and _body_mesh.material_override:
		var mat: StandardMaterial3D = _body_mesh.material_override
		mat.albedo_color = _color
		mat.emission = _color

func _process(delta: float) -> void:
	_bob_time += delta * 3.0

	if _attracted and _target and is_instance_valid(_target):
		var dir: Vector3 = (_target.global_position - global_position).normalized()
		dir.y = 0.0
		global_position += dir * _attract_speed * delta
		_attract_speed += 800.0 * delta

	global_position.y = 0.0

	# Scale pulse for bob effect (Y movement invisible in top-down)
	if _body_mesh:
		var pulse: float = 1.0 + sin(_bob_time) * 0.15
		_body_mesh.scale = Vector3.ONE * _spawn_scale * pulse

func attract_to(target: Node3D) -> void:
	_attracted = true
	_target = target

func collect() -> void:
	GameManager.add_xp(xp_value)
	var fx := Particles.pickup_collect(global_position, _color)
	get_tree().current_scene.add_child(fx)
	queue_free()
