extends ColorRect

## 只属于这一条蛇的视觉滤镜：去饱和（蛇的二色觉）、周边模糊、蛇头周围一小圈可视。
##
## 真正决定"视力"的参数都在 Snake 的 Vision 组里，这里只负责每帧把它们换算成
## 屏幕坐标喂给 shader：
##   vision_radius 是世界像素，乘以相机 zoom 得到屏幕像素，再除以屏幕高度归一化。
## 所以相机拉近拉远、屏幕换分辨率，蛇能看见的物理范围都不变。

## 从 Filter 节点出发到蛇 / 相机的路径。找不到时会退回到场景根节点同名节点。
@export var snake_path : NodePath = ^"../../Snake"
@export var camera_path : NodePath = ^"../../Camera2D"
## 视线圈跟随蛇头的平滑速度。镜头本身已经平滑了，这里再跟一遍会更稳。
@export var center_smoothing : float = 20.0

var _snake : Snake = null
var _cam : Camera2D = null
var _mat : ShaderMaterial = null
var _center : Vector2 = Vector2(0.5, 0.5)

func _ready() -> void:
	_mat = material as ShaderMaterial
	_snake = _pick(snake_path, "Snake") as Snake
	_cam = _pick(camera_path, "Camera2D") as Camera2D
	_center = _head_uv()
	_push(0.0)

func _pick(path: NodePath, fallback_name: String) -> Node:
	var n : Node = get_node_or_null(path)
	if n != null:
		return n
	var root : Node = owner
	if root == null:
		root = get_tree().current_scene
	if root != null:
		return root.get_node_or_null(fallback_name)
	return null

func _process(delta: float) -> void:
	_push(delta)

## Head position in viewport UV. Canvas transform already includes the camera.
func _head_uv() -> Vector2:
	if _snake == null:
		return Vector2(0.5, 0.5)
	var vp : Vector2 = get_viewport_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return Vector2(0.5, 0.5)
	var px : Vector2 = get_viewport().get_canvas_transform() * _snake.get_head_global_position()
	return Vector2(px.x / vp.x, px.y / vp.y)

func _push(delta: float) -> void:
	if _mat == null or _snake == null:
		return

	var vp : Vector2 = get_viewport_rect().size
	var h : float = maxf(vp.y, 1.0)
	var target : Vector2 = _head_uv()
	if delta > 0.0:
		_center = _center.lerp(target, clampf(center_smoothing * delta, 0.0, 1.0))
	else:
		_center = target

	var zoom : float = _cam.zoom.y if _cam != null else 1.0
	var radius_px : float = _snake.vision_radius * zoom

	_mat.set_shader_parameter("center", _center)
	_mat.set_shader_parameter("aspect", vp.x / h)
	_mat.set_shader_parameter("radius", radius_px / h)
	_mat.set_shader_parameter("softness", _snake.vision_softness)
	_mat.set_shader_parameter("darkness", _snake.vision_darkness)
	_mat.set_shader_parameter("near_shade", _snake.vision_near_shade)
	_mat.set_shader_parameter("mid_shade", _snake.vision_mid_shade)
	_mat.set_shader_parameter("near_u", _snake.vision_near_u)
	_mat.set_shader_parameter("mid_u", _snake.vision_mid_u)
	_mat.set_shader_parameter("brightness", _snake.vision_brightness)
	_mat.set_shader_parameter("saturation", _snake.vision_saturation)
	_mat.set_shader_parameter("blur_amount", _snake.vision_blur * zoom)
	_mat.set_shader_parameter("tint", Vector3(_snake.vision_tint.r, _snake.vision_tint.g, _snake.vision_tint.b))
	# 白线可见性的"灯"不再由蛇头决定：关卡里的罐顶天光负责（见 关卡.gd）。
