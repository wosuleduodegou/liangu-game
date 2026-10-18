extends Node2D

## 主菜单背景的鼠标视差：Parallax2D 的 scroll_offset 跟着鼠标相对屏幕中心偏移。
## 尺寸一律用 get_viewport_rect()（拉伸后的虚拟分辨率），
## 这样在任意窗口尺寸 / 屏幕比例下，鼠标偏移量都能对上。

@export var max_offset: Vector2 = Vector2(20.0, 20.0)
@export var smooth_speed: float = 6.0

var viewport_size: Vector2 = Vector2.ZERO
var parallax_layers: Array[Parallax2D] = []
var current_offset: Vector2 = Vector2.ZERO
var target_offset: Vector2 = Vector2.ZERO

func _ready() -> void:
	for child in get_children():
		if child is Parallax2D:
			parallax_layers.append(child)

	get_viewport().size_changed.connect(_on_viewport_changed)
	_on_viewport_changed()

func _on_viewport_changed() -> void:
	viewport_size = get_viewport_rect().size

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var center: Vector2 = viewport_size / 2.0
		if center.x <= 0.0 or center.y <= 0.0:
			return

		# 相对中心点的偏移比例（-1.0 ~ 1.0）
		var relative_x: float = (event.position.x - center.x) / center.x
		var relative_y: float = (event.position.y - center.y) / center.y
		target_offset = Vector2(relative_x * max_offset.x, relative_y * max_offset.y)

func _process(delta: float) -> void:
	current_offset = current_offset.lerp(target_offset, delta * smooth_speed)
	for layer in parallax_layers:
		layer.scroll_offset = current_offset * layer.scroll_scale
