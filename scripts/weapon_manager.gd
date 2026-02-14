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

# Lock-on (progressive)
var locked_target: Node3D = null
var tracking_target: Node3D = null
var lock_progress: float = 0.0
const LOCK_RANGE: float = 3000.0
const LOCK_CONE: float = 0.6  # dot product threshold (~53 degrees)
const LOCK_SPEED: float = 0.6  # ~1.7s at perfect centering
const LOCK_DECAY: float = 1.0  # lose tracking in ~1s

func _ready() -> void:
	projectile_scene = load("res://scenes/entities/projectile.tscn")
	player = get_parent() as CharacterBody3D

func _process(delta: float) -> void:
	if not player:
		return

	_update_lock_on(delta)

	if _cooldown > 0.0:
		_cooldown -= delta * player.fire_rate_mult
	if Input.is_action_pressed("shoot") and _cooldown <= 0.0:
		_cooldown = fire_rate
		_fire_missiles()

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

	# Find best candidate in cone
	var best_target: Node3D = null
	var best_dot: float = LOCK_CONE

	for enemy in get_tree().get_nodes_in_group("enemy"):
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
		if best_target != tracking_target:
			# Switched target — reset progress
			tracking_target = best_target
			lock_progress = 0.0

		# Progress proportional to how centered (dot remapped from cone..1 → 0..1)
		var center: float = clampf((best_dot - LOCK_CONE) / (1.0 - LOCK_CONE), 0.0, 1.0)
		lock_progress = minf(lock_progress + LOCK_SPEED * center * delta, 1.0)

		if lock_progress >= 1.0:
			locked_target = tracking_target
	else:
		# No target in cone — decay
		lock_progress = maxf(lock_progress - LOCK_DECAY * delta, 0.0)
		if lock_progress <= 0.0:
			tracking_target = null

func _fire_missiles() -> void:
	var container: Node = _get_projectile_container()
	if not container:
		return
	var heading: float = player._heading
	var aim_dir := Vector3(sin(heading), 0.0, -cos(heading))
	# Aim toward locked target if available
	if locked_target and is_instance_valid(locked_target):
		aim_dir = (locked_target.global_position - player.global_position).normalized()
	var total: int = missile_count + player.projectile_count_bonus
	var base_dmg: float = missile_damage * player.damage_mult

	for i in total:
		var spread: float = 0.0
		if total > 1:
			spread = deg_to_rad(4.0) * (i - (total - 1) / 2.0)
		var dir: Vector3 = aim_dir.rotated(Vector3.UP, spread)
		var proj: Area3D = projectile_scene.instantiate()
		proj.setup(dir, base_dmg, missile_speed)
		if locked_target and is_instance_valid(locked_target):
			proj.homing_target = locked_target
			proj.homing_turn_rate = missile_turn_rate
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
