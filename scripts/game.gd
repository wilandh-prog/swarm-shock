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
const WAVE_DELAY: float = 6.0  # seconds between waves

func _get_wave_config() -> Array[Dictionary]:
	if GameManager.game_mode == "wave":
		return WAVE_WAVE_CONFIG
	return MISSION_WAVE_CONFIG
var _wave_delay_timer: float = 0.0
var _waiting_for_next_wave: bool = false

# Wave config: each wave is a dictionary of EnemyType -> count
# Difficulty scales with wave index
# Mission mode waves (tighter progression)
const MISSION_WAVE_CONFIG: Array[Dictionary] = [
	{"BASIC": 1},
	{"BASIC": 2},
	{"BASIC": 2, "FAST": 1},
	{"BASIC": 1, "FAST": 2, "SWARM": 1},
	{"BASIC": 1, "FAST": 2, "SWARM": 3},
]
# Wave mode waves (gentler early game)
const WAVE_WAVE_CONFIG: Array[Dictionary] = [
	{"BASIC": 1},
	{"BASIC": 1},
	{"BASIC": 2},
	{"BASIC": 2},
	{"BASIC": 2, "FAST": 1},
	{"BASIC": 2, "FAST": 1},
	{"BASIC": 2, "FAST": 2},
	{"BASIC": 1, "FAST": 2, "SWARM": 1},
]

# Tutorial
enum TutorialStep { INTRO, WAIT_FLARE, WAIT_KILL_GUN, DONE }
var _tutorial_step: TutorialStep = TutorialStep.INTRO
var _tutorial_timer: float = 0.0
var _tutorial_enemy_1_dead: bool = false
var _tutorial_enemy_2_spawned: bool = false
var _tutorial_missile_warned: bool = false
var _tutorial_shown_flight: bool = false
var _tutorial_shown_lock: bool = false
var _tutorial_shown_missile_fire: bool = false
var _tutorial_shown_gun: bool = false
var _tutorial_shown_flare: bool = false

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
var ammo_pickup_scene: PackedScene
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
enum GamePhase { TUTORIAL, COMBAT, LANDING_APPROACH, LANDED, MISSION_2_LAUNCH, MISSION_2_COMBAT }
var _phase: GamePhase = GamePhase.TUTORIAL
var _mission: int = 1
var _carrier_heading: float = 0.0
var _carrier_mesh_y: float = 150.0   # carrier mesh origin
var _carrier_deck_y: float = 70.0    # just above visual deck (deck at ~53)
var _landing_timer: float = 0.0
var _scroll_blend: float = 1.0          # 1.0 = fast arcade scroll, 0.0 = world-correct
var _landing_offset_base: Vector2       # player pos when landing started
var _original_move_speed: float = 0.0   # saved before landing boost
const LANDING_ZONE_RADIUS: float = 900.0  # carrier is ~2000 units long at scale 500
const LANDING_ALT_THRESHOLD: float = 30.0  # must be close to deck level
const LANDING_SPEED_FACTOR: float = 0.65  # must brake to 65% of cruise speed
const LANDING_HEADING_TOL: float = 0.35  # ~20 degrees
const LANDING_FAIL_DIST: float = 400.0   # must be aligned when this close
const LANDING_FAIL_ALT: float = 80.0     # altitude window for fail check

# Mission 2 — convoy
var _ships_total: int = 0
var _convoy_heading: float = 0.0
var _m2_ships_warned: bool = false
const CONVOY_SHIP_COUNT: int = 3
const CONVOY_SPEED: float = 60.0
const CONVOY_SPACING: float = 800.0
const CONVOY_LATERAL: float = 300.0


func _ready() -> void:
	enemy_scene = load("res://scenes/entities/enemy.tscn")
	xp_gem_scene = load("res://scenes/entities/xp_gem.tscn")
	volt_pickup_scene = load("res://scenes/entities/volt_pickup.tscn")
	ammo_pickup_scene = load("res://scenes/entities/ammo_pickup.tscn")
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

	# Mission 1 briefing
	if GameManager.game_mode == "mission":
		hud.show_mission_briefing("MISSION 1: AIR SUPREMACY",
			"Clear hostile aircraft from the AO.\nOnce skies are clear, land on the carrier\nto prepare for a strike on an enemy convoy.",
			func():
				get_tree().paused = false)

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

	# Background follows player so terrain never ends
	# Freezes during landing and all of mission 2 (ships move over static ocean)
	var _ocean_frozen: bool = _phase in [GamePhase.LANDING_APPROACH, GamePhase.LANDED, GamePhase.MISSION_2_LAUNCH, GamePhase.MISSION_2_COMBAT]
	if _ground and not _ocean_frozen:
		_ground.global_position.x = player.global_position.x
		_ground.global_position.z = player.global_position.z
	if _bg_shader_mat:
		if _ocean_frozen:
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
		# Contextual tutorial text during early waves
		if _current_wave < 2:
			_update_tutorial_text()
		var wc: Array[Dictionary] = _get_wave_config()
		var max_waves: int = wc.size() if GameManager.game_mode == "mission" else 999999
		# Wave spawning
		if _current_wave < max_waves:
			if not _wave_spawned:
				if _current_wave < wc.size():
					_spawn_wave_from_config(_current_wave)
				else:
					_spawn_wave_generated(_current_wave)
				_wave_spawned = true
			elif _waiting_for_next_wave:
				_wave_delay_timer += delta
				if _wave_delay_timer >= WAVE_DELAY:
					_waiting_for_next_wave = false
					_wave_delay_timer = 0.0
					_current_wave += 1
					_wave_spawned = false
					if GameManager.game_mode == "wave" and hud.fighter_hud:
						hud.fighter_hud.show_wave_announcement("WAVE %d" % (_current_wave + 1))
			elif enemy_container.get_child_count() == 0:
				_waiting_for_next_wave = true
				_wave_delay_timer = 0.0
				awacs_message("PICTURE CLEAN. STANDBY FOR TASKING.", 3.0)
				# Level up every 2 waves cleared
				if _current_wave > 0 and _current_wave % 2 == 1:
					_on_player_leveled_up(_current_wave / 2 + 1)

		# Landing trigger: mission mode only, all waves done and all enemies dead
		if GameManager.game_mode == "mission" and _current_wave >= wc.size() and enemy_container.get_child_count() == 0:
			awacs_message("ALL TARGETS SPLASHED. RTB -- MARSHAL CARRIER BRC 270.", 4.0)
			_begin_landing_sequence()

	elif _phase == GamePhase.MISSION_2_COMBAT:
		var ships_left: int = enemy_container.get_child_count()
		if ships_left <= 2 and ships_left > 0 and not _m2_ships_warned:
			awacs_message("%d HOSTILE%s AFLOAT. PRESS ATTACK." % [ships_left, "" if ships_left == 1 else "S"], 3.0)
			_m2_ships_warned = true
		if _ships_total > 0 and ships_left == 0:
			awacs_message("CONVOY NEUTRALIZED. RTB BINGO FUEL.", 4.0)
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
		if GameManager.game_mode == "wave":
			hud.set_wave_info(_current_wave + 1, 0)
		else:
			var mc: Array[Dictionary] = _get_wave_config()
			hud.set_wave_info(mini(_current_wave + 1, mc.size()), mc.size())
	elif _phase in [GamePhase.MISSION_2_LAUNCH, GamePhase.MISSION_2_COMBAT]:
		var destroyed: int = _ships_total - enemy_container.get_child_count()
		hud.set_wave_info(maxi(destroyed, 0), _ships_total)


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
		_speak_awacs(_awacs_current.get("text", ""))

func _speak_awacs(text: String) -> void:
	var clean := text
	# Strip key hints like [F], [G], [SPACE]
	var regex := RegEx.new()
	regex.compile("\\[\\w+\\]")
	clean = regex.sub(clean, "", true)
	# Expand military abbreviations for natural TTS speech
	clean = clean.replace("RTB", "R T B")
	clean = clean.replace("BRAA", "brah")
	clean = clean.replace("BRC", "B R C")
	clean = clean.replace("CAT 1", "cat one")
	clean = clean.replace("--", ",")
	clean = clean.replace("  ", " ")
	clean = clean.strip_edges()
	if clean.is_empty():
		return
	# Slight pauses at punctuation give radio cadence without choppiness
	var rate := 1.3 + clampf(float(clean.split(" ", false).size() - 3) * 0.1, 0.0, 0.7)
	# pitch 1.5 = tinny radio, volume 70
	DisplayServer.tts_speak(clean, "", 70, 1.5, rate)

# --- Tutorial ---

func _update_tutorial(delta: float) -> void:
	_tutorial_timer += delta

	match _tutorial_step:
		TutorialStep.INTRO:
			# Show flight controls at start
			if not _tutorial_shown_flight:
				hud.set_tutorial_text(PackedStringArray([
					"[A] / [D]  TURN",
					"[W] / [S]  SPEED",
					"[UP] / [DOWN]  ALTITUDE",
				]))
				_tutorial_shown_flight = true
			if _tutorial_timer >= 4.0:
				awacs_message("TALLY ONE BANDIT BRAA 360. ENGAGED.", 4.0)
				_spawn_tutorial_enemy(1, true, 150.0)  # 1 missile, tutorial mode, tanky
				_tutorial_step = TutorialStep.WAIT_FLARE
				_tutorial_timer = 0.0

		TutorialStep.WAIT_FLARE:
			# Check for incoming missiles to show flare hint
			if not _tutorial_missile_warned:
				if GameManager.enemy_missiles.size() > 0:
					awacs_message("SPIKE! DEFEND! CHAFF FLARE [F]!", 5.0)
					_tutorial_missile_warned = true

			# When enemy 1 is dead, move to gun phase
			if _tutorial_enemy_1_dead and not _tutorial_enemy_2_spawned:
				awacs_message("SPLASH ONE. BOGEY DOPE -- GUNS GUNS GUNS.", 5.0)
				_tutorial_step = TutorialStep.WAIT_KILL_GUN
				_tutorial_timer = 0.0

		TutorialStep.WAIT_KILL_GUN:
			if _tutorial_timer >= 2.0 and not _tutorial_enemy_2_spawned:
				_spawn_tutorial_enemy(0, true)  # 0 missiles, passive
				_tutorial_enemy_2_spawned = true

			# When all tutorial enemies dead
			if _tutorial_enemy_2_spawned and enemy_container.get_child_count() == 0:
				awacs_message("PICTURE CLEAR. ALPHA CHECK -- WEAPONS FREE.", 3.0)
				_tutorial_step = TutorialStep.DONE
				_tutorial_timer = 0.0

		TutorialStep.DONE:
			if _tutorial_timer >= 3.0:
				_phase = GamePhase.COMBAT
				_current_wave = 0
				_wave_spawned = false

	# Contextual tutorial text — runs every frame during tutorial + early waves
	_update_tutorial_text()

func _update_tutorial_text() -> void:
	if not is_instance_valid(player):
		return
	var wm = player.weapon_manager
	if not wm:
		return

	# Incoming missile → flare prompt (highest priority)
	if GameManager.enemy_missiles.size() > 0:
		hud.set_tutorial_text(PackedStringArray([
			"MISSILE INCOMING!",
			"PRESS [F] TO DEPLOY FLARES",
		]))
		_tutorial_shown_flare = true
		return

	# Full lock → fire prompt
	if wm.locked_target and is_instance_valid(wm.locked_target):
		hud.set_tutorial_text(PackedStringArray([
			"TARGET LOCKED!",
			"PRESS [SPACE] TO FIRE MISSILE",
		]))
		_tutorial_shown_missile_fire = true
		return

	# Tracking → lock explanation
	if wm.tracking_target and is_instance_valid(wm.tracking_target) and wm.lock_progress < 1.0:
		hud.set_tutorial_text(PackedStringArray([
			"LOCKING ON...",
			"AIM AT TARGET -- WAIT FOR LOCK",
			"THEN PRESS [SPACE] TO FIRE MISSILE",
		]))
		_tutorial_shown_lock = true
		return

	# Gun phase
	if _tutorial_step == TutorialStep.WAIT_KILL_GUN or _tutorial_shown_gun:
		hud.set_tutorial_text(PackedStringArray([
			"HOLD [G] TO FIRE GUN",
			"AIM WITH THE PIPPER",
		]))
		_tutorial_shown_gun = true
		return

	# Default: show last relevant hint
	if _tutorial_shown_flare:
		hud.set_tutorial_text(PackedStringArray([
			"[SPACE]  FIRE MISSILE",
			"[G]  GUN    [F]  FLARES",
		]))
	elif _tutorial_shown_missile_fire or _tutorial_shown_lock:
		hud.set_tutorial_text(PackedStringArray([
			"AIM AT TARGET -- WAIT FOR LOCK",
			"PRESS [SPACE] TO FIRE MISSILE",
		]))
	elif _tutorial_step == TutorialStep.INTRO:
		return  # flight controls already showing
	else:
		hud.set_tutorial_text(PackedStringArray([
			"FLY TOWARD THE ENEMY",
			"AIM TO LOCK ON",
		]))

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

	var wc: Array[Dictionary] = _get_wave_config()
	var config: Dictionary = wc[wave_index]
	var diff_rate: float = 0.05 if GameManager.game_mode == "wave" else 0.15
	var difficulty_mult: float = 1.0 + wave_index * diff_rate

	# Clear tutorial text at wave 3
	if wave_index >= 2:
		hud.set_tutorial_text(PackedStringArray())

	# AWACS messages for wave start
	var bearing := (randi() % 36) * 10  # random bearing 0-350
	var angels := 5 + randi() % 20  # altitude in thousands
	awacs_message("PICTURE -- GROUP BULLSEYE %03d/%d ANGELS %d" % [bearing, 20 + randi() % 40, angels], 3.0)

	# Special warnings for new enemy types
	if wave_index == 2:
		awacs_message("BOGEY DOPE -- FAST MOVERS BEARING %03d HOT" % bearing, 3.0)
	elif wave_index == 3:
		awacs_message("GORILLA GROUP %03d -- MULTIPLE CONTACTS AZIMUTH" % bearing, 3.0)

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

func _spawn_wave_generated(wave_index: int) -> void:
	if not enemy_scene or not is_instance_valid(player):
		return

	# Very slow scaling: +1 enemy every 5 waves, TANK from wave 12
	var base_count: int = 2 + wave_index / 5
	var difficulty_mult: float = 1.0 + wave_index * 0.03

	var bearing := (randi() % 36) * 10
	var angels := 5 + randi() % 20
	awacs_message("PICTURE -- GROUPS BULLSEYE %03d ANGELS %d" % [bearing, angels], 3.0)

	# Build enemy composition with slow scaling
	var enemies_to_spawn: Array[int] = []  # array of EnemyType values
	for i in base_count:
		var roll: float = randf()
		if wave_index >= 12 and roll < 0.10:
			enemies_to_spawn.append(2)  # TANK
		elif wave_index >= 6 and roll < 0.25:
			enemies_to_spawn.append(3)  # SWARM
		elif roll < 0.45:
			enemies_to_spawn.append(1)  # FAST
		else:
			enemies_to_spawn.append(0)  # BASIC

	for enemy_type_val in enemies_to_spawn:
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

func _on_enemy_died(pos: Vector3, xp_value: int) -> void:
	GameManager.add_xp(xp_value)
	if _splash_sound:
		_splash_sound.play()
	_try_chain_lightning(pos)
	if randf() < 0.25:
		_spawn_ammo_pickup(pos)

func _spawn_ammo_pickup(pos: Vector3) -> void:
	if not ammo_pickup_scene:
		return
	var ammo: Area3D = ammo_pickup_scene.instantiate()
	pickup_container.call_deferred("add_child", ammo)
	ammo.set_deferred("global_position", pos)

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
	if _phase == GamePhase.LANDING_APPROACH:
		return  # already in landing
	_phase = GamePhase.LANDING_APPROACH
	_landing_timer = 0.0
	_scroll_blend = 1.0
	_landing_offset_base = Vector2(player.global_position.x, player.global_position.z)
	player.landing_mode = true
	hud.set_tutorial_text(PackedStringArray())  # clear tutorial text

	# Save original speed before boost (for mission 2 restore)
	_original_move_speed = player.move_speed

	# Boost actual speed for dramatic approach feel, but keep HUD numbers the same
	const LANDING_SPEED_BOOST: float = 2.5
	player.move_speed *= LANDING_SPEED_BOOST
	player._current_speed *= LANDING_SPEED_BOOST
	if hud.fighter_hud:
		hud.fighter_hud.speed_display_divisor = LANDING_SPEED_BOOST

	if _mission == 1:
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
	# Mission 2: carrier already positioned from mission 1, just ensure visible
	else:
		_carrier.visible = true

	print("=== LANDING SEQUENCE STARTED (Mission %d) ===" % _mission)
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
	var heading_raw: float = absf(fposmod(player._heading - _carrier_heading + PI, TAU) - PI)
	# Accept approach from either end of the carrier (0° or 180° offset)
	var heading_diff: float = minf(heading_raw, absf(heading_raw - PI))

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
	# Wave off — reposition for another approach
	EffectsManager.screen_flash(Color(1.0, 0.5, 0.1), 0.3)
	awacs_message("WAVE OFF, WAVE OFF -- GO AROUND. RE-ENTER THE PATTERN.", 4.0)
	if hud.fighter_hud:
		hud.fighter_hud.show_wave_announcement("WAVE OFF -- GO AROUND", Color(1.0, 0.3, 0.2))

	# Push player back and up for another pass
	var behind := Vector3(-sin(_carrier_heading), 0.0, cos(_carrier_heading))
	player.global_position = _carrier.global_position + behind * 5000.0 + Vector3(0, 800, 0)
	player._target_altitude = 800.0
	player._heading = _carrier_heading
	_landing_timer = 0.0

func _on_landing_success() -> void:
	_phase = GamePhase.LANDED
	player._current_speed = 0.0
	player.global_position.y = _carrier_deck_y + 15.0  # snap above deck so plane doesn't clip
	player.set_physics_process(false)

	EffectsManager.screen_flash(Color(0.3, 1.0, 0.5), 0.3)
	EffectsManager.chromatic_pulse(0.01)

	hud.stop_landing_guidance()

	if _mission == 1:
		await get_tree().create_timer(2.0).timeout
		_begin_mission_2()
	else:
		await get_tree().create_timer(1.5).timeout
		GameManager.end_run()
		hud.show_victory()

# --- Mission 2 — Convoy intercept ---

func _begin_mission_2() -> void:
	_mission = 2
	_phase = GamePhase.MISSION_2_LAUNCH

	# Restore player speed (undo landing boost); fallback if skipped via debug key
	if _original_move_speed > 0.0:
		player.move_speed = _original_move_speed
	else:
		_original_move_speed = player.move_speed
	player._current_speed = 0.0
	if hud.fighter_hud:
		hud.fighter_hud.speed_display_divisor = 1.0
		hud.fighter_hud.mission_label = "MISSION 2"
		hud.fighter_hud.radar_range = hud.fighter_hud.RADAR_RANGE_MISSION2

	# Place player on carrier deck
	player.global_position = Vector3(
		_carrier.global_position.x,
		_carrier_deck_y + 15.0,
		_carrier.global_position.z
	)
	player._heading = _carrier_heading
	player.landing_mode = false
	player.set_physics_process(false)

	# Stop landing guidance from mission 1
	hud.stop_landing_guidance()

	# Freeze ocean for mission 2 (ships move over static ocean)
	# Enlarge ground plane to cover long-range flight
	if _ground and _ground.mesh is PlaneMesh:
		_ground.mesh.size = Vector2(300000, 300000)
		_ground.mesh.subdivide_width = 512
		_ground.mesh.subdivide_depth = 512
	if _bg_shader_mat:
		_bg_shader_mat.set_shader_parameter("time_val", _game_time)
		_bg_shader_mat.set_shader_parameter("fog_intensity", 0.0)

	# Show briefing panel — launch button triggers catapult
	hud.show_mission_briefing("MISSION 2: CONVOY INTERCEPT",
		"Destroy all enemy missile cruisers.\nAGM missile [E] locks onto ships.\nMissiles [SPACE] and gun [G] also work.",
		_on_briefing_launch)

func _on_briefing_launch() -> void:
	awacs_message("OVERLORD COPIES -- STRIKE PACKAGE ALPHA CLEARED HOT.", 4.0)
	_catapult_launch()

const MISSION_2_SPEED_MULT: float = 3.0

func _catapult_launch() -> void:
	_phase = GamePhase.MISSION_2_COMBAT
	player.set_physics_process(true)

	# 3x speed for mission 2, HUD shows original values
	player.move_speed = _original_move_speed * MISSION_2_SPEED_MULT
	player._current_speed = _original_move_speed * MISSION_2_SPEED_MULT * 2.0  # catapult boost on top
	player._target_altitude = 800.0
	if hud.fighter_hud:
		hud.fighter_hud.speed_display_divisor = MISSION_2_SPEED_MULT

	# AGM tutorial — show briefly then clear
	hud.set_tutorial_text(PackedStringArray([
		"[E]  FIRE AGM AT SHIPS",
		"[SPACE]  MISSILES    [G]  GUN",
	]))
	get_tree().create_timer(10.0).timeout.connect(func():
		hud.set_tutorial_text(PackedStringArray()))

	EffectsManager.screen_flash(Color(1.0, 0.9, 0.7), 0.3)
	awacs_message("SHOOTER READY -- CAT 1 LAUNCH!", 2.0)

	await get_tree().create_timer(1.5).timeout
	awacs_message("FEET WET. WEAPONS FREE -- FOX MIKE ON GUARD.", 3.0)
	_spawn_convoy()

func _spawn_convoy() -> void:
	var ship_script: GDScript = load("res://scripts/ship.gd")
	if not ship_script:
		print("[ERROR] Could not load ship.gd")
		return

	# Convoy approaches from the direction the carrier faces
	# Carrier stern faces the player approach; ships come from the bow side
	var away_dir := Vector3(sin(_carrier_heading), 0.0, -cos(_carrier_heading))
	var base_spawn: Vector3 = _carrier.global_position + away_dir * 80000.0
	base_spawn.y = 0.0

	# Ships head toward carrier (opposite direction)
	_convoy_heading = fposmod(_carrier_heading + PI, TAU)

	_ships_total = CONVOY_SHIP_COUNT
	_m2_ships_warned = false

	# 2-column staggered formation
	var perp := Vector3(-away_dir.z, 0.0, away_dir.x)
	var positions: Array[Vector3] = []
	for i in CONVOY_SHIP_COUNT:
		var along: float = float(i) * CONVOY_SPACING
		var lateral: float = CONVOY_LATERAL * (1.0 if i % 2 == 0 else -1.0)
		positions.append(base_spawn + away_dir * along + perp * lateral)

	for pos in positions:
		var ship := Area3D.new()
		ship.set_script(ship_script)
		enemy_container.call_deferred("add_child", ship)
		ship.set_deferred("global_position", Vector3(pos.x, -18.0, pos.z))
		# configure after added to tree
		ship.configure(_convoy_heading, 200.0)
		ship.speed = CONVOY_SPEED
		ship.target = player
		ship.enemy_died.connect(_on_enemy_died)

	awacs_message("MAGNUM -- %d SURFACE CONTACTS BEARING 090. ENGAGE." % CONVOY_SHIP_COUNT, 4.0)

# --- Player events ---

func _on_player_leveled_up(level: int) -> void:
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
	# DEBUG: press 2 to skip straight to mission 2
	if event is InputEventKey and event.pressed and event.keycode == KEY_2:
		if _phase == GamePhase.TUTORIAL or _phase == GamePhase.COMBAT:
			for e in enemy_container.get_children():
				e.queue_free()
			# Position carrier since we skipped landing
			var forward := Vector3(sin(player._heading), 0.0, -cos(player._heading))
			var carrier_pos := player.global_position + forward * 1000.0
			carrier_pos.y = _carrier_mesh_y
			_carrier.global_position = carrier_pos
			_carrier.visible = true
			var look_target := _carrier.global_position + forward
			_carrier.look_at(Vector3(look_target.x, _carrier_mesh_y, look_target.z), Vector3.UP)
			_carrier.rotate_y(-PI * 0.5 - deg_to_rad(8.0) + PI)
			_carrier_heading = player._heading
			# Freeze ocean
			if _ground:
				_ground.global_position.x = player.global_position.x
				_ground.global_position.z = player.global_position.z
			_begin_mission_2()
