extends ColorRect

## 阳光穿过尘土的滤镜。全屏叠在蛇视野滤镜之上，画一束从左上角约 15° 斜射进来的
## 光，光柱里漂着淡淡的浮尘，像久未开封的陶罐。
##
## 只叠亮、不改暗，白线和暗场都不受影响。强度很淡（intensity 0.16），
## 是"要很留神才看得见"那一档。参数都 export 出来，方便在 Inspector 里调。

@export var beam_angle : float = 15.0
@export var beam_center : float = 0.35
@export var beam_width : float = 0.55
@export var beam_soft : float = 0.6
@export var intensity : float = 0.16
@export var dust_density : float = 0.9
@export var dust_size : float = 1.6
@export var dust_brightness : float = 0.5
@export var dust_drift : Vector2 = Vector2(0.08, 0.05)
@export var time_scale : float = 1.0

var _mat : ShaderMaterial = null

func _ready() -> void:
	_mat = material as ShaderMaterial
	_push_aspect()
	_push_params()

func _process(_delta: float) -> void:
	_push_aspect()

func _push_aspect() -> void:
	if _mat == null:
		return
	var vp : Vector2 = get_viewport_rect().size
	var h : float = maxf(vp.y, 1.0)
	_mat.set_shader_parameter("aspect", Vector2(vp.x / h, 1.0))

func _push_params() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter("beam_angle", beam_angle)
	_mat.set_shader_parameter("beam_center", beam_center)
	_mat.set_shader_parameter("beam_width", beam_width)
	_mat.set_shader_parameter("beam_soft", beam_soft)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("dust_density", dust_density)
	_mat.set_shader_parameter("dust_size", dust_size)
	_mat.set_shader_parameter("dust_brightness", dust_brightness)
	_mat.set_shader_parameter("dust_drift", dust_drift)
	_mat.set_shader_parameter("time_scale", time_scale)
