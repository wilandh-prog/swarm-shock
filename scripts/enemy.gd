extends Area3D
## Enemy plane (MiG-21 silhouette). Flies forward, turns toward player, banks into turns.
## Procedural mesh model. Takes damage, drops pickups on death.

signal enemy_died(pos: Vector3, enemy_value: int)

enum EnemyType { BASIC, FAST, TANK, SWARM }

@export var enemy_type: EnemyType = EnemyType.BASIC

# Stats
var max_hp: float = 30.0
var hp: float = 30.0
var speed: float = 80.0
var contact_damage: float = 10.0
var xp_value: int = 1
var volt_chance: float = 0.1
var size_radius: float = 14.0

# State
var target: Node3D = null
var _flash_timer: float = 0.0
var _base_color: Color = Color.RED
var _is_dead: bool = false
var _spawn_time: float = 0.0
var _hit_scale: float = 1.0

# Combat AI
enum AIState { APPROACH, FIRE, BREAK_AWAY, GUN_STRAFE }
var _ai_state: AIState = AIState.APPROACH
var _fire_cooldown: float = 0.0
var _missiles_remaining: int = 4
var _break_timer: float = 0.0
var _break_direction: float = 1.0  # +1 or -1 for left/right break
var _gun_cooldown: float = 0.0
var _burst_remaining: int = 0
const FIRE_RANGE: float = 1200.0
const FIRE_CONE: float = 0.85  # dot product (~30 degrees)
const BREAK_DURATION: float = 2.5
const FIRE_RATE: float = 3.0
const ENEMY_MISSILE_SPEED: float = 1000.0
const ENEMY_MISSILE_DAMAGE: float = 8.0
const ENEMY_GUN_SPEED: float = 3000.0
const ENEMY_GUN_DAMAGE: float = 4.0
const GUN_FIRE_RATE: float = 0.12
const GUN_BURST_COUNT: int = 6
const GUN_RANGE: float = 900.0

# Flight
var _heading: float = 0.0
var _turn_speed: float = 0.0
var _turn_rate: float = 2.5
var _bank_angle: float = 0.0
const MAX_BANK_ANGLE: float = 0.6
const BANK_LERP_SPEED: float = 6.0
const TURN_ACCEL: float = 4.0

# 3D visuals
var _plane_pivot: Node3D
var _plane_body: Node3D
var _model_instance: Node3D
var _shadow: MeshInstance3D
var _hp_bg: MeshInstance3D
var _hp_fill: MeshInstance3D
var _is_flashing: bool = false

# Shared resources (static — shared across all enemies)
static var _flash_mat_cached: StandardMaterial3D

# Type configs
const TYPE_CONFIG := {
	EnemyType.BASIC: {
		"hp": 30.0, "speed": 1500.0, "damage": 10.0,
		"xp": 1, "volt_chance": 0.1, "radius": 14.0,
		"color": Color(0.22, 0.24, 0.26),
		"model": "res://assets/mig-e8/mig-e8.glb",
		"scale": 30.0, "turn_rate": 1.2,
		"model_rot_y": 180.0, "unshaded": false,
	},
	EnemyType.FAST: {
		"hp": 15.0, "speed": 2000.0, "damage": 8.0,
		"xp": 1, "volt_chance": 0.08, "radius": 10.0,
		"color": Color(0.28, 0.30, 0.32),
		"model": "res://assets/sukhoi/sukhoi.glb",
		"scale": 25.0, "turn_rate": 0.8,
		"model_rot_y": 180.0, "unshaded": true,
	},
	EnemyType.TANK: {
		"hp": 100.0, "speed": 1000.0, "damage": 20.0,
		"xp": 3, "volt_chance": 0.25, "radius": 22.0,
		"color": Color(0.18, 0.20, 0.22),
		"model": "res://assets/mig-e8/mig-e8.glb",
		"scale": 40.0, "turn_rate": 0.6,
		"model_rot_y": 180.0, "unshaded": false,
	},
	EnemyType.SWARM: {
		"hp": 10.0, "speed": 1800.0, "damage": 5.0,
		"xp": 1, "volt_chance": 0.05, "radius": 8.0,
		"color": Color(0.25, 0.27, 0.28),
		"model": "res://assets/tornado/tornado.glb",
		"scale": 40.0, "turn_rate": 1.0,
		"model_rot_y": 270.0, "unshaded": true,
	},
}

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = 4
	collision_mask = 8
	monitoring = true
	monitorable = true
	_apply_type_config()
	_setup_collision()
	_setup_visuals()
	_setup_hp_bar()
	area_entered.connect(_on_area_entered)
	# Random initial heading so enemies don't all face the same way
	_heading = randf() * TAU

func configure(type: EnemyType, difficulty_mult: float = 1.0) -> void:
	enemy_type = type
	_apply_type_config()
	max_hp *= difficulty_mult
	hp = max_hp
	contact_damage *= difficulty_mult
	_update_model_for_type()

func _apply_type_config() -> void:
	var config: Dictionary = TYPE_CONFIG[enemy_type]
	max_hp = config["hp"]
	hp = max_hp
	speed = config["speed"]
	contact_damage = config["damage"]
	xp_value = config["xp"]
	volt_chance = config["volt_chance"]
	size_radius = config["radius"]
	_base_color = config["color"]
	_turn_rate = config["turn_rate"]

func _setup_collision() -> void:
	for child in get_children():
		if child is CollisionShape3D:
			child.queue_free()
	var shape := SphereShape3D.new()
	shape.radius = size_radius
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

func _setup_visuals() -> void:
	# Hierarchy: Enemy -> _plane_pivot (heading) -> _plane_body (banking) -> model
	_plane_pivot = Node3D.new()
	add_child(_plane_pivot)

	_plane_body = Node3D.new()
	_plane_pivot.add_child(_plane_body)

	_load_model()

	# Blob shadow on ground
	_shadow = MeshInstance3D.new()
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(24.0, 24.0)
	_shadow.mesh = shadow_mesh
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.35)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.no_depth_test = true
	_shadow.material_override = shadow_mat
	_shadow.position.y = 1.0
	add_child(_shadow)

# Cached model scenes per path (shared across all enemies)
static var _model_cache: Dictionary = {}

func _load_model() -> void:
	if _model_instance and is_instance_valid(_model_instance):
		_model_instance.queue_free()
		_model_instance = null

	var config: Dictionary = TYPE_CONFIG[enemy_type]
	var model_scale: float = config["scale"]
	var model_path: String = config["model"]

	# Load and cache the GLB scene
	if not _model_cache.has(model_path):
		var loaded = load(model_path)
		_model_cache[model_path] = loaded
		print("[Enemy] Loaded model: ", model_path, " -> ", loaded)

	var scene: PackedScene = _model_cache[model_path]
	if scene:
		_model_instance = scene.instantiate()
		var glb_scale: float = model_scale * 0.25
		_model_instance.scale = Vector3(glb_scale, glb_scale, glb_scale)
		var rot_y: float = config.get("model_rot_y", 180.0)
		_model_instance.rotation.y = deg_to_rad(rot_y)
		_model_instance.position.y = 20.0
		if config.get("unshaded", false):
			_make_unshaded_recursive(_model_instance)
		_plane_body.add_child(_model_instance)
		return

	# Fallback: procedural MiG-21 silhouette
	print("[Enemy] FALLBACK for: ", model_path, " type=", enemy_type)
	_load_procedural_model(config, model_scale)

func _load_procedural_model(config: Dictionary, model_scale: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _base_color
	mat.emission_enabled = true
	mat.emission = _base_color
	mat.emission_energy_multiplier = 0.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_model_instance = Node3D.new()

	var fuselage := MeshInstance3D.new()
	var fuse_mesh := CylinderMesh.new()
	fuse_mesh.top_radius = 0.32
	fuse_mesh.bottom_radius = 0.38
	fuse_mesh.height = 3.2
	fuse_mesh.radial_segments = 12
	fuse_mesh.material = mat
	fuselage.mesh = fuse_mesh
	_model_instance.add_child(fuselage)

	var nose := MeshInstance3D.new()
	var nose_mesh := CylinderMesh.new()
	nose_mesh.top_radius = 0.08
	nose_mesh.bottom_radius = 0.32
	nose_mesh.height = 1.2
	nose_mesh.radial_segments = 12
	nose_mesh.material = mat
	nose.mesh = nose_mesh
	nose.position.y = 2.2
	_model_instance.add_child(nose)

	var cockpit := MeshInstance3D.new()
	var cock_mesh := SphereMesh.new()
	cock_mesh.radius = 0.22
	cock_mesh.height = 0.3
	cock_mesh.radial_segments = 8
	cock_mesh.rings = 4
	var cock_mat := StandardMaterial3D.new()
	cock_mat.albedo_color = Color(0.15, 0.25, 0.4)
	cock_mat.emission_enabled = true
	cock_mat.emission = Color(0.2, 0.35, 0.6)
	cock_mat.emission_energy_multiplier = 1.5
	cock_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cock_mesh.material = cock_mat
	cockpit.mesh = cock_mesh
	cockpit.position.y = 1.0
	cockpit.position.z = 0.3
	_model_instance.add_child(cockpit)

	var wings := MeshInstance3D.new()
	var wing_mesh := PrismMesh.new()
	wing_mesh.size = Vector3(4.0, 2.4, 0.12)
	wing_mesh.material = mat
	wings.mesh = wing_mesh
	wings.position.y = -0.1
	_model_instance.add_child(wings)

	var tail_fin := MeshInstance3D.new()
	var tfin_mesh := PrismMesh.new()
	tfin_mesh.size = Vector3(0.1, 1.0, 0.8)
	tfin_mesh.material = mat
	tail_fin.mesh = tfin_mesh
	tail_fin.position.y = -1.2
	tail_fin.position.z = 0.5
	tail_fin.rotation.x = deg_to_rad(90.0)
	_model_instance.add_child(tail_fin)

	var htail := MeshInstance3D.new()
	var htail_mesh := PrismMesh.new()
	htail_mesh.size = Vector3(1.6, 0.9, 0.08)
	htail_mesh.material = mat
	htail.mesh = htail_mesh
	htail.position.y = -1.3
	_model_instance.add_child(htail)

	var exhaust := MeshInstance3D.new()
	var exh_mesh := CylinderMesh.new()
	exh_mesh.top_radius = 0.3
	exh_mesh.bottom_radius = 0.2
	exh_mesh.height = 0.4
	exh_mesh.radial_segments = 10
	var exh_mat := StandardMaterial3D.new()
	exh_mat.albedo_color = Color(1.0, 0.5, 0.2)
	exh_mat.emission_enabled = true
	exh_mat.emission = Color(1.0, 0.4, 0.1)
	exh_mat.emission_energy_multiplier = 4.0
	exh_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	exh_mesh.material = exh_mat
	exhaust.mesh = exh_mesh
	exhaust.position.y = -1.8
	_model_instance.add_child(exhaust)

	_model_instance.rotation.x = deg_to_rad(-90.0)
	_model_instance.scale = Vector3.ONE * model_scale
	_model_instance.position.y = 20.0
	_plane_body.add_child(_model_instance)

func _update_model_for_type() -> void:
	if _plane_body:
		_load_model()

func _setup_hp_bar() -> void:
	# Background
	_hp_bg = MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(size_radius * 2.0, 3.0)
	_hp_bg.mesh = bg_mesh
	_hp_bg.position = Vector3(0, 25.0, -size_radius - 8.0)
	_hp_bg.rotation_degrees = Vector3(-90, 0, 0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.6)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bg_mat.no_depth_test = true
	_hp_bg.material_override = bg_mat
	_hp_bg.visible = false
	add_child(_hp_bg)

	# Fill
	_hp_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(size_radius * 2.0, 3.0)
	_hp_fill.mesh = fill_mesh
	_hp_fill.position = Vector3(0, 25.0, -size_radius - 8.0)
	_hp_fill.rotation_degrees = Vector3(-90, 0, 0)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(1.0, 0.3, 0.3)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.no_depth_test = true
	_hp_fill.material_override = fill_mat
	_hp_fill.visible = false
	add_child(_hp_fill)

func _process(delta: float) -> void:
	if _is_dead:
		return

	_spawn_time += delta

	# --- Combat AI ---
	_fire_cooldown -= delta
	_gun_cooldown -= delta

	if target and is_instance_valid(target):
		var to_target: Vector3 = target.global_position - global_position
		to_target.y = 0.0
		var dist_to_target: float = to_target.length()
		var fwd := Vector3(sin(_heading), 0.0, -cos(_heading))

		match _ai_state:
			AIState.APPROACH:
				# Steer toward player
				var desired_heading: float = atan2(to_target.x, -to_target.z)
				var angle_diff: float = angle_difference(_heading, desired_heading)
				var turn_input: float = clampf(angle_diff / (PI * 0.25), -1.0, 1.0)
				if absf(turn_input) > 0.05:
					_turn_speed = move_toward(_turn_speed, turn_input * _turn_rate, TURN_ACCEL * delta)
				else:
					_turn_speed = move_toward(_turn_speed, 0.0, TURN_ACCEL * delta)

				# Check if in firing position
				if dist_to_target < FIRE_RANGE and _fire_cooldown <= 0.0 and _missiles_remaining > 0:
					var dot: float = fwd.dot(to_target.normalized())
					if dot > FIRE_CONE:
						_ai_state = AIState.FIRE
				elif _missiles_remaining <= 0 and dist_to_target < GUN_RANGE and _gun_cooldown <= 0.0:
					var dot: float = fwd.dot(to_target.normalized())
					if dot > FIRE_CONE:
						_ai_state = AIState.GUN_STRAFE
						_burst_remaining = GUN_BURST_COUNT

			AIState.FIRE:
				# Fire missile at player and immediately break
				_fire_missile_at_target()
				_missiles_remaining -= 1
				_fire_cooldown = FIRE_RATE
				_ai_state = AIState.BREAK_AWAY
				_break_timer = BREAK_DURATION
				_break_direction = [-1.0, 1.0][randi() % 2]

			AIState.BREAK_AWAY:
				# Hard turn away from player
				var away_heading: float = atan2(-to_target.x, to_target.z)
				var angle_diff: float = angle_difference(_heading, away_heading)
				# Add lateral offset for dramatic banking break
				var turn_input: float = clampf(angle_diff / (PI * 0.25), -1.0, 1.0)
				turn_input += _break_direction * 0.5
				turn_input = clampf(turn_input, -1.0, 1.0)
				_turn_speed = move_toward(_turn_speed, turn_input * _turn_rate * 1.5, TURN_ACCEL * 2.0 * delta)

				_break_timer -= delta
				if _break_timer <= 0.0:
					_ai_state = AIState.APPROACH

			AIState.GUN_STRAFE:
				# Strafing run: keep steering toward player, fire gun bursts
				var desired_heading: float = atan2(to_target.x, -to_target.z)
				var angle_diff: float = angle_difference(_heading, desired_heading)
				var turn_input: float = clampf(angle_diff / (PI * 0.25), -1.0, 1.0)
				_turn_speed = move_toward(_turn_speed, turn_input * _turn_rate, TURN_ACCEL * delta)

				if _gun_cooldown <= 0.0 and _burst_remaining > 0:
					_fire_gun_at_target()
					_burst_remaining -= 1
					_gun_cooldown = GUN_FIRE_RATE

				if _burst_remaining <= 0 or dist_to_target < 100.0:
					_ai_state = AIState.BREAK_AWAY
					_break_timer = BREAK_DURATION * 0.7
					_break_direction = [-1.0, 1.0][randi() % 2]
					_gun_cooldown = GUN_FIRE_RATE * 5.0
	else:
		_turn_speed = move_toward(_turn_speed, 0.0, TURN_ACCEL * delta)

	_heading += _turn_speed * delta

	# Always fly forward
	var forward := Vector3(sin(_heading), 0.0, -cos(_heading))
	global_position += forward * speed * delta
	if target and is_instance_valid(target):
		global_position.y = move_toward(global_position.y, target.global_position.y, speed * delta * 0.5)

	# Banking — same as player
	var target_bank: float = -(_turn_speed / _turn_rate) * MAX_BANK_ANGLE
	_bank_angle = lerp(_bank_angle, target_bank, BANK_LERP_SPEED * delta)

	# Update visuals
	if _plane_pivot:
		_plane_pivot.rotation.y = -_heading
	if _plane_body:
		_plane_body.rotation.z = _bank_angle

	# Flash decay — only toggle on state change, reuse cached material
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _model_instance:
			if _flash_timer > 0.0 and not _is_flashing:
				_is_flashing = true
				_set_model_flash(true)
			elif _flash_timer <= 0.0 and _is_flashing:
				_is_flashing = false
				_set_model_flash(false)

	# Hit scale spring back
	if _hit_scale != 1.0:
		_hit_scale = lerpf(_hit_scale, 1.0, 10.0 * delta)

	# Spawn grow-in + hit scale
	var spawn_scale: float = minf(_spawn_time * 5.0, 1.0)
	if _plane_pivot:
		_plane_pivot.scale = Vector3.ONE * spawn_scale * _hit_scale

	# Shadow
	if _shadow:
		_shadow.position.y = 1.0
		var s: float = size_radius / 14.0
		_shadow.scale = Vector3(s, 1.0, s)

	# HP bar
	if hp < max_hp and _hp_bg and _hp_fill:
		_hp_bg.visible = true
		_hp_fill.visible = true
		var frac: float = hp / max_hp
		_hp_fill.scale = Vector3(frac, 1.0, 1.0)

func _set_model_flash(on: bool) -> void:
	if not _model_instance:
		return
	if on:
		if not _flash_mat_cached:
			_flash_mat_cached = StandardMaterial3D.new()
			_flash_mat_cached.albedo_color = Color.WHITE
			_flash_mat_cached.emission_enabled = true
			_flash_mat_cached.emission = Color.WHITE
			_flash_mat_cached.emission_energy_multiplier = 3.0
			_flash_mat_cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_apply_material_recursive(_model_instance, _flash_mat_cached)
	else:
		_apply_material_recursive(_model_instance, null)

func _apply_material_recursive(node: Node, mat: StandardMaterial3D) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)

func _make_unshaded_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh:
			for i in mi.mesh.get_surface_count():
				var mat = mi.mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var dup := mat.duplicate() as StandardMaterial3D
					dup.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					mi.set_surface_override_material(i, dup)
	for child in node.get_children():
		_make_unshaded_recursive(child)

func _fire_missile_at_target() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir: Vector3 = (target.global_position - global_position).normalized()
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()

	var proj_scene: PackedScene = load("res://scenes/entities/projectile.tscn")
	if not proj_scene:
		return
	var proj: Area3D = proj_scene.instantiate()
	# Enemy missiles: red, slightly slower, aimed at player
	proj.is_enemy_missile = true
	proj.setup(dir, ENEMY_MISSILE_DAMAGE, ENEMY_MISSILE_SPEED)
	proj.homing_target = target
	proj.homing_turn_rate = 2.0
	get_tree().current_scene.call_deferred("add_child", proj)
	proj.set_deferred("global_position", global_position)

func _fire_gun_at_target() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir: Vector3 = (target.global_position - global_position).normalized()
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	dir = dir.normalized()
	# Slight spread
	var spread_rad: float = deg_to_rad(2.0)
	dir = dir.rotated(Vector3.UP, randf_range(-spread_rad, spread_rad))

	var proj_scene: PackedScene = load("res://scenes/entities/projectile.tscn")
	if not proj_scene:
		return
	var proj: Area3D = proj_scene.instantiate()
	proj.is_bullet = true
	proj.is_enemy_missile = true
	proj.lifetime = 2.0
	proj.explosion_radius = 0.0
	proj.setup(dir, ENEMY_GUN_DAMAGE, ENEMY_GUN_SPEED)
	proj.homing_target = target
	proj.homing_turn_rate = 0.0  # straight flight, homing_target for proximity hit detection
	get_tree().current_scene.call_deferred("add_child", proj)
	proj.set_deferred("global_position", global_position)

func take_damage(amount: float) -> void:
	if _is_dead:
		return
	hp -= amount
	_flash_timer = 0.08
	_hit_scale = 1.3

	# Spawn damage number
	var dmg_num_script := load("res://scripts/damage_number.gd")
	var dmg_num := Node3D.new()
	dmg_num.set_script(dmg_num_script)
	dmg_num.setup(int(amount), global_position, Color(1.0, 0.8, 0.3))
	get_tree().current_scene.add_child(dmg_num)

	if hp <= 0.0:
		_die()

func get_contact_damage() -> float:
	return contact_damage

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	GameManager.add_kill()

	var death_fx := Particles.enemy_death(global_position, _base_color, size_radius)
	get_tree().current_scene.add_child(death_fx)
	EffectsManager.small_impact()

	enemy_died.emit(global_position, xp_value)
	queue_free()

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("projectile") and area.has_method("get_damage"):
		take_damage(area.get_damage())
		if area.has_method("on_hit"):
			area.on_hit()
