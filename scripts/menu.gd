extends Control
## Main menu with neon styling and animated elements.

@onready var wave_button: Button = $VBoxContainer/WaveButton
@onready var mission_button: Button = $VBoxContainer/MissionButton
@onready var upgrades_button: Button = $VBoxContainer/UpgradesButton
@onready var xp_label: Label = $XPLabel
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var upgrade_panel: PanelContainer = $UpgradePanel
@onready var upgrade_list: VBoxContainer = $UpgradePanel/MarginContainer/VBoxContainer/UpgradeList
@onready var close_upgrades_button: Button = $UpgradePanel/MarginContainer/VBoxContainer/CloseButton

var _title_pulse: float = 0.0
var _model_pivot: Node3D

func _ready() -> void:
	wave_button.pressed.connect(_on_wave_pressed)
	mission_button.pressed.connect(_on_mission_pressed)
	upgrades_button.pressed.connect(_on_upgrades_pressed)
	close_upgrades_button.pressed.connect(_on_close_upgrades)
	GameManager.xp_changed.connect(_update_xp_display)

	upgrade_panel.visible = false
	_update_xp_display(GameManager.xp_total)
	_setup_3d_background()
	_apply_neon_theme()
	_create_best_scores()
	_animate_in()
	CrazySdk.loading_stop()

func _process(delta: float) -> void:
	# Pulse title
	_title_pulse += delta * 2.0
	if title_label:
		var pulse: float = (sin(_title_pulse) + 1.0) * 0.5
		var col: Color = Color(0.3, 0.7, 1.0).lerp(Color(0.5, 0.3, 1.0), pulse)
		title_label.add_theme_color_override("font_color", col)

	# Rotate model
	if _model_pivot:
		_model_pivot.rotation.y += delta * 0.4

func _setup_3d_background() -> void:
	var jet_scene: PackedScene = load("res://assets/f-14/f14d.glb")
	if not jet_scene:
		jet_scene = load("res://assets/Jet.glb")
	if not jet_scene:
		return

	# SubViewport for 3D rendering
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	# Camera
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 40.0
	camera.position = Vector3(0, 2, 8)
	camera.look_at(Vector3(0, 0, 0))
	viewport.add_child(camera)

	# Environment
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.5, 0.7)
	env.ambient_light_energy = 0.5
	camera.environment = env

	# Lights
	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-40, 30, 0)
	key_light.light_energy = 1.2
	key_light.light_color = Color(0.8, 0.85, 1.0)
	viewport.add_child(key_light)

	var rim_light := DirectionalLight3D.new()
	rim_light.rotation_degrees = Vector3(-20, -150, 0)
	rim_light.light_energy = 0.6
	rim_light.light_color = Color(0.3, 0.5, 1.0)
	viewport.add_child(rim_light)

	# Model pivot (for rotation)
	_model_pivot = Node3D.new()
	viewport.add_child(_model_pivot)

	var jet := jet_scene.instantiate()
	jet.scale = Vector3(0.6, 0.6, 0.6)
	jet.rotation.x = deg_to_rad(-90.0)
	_model_pivot.add_child(jet)
	_model_pivot.rotation.y = deg_to_rad(-30.0)
	_model_pivot.rotation.x = deg_to_rad(10.0)

	# Container to display the viewport
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(viewport)

	# Insert behind UI but in front of background
	move_child($Background, 0)
	add_child(container)
	move_child(container, 1)

func _apply_neon_theme() -> void:
	var accent := Color(0.3, 0.7, 1.0)

	# Wave button (prominent)
	_style_button(wave_button, Color(0.2, 0.8, 0.4), Color(0.03, 0.1, 0.05, 0.9))
	# Mission button
	_style_button(mission_button, Color(0.9, 0.6, 0.2), Color(0.1, 0.06, 0.02, 0.9))

	# Upgrades button
	_style_button(upgrades_button, accent, Color(0.03, 0.05, 0.12, 0.9))

	# Close button
	_style_button(close_upgrades_button, Color(0.6, 0.3, 0.3), Color(0.1, 0.03, 0.03, 0.9))

	# Upgrade panel
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.03, 0.1, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.3, 0.7, 1.0, 0.6)
	panel_style.corner_radius_top_left = 12
	panel_style.corner_radius_top_right = 12
	panel_style.corner_radius_bottom_left = 12
	panel_style.corner_radius_bottom_right = 12
	upgrade_panel.add_theme_stylebox_override("panel", panel_style)

func _style_button(btn: Button, border_color: Color, bg_color: Color) -> void:
	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var normal := _make_btn_style(border_color, bg_color)
	var hover := _make_btn_style(border_color.lightened(0.3), bg_color.lightened(0.05))
	var pressed := _make_btn_style(Color.WHITE, bg_color.lightened(0.1))
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)

func _make_btn_style(border_color: Color, bg_color: Color) -> StyleBoxFlat:
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
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _animate_in() -> void:
	title_label.modulate.a = 0.0
	wave_button.modulate.a = 0.0
	mission_button.modulate.a = 0.0
	upgrades_button.modulate.a = 0.0
	xp_label.modulate.a = 0.0

	var tween := create_tween().set_ease(Tween.EASE_OUT)
	# Title drops in
	title_label.position.y -= 40
	tween.tween_property(title_label, "modulate:a", 1.0, 0.5)
	tween.parallel().tween_property(title_label, "position:y", title_label.position.y + 40, 0.5).set_trans(Tween.TRANS_BACK)
	# Buttons slide in
	tween.tween_property(wave_button, "modulate:a", 1.0, 0.25)
	tween.tween_property(mission_button, "modulate:a", 1.0, 0.2)
	tween.tween_property(upgrades_button, "modulate:a", 1.0, 0.2)
	tween.tween_property(xp_label, "modulate:a", 1.0, 0.2)

func _start_game(mode: String) -> void:
	GameManager.game_mode = mode
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))

func _on_wave_pressed() -> void:
	_start_game("wave")

func _on_mission_pressed() -> void:
	_start_game("mission")

func _on_upgrades_pressed() -> void:
	upgrade_panel.visible = true
	upgrade_panel.modulate.a = 0.0
	upgrade_panel.scale = Vector2(0.85, 0.85)
	upgrade_panel.pivot_offset = upgrade_panel.size / 2.0
	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(upgrade_panel, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(upgrade_panel, "scale", Vector2.ONE, 0.3)
	_populate_upgrades()

func _on_close_upgrades() -> void:
	var tween := create_tween()
	tween.tween_property(upgrade_panel, "modulate:a", 0.0, 0.15)
	tween.tween_callback(func(): upgrade_panel.visible = false)

func _populate_upgrades() -> void:
	for child in upgrade_list.get_children():
		child.queue_free()

	var upgrades := [
		{"key": "max_health", "name": "Health", "desc": "+10% max HP per level", "color": Color(0.3, 1.0, 0.4)},
		{"key": "missile_ammo", "name": "Missiles", "desc": "+2 starting missiles per level", "color": Color(1.0, 0.7, 0.15)},
		{"key": "flare_count", "name": "Flares", "desc": "+10 starting flares per level", "color": Color(0.3, 0.7, 1.0)},
	]

	for upgrade in upgrades:
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		var lvl: int = GameManager.upgrade_levels.get(upgrade["key"], 0)
		name_label.text = "%s (Lv.%d)" % [upgrade["name"], lvl]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", upgrade["color"])
		name_label.add_theme_font_size_override("font_size", 16)
		hbox.add_child(name_label)

		var desc_label := Label.new()
		desc_label.text = upgrade["desc"]
		desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		desc_label.add_theme_font_size_override("font_size", 12)
		hbox.add_child(desc_label)

		var cost := GameManager.get_upgrade_cost(upgrade["key"])
		var buy_button := Button.new()
		buy_button.text = "%d XP" % cost
		buy_button.disabled = GameManager.xp_total < cost
		_style_button(buy_button, upgrade["color"], Color(0.1, 0.08, 0.02, 0.9))
		buy_button.pressed.connect(_on_buy_upgrade.bind(upgrade["key"]))
		hbox.add_child(buy_button)

		upgrade_list.add_child(hbox)

func _on_buy_upgrade(stat_key: String) -> void:
	if GameManager.purchase_upgrade(stat_key):
		_populate_upgrades()

func _update_xp_display(amount: int) -> void:
	if xp_label:
		xp_label.text = "XP: %d" % amount
		# Pulse on change
		var tween := create_tween()
		tween.tween_property(xp_label, "scale", Vector2(1.15, 1.15), 0.08)
		tween.tween_property(xp_label, "scale", Vector2.ONE, 0.12)

func _create_best_scores() -> void:
	if GameManager.best_kills == 0 and GameManager.best_time == 0.0:
		return  # No games played yet

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER_TOP)
	vbox.offset_top = 20.0
	vbox.offset_bottom = 140.0
	vbox.offset_left = -120.0
	vbox.offset_right = 120.0
	vbox.grow_horizontal = Control.GROW_DIRECTION_BOTH
	vbox.add_theme_constant_override("separation", 2)
	add_child(vbox)

	var header := Label.new()
	header.text = "PERSONAL BEST"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0, 0.7))
	vbox.add_child(header)

	var minutes := int(GameManager.best_time) / 60
	var seconds := int(GameManager.best_time) % 60
	var lines := [
		"Kills: %d" % GameManager.best_kills,
		"Time: %02d:%02d" % [minutes, seconds],
		"Wave: %d" % GameManager.best_wave,
		"Level: %d" % GameManager.best_level,
		"XP: %d" % GameManager.best_xp,
	]
	for line in lines:
		var lbl := Label.new()
		lbl.text = line
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color", Color(0.5, 0.55, 0.6, 0.6))
		vbox.add_child(lbl)

	vbox.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(vbox, "modulate:a", 1.0, 0.5).set_delay(0.8)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
