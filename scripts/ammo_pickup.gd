extends Area3D
## Missile ammo pickup. Grants +2 missiles on collect.

var _attracted: bool = false
var _attract_speed: float = 350.0
var _target: Node3D = null
var _bob_time: float = 0.0
var _color: Color = Color(1.0, 0.4, 0.15)
var _spawn_scale: float = 0.0
var _body_mesh: MeshInstance3D

func _ready() -> void:
	add_to_group("pickup")
	collision_layer = 16
	collision_mask = 0
	monitoring = false
	set_deferred("monitorable", true)

	var shape := SphereShape3D.new()
	shape.radius = 10.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.set_deferred("disabled", false)
	add_child(col)

	_bob_time = randf() * TAU

	# Missile-shaped: small cylinder with cone tip
	_body_mesh = MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.5
	mesh.bottom_radius = 2.0
	mesh.height = 12.0
	mesh.radial_segments = 6
	_body_mesh.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _color
	mat.emission_enabled = true
	mat.emission = _color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mesh.material_override = mat
	_body_mesh.scale = Vector3.ZERO
	add_child(_body_mesh)

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "_spawn_scale", 1.0, 0.25)

func _process(delta: float) -> void:
	_bob_time += delta * 4.0

	if _attracted and _target and is_instance_valid(_target):
		var dir: Vector3 = (_target.global_position - global_position).normalized()
		dir.y = 0.0
		global_position += dir * _attract_speed * delta
		_attract_speed += 600.0 * delta

	global_position.y = 0.0

	if _body_mesh:
		var pulse: float = 1.0 + sin(_bob_time) * 0.2
		_body_mesh.scale = Vector3.ONE * _spawn_scale * pulse
		_body_mesh.rotation_degrees.y += delta * 120.0

func attract_to(target: Node3D) -> void:
	_attracted = true
	_target = target

func collect() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.missile_ammo = mini(player.missile_ammo + 2, player.missile_ammo_max)
	var fx := Particles.pickup_collect(global_position, _color)
	get_tree().current_scene.add_child(fx)
	queue_free()
