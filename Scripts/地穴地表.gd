extends Node2D

## 地表的「地面上的东西」：地穴口 + 散落的食团。
##
## 单独一个节点，是为了让它排在背景之后、蚂蚁之前——地面标记要压在土下面，
## 虫子要走在土上面。关卡脚本只需要把 pellets 塞进来，它自己重画。

## 地穴口（世界坐标）。
@export var nest_pos : Vector2 = Vector2(2500.0, 2500.0)
## 洞口的半径。
@export_range(6.0, 120.0, 1.0, "suffix:px") var hole_radius : float = 34.0
## 洞口外圈那两道的亮度。
@export var rim_color : Color = Color(1.0, 1.0, 1.0, 0.20)
## 食团半径。
@export_range(2.0, 24.0, 0.5, "suffix:px") var pellet_radius : float = 5.5
@export var pellet_color : Color = Color(1.0, 0.96, 0.84, 0.94)

## 关卡脚本每帧写这一项；一变就重画。
var pellets : Array[Vector2] = []:
	set(value):
		pellets = value
		queue_redraw()

func _ready() -> void:
	queue_redraw()

func _draw() -> void:
	# 洞口：中间挖空的黑 + 两圈松动的土沿。
	draw_circle(nest_pos, hole_radius, Color(0.045, 0.035, 0.026, 0.96))
	draw_arc(nest_pos, hole_radius, 0.0, TAU, 44, Color(rim_color.r, rim_color.g, rim_color.b, 0.24), 1.5)
	draw_arc(nest_pos, hole_radius + 7.0, 0.0, TAU, 44, Color(rim_color.r, rim_color.g, rim_color.b, 0.10), 1.0)
	# 洞口的土堆：几道短弧，像被反复进出磨出来的。
	for i in 7:
		var a : float = TAU * float(i) / 7.0 + 0.35
		var p : Vector2 = nest_pos + Vector2.from_angle(a) * (hole_radius + 2.0)
		draw_arc(p, 7.0 + float(i % 3) * 2.0, a - 0.9, a + 0.9, 12,
			Color(rim_color.r, rim_color.g, rim_color.b, 0.10), 1.0)

	for p in pellets:
		draw_circle(p, pellet_radius, pellet_color)
		draw_arc(p, pellet_radius, 0.0, TAU, 14, Color(0.10, 0.08, 0.06, 0.55), 1.0)

	_draw_ground()

## 地表的细枝末节：蚁道、草根、土粒。让洞口之外不至于是一片空土。
func _draw_ground() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8848

	# 蚁道：从洞口朝外散开的几条淡线，微微打弯，像被踩出来的路。
	for i in 7:
		var ang : float = TAU * float(i) / 7.0 + rng.randf_range(-0.22, 0.22)
		var pts := PackedVector2Array()
		var steps : int = 14
		for k in steps + 1:
			var t : float = float(k) / float(steps)
			var r : float = hole_radius + t * (420.0 - hole_radius)
			var wob : float = sin(t * 5.0 + float(i)) * 14.0 * t
			pts.append(nest_pos + Vector2.from_angle(ang) * r
				+ Vector2.from_angle(ang + PI * 0.5) * wob)
		draw_polyline(pts, Color(1.0, 0.96, 0.86, 0.05), 2.0)

	# 草根：几段往土里钻的折线。
	for i in 12:
		var a : float = rng.randf_range(0.0, TAU)
		var r0 : float = rng.randf_range(150.0, 470.0)
		var p : Vector2 = nest_pos + Vector2.from_angle(a) * r0
		var dir : float = rng.randf_range(0.0, TAU)
		var pts2 := PackedVector2Array()
		pts2.append(p)
		for k in 5:
			dir += rng.randf_range(-0.7, 0.7)
			p += Vector2.from_angle(dir) * rng.randf_range(14.0, 30.0)
			pts2.append(p)
		draw_polyline(pts2, Color(1.0, 0.94, 0.80, 0.055), 1.0)

	# 土粒。
	for i in 160:
		var a2 : float = rng.randf_range(0.0, TAU)
		var r2 : float = sqrt(rng.randf()) * 470.0
		var p2 : Vector2 = nest_pos + Vector2.from_angle(a2) * r2
		if p2.distance_to(nest_pos) < hole_radius + 12.0:
			continue
		draw_circle(p2, rng.randf_range(0.8, 2.6),
			Color(1.0, 0.95, 0.86, rng.randf_range(0.02, 0.07)))
