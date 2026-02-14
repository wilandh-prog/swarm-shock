extends Control
## Main menu with neon styling and animated elements.

@onready var play_button: Button = $VBoxContainer/PlayButton
@onready var upgrades_button: Button = $VBoxContainer/UpgradesButton
@onready var volts_label: Label = $VoltsLabel
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var upgrade_panel: PanelContainer = $UpgradePanel
@onready var upgrade_list: VBoxContainer = $UpgradePanel/MarginContainer/VBoxContainer/UpgradeList
@onready var close_upgrades_button: Button = $UpgradePanel/MarginContainer/VBoxContainer/CloseButton

var _title_pulse: float = 0.0

func _ready() -> void:
	play_button.pressed.connect(_on_play_pressed)
	upgrades_button.pressed.connect(_on_upgrades_pressed)
	close_upgrades_button.pressed.connect(_on_close_upgrades)
	GameManager.volts_changed.connect(_update_volts_display)

	upgrade_panel.visible = false
	_update_volts_display(GameManager.volts)
	_apply_neon_theme()
	_animate_in()

func _process(delta: float) -> void:
	# Pulse title
	_title_pulse += delta * 2.0
	if title_label:
		var pulse: float = (sin(_title_pulse) + 1.0) * 0.5
		var col: Color = Color(0.3, 0.7, 1.0).lerp(Color(0.5, 0.3, 1.0), pulse)
		title_label.add_theme_color_override("font_color", col)

func _apply_neon_theme() -> void:
	var accent := Color(0.3, 0.7, 1.0)

	# Play button (prominent)
	_style_button(play_button, Color(0.2, 0.8, 0.4), Color(0.03, 0.1, 0.05, 0.9))

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
	play_button.modulate.a = 0.0
	upgrades_button.modulate.a = 0.0
	volts_label.modulate.a = 0.0

	var tween := create_tween().set_ease(Tween.EASE_OUT)
	# Title drops in
	title_label.position.y -= 40
	tween.tween_property(title_label, "modulate:a", 1.0, 0.5)
	tween.parallel().tween_property(title_label, "position:y", title_label.position.y + 40, 0.5).set_trans(Tween.TRANS_BACK)
	# Buttons slide in
	tween.tween_property(play_button, "modulate:a", 1.0, 0.25)
	tween.tween_property(upgrades_button, "modulate:a", 1.0, 0.2)
	tween.tween_property(volts_label, "modulate:a", 1.0, 0.2)

func _on_play_pressed() -> void:
	# Fade out transition
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))

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

	var stat_names := {
		"max_health": "Max Health",
		"move_speed": "Move Speed",
		"pickup_range": "Pickup Range",
		"damage_mult": "Damage",
		"chain_range": "Chain Range",
	}

	for stat_key in stat_names:
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_label := Label.new()
		name_label.text = "%s (Lv.%d)" % [stat_names[stat_key], GameManager.upgrade_levels[stat_key]]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		hbox.add_child(name_label)

		var cost := GameManager.get_upgrade_cost(stat_key)
		var buy_button := Button.new()
		buy_button.text = "%d V" % cost
		buy_button.disabled = GameManager.volts < cost
		_style_button(buy_button, Color(1.0, 0.9, 0.2), Color(0.1, 0.08, 0.02, 0.9))
		buy_button.pressed.connect(_on_buy_upgrade.bind(stat_key))
		hbox.add_child(buy_button)

		upgrade_list.add_child(hbox)

func _on_buy_upgrade(stat_key: String) -> void:
	if GameManager.purchase_upgrade(stat_key):
		_populate_upgrades()

func _update_volts_display(amount: int) -> void:
	if volts_label:
		volts_label.text = "Volts: %d" % amount
		# Pulse on change
		var tween := create_tween()
		tween.tween_property(volts_label, "scale", Vector2(1.15, 1.15), 0.08)
		tween.tween_property(volts_label, "scale", Vector2.ONE, 0.12)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
