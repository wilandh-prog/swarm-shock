extends Node3D
## Lock-on missile system. Progressive lock: circle shrinks as you center the target.

var player: CharacterBody3D = null
var projectile_scene: PackedScene

# Weapon stats
var missile_damage: float = 20.0
var fire_rate: float = 0.3
var missile_speed: float = 2400.0
var missile_turn_rate: float = 4.0
var missile_count: int = 1
var _cooldown: float = 0.0
var _missile_sound: AudioStreamPlayer
var _fox2_sound: AudioStreamPlayer

# Gun
var gun_damage: float = 15.0
var gun_speed: float = 5000.0
var gun_fire_rate: float = 0.08
var gun_spread: float = 1.5  # degrees
var _gun_cooldown: float = 0.0
var _gun_sound: AudioStreamPlayer

# Lock-on (progressive)
var locked_target: Node3D = null
var tracking_target: Node3D = null
var lock_progress: float = 0.0
const LOCK_RANGE: float = 3000.0
var lock_cone: float = 0.6  # dot product threshold (~53 degrees), upgradeable
var lock_speed: float = 0.6  # ~1.7s at perfect centering, upgradeable
const LOCK_DECAY: float = 1.0  # lose tracking in ~1s
var _lock_scan_frame: int = 0  # rate-limit candidate search

# AGM (Anti-Ground Missile) for ships
var agm_damage: float = 80.0
var agm_fire_rate: float = 2.0
var _agm_cooldown: float = 0.0
var _agm_sound: AudioStreamPlayer

# Ship lock-on (separate from air-to-air)
var ship_locked_target: Node3D = null
var ship_tracking_target: Node3D = null
var ship_lock_progress: float = 0.0
const AGM_LOCK_RANGE: float = 15000.0
const AGM_LOCK_CONE: float = 0.5  # ~60° half-cone (wider for big ships)
var agm_lock_speed: float = 1.0  # faster lock for large targets, upgradeable
const AGM_LOCK_DECAY: float = 0.5

func _ready() -> void:
	projectile_scene = load("res://scenes/entities/projectile.tscn")
	player = get_parent() as CharacterBody3D
	var launch_stream: AudioStream = load("res://assets/audio/Missile launch.mp3")
	if launch_stream:
		_missile_sound = AudioStreamPlayer.new()
		_missile_sound.stream = launch_stream
		_missile_sound.volume_db = -5.0
		_missile_sound.bus = &"Master"
		add_child(_missile_sound)
	var fox2_stream: AudioStream = load("res://assets/audio/fox2.mp3")
	if fox2_stream:
		_fox2_sound = AudioStreamPlayer.new()
		_fox2_sound.stream = fox2_stream
		_fox2_sound.volume_db = -2.0
		_fox2_sound.bus = &"Master"
		add_child(_fox2_sound)
	var gun_stream: AudioStream = load("res://assets/audio/gun.mp3")
	if gun_stream:
		_gun_sound = AudioStreamPlayer.new()
		_gun_sound.stream = gun_stream
		_gun_sound.volume_db = 0.0
		_gun_sound.bus = &"Master"
		add_child(_gun_sound)

func _process(delta: float) -> void:
	if not player:
		return

	_lock_scan_frame += 1
	_update_lock_on(delta)
	_update_ship_lock_on(delta)

	if _cooldown > 0.0:
		_cooldown -= delta * player.fire_rate_mult
	if Input.is_action_pressed("shoot") and _cooldown <= 0.0:
		_cooldown = fire_rate
		_fire_missiles()

	# Gun (G key)
	if _gun_cooldown > 0.0:
		_gun_cooldown -= delta * player.fire_rate_mult
	if Input.is_key_pressed(KEY_G) and _gun_cooldown <= 0.0:
		_gun_cooldown = gun_fire_rate
		_fire_gun()
	elif not Input.is_key_pressed(KEY_G) and _gun_sound and _gun_sound.playing:
		_gun_sound.stop()

	# AGM (E key) — requires ship lock
	if _agm_cooldown > 0.0:
		_agm_cooldown -= delta
	if Input.is_key_pressed(KEY_E) and _agm_cooldown <= 0.0:
		if ship_locked_target and is_instance_valid(ship_locked_target):
			_agm_cooldown = agm_fire_rate
			_fire_agm()

func _update_lock_on(delta: float) -> void:
	var heading: float = player._heading
	var fwd := Vector3(sin(heading), 0.0, -cos(heading))

	# If fully locked, keep lock as long as target is in range
	if locked_target and is_instance_valid(locked_target):
		var dist: float = player.global_position.distance_to(locked_target.global_position)
		if dist < LOCK_RANGE:
			tracking_target = locked_target
			return
		# Lost — out of range
		locked_target = null
		tracking_target = null
		lock_progress = 0.0

	# If already tracking, stick with it as long as it's in cone
	if tracking_target and is_instance_valid(tracking_target):
		var to_tt: Vector3 = tracking_target.global_position - player.global_position
		var tt_dist: float = to_tt.length()
		var tt_dot: float = fwd.dot(to_tt / tt_dist) if tt_dist > 1.0 else -1.0
		if tt_dist < LOCK_RANGE and tt_dot > lock_cone:
			# Still valid — advance progress
			var center: float = clampf((tt_dot - lock_cone) / (1.0 - lock_cone), 0.0, 1.0)
			lock_progress = minf(lock_progress + lock_speed * center * delta, 1.0)
			if lock_progress >= 1.0:
				locked_target = tracking_target
			return
		# Tracking target left cone — decay
		lock_progress = maxf(lock_progress - LOCK_DECAY * delta, 0.0)
		if lock_progress <= 0.0:
			tracking_target = null
		return

	# No current tracking target — find best candidate in cone (every 3rd frame)
	if _lock_scan_frame % 3 != 0:
		return
	var best_target: Node3D = null
	var best_dot: float = lock_cone

	for enemy in GameManager.enemies_alive:
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector3 = enemy.global_position - player.global_position
		var dist: float = to_enemy.length()
		if dist > LOCK_RANGE or dist < 10.0:
			continue
		var dot: float = fwd.dot(to_enemy / dist)
		if dot > best_dot:
			best_dot = dot
			best_target = enemy

	if best_target:
		tracking_target = best_target
		lock_progress = 0.0

func _update_ship_lock_on(delta: float) -> void:
	var heading: float = player._heading
	var fwd := Vector3(sin(heading), 0.0, -cos(heading))

	# If fully locked, keep lock while in range
	if ship_locked_target and is_instance_valid(ship_locked_target):
		var dist: float = player.global_position.distance_to(ship_locked_target.global_position)
		if dist < AGM_LOCK_RANGE:
			ship_tracking_target = ship_locked_target
			return
		ship_locked_target = null
		ship_tracking_target = null
		ship_lock_progress = 0.0

	# If tracking, stick with it in cone
	if ship_tracking_target and is_instance_valid(ship_tracking_target):
		var to_tt: Vector3 = ship_tracking_target.global_position - player.global_position
		var tt_dist: float = to_tt.length()
		var tt_dot: float = fwd.dot(to_tt / tt_dist) if tt_dist > 1.0 else -1.0
		if tt_dist < AGM_LOCK_RANGE and tt_dot > AGM_LOCK_CONE:
			var center: float = clampf((tt_dot - AGM_LOCK_CONE) / (1.0 - AGM_LOCK_CONE), 0.0, 1.0)
			ship_lock_progress = minf(ship_lock_progress + agm_lock_speed * center * delta, 1.0)
			if ship_lock_progress >= 1.0:
				ship_locked_target = ship_tracking_target
			return
		ship_lock_progress = maxf(ship_lock_progress - AGM_LOCK_DECAY * delta, 0.0)
		if ship_lock_progress <= 0.0:
			ship_tracking_target = null
		return

	# Find best ship in cone (every 3rd frame)
	if _lock_scan_frame % 3 != 0:
		return
	var best_target: Node3D = null
	var best_dot: float = AGM_LOCK_CONE
	for enemy in GameManager.enemies_alive:
		if not is_instance_valid(enemy):
			continue
		if not enemy.is_in_group("ship"):
			continue
		var to_enemy: Vector3 = enemy.global_position - player.global_position
		var dist: float = to_enemy.length()
		if dist > AGM_LOCK_RANGE or dist < 10.0:
			continue
		var dot: float = fwd.dot(to_enemy / dist)
		if dot > best_dot:
			best_dot = dot
			best_target = enemy

	if best_target:
		ship_tracking_target = best_target
		ship_lock_progress = 0.0

func _fire_agm() -> void:
	if not ship_locked_target or not is_instance_valid(ship_locked_target):
		return
	if _missile_sound:
		_missile_sound.play()
	if _fox2_sound:
		_fox2_sound.play()
	var container: Node = _get_projectile_container()
	if not container:
		return
	var aim_dir: Vector3 = (ship_locked_target.global_position - player.global_position).normalized()
	var spd: float = maxf(4000.0, player._current_speed * 1.5)
	var proj: Area3D = projectile_scene.instantiate()
	proj.setup(aim_dir, agm_damage * player.damage_mult, spd)
	proj.homing_target = ship_locked_target
	proj.homing_turn_rate = 2.0
	proj.explosion_radius = 150.0
	proj.scale = Vector3(4.0, 4.0, 4.0)
	container.add_child(proj)
	proj.global_position = player.global_position

func _fire_missiles() -> void:
	if player.missile_ammo <= 0:
		return
	if _missile_sound:
		_missile_sound.play()
	if _fox2_sound:
		_fox2_sound.play()
	var container: Node = _get_projectile_container()
	if not container:
		return
	var heading: float = player._heading
	var aim_dir := Vector3(sin(heading), 0.0, -cos(heading))
	# Aim toward locked target if available
	if locked_target and is_instance_valid(locked_target):
		aim_dir = (locked_target.global_position - player.global_position).normalized()
	var total: int = mini(missile_count + player.projectile_count_bonus, player.missile_ammo)
	var base_dmg: float = missile_damage * player.damage_mult

	var spd: float = maxf(missile_speed, player._current_speed + 500.0)
	for i in total:
		var spread: float = 0.0
		if total > 1:
			spread = deg_to_rad(4.0) * (i - (total - 1) / 2.0)
		var dir: Vector3 = aim_dir.rotated(Vector3.UP, spread)
		var proj: Area3D = projectile_scene.instantiate()
		proj.setup(dir, base_dmg, spd)
		if locked_target and is_instance_valid(locked_target):
			proj.homing_target = locked_target
			proj.homing_turn_rate = missile_turn_rate
		container.add_child(proj)
		proj.global_position = player.global_position
	player.missile_ammo -= total

func _fire_gun() -> void:
	if _gun_sound and not _gun_sound.playing:
		_gun_sound.play()
	var container: Node = _get_projectile_container()
	if not container:
		return
	var heading: float = player._heading
	var aim_dir := Vector3(sin(heading), 0.0, -cos(heading))

	# Auto-aim: find closest enemy in a wide cone and lead-target it (every 3rd frame cache)
	var best_enemy: Node3D = null
	var best_dot: float = 0.3  # ~72° cone
	for enemy in GameManager.enemies_alive:
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector3 = enemy.global_position - player.global_position
		var dist: float = to_enemy.length()
		if dist < 50.0 or dist > 2000.0:
			continue
		var dot: float = aim_dir.dot(to_enemy / dist)
		if dot > best_dot:
			best_dot = dot
			best_enemy = enemy

	if best_enemy:
		# Lead targeting: aim where enemy will be
		var to_enemy: Vector3 = best_enemy.global_position - player.global_position
		var flight_time: float = to_enemy.length() / gun_speed
		var enemy_vel: Vector3 = Vector3.ZERO
		if best_enemy.has_method("get_velocity"):
			enemy_vel = best_enemy.get_velocity()
		elif best_enemy.get("speed") != null and best_enemy.get("_heading") != null:
			var eh: float = best_enemy._heading
			enemy_vel = Vector3(sin(eh), 0.0, -cos(eh)) * best_enemy.speed
		var predicted: Vector3 = best_enemy.global_position + enemy_vel * flight_time
		aim_dir = (predicted - player.global_position).normalized()

	# Random spread
	var spread_rad: float = deg_to_rad(gun_spread)
	var sx: float = randf_range(-spread_rad, spread_rad)
	var sy: float = randf_range(-spread_rad, spread_rad)
	var dir: Vector3 = aim_dir.rotated(Vector3.UP, sx).rotated(aim_dir.cross(Vector3.UP).normalized(), sy)

	var proj: Area3D = projectile_scene.instantiate()
	proj.is_bullet = true
	proj.lifetime = 2.0
	proj.explosion_radius = 0.0
	proj.setup(dir, gun_damage * player.damage_mult, gun_speed)
	container.add_child(proj)
	proj.global_position = player.global_position

# Upgrade helpers
func upgrade_weapon_damage(multiplier: float) -> void:
	missile_damage *= multiplier

func upgrade_weapon_fire_rate(multiplier: float) -> void:
	fire_rate *= multiplier

func add_projectile_count(amount: int) -> void:
	missile_count += amount

func has_weapon(_weapon_id: String) -> bool:
	return true

func add_weapon(_weapon_id: String) -> void:
	pass

func _get_projectile_container() -> Node:
	var game_node := get_tree().current_scene
	if game_node and game_node.has_node("ProjectileContainer"):
		return game_node.get_node("ProjectileContainer")
	return get_tree().current_scene
