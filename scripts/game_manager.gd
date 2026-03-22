extends Node
## Global game state manager. Tracks meta-progression and current run state.

signal run_started
signal run_ended(stats: Dictionary)
signal xp_changed(amount: int)
signal player_leveled_up(level: int)

# --- Meta-progression (persists between runs) ---
var xp_total: int = 0 : set = _set_xp_total
var unlocked_characters: Array[String] = ["spark"]  # default character
var base_stats: Dictionary = {
	"max_health": 100.0,
	"move_speed": 200.0,
	"pickup_range": 80.0,
	"damage_mult": 1.0,
	"chain_range": 120.0,
	"lock_speed": 0.6,
}
var upgrade_levels: Dictionary = {
	"max_health": 0,
	"move_speed": 0,
	"pickup_range": 0,
	"damage_mult": 0,
	"chain_range": 0,
	"lock_speed": 0,
}
var selected_character: String = "spark"

# --- Entity tracking (cached lists, avoids get_nodes_in_group every frame) ---
var enemies_alive: Array[Area3D] = []
var enemy_missiles: Array[Area3D] = []
var flares_active: Array[Area3D] = []
var _radar_blip_sound: AudioStreamPlayer

func register_enemy(e: Area3D) -> void:
	enemies_alive.append(e)
	e.tree_exiting.connect(func(): enemies_alive.erase(e))
	if _radar_blip_sound:
		_radar_blip_sound.play()

func register_enemy_missile(m: Area3D) -> void:
	enemy_missiles.append(m)
	m.tree_exiting.connect(func(): enemy_missiles.erase(m))

func register_flare(f: Area3D) -> void:
	flares_active.append(f)
	f.tree_exiting.connect(func(): flares_active.erase(f))

# --- Game mode ---
var game_mode: String = "mission"  # "wave" or "mission"

# --- Current run state ---
var run_active: bool = false
var run_time: float = 0.0
var run_kills: int = 0
var run_level: int = 1
var run_xp: int = 0
var run_xp_to_next: int = 10
var run_xp_earned: int = 0

# --- Ad timing ---
var _last_ad_time: float = 0.0
const AD_COOLDOWN: float = 180.0  # 3 minutes between midgame ads
var _first_gameplay: bool = true  # never show ads before first gameplay

# --- Upgrade costs ---
const UPGRADE_COST_BASE: int = 50
const UPGRADE_COST_SCALE: float = 1.5

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var blip_stream: AudioStream = load("res://assets/audio/new radar object.mp3")
	if blip_stream:
		_radar_blip_sound = AudioStreamPlayer.new()
		_radar_blip_sound.stream = blip_stream
		_radar_blip_sound.volume_db = 0.0
		_radar_blip_sound.bus = &"Master"
		add_child(_radar_blip_sound)

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if run_active:
			get_tree().paused = true
		AudioManager.mute_all()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if run_active:
			get_tree().paused = false
		AudioManager.unmute_all()

func _process(delta: float) -> void:
	if run_active:
		run_time += delta

# --- Run lifecycle ---

func start_run() -> void:
	run_active = true
	run_time = 0.0
	run_kills = 0
	run_level = 1
	run_xp = 0
	run_xp_to_next = 10
	run_xp_earned = 0
	_first_gameplay = false
	CrazySdk.gameplay_start()
	run_started.emit()

func end_run() -> void:
	run_active = false
	CrazySdk.gameplay_stop()
	var stats := {
		"time": run_time,
		"kills": run_kills,
		"level": run_level,
		"xp_earned": run_xp_earned,
	}
	xp_total += run_xp_earned
	SaveManager.save_all()
	run_ended.emit(stats)

# --- XP and leveling ---

func add_xp(amount: int) -> void:
	run_xp += amount
	run_xp_earned += amount
	while run_xp >= run_xp_to_next:
		run_xp -= run_xp_to_next
		run_level += 1
		run_xp_to_next = _calc_xp_requirement(run_level)
		player_leveled_up.emit(run_level)

func _calc_xp_requirement(level: int) -> int:
	return int(10 * pow(level, 1.3))

func add_kill() -> void:
	run_kills += 1

# --- Meta upgrades ---

func get_stat(stat_name: String) -> float:
	var base: float = base_stats.get(stat_name, 0.0)
	var level: int = upgrade_levels.get(stat_name, 0)
	return base + (base * 0.1 * level)  # each level = +10%

func get_upgrade_cost(stat_name: String) -> int:
	var level: int = upgrade_levels.get(stat_name, 0)
	return int(UPGRADE_COST_BASE * pow(UPGRADE_COST_SCALE, level))

func purchase_upgrade(stat_name: String) -> bool:
	var cost := get_upgrade_cost(stat_name)
	if xp_total < cost:
		return false
	if not upgrade_levels.has(stat_name):
		return false
	xp_total -= cost
	upgrade_levels[stat_name] += 1
	SaveManager.save_all()
	return true

# --- Ads ---

func can_show_midgame_ad() -> bool:
	if _first_gameplay:
		return false
	return (Time.get_ticks_msec() / 1000.0 - _last_ad_time) >= AD_COOLDOWN

func show_midgame_ad(on_complete: Callable) -> void:
	if not can_show_midgame_ad():
		on_complete.call()
		return
	_last_ad_time = Time.get_ticks_msec() / 1000.0
	CrazySdk.show_midgame_ad(on_complete)

func show_rewarded_ad(on_reward: Callable, on_skip: Callable) -> void:
	CrazySdk.show_rewarded_ad(on_reward, on_skip)

# --- Setters ---

func _set_xp_total(value: int) -> void:
	xp_total = value
	xp_changed.emit(xp_total)
