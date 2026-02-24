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
const ALTITUDE_SPEED: float = 800.0
const MIN_ALTITUDE: float = 0.0
const MAX_ALTITUDE: float = 4000.0
var _target_altitude: float = 2000.0
var landing_mode: bool = false

# Banking & pitch
var _bank_angle: float = 0.0
var _pitch_angle: float = 0.0
const MAX_BANK_ANGLE: float = 0.5 # radians (~28 degrees)
const MAX_PITCH_ANGLE: float = 0.4 # radians (~23 degrees)
const BANK_LERP_SPEED: float = 6.0

# Flares
var _flare_cooldown: float = 0.0
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
var _shadow: MeshInstance3D
var _body_mat: StandardMaterial3D
var _afterburner_cores: Array[CPUParticles3D] = []
var _afterburner_outers: Array[CPUParticles3D] = []
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
const ALTITUDE_WARNING_THRESHOLD: float = 50.0

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
	_setup_audio()
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

	# Load F-14 model, fallback to Jet.glb
	var jet_scene: PackedScene = load("res://assets/f-14/f14d.glb")
	var f14_model: bool = jet_scene != null
	if not f14_model:
		jet_scene = load("res://assets/Jet.glb")
	if jet_scene == null:
		push_error("Failed to load any plane model!")
		return
	var jet_instance: Node3D = jet_scene.instantiate()
	if f14_model:
		jet_instance.scale = Vector3(15.0, 15.0, 15.0)
		jet_instance.rotation.x = deg_to_rad(-90.0)  # model Y (length) → Godot -Z (forward)
		jet_instance.position.y = 30.0
	else:
		jet_instance.scale = Vector3(15.0, 15.0, 15.0)
		jet_instance.position.y = 30.0
		jet_instance.rotation.y = deg_to_rad(180.0)
	_plane_body.add_child(jet_instance)

	if f14_model:
		_setup_wing_sweep(jet_instance)

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

	# Afterburner flames — one per engine (twin engines)
	# Jet is 15x scale, rotated 180° on Y. Engine nozzles offset in X.
	var engine_positions: Array[Vector3] = [
		Vector3(-12.0, 30.0, 6.0),  # left engine
		Vector3(12.0, 30.0, 6.0),   # right engine
	]

	# Shared meshes/materials (reused by both engines)
	var ab_mesh := CylinderMesh.new()
	ab_mesh.top_radius = 0.5
	ab_mesh.bottom_radius = 2.0
	ab_mesh.height = 8.0
	ab_mesh.radial_segments = 5
	ab_mesh.rings = 1
	var ab_mat := StandardMaterial3D.new()
	ab_mat.albedo_color = Color(1.0, 0.85, 0.6, 0.95)
	ab_mat.emission_enabled = true
	ab_mat.emission = Color(0.8, 0.9, 1.0)
	ab_mat.emission_energy_multiplier = 8.0
	ab_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ab_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ab_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	ab_mesh.material = ab_mat

	var outer_mesh := SphereMesh.new()
	outer_mesh.radius = 2.5
	outer_mesh.height = 5.0
	outer_mesh.radial_segments = 5
	outer_mesh.rings = 2
	var outer_mat := StandardMaterial3D.new()
	outer_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.5)
	outer_mat.emission_enabled = true
	outer_mat.emission = Color(1.0, 0.3, 0.0)
	outer_mat.emission_energy_multiplier = 4.0
	outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outer_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	outer_mesh.material = outer_mat

	# Shared gradients/curves
	var core_scale_curve := Curve.new()
	core_scale_curve.add_point(Vector2(0.0, 0.3))
	core_scale_curve.add_point(Vector2(0.15, 1.0))
	core_scale_curve.add_point(Vector2(1.0, 0.0))

	var flame_grad := Gradient.new()
	flame_grad.set_color(0, Color(0.9, 0.95, 1.0, 1.0))
	flame_grad.add_point(0.2, Color(1.0, 0.9, 0.4, 0.95))
	flame_grad.add_point(0.5, Color(1.0, 0.5, 0.1, 0.8))
	flame_grad.add_point(0.8, Color(1.0, 0.2, 0.05, 0.4))
	flame_grad.set_color(1, Color(0.4, 0.1, 0.05, 0.0))

	var outer_grad := Gradient.new()
	outer_grad.set_color(0, Color(1.0, 0.6, 0.1, 0.6))
	outer_grad.add_point(0.4, Color(1.0, 0.3, 0.05, 0.3))
	outer_grad.set_color(1, Color(0.3, 0.1, 0.0, 0.0))

	for eng_pos in engine_positions:
		# Inner core — tight, bright, white-blue
		var core := CPUParticles3D.new()
		core.amount = 40
		core.lifetime = 0.25
		core.one_shot = false
		core.explosiveness = 0.0
		core.direction = Vector3(0, -1, 0)
		core.spread = 3.0
		core.initial_velocity_min = 120.0
		core.initial_velocity_max = 250.0
		core.gravity = Vector3.ZERO
		core.damping_min = 60.0
		core.damping_max = 120.0
		core.scale_amount_min = 2.0
		core.scale_amount_max = 5.0
		core.scale_amount_curve = core_scale_curve
		core.mesh = ab_mesh
		core.color_ramp = flame_grad
		core.emitting = false
		core.position = eng_pos
		_plane_body.add_child(core)
		_afterburner_cores.append(core)

		# Outer glow — wider, softer, orange
		var outer := CPUParticles3D.new()
		outer.amount = 20
		outer.lifetime = 0.35
		outer.one_shot = false
		outer.explosiveness = 0.0
		outer.direction = Vector3(0, -1, 0)
		outer.spread = 10.0
		outer.initial_velocity_min = 60.0
		outer.initial_velocity_max = 140.0
		outer.gravity = Vector3.ZERO
		outer.damping_min = 40.0
		outer.damping_max = 100.0
		outer.scale_amount_min = 4.0
		outer.scale_amount_max = 10.0
		outer.scale_amount_curve = Particles._create_fade_curve()
		outer.mesh = outer_mesh
		outer.color_ramp = outer_grad
		outer.emitting = false
		outer.position = eng_pos
		_plane_body.add_child(outer)
		_afterburner_outers.append(outer)

		# Glow light per engine
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.1)
		light.light_energy = 0.0
		light.omni_range = 60.0
		light.position = eng_pos
		_plane_body.add_child(light)
		_afterburner_lights.append(light)

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
	elif landing_mode:
		target_speed = _current_speed  # Throttle hold: no input = keep speed
	_current_speed = move_toward(_current_speed, target_speed, SPEED_ACCEL * delta)

	# Forward direction from heading
	var forward := Vector3(sin(_heading), 0.0, -cos(_heading))
	facing_direction = forward

	# Altitude: Arrow Down = climb, Arrow Up = descend (inverted, like flight stick)
	var alt_input: float = 0.0
	if Input.is_key_pressed(KEY_DOWN):
		alt_input += 1.0
	if Input.is_key_pressed(KEY_UP):
		alt_input -= 1.0
	_target_altitude = clampf(_target_altitude + alt_input * ALTITUDE_SPEED * delta, MIN_ALTITUDE, MAX_ALTITUDE)

	velocity = forward * _current_speed
	# Landing mode: A/D also gives lateral drift for lineup corrections
	if landing_mode and absf(turn_input) > 0.1:
		var right := Vector3(cos(_heading), 0.0, sin(_heading))
		velocity += right * turn_input * _current_speed * 0.4
	velocity.y = (_target_altitude - global_position.y) * 10.0
	move_and_slide()


	# Flare deployment (Alt key)
	_flare_cooldown = maxf(_flare_cooldown - delta, 0.0)
	var f_pressed: bool = Input.is_key_pressed(KEY_F)
	if f_pressed and not _flare_key_was_pressed and _flare_cooldown <= 0.0:
		_deploy_flare()
		_flare_cooldown = FLARE_COOLDOWN
		if _flare_sound_player:
			_flare_sound_player.play()
	_flare_key_was_pressed = f_pressed

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

	# Pitch based on vertical velocity (climb = nose up, dive = nose down)
	var vert_speed: float = velocity.y if velocity else 0.0
	var max_vert: float = ALTITUDE_SPEED * 10.0  # match velocity.y multiplier
	var target_pitch: float = clampf(vert_speed / max_vert, -1.0, 1.0) * MAX_PITCH_ANGLE
	_pitch_angle = lerp(_pitch_angle, target_pitch, BANK_LERP_SPEED * delta)

	if _plane_body:
		_plane_body.rotation.z = _bank_angle
		_plane_body.rotation.x = _pitch_angle

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

	# Afterburner — ramp up when boosting, fade when not
	var boosting: bool = _current_speed > move_speed * 1.1
	var ab_target: float = 1.0 if boosting else 0.0
	_afterburner_intensity = lerpf(_afterburner_intensity, ab_target, 6.0 * delta)
	var ab_on: bool = _afterburner_intensity > 0.05
	for core in _afterburner_cores:
		core.emitting = ab_on
		core.initial_velocity_min = 120.0 + _afterburner_intensity * 180.0
		core.initial_velocity_max = 250.0 + _afterburner_intensity * 300.0
		core.scale_amount_max = 5.0 + _afterburner_intensity * 8.0
	for outer in _afterburner_outers:
		outer.emitting = ab_on
		outer.initial_velocity_min = 60.0 + _afterburner_intensity * 80.0
		outer.initial_velocity_max = 140.0 + _afterburner_intensity * 160.0
		outer.scale_amount_max = 10.0 + _afterburner_intensity * 8.0
	for light in _afterburner_lights:
		light.light_energy = _afterburner_intensity * 5.0

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
