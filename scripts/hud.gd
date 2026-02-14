extends CanvasLayer
## In-game HUD with neon styling and animated elements.

@onready var time_label: Label = $TopBar/TimeLabel
@onready var kills_label: Label = $TopBar/KillsLabel
@onready var level_label: Label = $TopBar/LevelLabel
@onready var xp_bar: ProgressBar = $TopBar/XPBar
@onready var volts_label: Label = $TopBar/VoltsLabel
@onready var health_bar: ProgressBar = $HealthBar
@onready var upgrade_panel: PanelContainer = $UpgradePanel
@onready var upgrade_buttons: VBoxContainer = $UpgradePanel/MarginContainer/VBoxContainer/UpgradeButtons
@onready var fighter_hud: Control = $FighterHUD

var _player: CharacterBody3D = null
var _upgrade_pool: Array[Dictionary] = []

# Animated values
var _display_xp: float = 0.0
var _display_health: float = 100.0
var _prev_kills: int = 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	upgrade_panel.visible = false
	_apply_neon_theme()

func setup(player: CharacterBody3D) -> void:
	_player = player
	if _player:
		_player.health_changed.connect(_on_health_changed)
		_display_health = _player.health
	if fighter_hud:
		fighter_hud.player = _player
	_build_upgrade_pool()

# --- Neon UI Theme ---

func _apply_neon_theme() -> void:
	# Style the upgrade panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.03, 0.1, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.3, 0.7, 1.0, 0.7)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0.2, 0.5, 1.0, 0.3)
	panel_style.shadow_size = 8
	upgrade_panel.add_theme_stylebox_override("panel", panel_style)

	# Style health bar
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0.15, 0.05, 0.05, 0.8)
	hp_bg.corner_radius_top_left = 4
	hp_bg.corner_radius_top_right = 4
	hp_bg.corner_radius_bottom_left = 4
	hp_bg.corner_radius_bottom_right = 4
	health_bar.add_theme_stylebox_override("background", hp_bg)

	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.2, 0.9, 0.3)
	hp_fill.corner_radius_top_left = 4
	hp_fill.corner_radius_top_right = 4
	hp_fill.corner_radius_bottom_left = 4
	hp_fill.corner_radius_bottom_right = 4
	health_bar.add_theme_stylebox_override("fill", hp_fill)

	# Style XP bar
	var xp_bg := StyleBoxFlat.new()
	xp_bg.bg_color = Color(0.05, 0.05, 0.15, 0.8)
	xp_bg.corner_radius_top_left = 3
	xp_bg.corner_radius_top_right = 3
	xp_bg.corner_radius_bottom_left = 3
	xp_bg.corner_radius_bottom_right = 3
	xp_bar.add_theme_stylebox_override("background", xp_bg)

	var xp_fill := StyleBoxFlat.new()
	xp_fill.bg_color = Color(0.3, 0.7, 1.0)
	xp_fill.corner_radius_top_left = 3
	xp_fill.corner_radius_top_right = 3
	xp_fill.corner_radius_bottom_left = 3
	xp_fill.corner_radius_bottom_right = 3
	xp_bar.add_theme_stylebox_override("fill", xp_fill)

func _create_button_style(border_color: Color, bg_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_bottom = 2
	style.border_width_top = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = border_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

# --- Display ---

func update_display() -> void:
	if not GameManager.run_active:
		return

	var minutes := int(GameManager.run_time) / 60
	var seconds := int(GameManager.run_time) % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]
	volts_label.text = "V: %d" % GameManager.run_volts_earned

	# Animated kill counter
	if GameManager.run_kills != _prev_kills:
		_prev_kills = GameManager.run_kills
		kills_label.text = "Kills: %d" % GameManager.run_kills
		# Pulse animation
		var tween := create_tween()
		tween.tween_property(kills_label, "scale", Vector2(1.15, 1.15), 0.05)
		tween.tween_property(kills_label, "scale", Vector2.ONE, 0.1)

	level_label.text = "Lv.%d" % GameManager.run_level

	# Smooth XP bar
	var target_xp: float = 0.0
	if GameManager.run_xp_to_next > 0:
		target_xp = float(GameManager.run_xp) / float(GameManager.run_xp_to_next) * 100.0
	_display_xp = lerpf(_display_xp, target_xp, 0.15)
	xp_bar.value = _display_xp

	# Smooth health bar with color
	if _player and is_instance_valid(_player):
		_display_health = lerpf(_display_health, _player.health, 0.15)
		health_bar.max_value = _player.max_health
		health_bar.value = _display_health

		# Health bar color: green → yellow → red
		var hp_frac: float = _display_health / _player.max_health
		var hp_fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if hp_fill:
			if hp_frac > 0.6:
				hp_fill.bg_color = Color(0.2, 0.9, 0.3)
			elif hp_frac > 0.3:
				hp_fill.bg_color = Color(0.9, 0.8, 0.2)
			else:
				hp_fill.bg_color = Color(0.9, 0.2, 0.2)

func _on_health_changed(current: float, maximum: float) -> void:
	pass  # Handled by smooth update in update_display

# --- Upgrade selection ---

func _build_upgrade_pool() -> void:
	_upgrade_pool = [
		{
			"id": "damage_up", "name": "Damage +15%",
			"description": "All weapons deal 15% more damage",
			"apply": func():
				if _player: _player.damage_mult *= 1.15,
			"repeatable": true,
		},
		{
			"id": "speed_up", "name": "Speed +12%",
			"description": "Move faster",
			"apply": func():
				if _player: _player.move_speed *= 1.12,
			"repeatable": true,
		},
		{
			"id": "chain_range_up", "name": "Chain Range +25%",
			"description": "Lightning chains reach further",
			"apply": func():
				if _player: _player.chain_range *= 1.25,
			"repeatable": true,
		},
		{
			"id": "chain_damage_up", "name": "Chain Damage +30%",
			"description": "Chain lightning deals more damage",
			"apply": func():
				if _player: _player.chain_damage_mult *= 1.3,
			"repeatable": true,
		},
		{
			"id": "health_up", "name": "Max HP +25",
			"description": "Increase maximum health and heal",
			"apply": func():
				if _player:
					_player.max_health += 25.0
					_player.heal(25.0),
			"repeatable": true,
		},
		{
			"id": "pickup_range_up", "name": "Pickup Range +30%",
			"description": "Attract pickups from further away",
			"apply": func():
				if _player: _player.pickup_range *= 1.3,
			"repeatable": true,
		},
		{
			"id": "fire_rate_up", "name": "Fire Rate +12%",
			"description": "All weapons fire faster",
			"apply": func():
				if _player: _player.fire_rate_mult *= 1.12,
			"repeatable": true,
		},
		{
			"id": "projectile_up", "name": "+1 Projectile",
			"description": "All weapons fire an extra projectile",
			"apply": func():
				if _player: _player.projectile_count_bonus += 1,
			"repeatable": true,
		},
		{
			"id": "weapon_spark_burst", "name": "NEW: Spark Burst",
			"description": "Fires projectiles in all directions",
			"apply": func():
				if _player and _player.weapon_manager:
					_player.weapon_manager.add_weapon("spark_burst"),
			"repeatable": false,
		},
		{
			"id": "weapon_piercing_ray", "name": "NEW: Piercing Ray",
			"description": "High damage beam that pierces enemies",
			"apply": func():
				if _player and _player.weapon_manager:
					_player.weapon_manager.add_weapon("piercing_ray"),
			"repeatable": false,
		},
	]

func show_upgrade_selection() -> void:
	upgrade_panel.visible = true

	# Animate panel in
	upgrade_panel.modulate.a = 0.0
	upgrade_panel.scale = Vector2(0.8, 0.8)
	upgrade_panel.pivot_offset = upgrade_panel.size / 2.0
	var panel_tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	panel_tween.tween_property(upgrade_panel, "modulate:a", 1.0, 0.2)
	panel_tween.parallel().tween_property(upgrade_panel, "scale", Vector2.ONE, 0.3)

	# Clear old buttons
	for child in upgrade_buttons.get_children():
		child.queue_free()

	# Build valid options
	var valid: Array[Dictionary] = []
	for upgrade in _upgrade_pool:
		if upgrade["repeatable"]:
			valid.append(upgrade)
		elif not _is_upgrade_taken(upgrade["id"]):
			valid.append(upgrade)

	valid.shuffle()
	var choices := valid.slice(0, mini(3, valid.size()))

	# Create styled buttons with staggered animation
	for i in choices.size():
		var upgrade: Dictionary = choices[i]
		var btn := Button.new()
		btn.text = upgrade["name"]
		btn.tooltip_text = upgrade["description"]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size.y = 65
		btn.add_theme_font_size_override("font_size", 22)
		btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0))

		# Neon button styles
		var accent: Color = Color(0.3, 0.7, 1.0)
		btn.add_theme_stylebox_override("normal",
			_create_button_style(accent, Color(0.05, 0.08, 0.18, 0.9)))
		btn.add_theme_stylebox_override("hover",
			_create_button_style(accent.lightened(0.3), Color(0.08, 0.12, 0.25, 0.95)))
		btn.add_theme_stylebox_override("pressed",
			_create_button_style(Color.WHITE, Color(0.12, 0.18, 0.35, 1.0)))

		btn.pressed.connect(_on_upgrade_chosen.bind(upgrade))
		upgrade_buttons.add_child(btn)

		# Staggered slide-in
		btn.modulate.a = 0.0
		btn.position.x = 50.0
		var btn_tween := create_tween().set_ease(Tween.EASE_OUT)
		btn_tween.tween_property(btn, "modulate:a", 1.0, 0.15).set_delay(0.1 * i)
		btn_tween.parallel().tween_property(btn, "position:x", 0.0, 0.2).set_delay(0.1 * i)

func _on_upgrade_chosen(upgrade: Dictionary) -> void:
	upgrade["apply"].call()
	if not upgrade["repeatable"]:
		_mark_upgrade_taken(upgrade["id"])

	# Reset XP bar display for smooth animation
	_display_xp = 0.0

	upgrade_panel.visible = false
	get_tree().paused = false

func is_upgrade_open() -> bool:
	return upgrade_panel.visible

var _taken_upgrades: Array[String] = []

func _is_upgrade_taken(id: String) -> bool:
	return id in _taken_upgrades

func _mark_upgrade_taken(id: String) -> void:
	_taken_upgrades.append(id)
