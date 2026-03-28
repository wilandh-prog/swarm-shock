extends Area3D
## Homing missile. Steers toward locked target, explodes on hit or after lifetime.

var direction: Vector3 = Vector3.FORWARD
var speed: float = 3000.0
var damage: float = 20.0
var explosion_radius: float = 50.0
var lifetime: float = 8.0
var _timer: float = 0.0
var _mesh_root: Node3D
var _trail: CPUParticles3D

# Homing
var homing_target: Node3D = null
var homing_turn_rate: float = 4.0
var is_enemy_missile: bool = false
var is_bullet: bool = false

# Shared materials (static — created once, reused by all projectiles)
static var _player_missile_mats: Dictionary = {}
static var _enemy_missile_mats: Dictionary = {}
static var _player_bullet_mat: StandardMaterial3D
static var _enemy_bullet_mat: StandardMaterial3D
static var _trail_mat_cached: StandardMaterial3D


func _ready() -> void:
	if is_enemy_missile:
		add_to_group("enemy_projectile")
		GameManager.register_enemy_missile(self)
		collision_layer = 0
	else:
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

static func _init_missile_mats(enemy: bool) -> Dictionary:
	var body_color: Color = Color(0.9, 0.2, 0.15) if enemy else Color(0.85, 0.88, 0.9)
	var mats: Dictionary = {}
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = body_color
	body_mat.emission_enabled = true
	body_mat.emission = body_color
	body_mat.emission_energy_multiplier = 2.0 if enemy else 1.5
	body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["body"] = body_mat
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.9, 0.2, 0.15) if enemy else Color(0.7, 0.75, 0.8)
	nose_mat.emission_enabled = true
	nose_mat.emission = nose_mat.albedo_color
	nose_mat.emission_energy_multiplier = 2.0
	nose_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["nose"] = nose_mat
	var fin_mat := StandardMaterial3D.new()
	fin_mat.albedo_color = body_color.darkened(0.2)
	fin_mat.emission_enabled = true
	fin_mat.emission = fin_mat.albedo_color
	fin_mat.emission_energy_multiplier = 1.0
	fin_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["fin"] = fin_mat
	var flame_mat := StandardMaterial3D.new()
	flame_mat.albedo_color = Color(1.0, 0.7, 0.1)
	flame_mat.emission_enabled = true
	flame_mat.emission = Color(1.0, 0.5, 0.05)
	flame_mat.emission_energy_multiplier = 6.0
	flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mats["flame"] = flame_mat
	return mats

static func _init_bullet_mat(enemy: bool) -> StandardMaterial3D:
	var bullet_color: Color = Color(1.0, 0.3, 0.15) if enemy else Color(1.0, 0.9, 0.3)
	var emit_color: Color = Color(1.0, 0.2, 0.1) if enemy else Color(1.0, 0.8, 0.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = bullet_color
	mat.emission_enabled = true
	mat.emission = emit_color
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func _get_trail_mat() -> StandardMaterial3D:
	if not _trail_mat_cached:
		_trail_mat_cached = StandardMaterial3D.new()
		_trail_mat_cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_trail_mat_cached.vertex_color_use_as_albedo = true
		_trail_mat_cached.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_trail_mat_cached.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	return _trail_mat_cached

func _build_mesh() -> void:
	_mesh_root = Node3D.new()

	if is_bullet:
		_build_bullet_mesh()
		return

	# Get or create cached materials for this missile type
	var mats: Dictionary
	if is_enemy_missile:
		if _enemy_missile_mats.is_empty():
			_enemy_missile_mats = _init_missile_mats(true)
		mats = _enemy_missile_mats
	else:
		if _player_missile_mats.is_empty():
			_player_missile_mats = _init_missile_mats(false)
		mats = _player_missile_mats

	# Sidewinder-style: long body
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 2.0
	body_mesh.bottom_radius = 2.5
	body_mesh.height = 40.0
	body_mesh.radial_segments = 8
	body_mesh.material = mats["body"]
	body.mesh = body_mesh
	_mesh_root.add_child(body)

	# Nose cone — long and pointed
	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.0
	nose_mesh.bottom_radius = 2.0
	nose_mesh.height = 8.0
	nose_mesh.radial_segments = 8
	nose_mesh.material = mats["nose"]
	nose.mesh = nose_mesh
	nose.position.y = 24.0
	_mesh_root.add_child(nose)

	# Tail fins — 4 cross fins
	for i in 4:
		var fin := MeshInstance3D.new()
		var fin_mesh := BoxMesh.new()
		fin_mesh.size = Vector3(0.3, 6.0, 4.0)
		fin_mesh.material = mats["fin"]
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
	flame_mesh.material = mats["flame"]
	flame.mesh = flame_mesh
	flame.position.y = -25.0
	_mesh_root.add_child(flame)

	# Smoke stream — thick persistent trail behind missile
	# emitting=false here; enabled from _process once in-tree (global transform needed)
	_trail = CPUParticles3D.new()
	_trail.emitting = false
	_trail.amount = 60
	_trail.lifetime = 3.0
	_trail.explosiveness = 0.0
	_trail.randomness = 0.3
	_trail.local_coords = false
	_trail.direction = Vector3.ZERO
	_trail.spread = 0.0
	_trail.initial_velocity_min = 0.0
	_trail.initial_velocity_max = 0.0
	_trail.gravity = Vector3(0, 12, 0)
	_trail.scale_amount_min = 12.0
	_trail.scale_amount_max = 25.0
	_trail.scale_amount_curve = Particles._create_grow_fade_curve()
	var trail_grad := Gradient.new()
	trail_grad.set_color(0, Color(1.0, 1.0, 1.0, 0.8))
	trail_grad.add_point(0.2, Color(0.9, 0.9, 0.9, 0.5))
	trail_grad.add_point(0.5, Color(0.7, 0.7, 0.7, 0.25))
	trail_grad.add_point(0.8, Color(0.5, 0.5, 0.5, 0.08))
	trail_grad.set_color(1, Color(0.4, 0.4, 0.4, 0.0))
	_trail.color_ramp = trail_grad
	_trail.mesh = Particles._get_smoke_mesh()
	_trail.position.y = -25.0
	_mesh_root.add_child(_trail)

	_update_mesh_orientation()
	add_child(_mesh_root)

func _build_bullet_mesh() -> void:
	var mat: StandardMaterial3D
	if is_enemy_missile:
		if not _enemy_bullet_mat:
			_enemy_bullet_mat = _init_bullet_mat(true)
		mat = _enemy_bullet_mat
	else:
		if not _player_bullet_mat:
			_player_bullet_mat = _init_bullet_mat(false)
		mat = _player_bullet_mat

	var body := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 12.0
	mesh.radial_segments = 6
	mesh.material = mat
	body.mesh = mesh
	_mesh_root.add_child(body)

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
	# Start smoke trail on first frame (node is guaranteed in-tree here)
	if _trail and not _trail.emitting:
		_trail.emitting = true

	# Homing: steer toward predicted intercept point
	if homing_target and is_instance_valid(homing_target):
		var to_target := homing_target.global_position - global_position
		var dist := to_target.length()
		if dist > 1.0:
			# Lead prediction: aim where target will be
			var intercept_pos := homing_target.global_position
			if homing_target.has_method("get_velocity"):
				var target_vel: Vector3 = homing_target.get_velocity()
				var closing_speed := speed - direction.dot(target_vel)
				if closing_speed > 10.0:
					var time_to_hit := dist / closing_speed
					intercept_pos += target_vel * time_to_hit * 0.7
			elif homing_target is CharacterBody3D:
				var target_vel: Vector3 = homing_target.velocity
				var closing_speed := speed - direction.dot(target_vel)
				if closing_speed > 10.0:
					var time_to_hit := dist / closing_speed
					intercept_pos += target_vel * time_to_hit * 0.7
			var desired := (intercept_pos - global_position).normalized()
			var turn := homing_turn_rate
			# Terminal guidance: tighten turn when close
			if dist < 400.0:
				turn *= 1.5 + (1.0 - dist / 400.0) * 4.0
			direction = direction.slerp(desired, turn * delta).normalized()
			_update_mesh_orientation()

	# Flare attraction for enemy missiles
	if is_enemy_missile:
		_check_flare_attract()

	global_position += direction * speed * delta
	_timer += delta
	if _timer >= lifetime:
		_explode()
		return

	# Proximity detonation for all homing missiles
	if homing_target and is_instance_valid(homing_target):
		var prox_radius: float = 60.0 if is_enemy_missile else 35.0
		var dist: float = global_position.distance_to(homing_target.global_position)
		if dist < prox_radius:
			if not is_enemy_missile and homing_target.has_method("take_damage"):
				homing_target.take_damage(damage)
			elif is_enemy_missile and homing_target.has_method("take_damage"):
				homing_target.take_damage(damage)
			_explode()
			return


func _check_flare_attract() -> void:
	var flares := GameManager.flares_active
	var pos: Vector3 = global_position
	for flare in flares:
		if not is_instance_valid(flare):
			continue
		var diff: Vector3 = flare.global_position - pos
		var dist_sq: float = diff.x * diff.x + diff.y * diff.y + diff.z * diff.z
		if dist_sq > 640000.0:  # 800^2
			continue
		var dist: float = sqrt(dist_sq)
		var chance: float = 0.04 * (1.0 - dist / 800.0)
		if randf() < chance:
			homing_target = flare
			return

func get_damage() -> float:
	return damage

func on_hit() -> void:
	_explode()

func _explode() -> void:
	# Bullets just disappear with a small spark
	if is_bullet:
		var spark := Particles.chain_spark(global_position)
		get_tree().current_scene.add_child(spark)
		queue_free()
		return

	# AOE damage (player missiles only)
	if not is_enemy_missile:
		var enemies := GameManager.enemies_alive
		var radius_sq: float = explosion_radius * explosion_radius
		var pos: Vector3 = global_position
		for enemy in enemies:
			if not is_instance_valid(enemy):
				continue
			var diff: Vector3 = enemy.global_position - pos
			var dist_sq: float = diff.x * diff.x + diff.y * diff.y + diff.z * diff.z
			if dist_sq <= radius_sq:
				var falloff: float = 1.0 - (sqrt(dist_sq) / explosion_radius) * 0.5
				if enemy.has_method("take_damage"):
					enemy.take_damage(damage * falloff)

	var scene_root: Node = get_tree().current_scene
	var pos: Vector3 = global_position

	if is_enemy_missile:
		# Small explosion for enemy missiles hitting the player
		var explosion := Particles.explosion(pos, 15.0)
		scene_root.add_child(explosion)
		EffectsManager.screen_shake(4.0, 0.1)
	else:
		# Big explosion for player missiles
		var explosion := Particles.explosion(pos, explosion_radius)
		scene_root.add_child(explosion)
		EffectsManager.chromatic_pulse(0.006)
		EffectsManager.screen_flash(Color(1.0, 0.6, 0.2), 0.15)

	queue_free()
