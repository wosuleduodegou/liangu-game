extends Node

## 临时演示驱动：让蜈蚣走一条缓慢的正弦路线，方便看转弯时身体和足的样子，
## 同时把相机钉在蛇头（这里是蜈蚣头）上。

@export var target_path : NodePath = ^"../Centipede"
@export var camera_path : NodePath = ^"../Camera2D"
@onready var _cp : Node = get_node_or_null(target_path)
@onready var _cam : Camera2D = get_node_or_null(camera_path)
var _t : float = 0.0

func _process(delta: float) -> void:
	_t += delta
	if _cp == null:
		return
	_cp.external_direction = sin(_t * 0.9) * 1.15
	if _cam != null:
		_cam.global_position = _cp.to_global(_cp.head_pos)
