@tool
extends Node2D

## 工蚁（worker ant）的程序化角色，极简线稿。
##
## 结构只有三样：轮廓（头/胸/腹三体段）、六条足、两根肘状触角。
## 全部在 _draw() 里现画，只有白线，没有填充和贴图。
##
## 身体是一条 3 节点的 follow-the-leader 链（头 / 胸 / 腹），转弯时自然弯曲；
## 六条足全挂在胸部节点上，用蜈蚣那套"脚尖钉地 + FABRIK 反解"的步态，
## 抬腿左右轮流、相邻腿反相；触角是肘状（柄节 + 鞭节折角），用惯性弹簧链，
## 转弯时会被甩出弧线。
##
## 尺寸基准沿用项目约定：1 米 = 500px。工蚁体长约 70px，比蜈蚣小一号。

# ------------------------------- Identity -------------------------------
@export_group("Identity")

@export var display_name : String = "Worker Ant"

## 击杀播报里显示的名字。英文原文同时是翻译表的 key。
@export var kill_label : String = "ANT"

## 蚁后标记：其他蚂蚁会主动往她身边聚（而不是找最近的同伴）。
@export var is_queen : bool = false

# ------------------------------- Body shape -------------------------------
@export_group("Body Shape")

## 身体骨节点数。固定 3：头 / 胸 / 腹。
const BODY_NODES : int = 3

## 头到胸、胸到腹的节点间距。
@export_range(2.0, 40.0, 0.5, "suffix:px") var segment_spacing : float = 3.0

## 头部半径（圆形头）。
@export_range(0.5, 20.0, 0.25, "suffix:px") var head_radius : float = 1.5

## 胸部半宽（蚂蚁胸部比头窄、比腹窄，是"细腰"的起点）。
@export_range(0.5, 20.0, 0.25, "suffix:px") var thorax_radius : float = 1.0

## 腹部半宽（工蚁腹部最大，是椭圆）。
@export_range(0.5, 30.0, 0.25, "suffix:px") var abdomen_radius : float = 1.75

## 腹部长度（椭圆长轴，比半宽大就是拉长的蛋形）。
@export_range(3.0, 50.0, 0.5, "suffix:px") var abdomen_length : float = 3.5

## 胸腹之间的"细腰"收束：1.0 = 不收紧，越小腰越细。
@export_range(0.3, 1.0, 0.02) var waist_pinch : float = 0.55

## 上颚（大颚）长度倍率。0 = 不长颚（工蚁）；
## 兵蚁调到 1.0 上下，就是一对朝内弯的大夹子。
@export_range(0.0, 2.5, 0.05) var jaw_scale : float = 0.0

## 翅膀大小倍率。0 = 无翅；雄蚁、还没脱翅的蚁后用。
@export_range(0.0, 2.5, 0.05) var wing_scale : float = 0.0

## 翅膀扇动幅度（0 = 静止张着）。
@export_range(0.0, 1.0, 0.02) var wing_beat : float = 0.24

# ------------------------------- Ghost look -------------------------------
@export_group("Ghost Look")

@export var ghost_line : Color = Color(1.0, 1.0, 1.0, 0.96)

@export var ghost_inner : Color = Color(1.0, 1.0, 1.0, 0.45)

@export_range(0.4, 5.0, 0.1, "suffix:px") var ghost_line_width : float = 1.8

# ------------------------------- Legs -------------------------------
@export_group("Legs")

## 单节腿长，相对节距的倍率。
@export_range(0.1, 1.2, 0.01) var leg_size : float = 0.60

## 脚尖离体侧多远，相对单节腿长的倍率。
@export_range(0.6, 5.0, 0.05) var leg_reach : float = 2.1

## 髋点相对体节中心往前偏多少。
@export_range(0.0, 1.2, 0.02) var leg_hip_forward : float = 0.30

## 脚尖偏离理想落点多少就抬腿重踩。
@export_range(0.1, 1.0, 0.01) var step_trigger : float = 0.5

## 迈一步的插值速度。
@export_range(2.0, 40.0, 0.5, "suffix:/s") var step_speed : float = 16.0

## 抬腿时脚尖朝髋收回多少。
@export_range(0.0, 1.0, 0.02) var leg_lift : float = 0.32

# ------------------------------- Antennae -------------------------------
@export_group("Antennae")

## 触角长度倍率。工蚁触角是肘状（柄节短、鞭节长）。
@export_range(0.4, 2.5, 0.05) var antenna_scale : float = 0.7

## 触角回弹刚度。
@export_range(0.05, 1.0, 0.01) var antenna_stiffness : float = 0.55

## 触角惯性保留量。
@export_range(0.0, 0.95, 0.01) var antenna_damping : float = 0.30

# ------------------------------- Motion -------------------------------
@export_group("Motion")

@export_range(10.0, 400.0, 5.0, "suffix:px/s") var speed : float = 85.0
@export_range(0.5, 30.0, 0.1) var turn_speed : float = 5.0
@export_range(1.0, 40.0, 0.5) var throttle_response : float = 9.0
@export_enum("Wander", "Follow Mouse", "Keyboard", "External") var control_mode : int = 0
## 外部控制时由外部脚本写入的朝向（弧度）。
@export var external_direction : float = 0.0

## 躲避蛇：蛇头进入这个距离（世界像素）就掉头逃跑。
@export_range(0.0, 800.0, 5.0, "suffix:px") var fear_range : float = 180.0
## 逃跑时比正常游走快多少倍。
@export_range(1.0, 3.0, 0.05) var flee_speed_boost : float = 1.8
## 聚群：蚂蚁会朝这个距离内的最近同伴靠拢（工蚁的社会性）。
@export_range(0.0, 800.0, 5.0, "suffix:px") var flock_range : float = 200.0
## 聚群的转向权重。越大越急着归队。
@export_range(0.0, 3.0, 0.05) var flock_strength : float = 1.2

# ------------------------------- Vitals -------------------------------
@export_group("Vitals")

@export_range(1.0, 2000.0, 1.0) var max_health : float = 26.0
@export_range(0.0, 3.0, 0.05) var poison_resist : float = 1.0
@export_range(0.2, 5.0, 0.1, "suffix:s") var death_fade : float = 1.2
## 饿死开关：>0 时饱食度归零就每秒扣这么多血，直到饿死。0 = 不会饿死。
@export_range(0.0, 50.0, 0.5, "suffix:/s") var starve_dps : float = 0.0
## 饿死/死亡后是否留下尸体（由关卡接管画蓝黑色尸体）。false 时照旧淡出消失。
@export var leave_corpse : bool = false

# ------------------------------- Attack -------------------------------
@export_group("Attack")

## 咬一口的伤害。0 = 不咬人（工蚁、雄蚁）。
@export_range(0.0, 100.0, 0.5) var attack_damage : float = 0.0

## 够多近才咬得着（世界像素）。
@export_range(0.0, 200.0, 1.0, "suffix:px") var attack_range : float = 28.0

## 两口之间隔多久。
@export_range(0.2, 5.0, 0.05, "suffix:s") var attack_cooldown : float = 1.0

## 咬哪个组里的东西。第二关的玩家蜈蚣在 "centipede" 组；
## 第一关没有这个组，所以兵蚁在第一关不会误伤玩家。
@export var attack_group : String = "centipede"

# ------------------------------- Bounds -------------------------------
@export_group("Bounds")

@export var stay_in_viewport : bool = true
@export var use_play_bounds : bool = false
@export_enum("Rectangle", "Circle") var bounds_shape : int = 1
@export var bounds_center : Vector2 = Vector2(2500, 2500)
@export_range(64.0, 12000.0, 1.0, "suffix:px") var bounds_radius : float = 500.0
@export var play_bounds : Rect2 = Rect2(0, 0, 1920, 1080)

# ------------------------------- Runtime state -------------------------------
var points : PackedVector2Array = []
var head_pos : Vector2 = Vector2.ZERO
var heading : float = 0.0
var t : float = 0.0

var _throttle : float = 0.0
var _speed_now : float = 0.0
var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _editor_sig : String = ""
var metab = null

## 热成像用：本帧每条腿的折线（本地坐标），每 4 个点一条腿：髋/膝/踝/尖。
var heat_leg_chains : PackedVector2Array = PackedVector2Array()
var heat_leg_slots : int = 0
## 热成像用：本帧整只虫的外轮廓（本地坐标，闭合）。
var heat_outline : PackedVector2Array = PackedVector2Array()
## 热成像用：整只蚂蚁的几何中心（本地坐标）。球形身体的红线判定就取这一个点。
var heat_center : Vector2 = Vector2.ZERO

var health : float = 26.0
var _hurt : float = 0.0
var _poison_time : float = 0.0
var _poison_dps : float = 0.0
var _dead : bool = false
var _death_time : float = 0.0
var _death_t : float = 0.0

## 咬人冷却、刚咬完那一下的头部前冲（纯表现）。
var _attack_cd : float = 0.0
var _bite_fx : float = 0.0
## 翅膀扇动的相位。
var _wing_phase : float = 0.0

func _ready() -> void:
	metab = get_node_or_null("Metabolism")
	health = max_health
	if Engine.is_editor_hint():
		return
	add_to_group("ant")
	_rng.randomize()
	_reset_body()

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not _dead:
		t += delta
	_tick_combat(delta)
	if _dead:
		queue_redraw()
		return
	if metab:
		metab.tick(delta)
		_tick_starve(delta)
	_move_head(delta)
	_follow_body()
	_update_legs(delta)
	_update_antennae()
	_tick_attack(delta)
	_wing_phase += delta
	queue_redraw()

# =============================== Combat ===============================
## 饿死：饱食度归零后持续掉血。饿死走同一套 take_damage / _die 流程，
## 但先标 starved_out，让关卡能认出「这具尸体是饿出来的」。
var starved_out : bool = false

func _tick_starve(delta: float) -> void:
	if starve_dps <= 0.0 or metab == null or _dead:
		return
	if float(metab.get("satiety")) <= 0.0:
		starved_out = true
		take_damage(starve_dps * delta)

func take_damage(amount: float, from_global: Vector2 = Vector2.ZERO,
		poison: float = 0.0, poison_time: float = 0.0) -> float:
	if _dead:
		return 0.0
	var dealt : float = minf(health, maxf(0.0, amount))
	health = maxf(0.0, health - maxf(0.0, amount))
	_hurt = 1.0
	if poison > 0.0 and poison_time > 0.0:
		_poison_dps = maxf(_poison_dps, poison * poison_resist)
		_poison_time = maxf(_poison_time, poison_time)
	if health <= 0.0:
		_die()
	return dealt

func is_dead() -> bool:
	return _dead

func is_poisoned() -> bool:
	return _poison_time > 0.0 and not _dead

func health_ratio() -> float:
	return clampf(health / maxf(1.0, max_health), 0.0, 1.0)

func _die() -> void:
	if _dead:
		return
	_dead = true
	_death_time = death_fade
	_death_t = 0.0
	_poison_time = 0.0
	_report_kill()


## 击杀播报：交给全局 Toast 弹一条左侧气泡。
## 编辑器里（@tool）没有 autoload，这里静默跳过。
func _report_kill() -> void:
	var toast : Node = get_node_or_null("/root/Toast")
	if toast != null and toast.has_method("kill"):
		toast.call("kill", kill_label)

func _tick_combat(delta: float) -> void:
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta * 5.0)
	if _dead:
		_death_t += delta
		_death_time = maxf(0.0, _death_time - delta)
		modulate.a = clampf(_death_time / maxf(0.01, death_fade), 0.0, 1.0)
		if _death_time <= 0.0:
			queue_free()
		return
	if _poison_time > 0.0:
		var tick : float = minf(delta, _poison_time)
		_poison_time = maxf(0.0, _poison_time - delta)
		health = maxf(0.0, health - _poison_dps * tick)
		if _poison_time <= 0.0:
			_poison_dps = 0.0
		if health <= 0.0:
			_die()

# =============================== Attack ===============================
## 兵蚁 / 蚁后：贴到目标就咬。目标是 attack_group 里的活物（默认第二关的蜈蚣）。
func _tick_attack(delta: float) -> void:
	_bite_fx = maxf(0.0, _bite_fx - delta * 4.0)
	if attack_damage <= 0.0 or _dead or points.is_empty():
		return
	_attack_cd = maxf(0.0, _attack_cd - delta)
	if _attack_cd > 0.0:
		return
	var my_head : Vector2 = to_global(points[0])
	var reach : float = attack_range + head_radius
	for n in get_tree().get_nodes_in_group(attack_group):
		if not is_instance_valid(n) or not (n is Node2D):
			continue
		if n == self or n.is_queued_for_deletion():
			continue
		if n.has_method("is_dead") and bool(n.call("is_dead")):
			continue
		var p : Vector2 = _nearest_body_point(n, my_head)
		var d : float = my_head.distance_to(p)
		if d > reach:
			continue
		_attack_cd = attack_cooldown
		_bite_fx = 1.0
		if n.has_method("take_damage"):
			n.call("take_damage", attack_damage, my_head)
		return

## 目标身上离咬点最近的一点：有骨链的逐节比，没有的就用节点原点。
func _nearest_body_point(n: Node2D, from: Vector2) -> Vector2:
	var best : Vector2 = n.global_position
	var best_d : float = from.distance_squared_to(best)
	var pts = n.get("points")
	if pts is PackedVector2Array:
		var arr : PackedVector2Array = pts
		var stride : int = maxi(1, int(ceil(float(arr.size()) / 24.0)))
		var i : int = 0
		while i < arr.size():
			var w : Vector2 = n.to_global(arr[i])
			var dd : float = from.distance_squared_to(w)
			if dd < best_d:
				best_d = dd
				best = w
			i += stride
	return best

# =============================== Movement ===============================
func _move_head(delta: float) -> void:
	var ease : float = clampf(turn_speed * delta, 0.0, 1.0)

	# 避蛇优先：蛇头进入恐惧范围就掉头跑。
	var fleeing : bool = _apply_fear(delta, ease)

	if not fleeing:
		match control_mode:
			0: # Wander：工蚁漫无目的地乱走，偶尔大角度掉头
				_throttle = 1.0
				heading += _rng.randf_range(-1.0, 1.0) * 1.2 * delta
				if _rng.randf() < 0.02:
					heading += _rng.randf_range(-1.4, 1.4)
			1:
				_throttle = 1.0
				var hp : Vector2 = to_global(points[0])
				var tgt : Vector2 = get_global_mouse_position()
				if tgt.distance_to(hp) > 3.0:
					heading = lerp_angle(heading, (tgt - hp).angle(), ease)
			2:
				_throttle = 1.0
				heading = lerp_angle(heading, external_direction, ease)
		# 聚群：没在逃命时，朝附近最近的同伴靠拢（社会性归队）。
		_apply_flock(ease)

	_speed_now = speed * _throttle
	if fleeing:
		_speed_now *= flee_speed_boost
	if metab:
		_speed_now *= float(metab.speed_mult())
	# 捕猎模式：蛇逼近时全场猎物减速。
	if Snake.hunt_mode:
		_speed_now *= Snake.HUNT_PREY_SLOW_MULT
	head_pos += Vector2.from_angle(heading) * _speed_now * delta
	if use_play_bounds or stay_in_viewport:
		_bounce_off_walls()
	points[0] = head_pos

## 蛇头进入恐惧范围就掉头远离，返回是否在逃跑。
func _apply_fear(delta: float, ease: float) -> bool:
	if fear_range <= 0.0:
		return false
	var snake : Node = get_tree().get_first_node_in_group("snake")
	if snake == null or not is_instance_valid(snake) or not (snake is Node2D):
		return false
	# 蛇静止藏住了：蚂蚁感觉不到它，照常走自己的路线。
	if snake.has_method("is_stealthed") and bool(snake.call("is_stealthed")):
		return false
	var my_head : Vector2 = to_global(points[0])
	var snake_head : Vector2 = snake.to_global(snake.points[0]) if snake.points.size() > 0 else snake.global_position
	var off : Vector2 = my_head - snake_head
	var d : float = off.length()
	if d > fear_range:
		return false
	var urgency : float = clampf(1.0 - d / fear_range, 0.0, 1.0)
	var away : float = off.angle()
	if d < 1.0:
		away = heading + PI
	heading = lerp_angle(heading, away, clampf(ease * (1.0 + urgency * 2.0), 0.0, 1.0))
	_throttle = 1.0
	return true

## 朝 flock_range 内最近的同伴靠拢。工蚁的社会性：落单了就归队。
## 场上有蚁后时优先归到蚁后身边，哪怕她比别人远一些。
func _apply_flock(ease: float) -> void:
	if flock_range <= 0.0:
		return
	var my_head : Vector2 = to_global(points[0])
	var nearest : Node = null
	var nearest_d : float = flock_range
	var queen : Node = null
	var queen_d : float = flock_range * 3.0
	for ant in get_tree().get_nodes_in_group("ant"):
		if ant == self or not is_instance_valid(ant) or not (ant is Node2D):
			continue
		if ant.has_method("is_dead") and bool(ant.call("is_dead")):
			continue
		var p = ant.get("points")
		if p == null or p.size() == 0:
			continue
		var ah : Vector2 = ant.to_global(p[0])
		var d : float = my_head.distance_to(ah)
		if bool(ant.get("is_queen")) and d < queen_d:
			queen_d = d
			queen = ant
		if d < nearest_d:
			nearest_d = d
			nearest = ant
	# 蚁后在场：朝她走，距离越近越不急（围着她转，不是撞上去）。
	if queen != null:
		var qp = queen.get("points")
		var qtarget : Vector2 = queen.to_global(qp[0])
		var toward_q : Vector2 = qtarget - my_head
		var ring : float = 26.0
		if toward_q.length() > ring:
			var pull : float = clampf(ease * flock_strength * 1.6, 0.0, 1.0)
			heading = lerp_angle(heading, toward_q.angle(), pull)
		else:
			heading = lerp_angle(heading, toward_q.angle() + PI * 0.5, ease * 0.8)
		return
	if nearest == null:
		return
	var p2 = nearest.get("points")
	var target : Vector2 = nearest.to_global(p2[0])
	var toward : Vector2 = target - my_head
	var closeness : float = clampf(1.0 - nearest_d / flock_range, 0.0, 1.0)
	heading = lerp_angle(heading, toward.angle(), clampf(ease * flock_strength * (0.4 + closeness), 0.0, 1.0))

func _bounce_off_walls() -> void:
	var wp : Vector2 = to_global(head_pos)
	if use_play_bounds and bounds_shape == 1:
		var rad : float = maxf(16.0, bounds_radius)
		var off : Vector2 = wp - bounds_center
		if off.length() > rad:
			var n : Vector2 = off.normalized()
			wp = bounds_center + n * rad
			var d : Vector2 = Vector2.from_angle(heading)
			d -= 2.0 * d.dot(n) * n
			heading = d.angle()
			head_pos = to_local(wp)
		return
	var rect : Rect2 = play_bounds if use_play_bounds else get_viewport_rect()
	var bounced : bool = false
	if wp.x < rect.position.x or wp.x > rect.end.x:
		heading = PI - heading
		wp.x = clampf(wp.x, rect.position.x, rect.end.x)
		bounced = true
	if wp.y < rect.position.y or wp.y > rect.end.y:
		heading = -heading
		wp.y = clampf(wp.y, rect.position.y, rect.end.y)
		bounced = true
	if bounced:
		head_pos = to_local(wp)

func _follow_body() -> void:
	for i in range(1, points.size()):
		var to_prev : Vector2 = points[i] - points[i - 1]
		var dist : float = to_prev.length()
		if dist < 0.0001:
			to_prev = Vector2.from_angle(heading)
			dist = 1.0
		points[i] = points[i - 1] + (to_prev / dist) * segment_spacing

func _reset_body() -> void:
	points.resize(BODY_NODES)
	head_pos = Vector2.ZERO
	heading = 0.0
	for i in BODY_NODES:
		points[i] = -Vector2.from_angle(heading) * segment_spacing * float(i)

func reset_body_heading(dir: float) -> void:
	_reset_body()
	heading = dir
	for i in points.size():
		points[i] = -Vector2.from_angle(dir) * segment_spacing * float(i)
	_rebuild_legs()

# =============================== Light ===============================
func _lit(p: Vector2) -> float:
	return Snake.light_at(to_global(p))

const WHITE_LIT_MIN : float = 0.80

func _wcol(p: Vector2, a: float) -> Color:
	var lit : float = _lit(p)
	var gate : float = smoothstep(WHITE_LIT_MIN, WHITE_LIT_MIN + 0.10, lit)
	return Color(1.0, 1.0, 1.0, a * gate)

# =============================== Shadow ===============================
var _occluder : LightOccluder2D = null

func _ensure_occluder() -> void:
	if _occluder != null:
		return
	_occluder = LightOccluder2D.new()
	var poly := OccluderPolygon2D.new()
	poly.closed = true
	_occluder.occluder = poly
	add_child(_occluder)

# =============================== Legs ===============================
## 六足，全挂胸部（index 1）。复用蜈蚣那套 CLegSystem：脚尖钉地 +
## FABRIK 反解 + 相邻腿反相。蚂蚁只有 3 对，所以 3 个 LegPair 就够了，
## 相邻反相会自然走成"三脚着地、三脚抬起"的六足步态。
class LegPair:
	const IDLE : int = 0
	const LEFT : int = 1
	const RIGHT : int = 2

	var body_index : int = 1
	var hip_l : Vector2 = Vector2.ZERO
	var hip_r : Vector2 = Vector2.ZERO
	var goal_l : Vector2 = Vector2.ZERO
	var goal_r : Vector2 = Vector2.ZERO
	var foot_l : Vector2 = Vector2.ZERO
	var foot_r : Vector2 = Vector2.ZERO
	var from_l : Vector2 = Vector2.ZERO
	var from_r : Vector2 = Vector2.ZERO
	var chain_l : Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var chain_r : Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var seg : float = 1.0
	var state : int = IDLE
	var move_lerp : float = 0.0

	func setup(h_l: Vector2, h_r: Vector2, out_l: Vector2, out_r: Vector2,
			tg: Vector2, s: float) -> void:
		hip_l = h_l
		hip_r = h_r
		seg = s
		var base_l : Vector2 = h_l - tg * (s * 2.6)
		var base_r : Vector2 = h_r - tg * (s * 2.6)
		for i in 4:
			chain_l[i] = base_l + out_l * (seg * float(i))
			chain_r[i] = base_r + out_r * (seg * float(i))
		goal_l = h_l + out_l * (seg * 3.0)
		goal_r = h_r + out_r * (seg * 3.0)
		foot_l = goal_l
		foot_r = goal_r
		from_l = goal_l
		from_r = goal_r

	func _fabrik(left: bool, hip: Vector2, foot: Vector2) -> void:
		var ch : Array = chain_l if left else chain_r
		var total : float = seg * 3.0
		var d : float = hip.distance_to(foot)
		if d >= total:
			var n : Vector2 = (foot - hip) / maxf(d, 0.0001)
			for i in 4:
				ch[i] = hip + n * (seg * float(i))
			return
		var loop : int = 0
		var dif : float = 1000000.0
		while dif > 0.001 and loop < 32:
			ch[3] = foot
			for i in range(2, -1, -1):
				var a : Vector2 = ch[i]
				var b : Vector2 = ch[i + 1]
				var dd : float = a.distance_to(b)
				if dd < 0.0001:
					break
				ch[i] = b + (a - b) * (seg / dd)
			ch[0] = hip
			for i in range(1, 4):
				var a2 : Vector2 = ch[i]
				var b2 : Vector2 = ch[i - 1]
				var dd2 : float = a2.distance_to(b2)
				if dd2 < 0.0001:
					break
				ch[i] = b2 + (a2 - b2) * (seg / dd2)
			dif = (ch[3] as Vector2).distance_to(foot)
			loop += 1

	func update(delta: float, hl: Vector2, hr: Vector2,
			gl: Vector2, gr: Vector2, prev: LegPair, trigger: float,
			spd: float, lift: float) -> void:
		hip_l = hl
		hip_r = hr
		goal_l = gl
		goal_r = gr
		if state == IDLE:
			_fabrik(true, hip_l, foot_l)
			_fabrik(false, hip_r, foot_r)
			var dl : float = foot_l.distance_to(goal_l)
			var dr : float = foot_r.distance_to(goal_r)
			if dl >= dr:
				if dl > trigger:
					state = LEFT
			else:
				if dr > trigger:
					state = RIGHT
			if state != IDLE and prev != null:
				if prev.state == LEFT:
					state = RIGHT
				elif prev.state == RIGHT:
					state = LEFT
			if state == LEFT:
				from_l = foot_l
			elif state == RIGHT:
				from_r = foot_r
			return
		var k : float = minf(move_lerp, 1.0)
		var arc : float = lift * sin(k * PI)
		if state == LEFT:
			foot_l = from_l.lerp(goal_l, k) + (hip_l - from_l).normalized() * arc
		else:
			foot_r = from_r.lerp(goal_r, k) + (hip_r - from_r).normalized() * arc
		_fabrik(true, hip_l, foot_l)
		_fabrik(false, hip_r, foot_r)
		_advance(delta, spd)

	func _advance(delta: float, spd: float) -> void:
		move_lerp += spd * delta
		if move_lerp >= 1.0:
			state = IDLE
			move_lerp = 0.0
			foot_l = goal_l
			foot_r = goal_r
			_fabrik(true, hip_l, foot_l)
			_fabrik(false, hip_r, foot_r)

var _legs : Array = []

func _rebuild_legs() -> void:
	_legs.clear()
	var s : float = leg_size * segment_spacing
	var fwd : float = leg_hip_forward * segment_spacing
	# 六足全挂在胸部（index 1）。三对腿分前中后，沿胸部前后错开。
	var offsets : Array = [-0.5, 0.0, 0.5]
	for off in offsets:
		var lp := LegPair.new()
		lp.body_index = 1
		var tg : Vector2 = _tangent_at(1)
		var nrm : Vector2 = tg.orthogonal()
		var half : float = thorax_radius * 0.9
		var c : Vector2 = points[1] + tg * (off * segment_spacing)
		lp.setup(c - nrm * half + tg * fwd, c + nrm * half + tg * fwd,
			-nrm, nrm, tg, s)
		_legs.append(lp)

func _update_legs(delta: float) -> void:
	if _legs.is_empty():
		_rebuild_legs()
	var s : float = leg_size * segment_spacing
	var fwd : float = leg_hip_forward * segment_spacing
	var reach : float = s * leg_reach
	var trigger : float = step_trigger * s * 3.0
	var lift : float = leg_lift * segment_spacing
	var offsets : Array = [-0.5, 0.0, 0.5]
	var prev : LegPair = null
	for idx in _legs.size():
		var lp : LegPair = _legs[idx]
		var tg : Vector2 = _tangent_at(1)
		var nrm : Vector2 = tg.orthogonal()
		var half : float = thorax_radius * 0.9
		var c : Vector2 = points[1] + tg * (offsets[idx] * segment_spacing)
		var out : float = half + reach
		lp.update(delta, c - nrm * half + tg * fwd, c + nrm * half + tg * fwd,
			c - nrm * out, c + nrm * out,
			prev, trigger, step_speed, lift)
		prev = lp

# =============================== Antennae ===============================
## 肘状触角：柄节（scapus）短、朝前外方翘起，鞭节（flagellum）在肘部
## 折一个角度继续往前伸。用弹簧链，转弯时会甩出弧线。
class SpringChain:
	var pos := PackedVector2Array()
	var prev := PackedVector2Array()
	var local := PackedVector2Array()
	var lens := PackedFloat32Array()
	var stiffness : float = 0.5
	var damping : float = 0.35
	var ready : bool = false

	func setup(pts: PackedVector2Array, stiff: float, damp: float) -> void:
		local = pts
		var n : int = pts.size()
		pos.resize(n)
		prev.resize(n)
		lens.resize(maxi(1, n - 1))
		for i in range(1, n):
			lens[i - 1] = pts[i].distance_to(pts[i - 1])
		stiffness = stiff
		damping = damp
		ready = false

	func update(head: Vector2, dir: Vector2) -> void:
		var n : int = pos.size()
		if n < 2:
			return
		var side : Vector2 = dir.orthogonal()
		if not ready:
			for i in n:
				var t0 : Vector2 = head + dir * local[i].x + side * local[i].y
				pos[i] = t0
				prev[i] = t0
			ready = true
			return
		pos[0] = head + dir * local[0].x + side * local[0].y
		prev[0] = pos[0]
		for i in range(1, n):
			var target : Vector2 = head + dir * local[i].x + side * local[i].y
			var vel : Vector2 = pos[i] - prev[i]
			var np : Vector2 = pos[i] + vel * damping + (target - pos[i]) * stiffness
			var d : Vector2 = np - pos[i - 1]
			if d.length_squared() < 0.000001:
				d = dir
			np = pos[i - 1] + d.normalized() * lens[i - 1]
			prev[i] = pos[i]
			pos[i] = np

var _antennae : Array = []
const ANTENNA_NODES : int = 5

func _rebuild_antennae() -> void:
	_antennae.clear()
	var unit : float = segment_spacing / 4.0
	var scapus : float = 6.0 * unit * antenna_scale   # 柄节，短
	var flag : float = 11.0 * unit * antenna_scale    # 鞭节，长
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var pts := PackedVector2Array()
		var p : Vector2 = Vector2(head_radius * 0.2, sf * head_radius * 0.45)
		pts.append(p)
		# 柄节：从头部向前外方翘起
		var ang1 : float = deg_to_rad(40.0)
		p += Vector2(cos(ang1), sf * sin(ang1)) * scapus
		pts.append(p)
		# 鞭节：在肘部折角，几乎转回正前方
		var ang2 : float = deg_to_rad(8.0)
		for i in range(2, ANTENNA_NODES):
			p += Vector2(cos(ang2), sf * sin(ang2)) * (flag / float(ANTENNA_NODES - 2))
			pts.append(p)
		var sc := SpringChain.new()
		sc.setup(pts, antenna_stiffness, antenna_damping)
		_antennae.append(sc)

func _update_antennae() -> void:
	if _antennae.is_empty():
		_rebuild_antennae()
	var dir : Vector2 = Vector2.from_angle(heading)
	for sc in _antennae:
		sc.update(points[0], dir)

# =============================== Drawing ===============================
func _draw() -> void:
	if points.size() < BODY_NODES:
		return
	_build_heat()
	_ensure_occluder()
	_occluder.occluder.polygon = heat_outline
	_draw_wings()
	_draw_legs()
	_draw_antennae()
	_draw_body()
	_draw_jaws()

## 身体：头（圆）/ 胸（窄）/ 腹（椭圆），轮廓 + 一条中轴，极简。
## 全部走 _wcol 光照门槛：照亮区才显白轮廓，暗区只剩红线感应。
func _draw_body() -> void:
	# 头部：圆，在 points[0]
	var h : Vector2 = _head_draw_pos()
	_draw_ellipse_outline(h, head_radius, head_radius, _tangent_at(0), _wcol(h, ghost_line.a).a)

	# 胸部：窄椭圆，在 points[1]
	var c : Vector2 = points[1]
	_draw_ellipse_outline(c, thorax_radius * 1.3, thorax_radius, _tangent_at(1), _wcol(c, ghost_line.a).a)

	# 腹部：大椭圆，在 points[2]
	var a : Vector2 = points[2]
	_draw_ellipse_outline(a, abdomen_length * 0.5, abdomen_radius, _tangent_at(2), _wcol(a, ghost_line.a).a)

	# 细腰：胸腹之间收束的两条内线，强调"工蚁细腰"的轮廓。
	var nrm : Vector2 = _tangent_at(1).orthogonal()
	var mid : Vector2 = (c + a) * 0.5
	var pinched : float = thorax_radius * waist_pinch
	draw_line(c + nrm * pinched, mid + nrm * pinched * 0.8, _wcol(mid, 0.6), ghost_line_width * 0.7, false)
	draw_line(c - nrm * pinched, mid - nrm * pinched * 0.8, _wcol(mid, 0.6), ghost_line_width * 0.7, false)

## 画头用的位置：咬中那一瞬间往前顶一下（纯视觉，不动物理骨点）。
func _head_draw_pos() -> Vector2:
	if _bite_fx <= 0.0:
		return points[0]
	return points[0] + _tangent_at(0) * (_bite_fx * segment_spacing * 0.55)

## 大颚：从头部前侧伸出两条朝内弯的夹子。兵蚁靠这一对认出身份。
func _draw_jaws() -> void:
	if jaw_scale <= 0.01 or points.is_empty():
		return
	var h : Vector2 = _head_draw_pos()
	var tg : Vector2 = _tangent_at(0)
	var nrm : Vector2 = tg.orthogonal()
	var reach : float = head_radius * 2.1 * jaw_scale
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var root : Vector2 = h + tg * (head_radius * 0.5) + nrm * (head_radius * 0.62 * sf)
		var mid : Vector2 = root + tg * (reach * 0.62) + nrm * (head_radius * 0.42 * sf)
		var tip : Vector2 = mid + tg * (reach * 0.55) - nrm * (head_radius * 0.80 * sf)
		draw_line(root, mid, _wcol(mid, 0.88), ghost_line_width * 1.55, false)
		draw_line(mid, tip, _wcol(tip, 0.96), ghost_line_width * 1.25, false)
		draw_circle(mid, maxf(0.5, ghost_line_width * 0.62), _wcol(mid, 0.9))
		draw_circle(tip, maxf(0.5, ghost_line_width * 0.7), _wcol(tip, 1.0))

## 翅膀：两对细长薄片，从胸部朝后外侧张开，轻微扇动。
func _draw_wings() -> void:
	if wing_scale <= 0.01 or points.size() < 2:
		return
	var c : Vector2 = points[1]
	var tg : Vector2 = _tangent_at(1)
	var nrm : Vector2 = tg.orthogonal()
	var beat : float = sin(_wing_phase * 26.0) * wing_beat * 0.16 * wing_scale
	var len_main : float = segment_spacing * 3.8 * wing_scale
	var half_w : float = segment_spacing * 0.72 * wing_scale
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var base_ang : float = (-tg * 0.5 + nrm * (0.87 * sf)).normalized().angle()
		for k in 2:
			var shrink : float = 1.0 - 0.26 * float(k)
			var ang : float = base_ang + beat * sf + (0.18 * float(k)) * sf
			var dir : Vector2 = Vector2.from_angle(ang)
			var root : Vector2 = c + tg * (segment_spacing * 0.35 * float(k))
			var wc : Vector2 = root + dir * (len_main * 0.5 * shrink)
			_draw_ellipse_outline(wc, len_main * 0.5 * shrink, half_w * shrink, dir,
				_wcol(wc, 0.34 - 0.06 * float(k)).a)

## 画一个椭圆轮廓（沿切线方向摆正），只描边不填充。
func _draw_ellipse_outline(c: Vector2, hl: float, hw: float, tg: Vector2, a: float) -> void:
	var nrm : Vector2 = tg.orthogonal()
	var pts := PackedVector2Array()
	var steps : int = 20
	for k in steps + 1:
		var ang : float = TAU * float(k) / float(steps)
		pts.append(c + tg * (cos(ang) * hl) + nrm * (sin(ang) * hw))
	pts.append(pts[0])
	draw_polyline(pts, Color(1, 1, 1, a), ghost_line_width, false)

func _draw_legs() -> void:
	for lp in _legs:
		_stroke_leg(lp.chain_l)
		_stroke_leg(lp.chain_r)

func _stroke_leg(c: Array) -> void:
	if c.size() < 4:
		return
	var p0 : Vector2 = c[0]
	var p1 : Vector2 = c[1]
	var p2 : Vector2 = c[2]
	var p3 : Vector2 = c[3]
	draw_line(p0, p1, _wcol(p0, 0.62), ghost_line_width * 0.80, false)
	draw_line(p1, p2, _wcol(p2, 0.82), ghost_line_width * 0.95, false)
	draw_line(p2, p3, _wcol(p3, 0.78), ghost_line_width * 0.85, false)
	draw_circle(p1, maxf(0.45, ghost_line_width * 0.55), _wcol(p1, 0.90))
	draw_circle(p2, maxf(0.45, ghost_line_width * 0.52), _wcol(p2, 0.94))
	draw_circle(p3, maxf(0.50, ghost_line_width * 0.62), _wcol(p3, 0.98))

func _draw_antennae() -> void:
	for sc in _antennae:
		_stroke_antenna(sc.pos)

func _stroke_antenna(c: PackedVector2Array) -> void:
	if c.size() < 2:
		return
	var n : float = float(c.size() - 1)
	for i in range(1, c.size()):
		var p0 : Vector2 = c[i - 1]
		var p1 : Vector2 = c[i]
		draw_line(p0, p1, _wcol(p1, 0.5 + 0.4 * (float(i) / n)), ghost_line_width * 0.7, false)
		draw_circle(p1, maxf(0.4, ghost_line_width * 0.45), _wcol(p1, 0.6 + 0.3 * (float(i) / n)))

# =============================== Heat data ===============================
func _build_heat() -> void:
	# 几何中心：头/胸/腹三个骨节点的质心（本地坐标）。
	heat_center = (points[0] + points[1] + points[2]) / 3.0

	# 球形身体 = 三个椭圆（头/胸/腹），各自采样成闭合轮廓。
	heat_outline.clear()
	_append_ellipse_heat(points[0], head_radius, head_radius, _tangent_at(0))
	_append_ellipse_heat(points[1], thorax_radius * 1.3, thorax_radius, _tangent_at(1))
	_append_ellipse_heat(points[2], abdomen_length * 0.5, abdomen_radius, _tangent_at(2))

	heat_leg_chains.clear()
	heat_leg_slots = _legs.size() * 2
	for lp in _legs:
		heat_leg_chains.append_array(PackedVector2Array(lp.chain_l))
		heat_leg_chains.append_array(PackedVector2Array(lp.chain_r))

## 把一个椭圆采样进 heat_outline（闭合，20 段）。
func _append_ellipse_heat(c: Vector2, hl: float, hw: float, tg: Vector2) -> void:
	var nrm : Vector2 = tg.orthogonal()
	var steps : int = 20
	for k in steps:
		var ang : float = TAU * float(k) / float(steps)
		heat_outline.append(c + tg * (cos(ang) * hl) + nrm * (sin(ang) * hw))

func _half_width_at(i: int) -> float:
	match i:
		0: return head_radius
		1: return thorax_radius
		_: return abdomen_radius

func _tangent_at(i: int) -> Vector2:
	var a : int = clampi(i - 1, 0, points.size() - 1)
	var b : int = clampi(i + 1, 0, points.size() - 1)
	var v : Vector2 = points[a] - points[b]
	if v.length() < 0.0001:
		return Vector2.from_angle(heading)
	return v.normalized()
