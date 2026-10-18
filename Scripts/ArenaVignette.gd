@tool
extends Node2D

## 陶罐内壁。
##
## 场地是一张 5000x5000 的方形图，真正的边界是它的内切圆。这个节点把圆外
## 一层层压黑，并在圆内边缘留一圈暖色暗角 —— 看起来就像蛇是在一只陶罐的
## 内壁上爬。
##
## 实现上只画一张径向渐变纹理：中心透明，到墙口开始变暗，越过墙很快全黑。
## 静止不动，运行时每帧零开销。

## 圆形场地中心，和 Snake 的 bounds_center 保持一致。
@export var arena_center : Vector2 = Vector2(2500, 2500)

## 圆形场地半径，和 Snake 的 bounds_radius 保持一致。
@export_range(64.0, 12000.0, 1.0, "suffix:px") var arena_radius : float = 500.0

## 越过墙之后多少像素完全变黑。
@export_range(0.0, 4000.0, 10.0, "suffix:px") var fade_width : float = 106.0

## 墙内暗角的宽度（贴壁的暖色阴影往场内延伸多远）。
@export_range(0.0, 1800.0, 10.0, "suffix:px") var inner_falloff : float = 88.0

## 贴壁处的暗角浓度（0 = 不压暗，1 = 全黑）。
@export_range(0.0, 1.0, 0.01) var wall_shade : float = 0.78

## 圆外（罐壁之外）的颜色。纯黑：那是到不了的地方，不该有任何可读信息。
@export var outside_color : Color = Color(0.0, 0.0, 0.0, 1.0)

## 墙内暗角的颜色，偏暖的陶土色，像罐壁反光。
@export var inner_tint : Color = Color(0.36, 0.25, 0.16, 1.0)

## 渐变贴图的覆盖半径。必须大于"场地半径 + 摄像机半对角线"，
## 否则镜头贴到墙边时会看到纹理边缘。
@export_range(200.0, 12000.0, 50.0, "suffix:px") var coverage_radius : float = 1200.0

## 渐变贴图分辨率。够用就行，2048 已经完全看不出色带。
@export_range(256, 4096, 128) var texture_size : int = 2048

var _tex : GradientTexture2D = null
var _sig : String = ""

func _ready() -> void:
	# 内壁是阴影，不能被蛇那盏光点亮 —— 用 unshaded 材质，light_mask 在
	# 兼容渲染器下不足以挡住加法混合的光。
	var mat := CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	light_mask = 0
	_rebuild()

func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		return
	_rebuild_if_needed()

func _rebuild_if_needed() -> void:
	var sig : String = "%s|%.1f|%.1f|%.1f|%.3f|%s|%s|%.1f|%d" % [
		arena_center, arena_radius, fade_width, inner_falloff, wall_shade,
		outside_color, inner_tint, coverage_radius, texture_size,
	]
	if sig == _sig:
		return
	_sig = sig
	_rebuild()

func _rebuild() -> void:
	var big : float = maxf(coverage_radius, arena_radius + fade_width + 200.0)
	var t_inner : float = clampf((arena_radius - inner_falloff) / big, 0.0, 1.0)
	var t_wall : float = clampf(arena_radius / big, 0.0, 1.0)
	var t_dark : float = clampf((arena_radius + fade_width) / big, 0.0, 1.0)

	var stops : Array = [
		[0.0, Color(inner_tint, 0.0)],
		[t_inner, Color(inner_tint, 0.0)],
		[t_wall, Color(inner_tint, wall_shade)],
		[lerpf(t_wall, t_dark, 0.34), Color(inner_tint.lerp(outside_color, 0.55), lerpf(wall_shade, 1.0, 0.56))],
		[lerpf(t_wall, t_dark, 0.68), Color(inner_tint.lerp(outside_color, 0.86), lerpf(wall_shade, 1.0, 0.83))],
		[t_dark, Color(outside_color, 1.0)],
		[1.0, Color(outside_color, 1.0)],
	]

	# Gradient 要求 offset 严格递增，参数调极端时会重合，这里做一次归一化。
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var last : float = -1.0
	for s in stops:
		var o : float = maxf(float(s[0]), last + 0.0005)
		if o >= 1.0:
			o = 1.0
		last = o
		offs.append(o)
		cols.append(s[1])

	var grad := Gradient.new()
	grad.offsets = offs
	grad.colors = cols

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = texture_size
	tex.height = texture_size
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	_tex = tex
	queue_redraw()

func _draw() -> void:
	if _tex == null:
		_rebuild()
	var r : float = maxf(coverage_radius, arena_radius + fade_width + 200.0)
	draw_texture_rect(_tex, Rect2(arena_center - Vector2(r, r), Vector2(r * 2.0, r * 2.0)), false)
