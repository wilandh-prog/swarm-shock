extends Node
## Global effects manager. Handles post-processing, screen shake, flashes.
## Autoload singleton.

var _canvas_layer: CanvasLayer
var _post_rect: ColorRect
var _post_mat: ShaderMaterial

# Chromatic aberration
var _aberration: float = 0.0
var _aberration_decay: float = 8.0

# Screen flash
var _flash: float = 0.0
var _flash_decay: float = 5.0

# Shake
var _shake_intensity: float = 0.0
var _shake_timer: float = 0.0
var _camera_base_pos: Vector3 = Vector3(0, 250, 350)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_post_processing()

func _setup_post_processing() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 100
	add_child(_canvas_layer)

	_post_rect = ColorRect.new()
	_post_rect.anchors_preset = Control.PRESET_FULL_RECT
	_post_rect.size = Vector2(1920, 1080)
	_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shader := load("res://shaders/vignette.gdshader")
	if shader:
		_post_mat = ShaderMaterial.new()
		_post_mat.shader = shader
		_post_rect.material = _post_mat

	_canvas_layer.add_child(_post_rect)

func _process(delta: float) -> void:
	# Decay chromatic aberration
	if _aberration > 0.001:
		_aberration = lerpf(_aberration, 0.0, _aberration_decay * delta)
		if _post_mat:
			_post_mat.set_shader_parameter("aberration_amount", _aberration)
	elif _aberration > 0.0:
		_aberration = 0.0
		if _post_mat:
			_post_mat.set_shader_parameter("aberration_amount", 0.0)

	# Decay flash
	if _flash > 0.001:
		_flash = lerpf(_flash, 0.0, _flash_decay * delta)
		if _post_mat:
			_post_mat.set_shader_parameter("flash_amount", _flash)
	elif _flash > 0.0:
		_flash = 0.0
		if _post_mat:
			_post_mat.set_shader_parameter("flash_amount", 0.0)

	# Screen shake
	if _shake_timer > 0.0:
		_shake_timer -= delta
		_apply_shake()
	elif _shake_intensity > 0.0:
		_shake_intensity = 0.0
		_reset_camera_offset()

# --- Public API ---

func chromatic_pulse(intensity: float = 0.008) -> void:
	_aberration = maxf(_aberration, intensity)

func screen_flash(color: Color = Color.WHITE, intensity: float = 0.3) -> void:
	_flash = intensity
	if _post_mat:
		_post_mat.set_shader_parameter("flash_color", color)
		_post_mat.set_shader_parameter("flash_amount", _flash)

func screen_shake(intensity: float = 8.0, duration: float = 0.2) -> void:
	_shake_intensity = intensity
	_shake_timer = duration

func big_impact() -> void:
	chromatic_pulse(0.012)
	screen_shake(12.0, 0.25)
	screen_flash(Color(0.3, 0.6, 1.0, 1.0), 0.15)

func small_impact() -> void:
	screen_shake(3.0, 0.08)

# --- Internal ---

func _apply_shake() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return
	var offset_x := randf_range(-1.0, 1.0) * _shake_intensity
	var offset_z := randf_range(-1.0, 1.0) * _shake_intensity
	cam.position = _camera_base_pos + Vector3(offset_x, 0, offset_z)

func _reset_camera_offset() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.position = _camera_base_pos
