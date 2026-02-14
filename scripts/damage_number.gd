extends Node3D
## Floating damage number that drifts upward (in -Z for screen up) and fades out.

var text: String = ""
var color: Color = Color.WHITE
var font_size: int = 18
var _velocity: Vector3 = Vector3(0, 0, -60)
var _lifetime: float = 0.7
var _timer: float = 0.0
var _alpha: float = 1.0
var _scale_anim: float = 1.5
var _label: Label3D

func setup(value: int, pos: Vector3, col: Color = Color.WHITE, big: bool = false) -> void:
	text = str(value)
	position = pos + Vector3(randf_range(-10, 10), 5.0, randf_range(-5, 5))
	color = col
	if big:
		font_size = 28
		_scale_anim = 2.0
		_velocity.z = -80.0
	_velocity.x = randf_range(-20, 20)

func _ready() -> void:
	_label = Label3D.new()
	_label.text = text
	_label.font_size = font_size
	_label.modulate = color
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.pixel_size = 0.5
	_label.outline_size = 4
	_label.outline_modulate = Color(0, 0, 0, 0.7)
	add_child(_label)

func _process(delta: float) -> void:
	_timer += delta
	var t: float = _timer / _lifetime

	position += _velocity * delta
	_velocity *= 0.95

	_alpha = 1.0 - t
	_scale_anim = lerpf(_scale_anim, 1.0, 5.0 * delta)

	if _label:
		_label.modulate = Color(color, _alpha)
		_label.scale = Vector3.ONE * _scale_anim

	if _timer >= _lifetime:
		queue_free()
