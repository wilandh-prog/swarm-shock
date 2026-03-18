extends Control
## Game over screen with animated stats, neon styling, rewarded ad option.

@onready var time_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsContainer/TimeValue
@onready var kills_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsContainer/KillsValue
@onready var level_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsContainer/LevelValue
@onready var xp_label: Label = $PanelContainer/MarginContainer/VBoxContainer/StatsContainer/XPValue
@onready var double_xp_button: Button = $PanelContainer/MarginContainer/VBoxContainer/DoubleXPButton
@onready var retry_button: Button = $PanelContainer/MarginContainer/VBoxContainer/RetryButton
@onready var menu_button: Button = $PanelContainer/MarginContainer/VBoxContainer/MenuButton
@onready var title_label: Label = $PanelContainer/MarginContainer/VBoxContainer/TitleLabel

var _run_stats: Dictionary = {}
var _doubled: bool = false

# Animated counters
var _display_kills: float = 0.0
var _display_xp: float = 0.0
var _display_time: float = 0.0
var _counter_speed: float = 0.0

func _ready() -> void:
	retry_button.pressed.connect(_on_retry)
	menu_button.pressed.connect(_on_menu)
	double_xp_button.pressed.connect(_on_double_xp)

	_run_stats = {
		"time": GameManager.run_time,
		"kills": GameManager.run_kills,
		"level": GameManager.run_level,
		"xp_earned": GameManager.run_xp_earned,
	}

	_apply_neon_theme()
	_animate_in()

	# Start counter animation after panel appears
	await get_tree().create_timer(0.5).timeout
	_start_counter_animation()

func _process(delta: float) -> void:
	_counter_speed += delta * 2.0
	var speed: float = minf(_counter_speed, 1.0)

	# Animate counters
	_display_time = lerpf(_display_time, _run_stats.get("time", 0.0), speed * 0.1)
	_display_kills = lerpf(_display_kills, float(_run_stats.get("kills", 0)), speed * 0.1)
	_display_xp = lerpf(_display_xp, float(_run_stats.get("xp_earned", 0)), speed * 0.1)

	var minutes := int(_display_time) / 60
	var seconds := int(_display_time) % 60
	time_label.text = "%02d:%02d" % [minutes, seconds]
	kills_label.text = str(int(_display_kills))
	xp_label.text = str(int(_display_xp))

func _start_counter_animation() -> void:
	# Level doesn't animate (just show it)
	level_label.text = str(_run_stats.get("level", 1))

func _apply_neon_theme() -> void:
	# Panel style
	var panel := $PanelContainer
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.03, 0.03, 0.1, 0.95)
	panel_style.border_width_bottom = 2
	panel_style.border_width_top = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(1.0, 0.3, 0.3, 0.6)
	panel_style.corner_radius_top_left = 16
	panel_style.corner_radius_top_right = 16
	panel_style.corner_radius_bottom_left = 16
	panel_style.corner_radius_bottom_right = 16
	panel_style.shadow_color = Color(1.0, 0.2, 0.2, 0.2)
	panel_style.shadow_size = 12
	panel.add_theme_stylebox_override("panel", panel_style)

	# Buttons
	_style_button(retry_button, Color(0.2, 0.8, 0.4), Color(0.03, 0.1, 0.05, 0.9))
	_style_button(menu_button, Color(0.5, 0.5, 0.6), Color(0.05, 0.05, 0.08, 0.9))
	_style_button(double_xp_button, Color(1.0, 0.9, 0.2), Color(0.1, 0.08, 0.02, 0.9))

func _style_button(btn: Button, border_color: Color, bg_color: Color) -> void:
	btn.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))

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
	return style

func _animate_in() -> void:
	var panel := $PanelContainer
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.7, 0.7)
	panel.pivot_offset = panel.size / 2.0

	var tween := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(panel, "scale", Vector2.ONE, 0.5)

	# Title flash red → white → red
	title_label.modulate = Color(1.0, 0.5, 0.5)
	var title_tween := create_tween()
	title_tween.tween_property(title_label, "modulate", Color.WHITE, 0.15)
	title_tween.tween_property(title_label, "modulate", Color(1.0, 0.3, 0.3), 0.2)

func _on_retry() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/game.tscn"))

func _on_menu() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))

func _on_double_xp() -> void:
	if _doubled:
		return
	GameManager.show_rewarded_ad(
		func():
			var bonus: int = _run_stats.get("xp_earned", 0)
			GameManager.xp_total += bonus
			_run_stats["xp_earned"] = _run_stats.get("xp_earned", 0) + bonus
			_display_xp = float(_run_stats["xp_earned"]) * 0.5  # Reset for animation
			double_xp_button.text = "Doubled!"
			double_xp_button.disabled = true
			_doubled = true
			SaveManager.save_all()
			CrazySdk.happy_time(),
		func():
			pass
	)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
