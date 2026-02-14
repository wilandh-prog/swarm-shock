extends CharacterBody3D
## Player character. Airplane that always flies forward, steered with left/right.
## Banks into turns. W/S for speed control.

signal died
signal health_changed(current: float, maximum: float)

# Stats (initialized from GameManager meta-upgrades)
var max_health: float = 100.0
var health: float = 100.0
var move_speed: float = 5000.0
var pickup_range: float = 80.0
var damage_mult: float = 1.0
var chain_range: float = 120.0
var chain_damage_mult: float = 0.5
var fire_rate_mult: float = 1.0
var projectile_count_bonus: int = 0

# Invincibility
var _invincible: bool = false
var _invincible_timer: float = 0.0
const INVINCIBLE_DURATION: float = 0.5

# Movement
var facing_direction: Vector3 = Vector3.RIGHT

# Flight
var _heading: float = 0.0 # radians, 0 = +X direction
var _turn_speed: float = 0.0
var _current_speed: float = 5000.0
const MAX_TURN_RATE: float = 2.2
const TURN_ACCEL: float = 5.0
const TURN_DECEL: float = 4.0
const SPEED_ACCEL: float = 1000.0
const MIN_SPEED_MULT: float = 0.5
const MAX_SPEED_MULT: float = 2.0
const ALTITUDE_SPEED: float = 150.0
const MIN_ALTITUDE: float = 0.0
const MAX_ALTITUDE: float = 4000.0
var _target_altitude: float = 2000.0

# Banking
var _bank_angle: float = 0.0
const MAX_BANK_ANGLE: float = 0.5 # radians (~28 degrees)
const BANK_LERP_SPEED: float = 6.0

# Flares
var _flare_cooldown: float = 0.0
const FLARE_COOLDOWN: float = 0.3
var _alt_was_pressed: bool = false

# Visual
var _body_color: Color = Color(0.2, 0.7, 1.0)
var _core_color: Color = Color(0.6, 0.9, 1.0)
var _pulse_time: float = 0.0

# 3D node references
var _plane_pivot: Node3D
var _plane_body: Node3D
var _glow_light: OmniLight3D
var _shadow: MeshInstance3D
var _body_mat: StandardMaterial3D

# Child nodes
var pickup_area: Area3D
var hurt_area: Area3D
var weapon_manager: Node3D

func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	_apply_base_stats()
	_setup_collision()
	_setup_pickup_area()
	_setup_hurt_area()
	_setup_weapon_manager()
	_setup_visuals()
	_current_speed = move_speed

func _apply_base_stats() -> void:
	max_health = GameManager.get_stat("max_health")
	health = max_health
	move_speed = GameManager.get_stat("move_speed")
	pickup_range = GameManager.get_stat("pickup_range")
	damage_mult = GameManager.get_stat("damage_mult")
	chain_range = GameManager.get_stat("chain_range")

func _setup_collision() -> void:
	var shape := SphereShape3D.new()
	shape.radius = 16.0
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)

func _setup_pickup_area() -> void:
	pickup_area = Area3D.new()
	pickup_area.collision_layer = 0
	pickup_area.collision_mask = 16
	pickup_area.monitoring = true
	pickup_area.monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = pickup_range
	var col := CollisionShape3D.new()
	col.shape = shape
	pickup_area.add_child(col)
	add_child(pickup_area)
	pickup_area.area_entered.connect(_on_pickup_entered)

func _setup_hurt_area() -> void:
	hurt_area = Area3D.new()
	hurt_area.collision_layer = 0
	hurt_area.collision_mask = 4
	hurt_area.monitoring = true
	hurt_area.monitorable = false
	var shape := SphereShape3D.new()
	shape.radius = 18.0
	var col := CollisionShape3D.new()
	col.shape = shape
	hurt_area.add_child(col)
	add_child(hurt_area)
	hurt_area.area_entered.connect(_on_enemy_contact)

func _setup_weapon_manager() -> void:
	var wm_script := load("res://scripts/weapon_manager.gd")
	weapon_manager = Node3D.new()
	weapon_manager.set_script(wm_script)
	add_child(weapon_manager)

func _setup_visuals() -> void:
	# Glow material for override
	_body_mat = StandardMaterial3D.new()
	_body_mat.albedo_color = _body_color
	_body_mat.emission_enabled = true
	_body_mat.emission = _body_color
	_body_mat.emission_energy_multiplier = 2.0
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	# Hierarchy: Player -> _plane_pivot (heading) -> _plane_body (banking) -> model
	_plane_pivot = Node3D.new()
	add_child(_plane_pivot)

	_plane_body = Node3D.new()
	_plane_pivot.add_child(_plane_body)

	# Load .glb model
	var jet_scene: PackedScene = load("res://assets/Jet.glb")
	if jet_scene == null:
		push_error("Failed to load Jet.glb!")
		return
	var jet_instance: Node3D = jet_scene.instantiate()
	jet_instance.scale = Vector3(15.0, 15.0, 15.0)
	jet_instance.position.y = 30.0 # lift above water for banking
	jet_instance.rotation.y = deg_to_rad(180.0) # nose forward (-Z)
	_plane_body.add_child(jet_instance)

	# Blob shadow on ground
	_shadow = MeshInstance3D.new()
	var shadow_mesh := PlaneMesh.new()
	shadow_mesh.size = Vector2(30.0, 30.0)
	_shadow.mesh = shadow_mesh
	var shadow_mat := StandardMaterial3D.new()
	shadow_mat.albedo_color = Color(0, 0, 0, 0.4)
	shadow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow_mat.no_depth_test = true
	_shadow.material_override = shadow_mat
	_shadow.position.y = 1.0 # just above ground
	add_child(_shadow)

	# Glow light
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = _body_color
	_glow_light.light_energy = 1.5
	_glow_light.omni_range = 80.0
	_glow_light.position.y = 10.0
	add_child(_glow_light)

func _apply_glow_to_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = _body_mat
	for child in node.get_children():
		_apply_glow_to_meshes(child)

func _physics_process(delta: float) -> void:
	# Steering: left/right turns the plane
	var turn_input: float = Input.get_axis("move_left", "move_right")

	# Smoothly accelerate/decelerate turn speed
	if absf(turn_input) > 0.1:
		_turn_speed = move_toward(_turn_speed, turn_input * MAX_TURN_RATE, TURN_ACCEL * delta)
	else:
		_turn_speed = move_toward(_turn_speed, 0.0, TURN_DECEL * delta)

	_heading += _turn_speed * delta

	# Speed control: W = boost, S = brake
	var speed_input: float = Input.get_axis("move_down", "move_up") # W is "up" = positive
	var target_speed: float = move_speed
	if speed_input > 0.1:
		target_speed = move_speed * MAX_SPEED_MULT
	elif speed_input < -0.1:
		target_speed = move_speed * MIN_SPEED_MULT
	_current_speed = move_toward(_current_speed, target_speed, SPEED_ACCEL * delta)

	# Forward direction from heading
	var forward := Vector3(sin(_heading), 0.0, -cos(_heading))
	facing_direction = forward

	# Altitude: Arrow Up = climb, Arrow Down = descend
	var alt_input: float = 0.0
	if Input.is_key_pressed(KEY_UP):
		alt_input += 1.0
	if Input.is_key_pressed(KEY_DOWN):
		alt_input -= 1.0
	_target_altitude = clampf(_target_altitude + alt_input * ALTITUDE_SPEED * delta, MIN_ALTITUDE, MAX_ALTITUDE)

	velocity = forward * _current_speed
	velocity.y = (_target_altitude - global_position.y) * 5.0
	move_and_slide()


	# Flare deployment (Alt key)
	_flare_cooldown = maxf(_flare_cooldown - delta, 0.0)
	var alt_pressed: bool = Input.is_key_pressed(KEY_ALT)
	if alt_pressed and not _alt_was_pressed and _flare_cooldown <= 0.0:
		if not get_tree().get_nodes_in_group("enemy_projectile").is_empty():
			_deploy_flare()
			_flare_cooldown = FLARE_COOLDOWN
	_alt_was_pressed = alt_pressed

	# Invincibility
	if _invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_invincible = false
			visible = true

	_pulse_time += delta
	_update_visuals(delta)

func _update_visuals(delta: float) -> void:
	# Heading rotation (negated to match Godot's Y-rotation convention)
	if _plane_pivot:
		_plane_pivot.rotation.y = -_heading

	# Banking based on turn speed
	var target_bank: float = -(_turn_speed / MAX_TURN_RATE) * MAX_BANK_ANGLE
	_bank_angle = lerp(_bank_angle, target_bank, BANK_LERP_SPEED * delta)
	if _plane_body:
		_plane_body.rotation.z = _bank_angle

	# Shadow: stays on ground, grows and fades with altitude
	if _shadow:
		_shadow.position.y = -global_position.y + 1.0 # keep on ground
		var alt_ratio: float = clampf(global_position.y / MAX_ALTITUDE, 0.0, 1.0)
		var shadow_scale: float = 1.0 + alt_ratio * 2.0 # bigger when higher
		_shadow.scale = Vector3(shadow_scale, 1.0, shadow_scale)
		var shadow_mat := _shadow.material_override as StandardMaterial3D
		if shadow_mat:
			shadow_mat.albedo_color.a = 0.4 * (1.0 - alt_ratio * 0.7) # fades when higher

	# Pulse glow
	var pulse: float = (sin(_pulse_time * 3.0) + 1.0) * 0.5
	if _glow_light:
		_glow_light.light_energy = 1.0 + pulse * 1.0

func take_damage(amount: float) -> void:
	if _invincible:
		return
	health -= amount
	health_changed.emit(health, max_health)

	_invincible = true
	_invincible_timer = INVINCIBLE_DURATION
	_flash_hit()

	# Effects
	EffectsManager.screen_shake(6.0, 0.15)
	EffectsManager.chromatic_pulse(0.005)
	var hit_particles := Particles.player_hit(global_position)
	get_tree().current_scene.add_child(hit_particles)

	if health <= 0.0:
		health = 0.0
		died.emit()

func heal(amount: float) -> void:
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)

func _flash_hit() -> void:
	# Blink visibility for invincibility
	var tween := create_tween()
	for i in 5:
		tween.tween_callback(func(): visible = false).set_delay(0.04)
		tween.tween_callback(func(): visible = true).set_delay(0.04)
	tween.tween_callback(func(): visible = true)

func _on_pickup_entered(area: Area3D) -> void:
	if area.has_method("collect"):
		area.collect()

func _on_enemy_contact(area: Area3D) -> void:
	if area.is_in_group("enemy") and area.has_method("get_contact_damage"):
		take_damage(area.get_contact_damage())

func _deploy_flare() -> void:
	var flare_script := load("res://scripts/flare.gd")
	var flare := Area3D.new()
	flare.set_script(flare_script)
	var backward := -facing_direction * 300.0
	backward.y = -50.0
	flare.setup(backward)
	get_tree().current_scene.call_deferred("add_child", flare)
	flare.set_deferred("global_position", global_position)

func get_nearest_enemy() -> Node3D:
	var enemies := get_tree().get_nodes_in_group("enemy")
	var nearest: Node3D = null
	var nearest_dist: float = INF
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var dist: float = global_position.distance_to(enemy.global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest = enemy
	return nearest
