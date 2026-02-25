extends Area3D
## Enemy ship (missile cruiser). Moves in convoy formation across ocean.
## Takes damage from player weapons. Fires SAMs at player.
## Joins "enemy" group so lock-on, radar, gun-aim all work automatically.

signal enemy_died(pos: Vector3, enemy_value: int)

# Stats
var max_hp: float = 200.0
var hp: float = 200.0
var speed: float = 60.0
var xp_value: int = 5
var _is_dead: bool = false

# Movement
var _heading: float = 0.0

# Combat — SAM (surface-to-air missile)
var target: Node3D = null
const SAM_COOLDOWN: float = 3.5
const SAM_RANGE: float = 15000.0
const SAM_SPEED: float = 2000.0
const SAM_DAMAGE: float = 12.0
const SAM_HOMING: float = 1.8
var _sam_timer: float = 2.0  # initial delay before first shot
var _missiles_remaining: int = 8

# Visuals
var _model_instance: Node3D
var _hp_bg: MeshInstance3D
var _hp_fill: MeshInstance3D
var _flash_timer: float = 0.0
var _fires: Array[CPUParticles3D] = []
const MAX_FIRES: int = 5

# Shared resources
static var _flash_mat_cached: StandardMaterial3D
static var _model_cache: PackedScene
static var _ship_mat: StandardMaterial3D
static var _proj_scene_cached: PackedScene
static var _dmg_num_script_cached: GDScript
static var _hp_bg_mat_cached: StandardMaterial3D
static var _hp_fill_mat_cached: StandardMaterial3D

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("ship")
	GameManager.register_enemy(self)
	collision_layer = 4
	collision_mask = 8
	monitoring = true
	monitorable = true
	_setup_collision()
	_setup_model()
	_setup_hp_bar()
	area_entered.connect(_on_area_entered)

func configure(heading: float, hp_amount: float) -> void:
	_heading = heading
	max_hp = hp_amount
	hp = hp_amount

func _setup_collision() -> void:
	var shape := BoxShape3D.new()
	# Ship at scale 25: ~180 wide (X), ~380 tall (Y), ~1330 long (Z)
	shape.size = Vector3(200.0, 300.0, 1400.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 100.0
	add_child(col)

func _setup_model() -> void:
	if not _model_cache:
		_model_cache = load("res://assets/missile-cruiser/missile_cruiser.glb")
	if _model_cache:
		_model_instance = _model_cache.instantiate()
		# Model length runs along Y axis (53 units). Rotate X -90 to lay flat.
		# After rotation: model Y -> game -Z (forward), model Z -> game Y (up)
		# Scale 25 gives ~1330 length, ~180 beam — comparable to carrier
		_model_instance.scale = Vector3(25.0, 25.0, 25.0)
		_model_instance.rotation.x = deg_to_rad(-90.0)
		# Offset Y so waterline sits at ocean surface (ground plane at Y=-18)
		_model_instance.position.y = 100.0
		add_child(_model_instance)

		# Apply per-part navy colors (model has no textures from .3DS)
		_apply_navy_colors(_model_instance)
		print("[Ship] Model setup done")

func _setup_hp_bar() -> void:
	if not _hp_bg_mat_cached:
		_hp_bg_mat_cached = StandardMaterial3D.new()
		_hp_bg_mat_cached.albedo_color = Color(0.2, 0.2, 0.2, 0.6)
		_hp_bg_mat_cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hp_bg_mat_cached.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_hp_bg_mat_cached.no_depth_test = true
	if not _hp_fill_mat_cached:
		_hp_fill_mat_cached = StandardMaterial3D.new()
		_hp_fill_mat_cached.albedo_color = Color(1.0, 0.3, 0.3)
		_hp_fill_mat_cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hp_fill_mat_cached.no_depth_test = true

	# Background
	_hp_bg = MeshInstance3D.new()
	var bg_mesh := QuadMesh.new()
	bg_mesh.size = Vector2(400.0, 25.0)
	_hp_bg.mesh = bg_mesh
	_hp_bg.position = Vector3(0, 350.0, 0)
	_hp_bg.rotation_degrees = Vector3(-90, 0, 0)
	_hp_bg.material_override = _hp_bg_mat_cached
	_hp_bg.visible = false
	add_child(_hp_bg)

	# Fill
	_hp_fill = MeshInstance3D.new()
	var fill_mesh := QuadMesh.new()
	fill_mesh.size = Vector2(400.0, 25.0)
	_hp_fill.mesh = fill_mesh
	_hp_fill.position = Vector3(0, 350.0, 0)
	_hp_fill.rotation_degrees = Vector3(-90, 0, 0)
	_hp_fill.material_override = _hp_fill_mat_cached
	_hp_fill.visible = false
	add_child(_hp_fill)

func _process(delta: float) -> void:
	if _is_dead:
		return

	# Move convoy forward
	var fwd := Vector3(sin(_heading), 0.0, -cos(_heading))
	global_position += fwd * speed * delta
	# Keep on ocean surface (ground plane at Y=-18)
	global_position.y = -18.0

	# Rotate visual to face heading
	rotation.y = _heading

	# Flash decay
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			# Restore per-part navy colors
			if _model_instance:
				_apply_colors_recursive(_model_instance)

	# SAM attack
	_sam_timer -= delta
	if _sam_timer <= 0.0 and _missiles_remaining > 0:
		if target and is_instance_valid(target):
			var dist: float = global_position.distance_to(target.global_position)
			if dist < SAM_RANGE:
				_fire_sam()
				_sam_timer = SAM_COOLDOWN
				_missiles_remaining -= 1
			else:
				_sam_timer = 1.0  # check again in 1 sec

	# Update HP bar
	if hp < max_hp:
		_hp_bg.visible = true
		_hp_fill.visible = true
		_hp_fill.scale = Vector3(hp / max_hp, 1.0, 1.0)

func _fire_sam() -> void:
	if not target or not is_instance_valid(target):
		return
	var dir: Vector3 = (target.global_position - global_position).normalized()
	if dir.length() < 0.01:
		return

	if not _proj_scene_cached:
		_proj_scene_cached = load("res://scenes/entities/projectile.tscn")
	if not _proj_scene_cached:
		return
	var proj: Area3D = _proj_scene_cached.instantiate()
	proj.is_enemy_missile = true
	proj.setup(dir, SAM_DAMAGE, SAM_SPEED)
	proj.homing_target = target
	proj.homing_turn_rate = SAM_HOMING
	get_tree().current_scene.call_deferred("add_child", proj)
	# Launch from superstructure height
	proj.set_deferred("global_position", global_position + Vector3(0, 150, 0))

func take_damage(amount: float) -> void:
	if _is_dead:
		return
	hp -= amount
	_flash_timer = 0.08
	_flash_hit()

	# Impact explosion at hit point (random offset along ship)
	var hit_offset := Vector3(
		randf_range(-80.0, 80.0),
		randf_range(50.0, 200.0),
		randf_range(-500.0, 500.0)
	)
	var hit_pos: Vector3 = global_position + hit_offset
	var impact := Particles.explosion(hit_pos, 60.0)
	get_tree().current_scene.add_child(impact)

	# Add persistent fire on the ship (more fires as HP drops)
	var hp_ratio: float = hp / max_hp
	if hp_ratio < 0.8 and _fires.size() < MAX_FIRES:
		_spawn_fire(hit_offset)

	# Spawn damage number
	if not _dmg_num_script_cached:
		_dmg_num_script_cached = load("res://scripts/damage_number.gd")
	var dmg_num := Node3D.new()
	dmg_num.set_script(_dmg_num_script_cached)
	dmg_num.setup(int(amount), global_position + Vector3(0, 100, 0), Color(1.0, 0.8, 0.3))
	get_tree().current_scene.add_child(dmg_num)

	if hp <= 0.0:
		_die()

func _spawn_fire(offset: Vector3) -> void:
	# Place fire well above the deck so it's visible
	var fire_pos := Vector3(offset.x * 0.5, 250.0, offset.z)

	# Fire material — additive blending, billboard
	var fire_mat := StandardMaterial3D.new()
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_mat.vertex_color_use_as_albedo = true
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fire_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fire_mat.no_depth_test = true
	var fire_mesh := QuadMesh.new()
	fire_mesh.size = Vector2(2.0, 2.0)
	fire_mesh.material = fire_mat

	var fire := CPUParticles3D.new()
	fire.emitting = false
	fire.amount = 25
	fire.lifetime = 1.5
	fire.explosiveness = 0.0
	fire.randomness = 0.3
	fire.direction = Vector3(0, 1, 0)
	fire.spread = 35.0
	fire.initial_velocity_min = 40.0
	fire.initial_velocity_max = 120.0
	fire.gravity = Vector3(0, 80, 0)
	fire.damping_min = 10.0
	fire.damping_max = 30.0
	fire.scale_amount_min = 40.0
	fire.scale_amount_max = 100.0
	fire.scale_amount_curve = _create_fire_curve()
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 1.0, 0.7, 1.0))
	grad.add_point(0.2, Color(1.0, 0.7, 0.2, 0.9))
	grad.add_point(0.5, Color(1.0, 0.3, 0.05, 0.7))
	grad.add_point(0.8, Color(0.3, 0.08, 0.02, 0.3))
	grad.set_color(1, Color(0.1, 0.05, 0.02, 0.0))
	fire.color_ramp = grad
	fire.mesh = fire_mesh
	fire.position = fire_pos
	add_child(fire)
	fire.set_deferred("emitting", true)
	_fires.append(fire)

	# Smoke column — use SphereMesh for 3D volume
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = 1.0
	smoke_mesh.height = 2.0
	smoke_mesh.radial_segments = 8
	smoke_mesh.rings = 4
	smoke_mesh.material = smoke_mat

	var smoke := CPUParticles3D.new()
	smoke.emitting = false
	smoke.amount = 15
	smoke.lifetime = 3.0
	smoke.explosiveness = 0.0
	smoke.randomness = 0.4
	smoke.direction = Vector3(0, 1, 0)
	smoke.spread = 25.0
	smoke.initial_velocity_min = 50.0
	smoke.initial_velocity_max = 150.0
	smoke.gravity = Vector3(0, 40, 0)
	smoke.damping_min = 5.0
	smoke.damping_max = 15.0
	smoke.scale_amount_min = 50.0
	smoke.scale_amount_max = 120.0
	smoke.scale_amount_curve = _create_fire_curve()
	var smoke_grad := Gradient.new()
	smoke_grad.set_color(0, Color(0.12, 0.10, 0.08, 0.5))
	smoke_grad.add_point(0.3, Color(0.10, 0.08, 0.06, 0.4))
	smoke_grad.add_point(0.7, Color(0.13, 0.10, 0.08, 0.15))
	smoke_grad.set_color(1, Color(0.15, 0.12, 0.10, 0.0))
	smoke.color_ramp = smoke_grad
	smoke.mesh = smoke_mesh
	smoke.position = fire_pos + Vector3(0, 30, 0)
	add_child(smoke)
	smoke.set_deferred("emitting", true)

static func _create_fire_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.3))
	c.add_point(Vector2(0.2, 1.0))
	c.add_point(Vector2(0.7, 0.6))
	c.add_point(Vector2(1.0, 0.0))
	return c

func get_contact_damage() -> float:
	return 0.0

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	GameManager.add_kill()

	# Multiple explosions along the ship length for dramatic sinking
	var scene_root: Node = get_tree().current_scene
	var fwd := Vector3(sin(_heading), 0.0, -cos(_heading))
	for i in 3:
		var offset_along: float = (float(i) - 1.0) * 400.0
		var boom_pos: Vector3 = global_position + fwd * offset_along + Vector3(0, randf_range(50, 150), 0)
		var boom := Particles.explosion(boom_pos, 120.0)
		scene_root.add_child(boom)
	var death_fx := Particles.enemy_death(global_position + Vector3(0, 80, 0), Color(0.4, 0.4, 0.5), 120.0)
	scene_root.add_child(death_fx)
	EffectsManager.big_impact()

	enemy_died.emit(global_position, xp_value)
	queue_free()

func _on_area_entered(area: Area3D) -> void:
	if area.is_in_group("projectile") and area.has_method("get_damage"):
		take_damage(area.get_damage())
		if area.has_method("on_hit"):
			area.on_hit()

func _flash_hit() -> void:
	if not _model_instance:
		return
	if not _flash_mat_cached:
		_flash_mat_cached = StandardMaterial3D.new()
		_flash_mat_cached.albedo_color = Color(1.0, 1.0, 1.0)
		_flash_mat_cached.emission_enabled = true
		_flash_mat_cached.emission = Color(1.0, 0.8, 0.5)
		_flash_mat_cached.emission_energy_multiplier = 3.0
		_flash_mat_cached.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_set_override_recursive(_model_instance, _flash_mat_cached)

# Part-name to color mapping for a realistic naval look
static var _part_materials: Dictionary = {}

func _make_unshaded_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _apply_navy_colors(node: Node) -> void:
	if _part_materials.is_empty():
		_part_materials["hull"] = _make_unshaded_mat(Color(0.35, 0.37, 0.40))
		_part_materials["boat"] = _part_materials["hull"]
		_part_materials["keel"] = _part_materials["hull"]
		_part_materials["waterlin"] = _part_materials["hull"]
		_part_materials["fuselage"] = _part_materials["hull"]

		_part_materials["deck"] = _make_unshaded_mat(Color(0.42, 0.44, 0.46))
		_part_materials["hatches"] = _part_materials["deck"]
		_part_materials["tarp"] = _part_materials["deck"]

		_part_materials["super1"] = _make_unshaded_mat(Color(0.50, 0.52, 0.54))
		_part_materials["super2"] = _part_materials["super1"]
		_part_materials["stack"] = _part_materials["super1"]
		_part_materials["base"] = _part_materials["super1"]
		_part_materials["mast"] = _part_materials["super1"]
		_part_materials["vents"] = _part_materials["super1"]

		_part_materials["tomahawk"] = _make_unshaded_mat(Color(0.28, 0.30, 0.32))
		_part_materials["seasparw"] = _part_materials["tomahawk"]
		_part_materials["tubes"] = _part_materials["tomahawk"]
		_part_materials["mark45"] = _part_materials["tomahawk"]
		_part_materials["phalanx1"] = _part_materials["tomahawk"]
		_part_materials["pbase"] = _part_materials["tomahawk"]
		_part_materials["phouse"] = _part_materials["tomahawk"]
		_part_materials["barrels"] = _part_materials["tomahawk"]

		_part_materials["radar"] = _make_unshaded_mat(Color(0.55, 0.57, 0.53))
		_part_materials["array"] = _part_materials["radar"]
		_part_materials["aegis"] = _part_materials["radar"]
		_part_materials["pdish"] = _part_materials["radar"]
		_part_materials["tacan1"] = _part_materials["radar"]
		_part_materials["tacan2"] = _part_materials["radar"]
		_part_materials["tacan3"] = _part_materials["radar"]
		_part_materials["ant"] = _part_materials["radar"]
		_part_materials["ant2"] = _part_materials["radar"]
		_part_materials["ant3"] = _part_materials["radar"]

		_part_materials["glass"] = _make_unshaded_mat(Color(0.15, 0.20, 0.30))
		_part_materials["cockpit"] = _part_materials["glass"]
		_part_materials["black"] = _part_materials["glass"]

		_part_materials["rails"] = _make_unshaded_mat(Color(0.40, 0.42, 0.44))
		_part_materials["davits"] = _part_materials["rails"]
		_part_materials["rrail"] = _part_materials["rails"]

		_part_materials["trotor"] = _make_unshaded_mat(Color(0.25, 0.27, 0.29))
		_part_materials["mrotor"] = _part_materials["trotor"]

		_part_materials["_default"] = _make_unshaded_mat(Color(0.45, 0.47, 0.50))

	_apply_colors_recursive(node)

func _apply_colors_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		# Match mesh name to part (mesh names are like "hull-Mesh", "deck-Mesh")
		var mesh_name: String = node.name.to_lower()
		var matched: bool = false
		for part_name in _part_materials:
			if part_name == "_default":
				continue
			if mesh_name.begins_with(part_name):
				node.material_override = _part_materials[part_name]
				matched = true
				break
		if not matched:
			node.material_override = _part_materials["_default"]
	for child in node.get_children():
		_apply_colors_recursive(child)

func _count_and_apply_mat(node: Node, mat: Material) -> int:
	var count: int = 0
	if node is MeshInstance3D:
		node.material_override = mat
		count += 1
	for child in node.get_children():
		count += _count_and_apply_mat(child, mat)
	return count

func _set_override_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = mat
	for child in node.get_children():
		_set_override_recursive(child, mat)
