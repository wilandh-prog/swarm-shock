extends Area3D
## Homing missile. Steers toward locked target, explodes on hit or after lifetime.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 3000.0
var damage: float = 20.0
var explosion_radius: float = 50.0
var lifetime: float = 8.0
var _timer: float = 0.0
var _mesh_root: Node3D

# Homing
var homing_target: Node3D = null
var homing_turn_rate: float = 4.0
var is_enemy_missile: bool = false

func _ready() -> void:
	add_to_group("projectile")
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true

	var shape := SphereShape3D.new()
	shape.radius = 6.0
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

func setup(dir: Vector3, dmg: float, spd: float = 3000.0, _prc: int = 1, _col: Color = Color.WHITE) -> void:
	direction = dir.normalized()
	damage = dmg
	speed = spd
	_build_mesh()

func _build_mesh() -> void:
	_mesh_root = Node3D.new()

	# Missile body — red for enemy, white for player
	var body_color: Color = Color(0.9, 0.2, 0.15) if is_enemy_missile else Color(0.85, 0.88, 0.9)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = body_color
	mat.emission_enabled = true
	mat.emission = body_color
	mat.emission_energy_multiplier = 2.0 if is_enemy_missile else 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Sidewinder-style: long body
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 2.0
	body_mesh.bottom_radius = 2.5
	body_mesh.height = 40.0
	body_mesh.radial_segments = 8
	body_mesh.material = mat
	body.mesh = body_mesh
	_mesh_root.add_child(body)

	# Nose cone — long and pointed
	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 2.0
	nose_mesh.height = 8.0
	nose_mesh.radial_segments = 8
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.9, 0.2, 0.15) if is_enemy_missile else Color(0.7, 0.75, 0.8)
	nose_mat.emission_enabled = true
	nose_mat.emission = nose_mat.albedo_color
	nose_mat.emission_energy_multiplier = 2.0
	nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	nose_mesh.material = nose_mat
	nose.mesh = nose_mesh
	nose.position.y = 24.0
	_mesh_root.add_child(nose)

	# Tail fins — 4 cross fins
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = body_color.darkened(0.2)
	fin_mat.emission_enabled = true
	fin_mat.emission = fin_mat.albedo_color
	fin_mat.emission_energy_multiplier = 1.0
	fin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 4:
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.3, 6.0, 4.0)
		fin_mesh.material = fin_mat
		fin.mesh = fin_mesh
		fin.position.y = -17.0
		fin.rotation.y = deg_to_rad(90.0 * i)
		_mesh_root.add_child(fin)

	# Big exhaust flame
	var flame := MeshInstance3D.new()
	var flame_mesh := CylinderMesh.new()
	flame_mesh.top_radius = 2.2
	flame_mesh.bottom_radius = 0.4
	flame_mesh.height = 10.0
	flame_mesh.radial_segments = 8
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.7, 0.1)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.05)
	flame_mat.emission_energy_multiplier = 6.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flame_mesh.material = flame_mat
	flame.mesh = flame_mesh
	flame.position.y = -25.0
	_mesh_root.add_child(flame)

	_update_mesh_orientation()
	add_child(_mesh_root)

func _update_mesh_orientation() -> void:
	if not _mesh_root:
		return
	var fwd := direction.normalized()
	if fwd.length() < 0.01:
		return
	var right := fwd.cross(Vector3.UP).normalized()
	if right.length() < 0.01:
		right = Vector3.RIGHT
	_mesh_root.basis = Basis(right, fwd, Vector3.UP)

func _process(delta: float) -> void:
	# Homing: steer toward target
	if homing_target and is_instance_valid(homing_target):
		var to_target := homing_target.global_position - global_position
		var dist := to_target.length()
		if dist > 1.0:
			var desired := to_target / dist
			# Smoothly rotate direction toward target (full 3D)
			direction = direction.slerp(desired, homing_turn_rate * delta).normalized()
			_update_mesh_orientation()

	global_position += direction * speed * delta
	_timer += delta
	if _timer >= lifetime:
		_explode()
		return

	# Proximity detonation for all homing missiles
	if homing_target and is_instance_valid(homing_target):
		var dist: float = global_position.distance_to(homing_target.global_position)
		if dist < 40.0:
			if not is_enemy_missile and homing_target.has_method("take_damage"):
				homing_target.take_damage(damage)
			elif is_enemy_missile and homing_target.has_method("take_damage"):
				homing_target.take_damage(damage)
			_explode()
			return

	# Enemy missiles check proximity to player (fallback)
	if is_enemy_missile and homing_target and is_instance_valid(homing_target):
		var dist: float = global_position.distance_to(homing_target.global_position)
		if dist < 30.0 and homing_target.has_method("take_damage"):
			homing_target.take_damage(damage)
			_explode()

func get_damage() -> float:
	return damage

func on_hit() -> void:
	_explode()

func _explode() -> void:
	# AOE damage (player missiles only)
	if not is_enemy_missile:
		var enemies := get_tree().get_nodes_in_group("enemy")
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			var dist: float = global_position.distance_to(enemy.global_position)
			if dist <= explosion_radius:
				var falloff: float = 1.0 - (dist / explosion_radius) * 0.5
				if enemy.has_method("take_damage"):
					enemy.take_damage(damage * falloff)

	# --- BIG explosion ---
	var scene_root: Node = get_tree().current_scene
	var pos: Vector3 = global_position

	# Fireball
	var fireball := MeshInstance3D.new()
	var fb_mesh := SphereMesh.new()
	fb_mesh.radius = explosion_radius * 0.5
	fb_mesh.height = explosion_radius
	fb_mesh.radial_segments = 16
	fb_mesh.rings = 8
	var fb_mat := StandardMaterial3D.new()
	fb_mat.albedo_color = Color(1.0, 0.6, 0.1, 0.8)
	fb_mat.emission_enabled = true
	fb_mat.emission = Color(1.0, 0.4, 0.05)
	fb_mat.emission_energy_multiplier = 8.0
	fb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fb_mesh.material = fb_mat
	fireball.mesh = fb_mesh
	scene_root.add_child(fireball)
	fireball.global_position = pos

	fireball.scale = Vector3.ONE * 0.1
	var tw := fireball.create_tween()
	tw.set_parallel(true)
	tw.tween_property(fireball, "scale", Vector3.ONE * 1.5, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(fb_mat, "albedo_color", Color(1.0, 0.3, 0.0, 0.0), 0.4).set_ease(Tween.EASE_IN)
	tw.tween_property(fb_mat, "emission_energy_multiplier", 0.0, 0.4)
	tw.chain().tween_callback(fireball.queue_free)

	# Shockwave ring
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = explosion_radius * 0.4
	ring_mesh.outer_radius = explosion_radius * 0.5
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 24
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
	scene_root.add_child(ring)
	ring.global_position = pos

	var tw2 := ring.create_tween()
	tw2.set_parallel(true)
	tw2.tween_property(ring, "scale", Vector3.ONE * 3.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw2.tween_property(ring_mat, "albedo_color", Color(1.0, 0.5, 0.1, 0.0), 0.35)
	tw2.chain().tween_callback(ring.queue_free)

	# Debris + smoke
	var debris := Particles.enemy_death(pos, Color(1.0, 0.5, 0.15), explosion_radius * 0.8)
	scene_root.add_child(debris)

	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.one_shot = true
	smoke.amount = 16
	smoke.lifetime = 0.6
	smoke.explosiveness = 0.9
	smoke.direction = Vector3.ZERO
	smoke.spread = 180.0
	smoke.initial_velocity_min = 30.0
	smoke.initial_velocity_max = 80.0
	smoke.gravity = Vector3(0, 40, 0)
	smoke.damping_min = 40.0
	smoke.damping_max = 80.0
	smoke.scale_amount_min = 8.0
	smoke.scale_amount_max = 18.0
	smoke.color = Color(0.3, 0.3, 0.3, 0.5)
	smoke.color_ramp = Particles._create_fade_gradient(Color(0.2, 0.2, 0.2, 0.4))
	smoke.position = pos
	smoke.finished.connect(smoke.queue_free)
	smoke.set_deferred("emitting", true)
	scene_root.add_child(smoke)

	EffectsManager.chromatic_pulse(0.006)
	EffectsManager.screen_flash(Color(1.0, 0.6, 0.2), 0.15)

	queue_free()
