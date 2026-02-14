extends Node3D
## Core gameplay scene. Manages game loop, spawning, chain lightning, effects.

@onready var enemy_container: Node3D = $EnemyContainer
@onready var pickup_container: Node3D = $PickupContainer
@onready var projectile_container: Node3D = $ProjectileContainer
@onready var hud: CanvasLayer = $HUD

var player: CharacterBody3D
var camera: Camera3D

# Enemy spawning
var _spawn_timer: float = 0.0
var _spawn_interval: float = 1.2
var _spawn_count: int = 2
var _difficulty_timer: float = 0.0
var _difficulty_level: int = 0
var _enemy_speed_mult: float = 1.0
const DIFFICULTY_INTERVAL: float = 30.0
const SPAWN_DISTANCE_MIN: float = 1500.0
const SPAWN_DISTANCE_MAX: float = 2500.0
const MAX_ENEMIES: int = 150

# Chain lightning
var _chain_arcs: Array[Dictionary] = []
const CHAIN_ARC_DURATION: float = 0.2
var _chain_active: bool = false
var _lightning_mesh: MeshInstance3D
var _lightning_mat: StandardMaterial3D

# Pickup attraction
var _attract_timer: float = 0.0
const ATTRACT_CHECK_INTERVAL: float = 0.15

# Preloaded scenes
var enemy_scene: PackedScene
var xp_gem_scene: PackedScene
var volt_pickup_scene: PackedScene
var player_scene: PackedScene

# Background
var _bg_shader_mat: ShaderMaterial
var _ground: MeshInstance3D
var _game_time: float = 0.0

# Ambient particles
var _ambient_particles: CPUParticles3D

func _ready() -> void:
	enemy_scene = load("res://scenes/entities/enemy.tscn")
	xp_gem_scene = load("res://scenes/entities/xp_gem.tscn")
	volt_pickup_scene = load("res://scenes/entities/volt_pickup.tscn")
	player_scene = load("res://scenes/entities/player.tscn")

	# Spawn player
	player = player_scene.instantiate()
	add_child(player)
	player.global_position = Vector3(0, 2000, 0)
	player.died.connect(_on_player_died)

	# Camera (orthographic, top-down)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70.0
	camera.position = Vector3(0, 250, 350)
	camera.rotation_degrees = Vector3(-30, 0, 0)
	camera.near = 1.0
	camera.far = 50000.0
	player.add_child(camera)
	camera.make_current()

	# Ground plane with background shader
	_setup_background()

	# Directional light
	var dir_light := DirectionalLight3D.new()
	dir_light.rotation_degrees = Vector3(-90, 0, 0)
	dir_light.light_energy = 0.8
	add_child(dir_light)

	# Ambient floating particles
	_ambient_particles = Particles.ambient_float()
	player.add_child(_ambient_particles)

	# Lightning mesh container
	_lightning_mesh = MeshInstance3D.new()
	_lightning_mesh.position.y = 2.0
	_lightning_mat = StandardMaterial3D.new()
	_lightning_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_lightning_mat.vertex_color_use_as_albedo = true
	_lightning_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_lightning_mat.no_depth_test = true
	_lightning_mesh.material_override = _lightning_mat
	add_child(_lightning_mesh)

	# HUD
	hud.setup(player)

	# Start run
	GameManager.start_run()
	GameManager.player_leveled_up.connect(_on_player_leveled_up)

func _setup_background() -> void:
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200000, 200000)
	plane.subdivide_width = 256
	plane.subdivide_depth = 256
	_ground.mesh = plane
	_ground.position = Vector3(0, -18, 0)

	var shader := load("res://shaders/background.gdshader")
	if shader:
		_bg_shader_mat = ShaderMaterial.new()
		_bg_shader_mat.shader = shader
		_ground.material_override = _bg_shader_mat

	add_child(_ground)

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	_spawn_timer += delta
	_difficulty_timer += delta
	_attract_timer += delta
	_game_time += delta

	# Background follows player so terrain never ends
	if _ground:
		_ground.global_position.x = player.global_position.x
		_ground.global_position.z = player.global_position.z
	if _bg_shader_mat:
		_bg_shader_mat.set_shader_parameter("offset", Vector2(player.global_position.x, player.global_position.z))
		_bg_shader_mat.set_shader_parameter("time_val", _game_time)

	# Spawn enemies
	if _spawn_timer >= _spawn_interval:
		_spawn_timer = 0.0
		_spawn_enemies()

	# Difficulty ramp
	if _difficulty_timer >= DIFFICULTY_INTERVAL:
		_difficulty_timer = 0.0
		_increase_difficulty()

	# Pickup attraction
	if _attract_timer >= ATTRACT_CHECK_INTERVAL:
		_attract_timer = 0.0
		_attract_nearby_pickups()

	# Chain arc decay
	_update_chain_arcs(delta)

	# Update lightning visual
	_update_lightning_mesh()

	# HUD
	hud.update_display()

# --- Spawning ---

func _spawn_enemies() -> void:
	if not enemy_scene or not is_instance_valid(player):
		return
	if enemy_container.get_child_count() >= MAX_ENEMIES:
		return

	for i in _spawn_count:
		var angle := randf() * TAU
		var dist := randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
		var spawn_pos := player.global_position + Vector3(cos(angle) * dist, randf_range(-50, 50), sin(angle) * dist)

		var enemy: Area3D = enemy_scene.instantiate()
		enemy.target = player

		var type_roll := randf()
		if _difficulty_level >= 4 and type_roll < 0.1:
			enemy.configure(enemy.EnemyType.TANK, 1.0 + _difficulty_level * 0.15)
		elif _difficulty_level >= 2 and type_roll < 0.3:
			enemy.configure(enemy.EnemyType.FAST, 1.0 + _difficulty_level * 0.15)
		elif _difficulty_level >= 1 and type_roll < 0.2:
			enemy.configure(enemy.EnemyType.SWARM, 1.0 + _difficulty_level * 0.15)
		else:
			enemy.configure(enemy.EnemyType.BASIC, 1.0 + _difficulty_level * 0.15)

		# Point enemy toward player on spawn (incoming bogey!)
		var to_player := player.global_position - spawn_pos
		to_player.y = 0.0
		enemy._heading = atan2(to_player.x, -to_player.z)
		# Ramp enemy speed with difficulty
		enemy.speed *= _enemy_speed_mult

		enemy.enemy_died.connect(_on_enemy_died)
		enemy_container.add_child(enemy)
		enemy.global_position = spawn_pos

func _increase_difficulty() -> void:
	_difficulty_level += 1
	_spawn_interval = maxf(_spawn_interval * 0.88, 0.25)
	_spawn_count = mini(_spawn_count + 1, 15)
	# Enemies get faster each wave — ramp toward Top Gun insanity
	_enemy_speed_mult = 1.0 + _difficulty_level * 0.15

# --- Enemy death ---

func _on_enemy_died(pos: Vector3, xp_value: int) -> void:
	_spawn_xp_gem(pos, xp_value)
	if randf() < 0.12:
		_spawn_volt_pickup(pos)
	_try_chain_lightning(pos)

func _spawn_xp_gem(pos: Vector3, value: int) -> void:
	if not xp_gem_scene:
		return
	var gem: Area3D = xp_gem_scene.instantiate()
	gem.setup(value)
	pickup_container.call_deferred("add_child", gem)
	gem.set_deferred("global_position", pos + Vector3(randf_range(-10, 10), 0, randf_range(-10, 10)))

func _spawn_volt_pickup(pos: Vector3) -> void:
	if not volt_pickup_scene:
		return
	var volt: Area3D = volt_pickup_scene.instantiate()
	pickup_container.call_deferred("add_child", volt)
	volt.set_deferred("global_position", pos)

# --- Chain lightning ---

func _try_chain_lightning(origin_pos: Vector3) -> void:
	if _chain_active or not is_instance_valid(player):
		return
	_chain_active = true

	var chain_range: float = player.chain_range
	var chain_damage: float = player.damage_mult * 8.0 * player.chain_damage_mult
	var hit_positions: Array[Vector3] = [origin_pos]
	var sources: Array[Vector3] = [origin_pos]
	var max_chains: int = 5
	var chains_done: int = 0

	while sources.size() > 0 and chains_done < max_chains:
		var check_pos: Vector3 = sources.pop_front()

		for enemy in enemy_container.get_children():
			if chains_done >= max_chains:
				break
			if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
				continue
			var dist: float = check_pos.distance_to(enemy.global_position)
			if dist > 0.1 and dist <= chain_range:
				var already_hit: bool = false
				for hp in hit_positions:
					if hp.distance_to(enemy.global_position) < 5.0:
						already_hit = true
						break
				if already_hit:
					continue

				_chain_arcs.append({
					"from": check_pos,
					"to": enemy.global_position,
					"timer": CHAIN_ARC_DURATION,
				})

				var spark := Particles.chain_spark(enemy.global_position)
				add_child(spark)

				hit_positions.append(enemy.global_position)
				sources.append(enemy.global_position)
				chains_done += 1
				enemy.take_damage(chain_damage)
				break

	if chains_done >= 3:
		EffectsManager.big_impact()
	elif chains_done >= 1:
		EffectsManager.chromatic_pulse(0.003)

	_chain_active = false

func _update_chain_arcs(delta: float) -> void:
	var i: int = _chain_arcs.size() - 1
	while i >= 0:
		_chain_arcs[i]["timer"] -= delta
		if _chain_arcs[i]["timer"] <= 0.0:
			_chain_arcs.remove_at(i)
		i -= 1

func _update_lightning_mesh() -> void:
	if _chain_arcs.is_empty():
		_lightning_mesh.mesh = null
		return

	var im := ImmediateMesh.new()

	for arc in _chain_arcs:
		var alpha: float = arc["timer"] / CHAIN_ARC_DURATION
		var from_pos: Vector3 = arc["from"]
		var to_pos: Vector3 = arc["to"]
		_draw_lightning_3d(im, from_pos, to_pos, alpha, 4)

	_lightning_mesh.mesh = im

func _draw_lightning_3d(im: ImmediateMesh, from: Vector3, to: Vector3, alpha: float, segments: int) -> void:
	var dir: Vector3 = to - from
	var perp := Vector3(-dir.z, 0, dir.x).normalized()

	var points: PackedVector3Array = [from]
	for i in range(1, segments):
		var t: float = float(i) / float(segments)
		var mid: Vector3 = from + dir * t + perp * randf_range(-18.0, 18.0)
		mid.y = 2.0
		points.append(mid)
	points[0].y = 2.0
	points.append(Vector3(to.x, 2.0, to.z))

	# Core bright line
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for p in points:
		im.surface_set_color(Color(1.0, 1.0, 1.0, alpha * 0.8))
		im.surface_add_vertex(p)
	im.surface_end()

	# Glow lines at slight offset
	for offset_y in [-0.5, 0.5]:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for p in points:
			im.surface_set_color(Color(0.4, 0.85, 1.0, alpha * 0.3))
			im.surface_add_vertex(p + Vector3(0, offset_y, 0))
		im.surface_end()

# --- Pickup attraction ---

func _attract_nearby_pickups() -> void:
	if not is_instance_valid(player):
		return
	for pickup in pickup_container.get_children():
		if not is_instance_valid(pickup):
			continue
		if pickup.has_method("attract_to"):
			var dist: float = player.global_position.distance_to(pickup.global_position)
			if dist <= player.pickup_range:
				pickup.attract_to(player)

# --- Player events ---

func _on_player_leveled_up(level: int) -> void:
	get_tree().paused = true
	if is_instance_valid(player):
		var burst := Particles.level_up_burst(player.global_position)
		add_child(burst)
		EffectsManager.screen_flash(Color(0.3, 0.7, 1.0), 0.2)
		EffectsManager.chromatic_pulse(0.006)
	hud.show_upgrade_selection()

func _on_player_died() -> void:
	GameManager.end_run()
	EffectsManager.screen_flash(Color(1.0, 0.2, 0.2), 0.4)
	EffectsManager.chromatic_pulse(0.015)
	EffectsManager.screen_shake(15.0, 0.4)
	await get_tree().create_timer(0.5).timeout
	GameManager.show_midgame_ad(func():
		get_tree().change_scene_to_file("res://scenes/game_over.tscn")
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause"):
		if not hud.is_upgrade_open():
			get_tree().paused = !get_tree().paused
