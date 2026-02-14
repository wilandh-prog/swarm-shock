extends Control
## Entry point / splash screen. Animated title with neon effects.

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $VBoxContainer/SubtitleLabel
@onready var loading_bar: ProgressBar = $VBoxContainer/LoadingBar

var _load_progress: float = 0.0
var _title_pulse: float = 0.0

func _ready() -> void:
	_style_loading_bar()
	_animate_intro()

func _style_loading_bar() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.15, 0.8)
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	loading_bar.add_theme_stylebox_override("background", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.3, 0.7, 1.0)
	fill.corner_radius_top_left = 4
	fill.corner_radius_top_right = 4
	fill.corner_radius_bottom_left = 4
	fill.corner_radius_bottom_right = 4
	loading_bar.add_theme_stylebox_override("fill", fill)

func _animate_intro() -> void:
	title_label.modulate.a = 0.0
	subtitle_label.modulate.a = 0.0
	loading_bar.modulate.a = 0.0

	var tween := create_tween().set_ease(Tween.EASE_OUT)
	# Title slides up and fades in
	title_label.position.y += 30
	tween.tween_property(title_label, "modulate:a", 1.0, 0.6)
	tween.parallel().tween_property(title_label, "position:y", title_label.position.y - 30, 0.6)
	tween.tween_property(subtitle_label, "modulate:a", 1.0, 0.3)
	tween.tween_property(loading_bar, "modulate:a", 1.0, 0.3)
	tween.tween_callback(_start_loading)

func _start_loading() -> void:
	var tween := create_tween().set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "_load_progress", 1.0, 1.2)
	tween.tween_callback(_go_to_menu)

func _process(delta: float) -> void:
	if loading_bar:
		loading_bar.value = _load_progress * 100.0

	# Pulse title color
	_title_pulse += delta * 2.0
	if title_label:
		var pulse: float = (sin(_title_pulse) + 1.0) * 0.5
		var col: Color = Color(0.3, 0.7, 1.0).lerp(Color(0.5, 0.4, 1.0), pulse)
		title_label.add_theme_color_override("font_color", col)

func _go_to_menu() -> void:
	# Fade out
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): get_tree().change_scene_to_file("res://scenes/menu.tscn"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
