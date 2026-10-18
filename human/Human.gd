@tool
extends Node2D

## 第四关的玩家角色：一个巨大的人，占满整张地图。
##
## 人本体固定不动，玩家用鼠标操控一只「手」——手跟随鼠标在场地里游走，
## 按住鼠标左键（或 E）进入抓取模式，手碰到第一个实体就抓住、拖回来吃掉，
## 补充饥饿值。
##
## 人本身会饿（饥饿值随时间下降），饿到 0 就死。场上的蛇/蜈蚣/蟾蜍/蚂蚁
## 也会被饿死。抓取 + 吃掉是唯一的进食手段，也是唯一的攻击手段——
## 吃光所有实体即通关。
##
## 尺寸沿用项目约定：1 米 = 500px。这个「人」是巨物，身体填满罐底。

# ------------------------------- Identity -------------------------------
@export_group("Identity")
@export var display_name : String = "Human"
@export var kill_label : String = "HUMAN"

# ------------------------------- Body shape -------------------------------
@export_group("Body Shape")
## 身体半径（人是巨物，几乎占满半径 510px 的场地）。
@export_range(100.0, 600.0, 5.0, "suffix:px") var body_radius : float = 420.0
## 头半径。
@export_range(10.0, 120.0, 1.0, "suffix:px") var head_radius : float = 60.0
## 躯干半宽（画身体轮廓的粗细）。
@export_range(5.0, 80.0, 0.5, "suffix:px") var torso_width : float = 26.0

# ------------------------------- Ghost look -------------------------------
@export_group("Ghost Look")
@export var ghost_line : Color = Color(1.0, 1.0, 1.0, 0.96)
@export var ghost_inner : Color = Color(1.0, 1.0, 1.0, 0.12)
@export_range(0.4, 5.0, 0.1, "suffix:px") var ghost_line_width : float = 1.2

# ------------------------------- Hand -------------------------------
@export_group("Hand")
## 手的大小（画出来的圆点半径）。
@export_range(2.0, 30.0, 0.5, "suffix:px") var hand_radius : float = 14.0
## 手的移动速度。
@export_range(50.0, 800.0, 5.0, "suffix:px/s") var hand_speed : float = 360.0
## 手能在场地内走多远（相对人中心的半径）。
@export_range(100.0, 700.0, 5.0, "suffix:px") var hand_reach : float = 470.0
## 抓取判定半径：手离实体多近算「碰到」。
@export_range(4.0, 80.0, 1.0, "suffix:px") var grab_range : float = 30.0

# ------------------------------- Hunger -------------------------------
@export_group("Hunger")
## 饥饿值上限。
@export_range(10.0, 400.0, 1.0) var max_satiety : float = 100.0
## 每秒自然消耗。
@export_range(0.0, 20.0, 0.05, "suffix:/s") var satiety_drain : float = 1.2
## 吃掉一只实体补多少饥饿值（按实体类型加权）。
@export_range(5.0, 200.0, 1.0) var eat_gain : float = 40.0

# ------------------------------- Vitals -------------------------------
@export_group("Vitals")
@export_range(1.0, 2000.0, 1.0) var max_health : float = 100.0
@export_range(0.2, 5.0, 0.1, "suffix:s") var death_fade : float = 1.4

# ------------------------------- Bounds -------------------------------
@export_group("Bounds")
@export var bounds_center : Vector2 = Vector2(2500, 2500)
@export_range(64.0, 12000.0, 1.0, "suffix:px") var bounds_radius : float = 500.0

# ------------------------------- Runtime state -------------------------------
var health : float = 100.0
var satiety : float = 100.0
var _dead : bool = false
var _death_t : float = 0.0

## 手的位置（世界坐标）。初始在人正上方。
var hand_pos : Vector2 = Vector2.ZERO
## 抓取模式：E 按住时为 true，手碰到实体就抓住吃掉。
var grabbing : bool = false
## 正在抓住/拖回中的实体。
var _held = null
## 手刚刚吃掉东西的反馈（画个小动画用）。
var _eat_fx : float = 0.0
var _hurt : float = 0.0

var t : float = 0.0

## 已获得的特性（沿用之前的永久特性系统，保留兼容）。
var traits : Dictionary = {}

## 热成像给其它实体用的几何中心 / 轮廓。
var heat_center : Vector2 = Vector2.ZERO
var heat_outline : PackedVector2Array = PackedVector2Array()

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	health = max_health
	satiety = max_satiety
	if Engine.is_editor_hint():
		return
	add_to_group("human")
	_rng.randomize()
	# 手出生在头顶，等玩家接管。
	hand_pos = global_position + Vector2(0, -body_radius * 0.4)

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _dead:
		t += delta
	_tick_combat(delta)
	if _dead:
		queue_redraw()
		return
	_tick_hunger(delta)
	_tick_hand(delta)
	queue_redraw()

# =============================== Combat ===============================
func take_damage(amount: float, from_global: Vector2 = Vector2.ZERO,
		poison: float = 0.0, poison_time: float = 0.0) -> float:
	if _dead:
		return 0.0
	var dmg : float = maxf(0.0, amount)
	if traits.has("endurance"):
		dmg *= (1.0 - 0.15)
	var dealt : float = minf(health, dmg)
	health = maxf(0.0, health - dmg)
	_hurt = 1.0
	if health <= 0.0:
		_die()
	return dealt

## 被攻击时获得对应生物的特性（永久）。保留兼容。
func gain_trait(kind: String) -> bool:
	var id : String = ""
	match kind:
		"snake": id = "venom"
		"centipede":
			id = "centipede_venom"
			if not traits.has("endurance"):
				traits["endurance"] = true
		"toad": id = "toad_skin"
	if id == "" or traits.has(id):
		return false
	traits[id] = true
	return true

func has_trait(id: String) -> bool:
	return traits.has(id)

func is_dead() -> bool:
	return _dead

func health_ratio() -> float:
	return clampf(health / maxf(1.0, max_health), 0.0, 1.0)

## 饱食度比例（给 HUD 显示）。
func satiety_ratio() -> float:
	return clampf(satiety / maxf(1.0, max_satiety), 0.0, 1.0)

func _die() -> void:
	if _dead:
		return
	_dead = true
	_death_t = 0.0

func _tick_combat(delta: float) -> void:
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta * 5.0)
	_eat_fx = maxf(0.0, _eat_fx - delta * 3.0)
	if _dead:
		_death_t += delta
		modulate.a = clampf(1.0 - _death_t / maxf(0.01, death_fade), 0.0, 1.0)
		if _death_t >= death_fade:
			queue_free()

# =============================== Hunger ===============================
func _tick_hunger(delta: float) -> void:
	if satiety > 0.0:
		satiety = maxf(0.0, satiety - satiety_drain * delta)
	if satiety <= 0.0 and not _dead:
		# 饿死：持续掉血。
		health = maxf(0.0, health - 3.0 * delta)
		if health <= 0.0:
			_die()

func feed(amount: float) -> void:
	if amount <= 0.0:
		return
	satiety = clampf(satiety + amount, 0.0, max_satiety)

# =============================== Hand ===============================
func _tick_hand(delta: float) -> void:
	if _dead:
		return
	# 鼠标操纵：手朝鼠标指向的世界坐标移动（鼠标在可及范围外则停在边界）。
	var mouse : Vector2 = get_global_mouse_position()
	var target : Vector2 = mouse
	var off : Vector2 = target - global_position
	if off.length() > hand_reach:
		target = global_position + off.normalized() * hand_reach

	# 手朝目标平滑移动（速度上限 hand_speed）。
	var step : Vector2 = target - hand_pos
	var max_step : float = hand_speed * delta
	if step.length() > max_step:
		hand_pos += step.normalized() * max_step
	else:
		hand_pos = target

	# 抓取模式：E 键或按住鼠标左键。
	grabbing = Input.is_key_pressed(KEY_E) or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

	# 抓取：碰到第一个活实体就抓住吃掉。
	if grabbing:
		_try_grab()

## 找手上「碰到」的最近活实体，抓住并吃掉。
func _try_grab() -> void:
	for group in ["snake", "centipede", "toad", "ant"]:
		for n in get_tree().get_nodes_in_group(group):
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			if n.is_queued_for_deletion():
				continue
			if n.has_method("is_dead") and bool(n.call("is_dead")):
				continue
			var p : Vector2 = _body_center(n)
			if hand_pos.distance_to(p) <= grab_range:
				_eat(n)
				return

## 吃掉一只实体：直接击杀 + 回饥饿。
func _eat(n) -> void:
	var gain : float = eat_gain
	# 按体型加权：蛇/蟾蜍吃得饱，蚂蚁小。
	if n.is_in_group("snake") or n.is_in_group("toad"):
		gain = eat_gain * 1.4
	elif n.is_in_group("centipede"):
		gain = eat_gain * 1.1
	if n.has_method("take_damage"):
		n.call("take_damage", 100000.0, hand_pos)
	feed(gain)
	_eat_fx = 1.0
	var toast : Node = get_node_or_null("/root/Toast")
	if toast != null and toast.has_method("good"):
		toast.call("good", tr("ATE A PREY  +%d") % int(gain), "human_eat")

## 目标的身体中心：有 points 的取头部，否则节点原点。
func _body_center(n: Node2D) -> Vector2:
	var pts = n.get("points")
	if pts is PackedVector2Array and not (pts as PackedVector2Array).is_empty():
		return n.to_global((pts as PackedVector2Array)[0])
	return n.global_position

# =============================== Drawing ===============================
func _draw() -> void:
	_build_heat()
	var lit := Color(1.0, 1.0, 1.0, ghost_line.a)
	if _hurt > 0.0:
		lit = Color(1.0, 0.7, 0.7, 1.0)

	# 巨大的人形轮廓：占满场地。头朝上，躯干向下铺开。
	_draw_giant_body(lit)
	# 手：一个独立的圆点，在场地里游走。
	_draw_hand(lit)

## 巨大人形：一个填满罐底的大轮廓（头 + 躯干 + 摊开的四肢，极简线稿）。
func _draw_giant_body(lit: Color) -> void:
	var r : float = body_radius
	# 头：一个大圆，在顶部。
	var head_c : Vector2 = Vector2(0, -r * 0.72)
	draw_circle(head_c, head_radius, Color(lit.r, lit.g, lit.b, ghost_inner.a))
	draw_arc(head_c, head_radius, 0.0, TAU, 40, lit, ghost_line_width, false)
	# 眼睛：两个点，让「人」有神情。
	draw_circle(head_c + Vector2(-head_radius * 0.35, -head_radius * 0.15), 3.0, lit)
	draw_circle(head_c + Vector2(head_radius * 0.35, -head_radius * 0.15), 3.0, lit)

	# 躯干：从头向下延伸的宽体。
	var neck : Vector2 = head_c + Vector2(0, head_radius)
	var torso_bot : Vector2 = Vector2(0, r * 0.55)
	draw_line(neck, torso_bot, lit, torso_width, false)

	# 两条腿：从躯干底部向两侧摊开（跪坐/瘫坐的姿态，占满底部）。
	var hip : Vector2 = torso_bot
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var knee : Vector2 = hip + Vector2(sf * r * 0.55, r * 0.25)
		var foot : Vector2 = knee + Vector2(sf * r * 0.25, r * 0.28)
		draw_polyline(PackedVector2Array([hip, knee, foot]), lit, ghost_line_width * 1.1, false)
		draw_circle(foot, 5.0, lit)

	# 两条臂：一条是玩家操控的手（画在别处），这里画一条摊在地上的残臂。
	# 右臂残肢：从肩部向右侧垂下。
	var shoulder : Vector2 = Vector2(-torso_width, -r * 0.40)
	draw_line(shoulder, shoulder + Vector2(r * 0.4, r * 0.5), lit, ghost_line_width * 0.9, false)

## 玩家操控的手：一个游走的圆点，抓取模式下变大变色。
func _draw_hand(lit: Color) -> void:
	var local : Vector2 = to_local(hand_pos)
	var col : Color = lit
	var rad : float = hand_radius
	if grabbing:
		# 抓取模式：手张开，泛暖色。
		col = Color(1.0, 0.85, 0.55, 1.0)
		rad = hand_radius * 1.4
	if _eat_fx > 0.0:
		col = Color(1.0, 0.6, 0.4, 1.0)
		rad = hand_radius * (1.0 + _eat_fx * 0.6)
	draw_circle(local, rad, Color(col.r, col.g, col.b, ghost_inner.a * 1.5))
	draw_arc(local, rad, 0.0, TAU, 24, col, ghost_line_width, false)
	# 抓取模式下手边画几根「手指」般的短线。
	if grabbing:
		for i in 5:
			var a : float = t * 2.0 + TAU * float(i) / 5.0
			draw_line(local, local + Vector2.from_angle(a) * (rad + 6.0), col, ghost_line_width * 0.7, false)

func _build_heat() -> void:
	heat_center = Vector2.ZERO
	heat_outline.clear()
	# 简化：人的轮廓用一个占满场地的大圆近似。
	var steps : int = 24
	for k in steps:
		var a : float = TAU * float(k) / float(steps)
		heat_outline.append(Vector2(cos(a) * body_radius, sin(a) * body_radius))
