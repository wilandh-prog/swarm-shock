extends Node3D
## Lock-on missile system. Tracks best target, shows green reticle, fires homing missiles.

var player: CharacterBody3D = null
var projectile_scene: PackedScene

# Weapon stats
var missile_damage: float = 20.0
var fire_rate: float = 0.3
var missile_speed: float = 1200.0
var missile_turn_rate: float = 3.0
var missile_count: int = 1
var _cooldown: float = 0.0

# Lock-on
var locked_target: Node3D = null
const LOCK_RANGE: float = 3000.0
const LOCK_CONE: float = 0.6  # dot product threshold (~53 degrees)
var _reticle: Node3D = null

func _ready() -> void:
	projectile_scene = load("res://scenes/entities/projectile.tscn")
	player = get_parent() as CharacterBody3D
	_create_reticle()

func _process(delta: float) -> void:
	if not player:
		return

	_update_lock_on()
	_update_reticle()

	if _cooldown > 0.0:
		_cooldown -= delta * player.fire_rate_mult
	if Input.is_action_pressed("shoot") and _cooldown <= 0.0:
		_cooldown = fire_rate
		_fire_missiles()

func _update_lock_on() -> void:
	var heading: float = player._heading
	var fwd := Vector3(sin(heading), 0.0, -cos(heading))
	var best_score: float = -1.0
	locked_target = null

	var enemies := get_tree().get_nodes_in_group("enemy")
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var to_enemy: Vector3 = enemy.global_position - player.global_position
		var dist: float = to_enemy.length()
		if dist > LOCK_RANGE or dist < 10.0:
			continue
		var dir: Vector3 = to_enemy / dist
		var dot: float = fwd.dot(dir)
		if dot < LOCK_CONE:
			continue
		# Score: prefer enemies directly ahead and closer
		var score: float = dot * (1.0 - dist / LOCK_RANGE)
		if score > best_score:
			best_score = score
			locked_target = enemy

func _create_reticle() -> void:
	_reticle = Node3D.new()
	var green_mat := StandardMaterial3D.new()
	green_mat.albedo_color = Color(0.0, 1.0, 0.2, 0.9)
	green_mat.emission_enabled = true
	green_mat.emission = Color(0.0, 1.0, 0.2)
	green_mat.emission_energy_multiplier = 3.0
	green_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	green_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	green_mat.no_depth_test = true

	# 4 edges of a rectangle
	var size: float = 30.0
	var thickness: float = 2.0
	var half: float = size * 0.5
	var edges := [
		Vector3(0, 0, -half),   # top
		Vector3(0, 0, half),    # bottom
		Vector3(-half, 0, 0),   # left
		Vector3(half, 0, 0),    # right
	]
	var scales := [
		Vector3(size, 1.0, thickness),  # top (wide)
		Vector3(size, 1.0, thickness),  # bottom (wide)
		Vector3(thickness, 1.0, size),  # left (tall)
		Vector3(thickness, 1.0, size),  # right (tall)
	]
	for i in 4:
		var edge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1, 0.5, 1)
		mesh.material = green_mat
		edge.mesh = mesh
		edge.position = edges[i]
		edge.scale = scales[i]
		_reticle.add_child(edge)

	# Corner brackets for extra flair
	var corner_size: float = 8.0
	var corner_t: float = 2.5
	var corners := [
		Vector3(-half, 0, -half), Vector3(half, 0, -half),
		Vector3(-half, 0, half), Vector3(half, 0, half),
	]
	for c_pos in corners:
		# Horizontal bracket arm
		var h := MeshInstance3D.new()
		var hm := BoxMesh.new()
		hm.size = Vector3(corner_size, 1.0, corner_t)
		hm.material = green_mat
		h.mesh = hm
		h.position = c_pos + Vector3(sign(c_pos.x) * corner_size * -0.5, 0.5, 0)
		_reticle.add_child(h)
		# Vertical bracket arm
		var v := MeshInstance3D.new()
		var vm := BoxMesh.new()
		vm.size = Vector3(corner_t, 1.0, corner_size)
		vm.material = green_mat
		v.mesh = vm
		v.position = c_pos + Vector3(0, 0.5, sign(c_pos.z) * corner_size * -0.5)
		_reticle.add_child(v)

	_reticle.visible = false
	get_tree().current_scene.call_deferred("add_child", _reticle)

func _update_reticle() -> void:
	if not _reticle:
		return
	if locked_target and is_instance_valid(locked_target):
		_reticle.visible = true
		_reticle.global_position = locked_target.global_position
	else:
		_reticle.visible = false

func _fire_missiles() -> void:
	var container: Node = _get_projectile_container()
	if not container:
		return
	var heading: float = player._heading
	var aim_dir := Vector3(sin(heading), 0.0, -cos(heading))
	var total: int = missile_count + player.projectile_count_bonus
	var base_dmg: float = missile_damage * player.damage_mult

	for i in total:
		var spread: float = 0.0
		if total > 1:
			spread = deg_to_rad(4.0) * (i - (total - 1) / 2.0)
		var dir: Vector3 = aim_dir.rotated(Vector3.UP, spread)
		var proj: Area3D = projectile_scene.instantiate()
		proj.setup(dir, base_dmg, missile_speed)
		# Assign homing target
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
