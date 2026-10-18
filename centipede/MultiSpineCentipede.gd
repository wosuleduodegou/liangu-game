@tool
extends "res://centipede/Centipede.gd"

## 多棘蜈蚣（Scolopendra subspinipes）——少棘蜈蚣的近亲，直接继承同一套程序化身体。
##
## 和少棘的区别全在默认参数上：
##   * 大一号：每节更长更宽，整体约 24cm，比少棘粗壮一圈
##   * 头板偏暗红褐，背板墨绿发黑，末段发黄，步足橙黄
##   * 触角更长（多棘的触角几乎是体长的四分之一）
##   * 末对曳步足更粗长，向后拖得更远
##   * 步子频率低一些但幅度大，窜得更快
##
## 绘制、步态、IK、边界反弹的代码一行都没复制，全部沿用父类。
## 以后要改行为，动 Centipede.gd 就行，这个副本会一起变。

func _init() -> void:
	display_name = "Scolopendra subspinipes"

	# ---- 形体：21 节 20 对足不变，但每节拉长拉宽 ----
	segment_count = 21
	segment_spacing = 13.5
	body_radius = 8.2
	head_width_scale = 1.22
	head_length_scale = 1.12
	plate_gap = 0.10
	plate_round = 0.55

	# ---- 外观：和纯白线主体保持一致，只把轮廓加粗一点，显得更"厚" ----
	ghost_line_width = 4.05
	ghost_inner = Color(1.0, 1.0, 1.0, 0.45)

	# ---- 步态：大个体腿长一点、站得开一点，频率略低 ----
	leg_size = 0.62
	leg_reach = 2.0
	leg_hip_forward = 0.40
	step_trigger = 0.55
	speed = 128.0

	# ---- 形态配件 ----
	antenna_scale = 1.5
	ultimate_leg_scale = 1.2

	# ---- 体质：个体更大更耐打，毒抗也高一点 ----
	max_health = 118.0
	poison_resist = 0.82
