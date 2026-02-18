extends Node3D
## Core gameplay scene. Manages game loop, spawning, chain lightning, effects.

@onready var enemy_container: Node3D = $EnemyContainer
@onready var pickup_container: Node3D = $PickupContainer
@onready var projectile_container: Node3D = $ProjectileContainer
@onready var hud: CanvasLayer = $HUD

var player: CharacterBody3D
var camera: Camera3D

# Wave spawning
var _current_wave: int = 0
var _wave_spawned: bool = false
const SPAWN_DISTANCE_MIN: float = 5000.0
const SPAWN_DISTANCE_MAX: float = 8000.0
const WAVE_DELAY: float = 3.0  # seconds between waves
var _wave_delay_timer: float = 0.0
var _waiting_for_next_wave: bool = false

# Wave config: each wave is a dictionary of EnemyType -> count
# Difficulty scales with wave index
const WAVE_CONFIG: Array[Dictionary] = [
	{"BASIC": 1},
	{"BASIC": 2},
	{"BASIC": 2, "FAST": 1},
	{"BASIC": 1, "FAST": 2, "SWARM": 1},
	{"BASIC": 1, "FAST": 2, "SWARM": 3},
]

# Tutorial
enum TutorialStep { INTRO, WAIT_FLARE, WAIT_KILL_GUN, DONE }
var _tutorial_step: TutorialStep = TutorialStep.INTRO
var _tutorial_timer: float = 0.0
var _tutorial_enemy_1_dead: bool = false
var _tutorial_enemy_2_spawned: bool = false
var _tutorial_missile_warned: bool = false

# AWACS message queue
var _awacs_queue: Array[Dictionary] = []
var _awacs_current: Dictionary = {}
var _awacs_timer: float = 0.0

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

# Camera chase
const CAM_DIST: float = 350.0
const CAM_HEIGHT: float = 250.0
const CAM_LERP: float = 5.0
var _cam_initialized: bool = false

# Background
var _bg_shader_mat: ShaderMaterial
var _ground: MeshInstance3D
var _game_time: float = 0.0

# Ambient particles
var _ambient_particles: CPUParticles3D

# Audio
var _splash_sound: AudioStreamPlayer

# Carrier
var _carrier: Node3D

# Landing sequence
enum GamePhase { TUTORIAL, COMBAT, LANDING_APPROACH, LANDED }
var _phase: GamePhase = GamePhase.TUTORIAL
var _carrier_heading: float = 0.0
var _carrier_mesh_y: float = 150.0   # carrier mesh origin
var _carrier_deck_y: float = 70.0    # just above visual deck (deck at ~53)
var _landing_timer: float = 0.0
var _scroll_blend: float = 1.0          # 1.0 = fast arcade scroll, 0.0 = world-correct
var _landing_offset_base: Vector2       # player pos when landing started
const LANDING_ZONE_RADIUS: float = 900.0  # carrier is ~2000 units long at scale 500
const LANDING_ALT_THRESHOLD: float = 30.0  # must be close to deck level
const LANDING_SPEED_FACTOR: float = 0.65  # must brake to 65% of cruise speed
const LANDING_HEADING_TOL: float = 0.35  # ~20 degrees
const LANDING_FAIL_DIST: float = 400.0   # must be aligned when this close
const LANDING_FAIL_ALT: float = 80.0     # altitude window for fail check


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

	# Camera (chase cam behind player)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 70.0
	camera.near = 1.0
	camera.far = 50000.0
	add_child(camera)
	camera.make_current()

	# Sky/background color matching horizon_color in the ocean shader
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.3
	camera.environment = env

	# Ground plane with background shader
	_setup_background()

	# Aircraft carrier on the ocean
	_setup_carrier()

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

	# Splash radio callout on enemy kill
	var splash_stream: AudioStream = load("res://assets/audio/splash.mp3")
	if splash_stream:
		_splash_sound = AudioStreamPlayer.new()
		_splash_sound.stream = splash_stream
		_splash_sound.volume_db = -2.0
		_splash_sound.bus = &"Master"
		add_child(_splash_sound)

	# Start run
	GameManager.start_run()
	GameManager.player_leveled_up.connect(_on_player_leveled_up)

func _setup_background() -> void:
	_ground = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100000, 100000)
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

func _setup_carrier() -> void:
	var carrier_scene: PackedScene = load("res://assets/carrier/essex_scb-125_generic.glb")
	if not carrier_scene:
		return

	# Node3D container — mesh and collision as separate children
	_carrier = Node3D.new()
	_carrier.position = Vector3(0, -9999, 0)  # hidden until landing
	_carrier.visible = false

	# Visual model (scaled 500x)
	var carrier_model: Node3D = carrier_scene.instantiate()
	carrier_model.scale = Vector3(500.0, 500.0, 500.0)
	_carrier.add_child(carrier_model)

	add_child(_carrier)

func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	_attract_timer += delta
	_game_time += delta

	# Chase camera: smooth follow behind player
	var behind := Vector3(-sin(player._heading), 0.0, cos(player._heading)) * CAM_DIST
	var target_pos := player.global_position + behind + Vector3(0, CAM_HEIGHT, 0)
	if not _cam_initialized:
		camera.global_position = target_pos
		_cam_initialized = true
	else:
		camera.global_position = camera.global_position.lerp(target_pos, CAM_LERP * delta)
	camera.look_at(player.global_position + player.facing_direction * 200.0, Vector3.UP)

	# Dynamic FOV: wider at high speed, narrower when slow
	var speed_ratio: float = player._current_speed / player.move_speed
	var target_fov: float = 60.0 + speed_ratio * 25.0  # 60° slow, 85° at cruise, 110° at boost
	camera.fov = lerpf(camera.fov, target_fov, delta * 3.0)

	# Background follows player so terrain never ends (but freezes during landing)
	if _ground and _phase != GamePhase.LANDING_APPROACH and _phase != GamePhase.LANDED:
		_ground.global_position.x = player.global_position.x
		_ground.global_position.z = player.global_position.z
	if _bg_shader_mat:
		if _phase == GamePhase.LANDING_APPROACH or _phase == GamePhase.LANDED:
			# Freeze offset so ocean pattern is fixed in world space — carrier stays pinned
			_bg_shader_mat.set_shader_parameter("time_val", _game_time)
		else:
			var pp := Vector2(player.global_position.x, player.global_position.z)
			_bg_shader_mat.set_shader_parameter("offset", pp)
			_bg_shader_mat.set_shader_parameter("time_val", _game_time)

	# AWACS message system
	_update_awacs(delta)

	# Phase-specific logic
	if _phase == GamePhase.TUTORIAL:
		_update_tutorial(delta)
	elif _phase == GamePhase.COMBAT:
		# Wave spawning
		if _current_wave < WAVE_CONFIG.size():
			if not _wave_spawned:
				_spawn_wave_from_config(_current_wave)
				_wave_spawned = true
			elif _waiting_for_next_wave:
				_wave_delay_timer += delta
				if _wave_delay_timer >= WAVE_DELAY:
					_waiting_for_next_wave = false
					_wave_delay_timer = 0.0
					_current_wave += 1
					_wave_spawned = false
			elif enemy_container.get_child_count() == 0:
				_waiting_for_next_wave = true
				_wave_delay_timer = 0.0
				awacs_message("AREA CLEAR. STANDBY.", 3.0)

		# Landing trigger: all waves done and all enemies dead
		if _current_wave >= WAVE_CONFIG.size() and enemy_container.get_child_count() == 0:
			awacs_message("ALL TARGETS DOWN. RTB -- CARRIER AHEAD.", 4.0)
			_begin_landing_sequence()

	# Landing approach update
	if _phase == GamePhase.LANDING_APPROACH:
		_update_landing(delta)

	# Send AWACS text + wave info to HUD
	if _awacs_current.size() > 0:
		hud.set_awacs_message(_awacs_current.get("text", ""))
	else:
		hud.set_awacs_message("")
	if _phase == GamePhase.TUTORIAL:
		hud.set_wave_info(0, 0)
	elif _phase == GamePhase.COMBAT:
		hud.set_wave_info(mini(_current_wave + 1, WAVE_CONFIG.size()), WAVE_CONFIG.size())


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

# --- AWACS message system ---

func awacs_message(text: String, duration: float = 4.0) -> void:
	_awacs_queue.append({"text": text, "duration": duration})

func _update_awacs(delta: float) -> void:
	if _awacs_current.size() > 0:
		_awacs_timer -= delta
		if _awacs_timer <= 0.0:
			_awacs_current = {}
	if _awacs_current.size() == 0 and _awacs_queue.size() > 0:
		_awacs_current = _awacs_queue.pop_front()
		_awacs_timer = _awacs_current.get("duration", 4.0)

# --- Tutorial ---

func _update_tutorial(delta: float) -> void:
	_tutorial_timer += delta

	match _tutorial_step:
		TutorialStep.INTRO:
			if _tutorial_timer >= 2.0:
				awacs_message("BANDIT APPROACHING. STANDBY.", 4.0)
				_spawn_tutorial_enemy(1, true, 150.0)  # 1 missile, tutorial mode, tanky
				_tutorial_step = TutorialStep.WAIT_FLARE
				_tutorial_timer = 0.0

		TutorialStep.WAIT_FLARE:
			# Check for incoming missiles to show flare hint
			if not _tutorial_missile_warned:
				var missiles := get_tree().get_nodes_in_group("enemy_projectile")
				if missiles.size() > 0:
					awacs_message("MISSILE INBOUND! DEPLOY FLARE [F]", 5.0)
					_tutorial_missile_warned = true

			# When enemy 1 is dead, move to gun phase
			if _tutorial_enemy_1_dead and not _tutorial_enemy_2_spawned:
				awacs_message("SPLASH ONE. USE GUN [G] ON NEXT TARGET.", 5.0)
				_tutorial_step = TutorialStep.WAIT_KILL_GUN
				_tutorial_timer = 0.0

		TutorialStep.WAIT_KILL_GUN:
			if _tutorial_timer >= 2.0 and not _tutorial_enemy_2_spawned:
				_spawn_tutorial_enemy(0, true)  # 0 missiles, passive
				_tutorial_enemy_2_spawned = true

			# When all tutorial enemies dead
			if _tutorial_enemy_2_spawned and enemy_container.get_child_count() == 0:
				awacs_message("ALL HOSTILES DOWN. COMBAT BEGINS.", 3.0)
				_tutorial_step = TutorialStep.DONE
				_tutorial_timer = 0.0

		TutorialStep.DONE:
			if _tutorial_timer >= 3.0:
				_phase = GamePhase.COMBAT
				_current_wave = 0
				_wave_spawned = false

func _spawn_tutorial_enemy(missiles: int, tutorial: bool, hp_override: float = 0.0) -> void:
	if not enemy_scene or not is_instance_valid(player):
		return
	# Spawn closer so the enemy reaches firing range quickly
	var angle := randf() * TAU
	var dist := randf_range(2500.0, 3500.0)
	var spawn_pos := player.global_position + Vector3(cos(angle) * dist, randf_range(-30, 30), sin(angle) * dist)

	var enemy: Area3D = enemy_scene.instantiate()
	enemy.target = player
	enemy.configure(enemy.EnemyType.BASIC, 0.5)
	enemy.tutorial_mode = tutorial
	enemy._missiles_remaining = missiles
	# Override HP so the enemy survives long enough to fire
	if hp_override > 0.0:
		enemy.max_hp = hp_override
		enemy.hp = hp_override

	var to_player := player.global_position - spawn_pos
	to_player.y = 0.0
	enemy._heading = atan2(to_player.x, -to_player.z)

	enemy.enemy_died.connect(_on_enemy_died)
	enemy.enemy_died.connect(_on_tutorial_enemy_died)
	enemy_container.add_child(enemy)
	enemy.global_position = spawn_pos

func _on_tutorial_enemy_died(_pos: Vector3, _xp_value: int) -> void:
	if _phase == GamePhase.TUTORIAL and _tutorial_step == TutorialStep.WAIT_FLARE:
		_tutorial_enemy_1_dead = true

# --- Spawning ---

func _spawn_wave_from_config(wave_index: int) -> void:
	if not enemy_scene or not is_instance_valid(player):
		return

	var config: Dictionary = WAVE_CONFIG[wave_index]
	var difficulty_mult: float = 1.0 + wave_index * 0.15

	# AWACS messages for wave start
	awacs_message("WAVE %d -- BANDITS INBOUND" % (wave_index + 1), 3.0)

	# Special warnings for new enemy types
	if wave_index == 2:
		awacs_message("WARNING -- FAST MOVERS DETECTED", 3.0)
	elif wave_index == 3:
		awacs_message("MULTIPLE CONTACTS. SWARM FORMATION.", 3.0)

	# EnemyType enum mapping
	var type_map := {
		"BASIC": 0,  # EnemyType.BASIC
		"FAST": 1,   # EnemyType.FAST
		"SWARM": 3,  # EnemyType.SWARM
	}

	for type_name in config:
		var count: int = config[type_name]
		var enemy_type_val: int = type_map.get(type_name, 0)
		for i in count:
			var angle := randf() * TAU
			var dist := randf_range(SPAWN_DISTANCE_MIN, SPAWN_DISTANCE_MAX)
			var spawn_pos := player.global_position + Vector3(cos(angle) * dist, randf_range(-50, 50), sin(angle) * dist)

			var enemy: Area3D = enemy_scene.instantiate()
			enemy.target = player
			enemy.configure(enemy_type_val, difficulty_mult)

			var to_player := player.global_position - spawn_pos
			to_player.y = 0.0
			enemy._heading = atan2(to_player.x, -to_player.z)

			enemy.enemy_died.connect(_on_enemy_died)
			enemy_container.add_child(enemy)
			enemy.global_position = spawn_pos

# --- Enemy death ---

func _on_enemy_died(pos: Vector3, _xp_value: int) -> void:
	# Pickups disabled for now
	if _splash_sound:
		_splash_sound.play()
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

# --- Landing sequence ---

func _begin_landing_sequence() -> void:
	_phase = GamePhase.LANDING_APPROACH
	_landing_timer = 0.0
	_scroll_blend = 1.0
	_landing_offset_base = Vector2(player.global_position.x, player.global_position.z)
	player.landing_mode = true

	# Position carrier 8000 units ahead
	var forward := Vector3(sin(player._heading), 0.0, -cos(player._heading))
	var carrier_pos := player.global_position + forward * 8000.0
	carrier_pos.y = _carrier_mesh_y
	_carrier.global_position = carrier_pos
	_carrier.visible = true

	# Align carrier: stern faces player (rotated 180°) so the angled deck
	# approach comes from the aft end — one clear runway, no tower confusion
	var look_target := _carrier.global_position + forward
	_carrier.look_at(Vector3(look_target.x, _carrier_mesh_y, look_target.z), Vector3.UP)
	_carrier.rotate_y(-PI * 0.5 - deg_to_rad(8.0) + PI)
	_carrier_heading = player._heading

	print("=== LANDING SEQUENCE STARTED ===")
	print("Carrier pos: ", _carrier.global_position)
	print("Player heading: ", rad_to_deg(player._heading))
	print("Player speed: ", player._current_speed)

	# Tell HUD to start landing guidance
	hud.start_landing_guidance(_carrier, _carrier_heading, _carrier_deck_y)

	EffectsManager.screen_flash(Color(0.3, 0.9, 0.5), 0.15)

func _update_landing(_delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(_carrier):
		return

	# Carrier is stationary — ocean ground is also frozen, so carrier sits on the waves

	var to_carrier: Vector3 = _carrier.global_position - player.global_position
	var dist_horiz: float = Vector2(to_carrier.x, to_carrier.z).length()

	# Deck collision clamp: prevent player from descending below deck when near carrier
	if dist_horiz < LANDING_ZONE_RADIUS:
		var min_alt: float = _carrier_deck_y + 15.0  # just above deck visual
		if player.global_position.y < min_alt:
			player.global_position.y = min_alt
			player._target_altitude = maxf(player._target_altitude, min_alt)

	var alt_diff: float = player.global_position.y - _carrier_deck_y
	var heading_diff: float = absf(fposmod(player._heading - _carrier_heading + PI, TAU) - PI)

	# Check landing conditions — speed threshold relative to cruise speed
	var landing_speed_max: float = player.move_speed * LANDING_SPEED_FACTOR
	var speed_ok: bool = player._current_speed < landing_speed_max
	var dist_ok := dist_horiz < LANDING_ZONE_RADIUS
	var alt_ok := alt_diff < LANDING_ALT_THRESHOLD and alt_diff > -50.0
	var hdg_ok := heading_diff < LANDING_HEADING_TOL

	# Lateral offset (same formula as HUD)
	var runway_dir := Vector3(sin(_carrier_heading), 0.0, -cos(_carrier_heading))
	var perp := Vector3(-runway_dir.z, 0.0, runway_dir.x)
	var lateral: float = absf(to_carrier.dot(perp) - 150.0)  # 150 port offset
	var lat_ok := lateral < 100.0

	if dist_ok and alt_ok and hdg_ok and speed_ok and lat_ok:
		_landing_timer += _delta
		if _landing_timer > 0.5:
			print(">>> LANDING SUCCESS! speed=%.0f (max=%.0f)" % [player._current_speed, landing_speed_max])
			_on_landing_success()
	else:
		_landing_timer = maxf(_landing_timer - _delta * 2.0, 0.0)

		# Fail check: close to carrier at deck altitude but not aligned
		if dist_horiz < LANDING_FAIL_DIST and alt_diff < LANDING_FAIL_ALT and alt_diff > -50.0:
			if not speed_ok or not hdg_ok or not lat_ok:
				_on_landing_failed()

func _on_landing_failed() -> void:
	_phase = GamePhase.LANDED  # stop further checks
	player.set_physics_process(false)

	EffectsManager.screen_flash(Color(1.0, 0.1, 0.1), 0.4)
	EffectsManager.screen_shake(10.0, 0.3)

	hud.stop_landing_guidance()
	hud.show_landing_failed()

	await get_tree().create_timer(2.5).timeout
	GameManager.end_run()
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func _on_landing_success() -> void:
	_phase = GamePhase.LANDED
	player._current_speed = 0.0
	player.global_position.y = _carrier_deck_y + 15.0  # snap above deck so plane doesn't clip
	player.set_physics_process(false)

	EffectsManager.screen_flash(Color(0.3, 1.0, 0.5), 0.3)
	EffectsManager.chromatic_pulse(0.01)

	hud.stop_landing_guidance()

	await get_tree().create_timer(1.5).timeout
	GameManager.end_run()
	hud.show_victory()

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
	# DEBUG: press L to skip straight to landing
	if event is InputEventKey and event.pressed and event.keycode == KEY_L:
		if _phase == GamePhase.TUTORIAL or _phase == GamePhase.COMBAT:
			for e in enemy_container.get_children():
				e.queue_free()
			_begin_landing_sequence()
