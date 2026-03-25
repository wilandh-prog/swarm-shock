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
const SPEED_ACCEL: float = 200.0
const MIN_SPEED_MULT: float = 0.5
const MAX_SPEED_MULT: float = 2.0
const TURN_SPEED_BLEED: float = 1500.0 # speed lost per second at full turn
const ALTITUDE_SPEED: float = 800.0
const MIN_ALTITUDE: float = -50.0
const MAX_ALTITUDE: float = 4000.0
var _target_altitude: float = 2000.0
var landing_mode: bool = false
var deck_min_altitude: float = -9999.0  # set by game.gd during landing

# Banking & pitch
var _bank_angle: float = 0.0
var _pitch_angle: float = 0.0
const MAX_BANK_ANGLE: float = 0.5 # radians (~28 degrees)
const MAX_PITCH_ANGLE: float = 0.4 # radians (~23 degrees)
const BANK_LERP_SPEED: float = 6.0

# Missile ammo
var missile_ammo: int = 4
var missile_ammo_max: int = 4
var _missile_regen_timer: float = 0.0
const MISSILE_REGEN_INTERVAL: float = 10.0

# Flares
var flare_count: int = 30
var flare_count_max: int = 30
var _flare_cooldown: float = 0.0
var _flare_regen_timer: float = 0.0
const FLARE_REGEN_INTERVAL: float = 8.0
const FLARE_COOLDOWN: float = 0.3
var _flare_key_was_pressed: bool = false

# Visual
var _body_color: Color = Color(0.2, 0.7, 1.0)
var _core_color: Color = Color(0.6, 0.9, 1.0)
var _pulse_time: float = 0.0

# 3D node references
var _plane_pivot: Node3D
var _plane_body: Node3D
var _glow_light: OmniLight3D
var _body_mat: StandardMaterial3D
var _afterburner_meshes: Array[MeshInstance3D] = []
var _afterburner_lights: Array[OmniLight3D] = []
var _afterburner_intensity: float = 0.0

# F-14 variable-sweep wings
var _wing_pivot_right: Node3D
var _wing_pivot_left: Node3D
var _wing_sweep_angle: float = 0.0  # current sweep in radians

# Audio
var _jet_engine_player: AudioStreamPlayer
var _lock_sound_player: AudioStreamPlayer
var _lock_sound_playing: bool = false
var _tracking_sound_player: AudioStreamPlayer
var _tracking_sound_playing: bool = false
var _incoming_sound_player: AudioStreamPlayer
var _incoming_sound_playing: bool = false
var _flare_sound_player: AudioStreamPlayer
var _altitude_sound_player: AudioStreamPlayer
var _altitude_warning_active: bool = false
const ALTITUDE_WARNING_THRESHOLD: float = 100.0

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
	_apply_weapon_upgrades()
	_setup_visuals()
	_setup_audio()
	_current_speed = move_speed

func _apply_base_stats() -> void:
	max_health = GameManager.get_stat("max_health")
	health = max_health
	move_speed = GameManager.get_stat("move_speed")
	pickup_range = GameManager.get_stat("pickup_range")
	damage_mult = GameManager.get_stat("damage_mult")
	chain_range = GameManager.get_stat("chain_range")
	missile_ammo_max = 4 + GameManager.upgrade_levels.get("missile_ammo", 0) * 2
	missile_ammo = missile_ammo_max
	flare_count_max = 30 + GameManager.upgrade_levels.get("flare_count", 0) * 10
	flare_count = flare_count_max

func _apply_weapon_upgrades() -> void:
	if weapon_manager:
		var ls: float = GameManager.get_stat("lock_speed")
		weapon_manager.lock_speed = ls
		# Scale AGM lock speed proportionally (base 1.0 when lock_speed is 0.6)
		weapon_manager.agm_lock_speed = 1.0 * (ls / 0.6)

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

	# Load F-14 model
	var jet_scene: PackedScene = load("res://assets/f-14/f14d.glb")
	if jet_scene == null:
		push_error("Failed to load F-14 model!")
		return
	var jet_instance: Node3D = jet_scene.instantiate()
	jet_instance.scale = Vector3(15.0, 15.0, 15.0)
	jet_instance.rotation.x = deg_to_rad(-90.0)
	jet_instance.position.y = 30.0
	_plane_body.add_child(jet_instance)

	_setup_wing_sweep(jet_instance)

	# Glow handled by emission materials (no dynamic light for perf)

	# Afterburner flames — one per engine (twin engines)
	# F-14 model: 15x scale, rotated -90° on X. Nozzle exit at model Y≈-9.5 → Z≈142.
	var engine_positions: Array[Vector3] = [
		Vector3(-21.0, 30.0, 150.0),  # left engine nozzle
		Vector3(21.0, 30.0, 150.0),   # right engine nozzle
	]

	# Shader-driven afterburner cones
	var ab_shader: Shader = load("res://shaders/afterburner.gdshader")
	var ab_cone := CylinderMesh.new()
	ab_cone.top_radius = 1.0
	ab_cone.bottom_radius = 8.0
	ab_cone.height = 30.0
	ab_cone.radial_segments = 8
	ab_cone.rings = 4

	for eng_pos in engine_positions:
		var mesh_inst := MeshInstance3D.new()
		mesh_inst.mesh = ab_cone
		var mat := ShaderMaterial.new()
		mat.shader = ab_shader
		mat.set_shader_parameter("intensity", 1.0)
		mat.set_shader_parameter("flame_speed", 3.0)
		mat.set_shader_parameter("flame_length", 1.5)
		mesh_inst.material_override = mat
		mesh_inst.position = eng_pos + Vector3(0, 0, 15.0)
		mesh_inst.rotation.x = deg_to_rad(90.0)
		_plane_body.add_child(mesh_inst)
		_afterburner_meshes.append(mesh_inst)


func _setup_audio() -> void:
	# Jet engine — single player, OGG loops seamlessly
	var jet_stream: AudioStreamOggVorbis = load("res://assets/audio/jet_engine.ogg")
	if jet_stream:
		jet_stream.loop = true
		_jet_engine_player = AudioStreamPlayer.new()
		_jet_engine_player.stream = jet_stream
		_jet_engine_player.volume_db = -10.0
		_jet_engine_player.bus = &"Master"
		add_child(_jet_engine_player)
		_jet_engine_player.play()

	# Lock-on tone (full lock) — one-shot
	var lock_stream: AudioStream = load("res://assets/audio/lock.mp3")
	if lock_stream:
		_lock_sound_player = AudioStreamPlayer.new()
		_lock_sound_player.stream = lock_stream
		_lock_sound_player.volume_db = -5.0
		_lock_sound_player.bus = &"Master"
		add_child(_lock_sound_player)

	# Sidewinder tracking tone (acquiring lock)
	var tracking_stream: AudioStream = load("res://assets/audio/sidewinder allmost lock.mp3")
	if tracking_stream:
		tracking_stream.loop = true
		_tracking_sound_player = AudioStreamPlayer.new()
		_tracking_sound_player.stream = tracking_stream
		_tracking_sound_player.volume_db = -5.0
		_tracking_sound_player.bus = &"Master"
		add_child(_tracking_sound_player)

	# Incoming missile warning
	var incoming_stream: AudioStream = load("res://assets/audio/incoming missile.mp3")
	if incoming_stream:
		incoming_stream.loop = true
		_incoming_sound_player = AudioStreamPlayer.new()
		_incoming_sound_player.stream = incoming_stream
		_incoming_sound_player.volume_db = -3.0
		_incoming_sound_player.bus = &"Master"
		add_child(_incoming_sound_player)

	# Flare deploy sound
	var flare_stream: AudioStream = load("res://assets/audio/flare.mp3")
	if flare_stream:
		_flare_sound_player = AudioStreamPlayer.new()
		_flare_sound_player.stream = flare_stream
		_flare_sound_player.volume_db = -3.0
		_flare_sound_player.bus = &"Master"
		add_child(_flare_sound_player)

	# Altitude warning
	var alt_stream: AudioStream = load("res://assets/audio/altitude warning.mp3")
	if alt_stream:
		alt_stream.loop = true
		_altitude_sound_player = AudioStreamPlayer.new()
		_altitude_sound_player.stream = alt_stream
		_altitude_sound_player.volume_db = -3.0
		_altitude_sound_player.bus = &"Master"
		add_child(_altitude_sound_player)

func _apply_glow_to_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		node.material_override = _body_mat
	for child in node.get_children():
		_apply_glow_to_meshes(child)

func _process(delta: float) -> void:
	# --- Flight & input (all in _process for smooth rendering) ---
	var turn_input: float = Input.get_axis("move_left", "move_right")

	var speed_ratio: float = _current_speed / move_speed
	var turn_scale: float = lerpf(1.2, 0.7, clampf((speed_ratio - MIN_SPEED_MULT) / (MAX_SPEED_MULT - MIN_SPEED_MULT), 0.0, 1.0))
	var effective_turn_rate: float = MAX_TURN_RATE * turn_scale

	if absf(turn_input) > 0.1:
		_turn_speed = move_toward(_turn_speed, turn_input * effective_turn_rate, TURN_ACCEL * delta)
	else:
		_turn_speed = move_toward(_turn_speed, 0.0, TURN_DECEL * delta)

	_heading += _turn_speed * delta

	var speed_input: float = Input.get_axis("move_down", "move_up")
	var target_speed: float = move_speed
	if speed_input > 0.1:
		target_speed = move_speed * MAX_SPEED_MULT
	elif speed_input < -0.1:
		target_speed = move_speed * MIN_SPEED_MULT
	elif landing_mode:
		target_speed = _current_speed
	_current_speed = move_toward(_current_speed, target_speed, SPEED_ACCEL * delta)

	var turn_intensity: float = absf(_turn_speed) / MAX_TURN_RATE
	var speed_bleed: float = turn_intensity * turn_intensity * TURN_SPEED_BLEED * delta
	_current_speed = maxf(_current_speed - speed_bleed, move_speed * MIN_SPEED_MULT)

	var forward := Vector3(sin(_heading), 0.0, -cos(_heading))
	facing_direction = forward

	var alt_input: float = 0.0
	if Input.is_key_pressed(KEY_DOWN):
		alt_input += 1.0
	if Input.is_key_pressed(KEY_UP):
		alt_input -= 1.0
	_target_altitude = clampf(_target_altitude + alt_input * ALTITUDE_SPEED * delta, MIN_ALTITUDE, MAX_ALTITUDE)

	# Direct position update (no move_and_slide — no collision needed)
	var move_vel := forward * _current_speed
	if landing_mode and absf(turn_input) > 0.1:
		var right := Vector3(cos(_heading), 0.0, sin(_heading))
		move_vel += right * turn_input * _current_speed * 0.4
	move_vel.y = (_target_altitude - global_position.y) * 10.0
	global_position += move_vel * delta

	# Deck collision clamp (set by game.gd during carrier landing)
	if global_position.y < deck_min_altitude:
		global_position.y = deck_min_altitude
		_target_altitude = maxf(_target_altitude, deck_min_altitude)

	if global_position.y < -10.0:
		take_damage(max_health * 10.0)

	# Missile regen
	if missile_ammo <= 0:
		_missile_regen_timer += delta
		if _missile_regen_timer >= MISSILE_REGEN_INTERVAL:
			_missile_regen_timer -= MISSILE_REGEN_INTERVAL
			missile_ammo = mini(missile_ammo + 1, missile_ammo_max)
	else:
		_missile_regen_timer = 0.0

	# Flare deployment
	_flare_cooldown = maxf(_flare_cooldown - delta, 0.0)
	var f_pressed: bool = Input.is_key_pressed(KEY_F)
	if f_pressed and not _flare_key_was_pressed and _flare_cooldown <= 0.0 and flare_count > 0:
		_deploy_flare()
		flare_count -= 1
		_flare_cooldown = FLARE_COOLDOWN
		if _flare_sound_player:
			_flare_sound_player.play()
	_flare_key_was_pressed = f_pressed

	# Flare regen
	if flare_count < flare_count_max:
		_flare_regen_timer += delta
		if _flare_regen_timer >= FLARE_REGEN_INTERVAL:
			_flare_regen_timer -= FLARE_REGEN_INTERVAL
			flare_count += 1
	else:
		_flare_regen_timer = 0.0

	# Invincibility
	if _invincible:
		_invincible_timer -= delta
		if _invincible_timer <= 0.0:
			_invincible = false
			visible = true

	_pulse_time += delta
	_update_visuals(delta)

func _update_visuals(delta: float) -> void:
	# Heading rotation (direct — movement and visuals both in _process)
	if _plane_pivot:
		_plane_pivot.rotation.y = -_heading

	# Banking based on turn speed
	var target_bank: float = -(_turn_speed / MAX_TURN_RATE) * MAX_BANK_ANGLE
	_bank_angle = lerp(_bank_angle, target_bank, BANK_LERP_SPEED * delta)

	# Pitch based on vertical velocity (climb = nose up, dive = nose down)
	var vert_speed: float = velocity.y if velocity else 0.0
	var max_vert: float = ALTITUDE_SPEED * 10.0  # match velocity.y multiplier
	var target_pitch: float = clampf(vert_speed / max_vert, -1.0, 1.0) * MAX_PITCH_ANGLE
	_pitch_angle = lerp(_pitch_angle, target_pitch, BANK_LERP_SPEED * delta)

	if _plane_body:
		_plane_body.rotation.z = _bank_angle
		_plane_body.rotation.x = _pitch_angle

	# Pulse time (used for visual effects)
	var pulse: float = (sin(_pulse_time * 3.0) + 1.0) * 0.5

	# Afterburner — ramp up when boosting, fade when not
	var boosting: bool = _current_speed > move_speed * 1.1
	var ab_target: float = 1.0 if boosting else 0.15
	_afterburner_intensity = lerpf(_afterburner_intensity, ab_target, 6.0 * delta)
	for mesh_inst in _afterburner_meshes:
		var mat: ShaderMaterial = mesh_inst.material_override
		if mat:
			mat.set_shader_parameter("intensity", _afterburner_intensity)
		mesh_inst.visible = _afterburner_intensity > 0.02

	# Jet engine audio: pitch follows speed
	if _jet_engine_player:
		var speed_ratio: float = _current_speed / move_speed
		_jet_engine_player.pitch_scale = 0.7 + speed_ratio * 0.6

	# Lock-on audio: tracking tone while acquiring, lock tone when locked
	if weapon_manager:
		var has_lock: bool = weapon_manager.locked_target != null and is_instance_valid(weapon_manager.locked_target)
		var is_tracking: bool = not has_lock and weapon_manager.tracking_target != null and is_instance_valid(weapon_manager.tracking_target) and weapon_manager.lock_progress > 0.0

		# Full lock tone
		if _lock_sound_player:
			if has_lock and not _lock_sound_playing:
				_lock_sound_player.play()
				_lock_sound_playing = true
				# Stop tracking tone when we get full lock
				if _tracking_sound_player and _tracking_sound_playing:
					_tracking_sound_player.stop()
					_tracking_sound_playing = false
			elif not has_lock and _lock_sound_playing:
				_lock_sound_player.stop()
				_lock_sound_playing = false

		# Sidewinder tracking tone (acquiring lock)
		if _tracking_sound_player:
			if is_tracking and not _tracking_sound_playing:
				_tracking_sound_player.play()
				_tracking_sound_playing = true
			elif not is_tracking and _tracking_sound_playing:
				_tracking_sound_player.stop()
				_tracking_sound_playing = false

	# Incoming missile warning
	if _incoming_sound_player:
		var has_incoming: bool = not GameManager.enemy_missiles.is_empty()
		if has_incoming and not _incoming_sound_playing:
			_incoming_sound_player.play()
			_incoming_sound_playing = true
		elif not has_incoming and _incoming_sound_playing:
			_incoming_sound_player.stop()
			_incoming_sound_playing = false

	# Altitude warning (below 50m)
	if _altitude_sound_player:
		var low_alt: bool = global_position.y < ALTITUDE_WARNING_THRESHOLD and global_position.y > 0.0
		if low_alt and not _altitude_warning_active:
			_altitude_sound_player.play()
			_altitude_warning_active = true
		elif not low_alt and _altitude_warning_active:
			_altitude_sound_player.stop()
			_altitude_warning_active = false

	# F-14 wing sweep: forward at slow speed, swept back at high speed
	if _wing_pivot_right and _wing_pivot_left:
		# 0.0 at min speed → 1.0 at max speed
		var sweep_t: float = clampf((_current_speed - move_speed * MIN_SPEED_MULT) / (move_speed * MAX_SPEED_MULT - move_speed * MIN_SPEED_MULT), 0.0, 1.0)
		var target_sweep: float = deg_to_rad(MAX_SWEEP_DEG) * sweep_t
		_wing_sweep_angle = lerpf(_wing_sweep_angle, target_sweep, 2.0 * delta)
		# Rotate around Z in model space (right wing: negative = sweep back, left: positive)
		_wing_pivot_right.rotation.z = -_wing_sweep_angle
		_wing_pivot_left.rotation.z = _wing_sweep_angle

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
	var enemies := GameManager.enemies_alive
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

# --- F-14 variable-sweep wings ---

const RIGHT_WING_PARTS: Array[String] = ["Part165", "Part166", "Part168", "Part169", "Part170", "Part171", "Part172"]
const LEFT_WING_PARTS: Array[String] = ["Part174", "Part176", "Part177", "Part178", "Part179", "Part180", "Part181"]
# Hinge point in model space (X=side, Y=length, Z=height)
const WING_HINGE_X: float = 2.3
const WING_HINGE_Y: float = -1.5
const WING_HINGE_Z: float = 0.5
const MAX_SWEEP_DEG: float = 50.0  # additional sweep angle at max speed

func _setup_wing_sweep(model: Node3D) -> void:
	# Create pivot nodes at wing hinge points (model space)
	_wing_pivot_right = Node3D.new()
	_wing_pivot_right.position = Vector3(WING_HINGE_X, WING_HINGE_Y, WING_HINGE_Z)
	model.add_child(_wing_pivot_right)

	_wing_pivot_left = Node3D.new()
	_wing_pivot_left.position = Vector3(-WING_HINGE_X, WING_HINGE_Y, WING_HINGE_Z)
	model.add_child(_wing_pivot_left)

	# Reparent wing meshes to pivot nodes
	for part_name in RIGHT_WING_PARTS:
		_reparent_to_pivot(model, part_name, _wing_pivot_right)
	for part_name in LEFT_WING_PARTS:
		_reparent_to_pivot(model, part_name, _wing_pivot_left)

func _reparent_to_pivot(model: Node3D, part_name: String, pivot: Node3D) -> void:
	var node := _find_node_recursive(model, part_name)
	if not node:
		return
	var old_pos: Vector3 = node.position
	node.get_parent().remove_child(node)
	pivot.add_child(node)
	# Offset position so vertices stay in the same place
	node.position = old_pos - pivot.position

func _find_node_recursive(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node_recursive(child, node_name)
		if found:
			return found
	return null
