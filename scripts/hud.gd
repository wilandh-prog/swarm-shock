extends CanvasLayer
## In-game HUD with neon styling and animated elements.

@onready var time_label: Label = $TopBar/TimeLabel
@onready var kills_label: Label = $TopBar/KillsLabel
@onready var health_label: Label = $TopBar/HealthLabel
@onready var level_label: Label = $TopBar/LevelLabel
@onready var xp_bar: ProgressBar = $TopBar/XPBar
@onready var xp_label: Label = $TopBar/XPLabel
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
	xp_label.text = "XP: %d" % GameManager.run_xp_earned

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

	# Smooth health display
	if _player and is_instance_valid(_player):
		_display_health = lerpf(_display_health, _player.health, 0.15)
		health_bar.max_value = _player.max_health
		health_bar.value = _display_health

		# Health label in top bar with color
		health_label.text = "HP: %d" % int(_display_health)
		var hp_frac: float = _display_health / _player.max_health
		if hp_frac > 0.6:
			health_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
		elif hp_frac > 0.3:
			health_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.2))
		else:
			health_label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))

		# Health bar color matches
		var hp_fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill") as StyleBoxFlat
		if hp_fill:
			hp_fill.bg_color = health_label.get_theme_color("font_color")

func _on_health_changed(current: float, maximum: float) -> void:
	pass  # Handled by smooth update in update_display

# --- Upgrade selection ---

var _pending_upgrades: int = 0

func _build_upgrade_pool() -> void:
	_upgrade_pool = [
		# Missile branch (amber)
		{
			"id": "missile_capacity", "name": "EXPANDED MAGAZINE",
			"description": "Max missiles +2",
			"branch": "missile",
			"apply": func():
				if _player:
					_player.missile_ammo_max += 2
					_player.missile_ammo = mini(_player.missile_ammo + 2, _player.missile_ammo_max),
		},
		# Lock-on branch (cyan)
		{
			"id": "lock_speed", "name": "FAST LOCK",
			"description": "Lock-on speed +30%",
			"branch": "lockon",
			"apply": func():
				if _player and _player.weapon_manager:
					_player.weapon_manager.lock_speed *= 1.3
					_player.weapon_manager.agm_lock_speed *= 1.3,
		},
		{
			"id": "lock_cone", "name": "WIDE SEEKER",
			"description": "Lock cone wider",
			"branch": "lockon",
			"apply": func():
				if _player and _player.weapon_manager:
					_player.weapon_manager.lock_cone = maxf(_player.weapon_manager.lock_cone - 0.1, 0.2),
		},
		# Defensive branch (green)
		{
			"id": "repair", "name": "REPAIR +30 HP",
			"description": "Heal 30 HP, +15 max HP",
			"branch": "defensive",
			"apply": func():
				if _player:
					_player.max_health += 15.0
					_player.heal(30.0),
		},
		{
			"id": "extra_flares", "name": "EXTRA FLARES +30",
			"description": "Get 30 more flares",
			"branch": "defensive",
			"apply": func():
				if _player:
					_player.flare_count_max += 30
					_player.flare_count = mini(_player.flare_count + 30, _player.flare_count_max),
		},
		{
			"id": "speed_boost", "name": "AFTERBURNER TUNE",
			"description": "Move speed +10%",
			"branch": "defensive",
			"apply": func():
				if _player:
					_player.move_speed *= 1.1,
		},
	]

func show_upgrade_selection() -> void:
	_pending_upgrades += 1
	if _pending_upgrades > 1:
		return  # already showing picker, will re-show after current pick
	_show_upgrade_cards()

func _show_upgrade_cards() -> void:
	# Show all upgrades
	var choices: Array[Dictionary] = _upgrade_pool

	# Clear old buttons
	for child in upgrade_buttons.get_children():
		child.queue_free()

	# Create card buttons
	for upgrade in choices:
		var btn := Button.new()
		btn.text = "%s\n%s" % [upgrade["name"], upgrade["description"]]
		btn.custom_minimum_size.y = 60
		btn.add_theme_font_size_override("font_size", 16)

		var border_color: Color = _branch_color(upgrade["branch"])
		btn.add_theme_color_override("font_color", border_color.lightened(0.3))
		btn.add_theme_stylebox_override("normal", _create_button_style(border_color, Color(0.03, 0.03, 0.08, 0.9)))
		btn.add_theme_stylebox_override("hover", _create_button_style(border_color.lightened(0.3), Color(0.06, 0.06, 0.12, 0.95)))
		btn.add_theme_stylebox_override("pressed", _create_button_style(Color.WHITE, Color(0.08, 0.08, 0.15, 1.0)))

		btn.pressed.connect(func():
			upgrade["apply"].call()
			_on_upgrade_picked()
		)
		upgrade_buttons.add_child(btn)

	upgrade_panel.visible = true

	# Animate in
	upgrade_panel.modulate.a = 0.0
	upgrade_panel.scale = Vector2(0.8, 0.8)
	upgrade_panel.pivot_offset = upgrade_panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(upgrade_panel, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(upgrade_panel, "scale", Vector2.ONE, 0.35)

func _on_upgrade_picked() -> void:
	_pending_upgrades -= 1
	_display_xp = 0.0
	if _pending_upgrades > 0:
		_show_upgrade_cards()
	else:
		upgrade_panel.visible = false

func _branch_color(branch: String) -> Color:
	match branch:
		"missile": return Color(1.0, 0.7, 0.15)
		"lockon": return Color(0.3, 0.7, 1.0)
		"defensive": return Color(0.3, 1.0, 0.4)
	return Color(0.7, 0.7, 0.7)

func is_upgrade_open() -> bool:
	return upgrade_panel.visible

# --- Escape menu ---

var _escape_panel: PanelContainer = null

func is_escape_open() -> bool:
	return _escape_panel != null

func show_escape_menu() -> void:
	if _escape_panel or is_controls_open():
		return
	get_tree().paused = true

	_escape_panel = PanelContainer.new()
	_escape_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_escape_panel.set_anchors_preset(Control.PRESET_CENTER)
	_escape_panel.custom_minimum_size = Vector2(360, 200)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.03, 0.1, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.9, 0.6, 0.2, 0.7)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0.9, 0.5, 0.1, 0.2)
	panel_style.shadow_size = 10
	_escape_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_escape_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "RETURN TO MAIN MENU?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	vbox.add_child(title)

	var warn := Label.new()
	warn.text = "Progress will not be saved"
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.add_theme_font_size_override("font_size", 14)
	warn.add_theme_color_override("font_color", Color(0.6, 0.5, 0.5))
	vbox.add_child(warn)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var yes_btn := Button.new()
	yes_btn.text = "MAIN MENU"
	yes_btn.custom_minimum_size = Vector2(140, 45)
	yes_btn.add_theme_font_size_override("font_size", 18)
	yes_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	var red := Color(0.9, 0.3, 0.2)
	yes_btn.add_theme_stylebox_override("normal", _create_button_style(red, Color(0.1, 0.03, 0.03, 0.9)))
	yes_btn.add_theme_stylebox_override("hover", _create_button_style(red.lightened(0.3), Color(0.15, 0.05, 0.05, 0.95)))
	yes_btn.add_theme_stylebox_override("pressed", _create_button_style(Color.WHITE, Color(0.2, 0.08, 0.08, 1.0)))
	yes_btn.pressed.connect(func():
		get_tree().paused = false
		GameManager.end_run()
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)
	btn_row.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "RESUME"
	no_btn.custom_minimum_size = Vector2(140, 45)
	no_btn.add_theme_font_size_override("font_size", 18)
	no_btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	var green := Color(0.2, 0.9, 0.4)
	no_btn.add_theme_stylebox_override("normal", _create_button_style(green, Color(0.03, 0.1, 0.05, 0.9)))
	no_btn.add_theme_stylebox_override("hover", _create_button_style(green.lightened(0.3), Color(0.05, 0.15, 0.08, 0.95)))
	no_btn.add_theme_stylebox_override("pressed", _create_button_style(Color.WHITE, Color(0.08, 0.2, 0.1, 1.0)))
	no_btn.pressed.connect(func():
		hide_escape_menu()
	)
	btn_row.add_child(no_btn)

	add_child(_escape_panel)

	_escape_panel.modulate.a = 0.0
	_escape_panel.scale = Vector2(0.8, 0.8)
	_escape_panel.pivot_offset = _escape_panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_escape_panel, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(_escape_panel, "scale", Vector2.ONE, 0.3)

func hide_escape_menu() -> void:
	if not _escape_panel:
		return
	get_tree().paused = false
	_escape_panel.queue_free()
	_escape_panel = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and is_escape_open():
		hide_escape_menu()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_C:
		if is_controls_open():
			hide_controls()
		else:
			show_controls()
		get_viewport().set_input_as_handled()

# --- Controls overlay ---

var _controls_panel: PanelContainer = null

func is_controls_open() -> bool:
	return _controls_panel != null

func show_controls() -> void:
	if _controls_panel or is_escape_open() or is_upgrade_open():
		return
	get_tree().paused = true

	_controls_panel = PanelContainer.new()
	_controls_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_controls_panel.set_anchors_preset(Control.PRESET_CENTER)
	_controls_panel.custom_minimum_size = Vector2(420, 400)

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.03, 0.08, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.3, 0.7, 1.0, 0.7)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0.2, 0.5, 1.0, 0.2)
	panel_style.shadow_size = 10
	_controls_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_controls_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "CONTROLS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	var controls := [
		["A / D", "Turn left / right"],
		["W / S", "Speed up / slow down"],
		["UP / DOWN", "Climb / descend"],
		["SPACE", "Fire missile (lock on first)"],
		["G", "Fire gun (hold)"],
		["F", "Deploy flares (vs missiles)"],
		["E", "Fire AGM (ground targets)"],
		["P", "Pause / main menu"],
		["C", "Toggle this screen"],
	]

	for entry in controls:
		var row := HBoxContainer.new()
		var key_label := Label.new()
		key_label.text = entry[0]
		key_label.custom_minimum_size.x = 130
		key_label.add_theme_font_size_override("font_size", 16)
		key_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
		row.add_child(key_label)

		var desc_label := Label.new()
		desc_label.text = entry[1]
		desc_label.add_theme_font_size_override("font_size", 16)
		desc_label.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		row.add_child(desc_label)

		vbox.add_child(row)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	vbox.add_child(spacer)

	var hint := Label.new()
	hint.text = "Press [C] to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.4, 0.45, 0.5))
	vbox.add_child(hint)

	add_child(_controls_panel)

	_controls_panel.modulate.a = 0.0
	_controls_panel.scale = Vector2(0.8, 0.8)
	_controls_panel.pivot_offset = _controls_panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_controls_panel, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(_controls_panel, "scale", Vector2.ONE, 0.3)

func hide_controls() -> void:
	if not _controls_panel:
		return
	get_tree().paused = false
	_controls_panel.queue_free()
	_controls_panel = null

# --- AWACS radio ---

func set_awacs_message(text: String) -> void:
	if fighter_hud:
		fighter_hud.awacs_text = text
		fighter_hud._awacs_alpha = 1.0

func set_tutorial_text(lines: PackedStringArray) -> void:
	if fighter_hud:
		fighter_hud.tutorial_lines = lines

func set_wave_info(current: int, total: int) -> void:
	if fighter_hud:
		fighter_hud.wave_current = current
		fighter_hud.wave_total = total

# --- Landing guidance ---

func start_landing_guidance(carrier: Node3D, heading: float, deck_y: float) -> void:
	if fighter_hud:
		fighter_hud.start_landing(carrier, heading, deck_y)

func stop_landing_guidance() -> void:
	if fighter_hud:
		fighter_hud.landing_active = false

# --- Landing failed ---

func show_landing_failed() -> void:
	var fail_label := Label.new()
	fail_label.text = "LANDING FAILED"
	fail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fail_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fail_label.set_anchors_preset(Control.PRESET_CENTER)
	fail_label.add_theme_font_size_override("font_size", 72)
	fail_label.add_theme_color_override("font_color", Color(1.0, 0.1, 0.1))
	fail_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	fail_label.add_theme_constant_override("outline_size", 6)
	fail_label.pivot_offset = Vector2(300, 40)
	fail_label.position -= Vector2(300, 40)
	add_child(fail_label)

	# Animate: scale up with shake
	fail_label.modulate.a = 0.0
	fail_label.scale = Vector2(1.5, 1.5)
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(fail_label, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(fail_label, "scale", Vector2.ONE, 0.4)

# --- Victory panel ---

var _victory_panel: PanelContainer = null

func show_victory() -> void:
	get_tree().paused = true

	_victory_panel = PanelContainer.new()
	_victory_panel.set_anchors_preset(Control.PRESET_CENTER)
	_victory_panel.custom_minimum_size = Vector2(400, 350)

	# Panel style (green/gold neon)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.06, 0.03, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.3, 1.0, 0.4, 0.7)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.shadow_color = Color(0.2, 1.0, 0.3, 0.2)
	panel_style.shadow_size = 12
	_victory_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	_victory_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "MISSION COMPLETE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	# Stats
	var minutes := int(GameManager.run_time) / 60
	var seconds := int(GameManager.run_time) % 60
	_add_stat_row(vbox, "TIME", "%02d:%02d" % [minutes, seconds])
	_add_stat_row(vbox, "KILLS", str(GameManager.run_kills))
	_add_stat_row(vbox, "LEVEL", str(GameManager.run_level))
	_add_stat_row(vbox, "XP EARNED", str(GameManager.run_xp_earned))

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	vbox.add_child(spacer)

	# Play Again button
	var retry_btn := Button.new()
	retry_btn.text = "PLAY AGAIN"
	retry_btn.custom_minimum_size.y = 45
	retry_btn.add_theme_font_size_override("font_size", 18)
	retry_btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	var green := Color(0.2, 0.9, 0.4)
	retry_btn.add_theme_stylebox_override("normal", _create_button_style(green, Color(0.03, 0.1, 0.05, 0.9)))
	retry_btn.add_theme_stylebox_override("hover", _create_button_style(green.lightened(0.3), Color(0.05, 0.15, 0.08, 0.95)))
	retry_btn.add_theme_stylebox_override("pressed", _create_button_style(Color.WHITE, Color(0.08, 0.2, 0.1, 1.0)))
	retry_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/game.tscn")
	)
	vbox.add_child(retry_btn)

	# Main Menu button
	var menu_btn := Button.new()
	menu_btn.text = "MAIN MENU"
	menu_btn.custom_minimum_size.y = 45
	menu_btn.add_theme_font_size_override("font_size", 18)
	menu_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	var gray := Color(0.5, 0.5, 0.6)
	menu_btn.add_theme_stylebox_override("normal", _create_button_style(gray, Color(0.05, 0.05, 0.08, 0.9)))
	menu_btn.add_theme_stylebox_override("hover", _create_button_style(gray.lightened(0.3), Color(0.08, 0.08, 0.12, 0.95)))
	menu_btn.add_theme_stylebox_override("pressed", _create_button_style(Color.WHITE, Color(0.1, 0.1, 0.15, 1.0)))
	menu_btn.pressed.connect(func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/menu.tscn")
	)
	vbox.add_child(menu_btn)

	add_child(_victory_panel)

	# Animate in
	_victory_panel.modulate.a = 0.0
	_victory_panel.scale = Vector2(0.7, 0.7)
	_victory_panel.pivot_offset = _victory_panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_victory_panel, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(_victory_panel, "scale", Vector2.ONE, 0.5)

func _add_stat_row(parent: VBoxContainer, label_text: String, value_text: String) -> void:
	var row := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var val := Label.new()
	val.text = value_text
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(val)

	parent.add_child(row)

# --- Mission briefing panel ---

var _briefing_panel: PanelContainer = null

func show_mission_briefing(title_text: String, body_text: String, launch_callback: Callable) -> void:
	get_tree().paused = true

	_briefing_panel = PanelContainer.new()
	_briefing_panel.set_anchors_preset(Control.PRESET_CENTER)
	_briefing_panel.custom_minimum_size = Vector2(450, 320)

	# Military green panel style
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.05, 0.03, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.3, 0.9, 0.4, 0.8)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	panel_style.shadow_color = Color(0.2, 0.8, 0.3, 0.2)
	panel_style.shadow_size = 10
	_briefing_panel.add_theme_stylebox_override("panel", panel_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_briefing_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	margin.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = title_text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	vbox.add_child(title)

	# Separator
	var sep := HSeparator.new()
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	vbox.add_child(sep)

	# Body text
	var body := Label.new()
	body.text = body_text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", 16)
	body.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	vbox.add_child(body)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 12
	vbox.add_child(spacer)

	# LAUNCH button
	var launch_btn := Button.new()
	launch_btn.text = "LAUNCH"
	launch_btn.custom_minimum_size.y = 50
	launch_btn.add_theme_font_size_override("font_size", 22)
	launch_btn.add_theme_color_override("font_color", Color(0.9, 1.0, 0.9))
	var green := Color(0.2, 0.9, 0.4)
	launch_btn.add_theme_stylebox_override("normal", _create_button_style(green, Color(0.03, 0.12, 0.05, 0.9)))
	launch_btn.add_theme_stylebox_override("hover", _create_button_style(green.lightened(0.3), Color(0.05, 0.18, 0.08, 0.95)))
	launch_btn.add_theme_stylebox_override("pressed", _create_button_style(Color.WHITE, Color(0.08, 0.22, 0.1, 1.0)))
	launch_btn.pressed.connect(func():
		get_tree().paused = false
		_briefing_panel.queue_free()
		_briefing_panel = null
		launch_callback.call()
	)
	vbox.add_child(launch_btn)

	add_child(_briefing_panel)

	# Animate in
	_briefing_panel.modulate.a = 0.0
	_briefing_panel.scale = Vector2(0.7, 0.7)
	_briefing_panel.pivot_offset = _briefing_panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(_briefing_panel, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(_briefing_panel, "scale", Vector2.ONE, 0.5)
