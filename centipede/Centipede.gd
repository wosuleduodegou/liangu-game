@tool
extends Node2D

## 少棘蜈蚣（Scolopendra mutilans）的程序化角色。
##
## 没有任何帧动画资源，全部在 _draw() 里现画，而且只有白线、没有填充和贴图：
##   * 身体是一串 follow-the-leader 的骨节点，转弯时自然留下弯曲轨迹
##   * 每一节是一个沿切线摆正的圆角方块，节间留缝 —— 弯多少一眼就看得出来
##   * 20 对步足，脚尖一旦落地就钉在世界里，偏离理想落点才抬腿重踩
##   * 每对足用两段解析 IK 求膝点，所以膝弯是算出来的、永远清晰
##   * 一对多节触角 + 一对尾须，都是惯性弹簧链，转弯时会甩出弧线
##
## 尺寸基准沿用项目约定：1 米 = 500px。默认体长约 180px，也就是一条
## 30cm 上下的大个体，方便在小场地里看清足的动作。

# ------------------------------- Identity -------------------------------
@export_group("Identity")

## 显示名。之后做状态面板 / 图鉴可以直接读它。
@export var display_name : String = "Scolopendra mutilans"

# ------------------------------- Body shape -------------------------------
@export_group("Body Shape")

## 背板数量（含头板）。少棘蜈蚣是 21 节、20 对步足。
@export_range(6, 60, 1) var segment_count : int = 21

## 相邻骨节点的间距，也就是每节的长度。
@export_range(3.0, 40.0, 0.5, "suffix:px") var segment_spacing : float = 9.0

## 身体半宽（最宽处）。蜈蚣是扁的，这个值同时也决定背板的横向尺寸。
@export_range(2.0, 30.0, 0.25, "suffix:px") var body_radius : float = 5.0

## 头板相对身体再宽多少。少棘蜈蚣的头板比后面的背板略宽。
@export_range(0.2, 2.0, 0.01) var head_width_scale : float = 1.18

## 头板相对身体的长度倍率。头是一块略扁的圆板，不是方块。
@export_range(0.6, 2.0, 0.01) var head_length_scale : float = 1.10

## 相邻两节之间留多宽的缝，占节距的比例。
## 转弯时内侧的缝被压窄、外侧被撑开，身体的弯曲一眼就能看出来。
@export_range(0.0, 0.6, 0.01) var plate_gap : float = 0.08

## 圆角半径，占短边一半的比例。0.58 是"圆角方块"，1.0 就成椭圆了。
@export_range(0.1, 1.0, 0.01) var plate_round : float = 0.52

## 每一节边框线的相对亮度。1.0 和身体其它线一样亮。
@export_range(0.2, 1.5, 0.05) var plate_line_boost : float = 1.0

# ------------------------------- Ghost look -------------------------------
@export_group("Ghost Look")

## 外轮廓线。纯白线，整只虫就靠这一圈读出来。
@export var ghost_line : Color = Color(1.0, 1.0, 1.0, 0.94)

## 分节线 / 内部结构线，比轮廓暗一档。
@export var ghost_inner : Color = Color(1.0, 1.0, 1.0, 0.45)

## 轮廓线宽度。
@export_range(0.4, 5.0, 0.1, "suffix:px") var ghost_line_width : float = 1.15

# ------------------------------- Legs -------------------------------
@export_group("Legs")

## 单节腿长，相对节距的倍率。参考工程是 12/32 = 0.375，三段**等长**。
## 三条腿一样长，比例才对得上参考 —— 之前股 / 胫 / 跗 三段不等长是错的。
@export_range(0.1, 1.2, 0.01) var leg_size : float = 0.72

## 脚尖离体侧多远，相对"单节腿长"的倍率。参考是 2.3。
@export_range(0.6, 5.0, 0.05) var leg_reach : float = 1.9

## 髋点相对体节中心往前偏多少，相对节距。参考是 0.5。
## 这一项决定腿是"挂在前面、往后伸"的 —— 少了它腿会朝正侧面平伸，很呆。
@export_range(0.0, 1.2, 0.02) var leg_hip_forward : float = 0.38

## 脚尖偏离理想落点多少就抬腿重踩，相对"整条腿长"的比例。参考是 0.55。
@export_range(0.1, 1.0, 0.01) var step_trigger : float = 0.55

## 迈一步的插值速度（每秒进度）。14 大约 70ms 一步。
@export_range(2.0, 40.0, 0.5, "suffix:/s") var step_speed : float = 14.0

## 腿抬起时脚尖朝髋收回多少（相对节长）。俯视看，收短就等于抬起来了。
@export_range(0.0, 1.0, 0.02) var leg_lift : float = 0.30

# ------------------------------- Appendages -------------------------------
@export_group("Appendages")

## 触角长度倍率。多棘蜈蚣的触角比少棘长得多。
@export_range(0.4, 2.5, 0.05) var antenna_scale : float = 1.0

## 尾须长度倍率。
@export_range(0.4, 2.5, 0.05) var cerci_scale : float = 1.0

## 末对曳步足的长度倍率。大个体这对足又粗又长。
@export_range(0.5, 3.0, 0.05) var ultimate_leg_scale : float = 1.0

# ------------------------------- Springs -------------------------------
@export_group("Springs")

## 触角/尾须的回弹刚度。越小越软、越飘。
@export_range(0.05, 1.0, 0.01) var antenna_stiffness : float = 0.52

## 惯性保留量。越大甩得越厉害，0 就是硬邦邦地跟着走。
@export_range(0.0, 0.95, 0.01) var antenna_damping : float = 0.35

# ------------------------------- Motion -------------------------------
@export_group("Motion")

@export_range(10.0, 600.0, 5.0, "suffix:px/s") var speed : float = 105.0
@export_range(0.5, 30.0, 0.1) var turn_speed : float = 4.5
## 松手后的减速有多快（每秒油门变化量）。
@export_range(1.0, 40.0, 0.5) var throttle_response : float = 9.0
@export_enum("Wander", "Follow Mouse", "Keyboard", "External") var control_mode : int = 2
## 外部控制时由外部脚本写入的朝向（弧度）。
@export var external_direction : float = 0.0

## 躲避蛇：蛇头进入这个距离（世界像素）就掉头逃跑。
@export_range(0.0, 800.0, 5.0, "suffix:px") var fear_range : float = 260.0
## 逃跑时比正常游走快多少倍。
@export_range(1.0, 3.0, 0.05) var flee_speed_boost : float = 1.6

# ------------------------------- Vitals -------------------------------
@export_group("Vitals")

## 生命值。被毒蛇咬到会掉，归零后抽搐一下消失。
@export_range(1.0, 2000.0, 1.0) var max_health : float = 58.0

## 毒抗：中毒每秒伤害乘以这个系数。大个体更耐毒，可以给小于 1 的值。
@export_range(0.0, 3.0, 0.05) var poison_resist : float = 1.0

## 死亡后多久淡出消失。
@export_range(0.2, 5.0, 0.1, "suffix:s") var death_fade : float = 1.5
## 饿死开关：>0 时饱食度归零就每秒扣这么多血，直到饿死。0 = 不会饿死。
@export_range(0.0, 50.0, 0.5, "suffix:/s") var starve_dps : float = 0.0
## 饿死/死亡后是否留下尸体（由关卡接管画蓝黑色尸体）。false 时照旧淡出消失。
@export var leave_corpse : bool = false

@export_group("Bounds")

## 不给场地时也把身体留在视口里。
@export var stay_in_viewport : bool = true
@export var use_play_bounds : bool = false
@export_enum("Rectangle", "Circle") var bounds_shape : int = 1
@export var bounds_center : Vector2 = Vector2(2500, 2500)
@export_range(64.0, 12000.0, 1.0, "suffix:px") var bounds_radius : float = 500.0
## 只在 bounds_shape 为 Rectangle 时使用。
@export var play_bounds : Rect2 = Rect2(0, 0, 1920, 1080)

@export_group("Editor Preview")

@export var show_editor_gizmos : bool = true
@export var gizmo_color : Color = Color(1.0, 0.62, 0.2, 0.85)

# ------------------------------- Runtime state -------------------------------
var points : PackedVector2Array = []
var head_pos : Vector2 = Vector2.ZERO
var heading : float = 0.0
var t : float = 0.0

var _throttle : float = 0.0
var _speed_now : float = 0.0
var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _editor_sig : String = ""
## 代谢组件（可选）。饿了会变虚弱，爬得慢。
var metab = null

## 热成像用：本帧每条腿的折线（本地坐标），每 3 个点一条腿：根 / 膝 / 尖。
## 由 _draw() 里顺手填好，保证和外层肉眼看得到的肢体严丝合缝。
var heat_leg_chains : PackedVector2Array = PackedVector2Array()
var heat_leg_slots : int = 0
## 热成像用：本帧整条虫的外轮廓（本地坐标，闭合）。画成"透明 + 白描边"。
var heat_outline : PackedVector2Array = PackedVector2Array()

# ------------------------------ Combat state ------------------------------
var health : float = 58.0
## 受击白闪强度 0..1，按时间衰减。
var _hurt : float = 0.0
var _poison_time : float = 0.0
var _poison_dps : float = 0.0
var _dead : bool = false
var _death_time : float = 0.0
## 死亡抽搐用的时间轴。
var _death_t : float = 0.0

func _ready() -> void:
	metab = get_node_or_null("Metabolism")
	health = max_health
	if Engine.is_editor_hint():
		return
	add_to_group("centipede")
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
	_update_springs()
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

## 被咬 / 中毒掉血。返回实际扣掉的血量。
## poison 是每秒毒伤，poison_time 是持续时间；毒抗会打折。
func take_damage(amount: float, from_global: Vector2 = Vector2.ZERO,
		poison: float = 0.0, poison_time: float = 0.0) -> float:
	if _dead:
		return 0.0
	var dealt : float = minf(health, maxf(0.0, amount))
	health = maxf(0.0, health - maxf(0.0, amount))
	_hurt = 1.0
	if poison > 0.0 and poison_time > 0.0:
		var pps : float = poison * poison_resist
		_poison_dps = maxf(_poison_dps, pps)
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
		toast.call("kill", "CENTIPEDE")

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

# =============================== Movement ===============================
func _move_head(delta: float) -> void:
	var ease : float = clampf(turn_speed * delta, 0.0, 1.0)

	# 避蛇优先：蛇头进入恐惧范围就掉头跑，压过其它一切控制。
	var fleeing : bool = _apply_fear(delta, ease)

	if not fleeing:
		match control_mode:
			0: # Wander
				_throttle = 1.0
				heading += _rng.randf_range(-1.0, 1.0) * 1.1 * delta
			1: # Follow mouse
				_throttle = 1.0
				var hp : Vector2 = to_global(points[0])
				var tgt : Vector2 = get_global_mouse_position()
				if tgt.distance_to(hp) > 3.0:
					heading = lerp_angle(heading, (tgt - hp).angle(), ease)
			2: # Keyboard
				var d : Vector2 = _read_keyboard()
				var moving : bool = d.length() > 0.1
				if moving:
					heading = lerp_angle(heading, d.angle(), ease)
				_throttle = move_toward(_throttle, 1.0 if moving else 0.0, throttle_response * delta)
			3: # External
				_throttle = 1.0
				heading = lerp_angle(heading, external_direction, ease)

	_speed_now = speed * _throttle
	if fleeing:
		_speed_now *= flee_speed_boost
	if metab:
		_speed_now *= float(metab.speed_mult())
	if control_mode == 2 and Input.is_key_pressed(KEY_SHIFT):
		_speed_now *= 1.75
	# 捕猎模式：蛇逼近时全场猎物减速，慢动作。
	if Snake.hunt_mode:
		_speed_now *= Snake.HUNT_PREY_SLOW_MULT

	head_pos += Vector2.from_angle(heading) * _speed_now * delta

	if control_mode != 3 and (use_play_bounds or stay_in_viewport):
		_bounce_off_walls()

	points[0] = head_pos

## 蛇头进入恐惧范围就掉头远离，返回是否在逃跑。
func _apply_fear(delta: float, ease: float) -> bool:
	if fear_range <= 0.0:
		return false
	# 玩家操控的这条（Keyboard 模式）不能被"怕蛇"劫持方向，
	# 否则一靠近蛇就自动掉头，操作感全没了。第二关蜈蚣主角靠这条。
	if control_mode == 2:
		return false
	var snake : Node = get_tree().get_first_node_in_group("snake")
	if snake == null or not is_instance_valid(snake) or not (snake is Node2D):
		return false
	# 蛇静止藏住了：蜈蚣感觉不到它，照常游走。
	if snake.has_method("is_stealthed") and bool(snake.call("is_stealthed")):
		return false
	var my_head : Vector2 = to_global(points[0])
	var snake_head : Vector2 = snake.to_global(snake.points[0]) if snake.points.size() > 0 else snake.global_position
	var off : Vector2 = my_head - snake_head
	var d : float = off.length()
	if d > fear_range:
		return false
	# 越近越急，掉头越果断。
	var urgency : float = clampf(1.0 - d / fear_range, 0.0, 1.0)
	var away : float = off.angle()
	if d < 1.0:
		away = heading + PI
	heading = lerp_angle(heading, away, clampf(ease * (1.0 + urgency * 2.0), 0.0, 1.0))
	_throttle = 1.0
	return true

## 圆形场地用镜面反射，矩形用逐轴翻转。和蛇那套保持一致。
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

## 像链条一样，每一节被前一节拉着走。这是身体弯曲的全部来源。
func _follow_body() -> void:
	for i in range(1, points.size()):
		var to_prev : Vector2 = points[i] - points[i - 1]
		var dist : float = to_prev.length()
		if dist < 0.0001:
			to_prev = Vector2.from_angle(heading)
			dist = 1.0
		points[i] = points[i - 1] + (to_prev / dist) * segment_spacing

func _read_keyboard() -> Vector2:
	# 只认 WASD，和蛇保持一致。
	var v : Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_key_pressed(KEY_W):
		v.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		v.y += 1.0
	return v.normalized()

## 沿当前朝向铺直，只在开局和编辑器预览里用。
func _reset_body() -> void:
	points.resize(segment_count)
	head_pos = Vector2.ZERO
	heading = 0.0
	for i in segment_count:
		points[i] = -Vector2.from_angle(heading) * segment_spacing * float(i)

## 按指定朝向重新铺直身体。关卡开局摆位时用。
func reset_body_heading(dir: float) -> void:
	_reset_body()
	heading = dir
	for i in points.size():
		points[i] = -Vector2.from_angle(dir) * segment_spacing * float(i)
	# 身体整条搬走了，钉在地上的脚尖全在旧位置，直接重铺一遍。
	_rebuild_legs()

# =============================== Light ===============================
## 白线是体表：黑暗里看不见，只在该受光的地方出现。
## 光源就是蛇头周围那圈视野（SnakeVision 每帧写进 Snake 的静态量）。
## 光圈外整只虫只剩 AimOverlay 画的骨骼红线。
func _lit(p: Vector2) -> float:
	return Snake.light_at(to_global(p))

## 白骨架的显形门槛：光照程度超过 white_threshold 才算"看得见"，
## 照不亮的区域整只虫只剩 AimOverlay 的红线感应。
const WHITE_LIT_MIN : float = 0.80

func _wcol(p: Vector2, a: float) -> Color:
	var lit : float = _lit(p)
	# 硬门槛 + 一点过渡带，跨过 80% 白线才亮起来。
	var gate : float = smoothstep(WHITE_LIT_MIN, WHITE_LIT_MIN + 0.10, lit)
	return Color(1.0, 1.0, 1.0, a * gate)

# =============================== Shadow ===============================
## 实物投影：一只 LightOccluder2D，多边形每帧跟 _build_heat 的外轮廓同步，
## 罐顶天光被虫身挡住，身后拖出一片软阴影（阴影参数在 Torch 上调）。
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
## 一对足。移植自参考项目 game_ProceduralAnimation 的 CLegSystem：
##
##   * 髋点钉在体侧，每帧跟着体节走
##   * 脚尖一旦落地就钉死在世界里（支撑相），身体往前走，腿自己就弯了
##   * 每帧量一次"脚尖离理想落点有多远"，超过阈值就抬腿重踩
##   * 抬腿时左右轮流：前一条腿正在迈同侧，这条就改迈另一侧
##   * 抬起来的脚用 lerp 追向理想落点，链用 FABRIK 反解关节
##
## 和"按正弦摆腿"的区别：脚是真的钉住的，所以身体转弯时会自然拖出弯腿、
## 直行时腿几乎不动。步态是算出来的，不是摆出来的。
##
## 这一版是**照抄**参考工程（CIKChain.pointTailTo + CLegSystem.update），
## 不再自己解三角形：
##   * 4 个节点、三段**等长**（参考里是 12/12/12），髋点钉在体侧靠前一点，
##     脚尖钉在地上；
##   * 每帧从**上一帧的姿态**继续迭代（32 次，容差 0.001），不是重新解一遍。
##     腿看起来软，就是因为姿态有记忆 —— 弯曲方向是连续演化的，
##     不会每帧被重算成一个全新的几何形状。
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
	## 这一步是从哪儿抬起来的。插值必须以它为起点，
	## 否则每帧都在改写 foot，lerp 会变成指数逼近，脚永远落不了地。
	var from_l : Vector2 = Vector2.ZERO
	var from_r : Vector2 = Vector2.ZERO
	## 每条腿四个节点：髋 / 膝 / 踝 / 尖，三段等长。
	##
	## 这里必须用 Array 而不是 PackedVector2Array：Packed 是值类型，
	## 传进函数时会被复制，FABRIK 迭代就改不到原数组上了。
	var chain_l : Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	var chain_r : Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
	## 单节长度。整条腿 = seg * 3。
	var seg : float = 1.0
	var state : int = IDLE
	var move_lerp : float = 0.0

	func setup(h_l: Vector2, h_r: Vector2, out_l: Vector2, out_r: Vector2,
			tg: Vector2, s: float) -> void:
		hip_l = h_l
		hip_r = h_r
		seg = s
		# 初始姿态：整条腿在髋点**后方**、水平朝外排开。
		#
		# 这个"错位"是照抄参考工程的：它的链初始 y 恒为 -16，而髋点 y 是 +16，
		# 相差整整一个节距。FABRIK 要把这条"横在后方的直线"拉到"髋在前、
		# 脚在外"的目标上，中间就必然扭出一个弯 —— 腿的折角就是这么来的。
		# 如果初始链直接从髋点出发，收敛结果会几乎是直线（之前就是这个问题）。
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

	## FABRIK：头端钉髋、尾端钉脚，中间节点在两者之间滑，直到每段长度对上。
	## 完全照抄参考工程：32 次迭代、容差 0.001、先收尾再收头。
	## 关键在"从上一帧的姿态继续迭代"—— 链本身就是一个持续演化的状态。
	func _fabrik(left: bool, hip: Vector2, foot: Vector2) -> void:
		var ch : Array = chain_l if left else chain_r
		var total : float = seg * 3.0
		var d : float = hip.distance_to(foot)
		if d >= total:
			# 够不着：整条腿拉直，只指向目标。
			var n : Vector2 = (foot - hip) / maxf(d, 0.0001)
			for i in 4:
				ch[i] = hip + n * (seg * float(i))
			return
		var loop : int = 0
		var dif : float = 1000000.0
		while dif > 0.001 and loop < 32:
			# 尾 → 头：先把脚尖推到目标上
			ch[3] = foot
			for i in range(2, -1, -1):
				var a : Vector2 = ch[i]
				var b : Vector2 = ch[i + 1]
				var dd : float = a.distance_to(b)
				if dd < 0.0001:
					break
				ch[i] = b + (a - b) * (seg / dd)
			# 头 → 尾：再把髋推回原处
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
			# 被拉得更长的那一侧先抬。
			if dl >= dr:
				if dl > trigger:
					state = LEFT
			else:
				if dr > trigger:
					state = RIGHT
			# 相邻腿反相：前一条正在迈这条刚选中的同侧，就改迈另一侧。
			# 这一句就是"波"的来源，没有它整排腿会一起蹦。
			if state != IDLE and prev != null:
				if prev.state == LEFT:
					state = RIGHT
				elif prev.state == RIGHT:
					state = LEFT
			# 记下起抬点：插值必须从固定的起点算，否则 lerp 会退化成指数逼近。
			if state == LEFT:
				from_l = foot_l
			elif state == RIGHT:
				from_r = foot_r
			return

		var k : float = minf(move_lerp, 1.0)
		# 抬起来的那只脚：一边追新落点，一边朝髋收一点，俯视下就是抬起来了。
		var arc : float = lift * sin(k * PI)
		if state == LEFT:
			foot_l = from_l.lerp(goal_l, k) + (hip_l - from_l).normalized() * arc
			_fabrik(true, hip_l, foot_l)
			_fabrik(false, hip_r, foot_r)
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
			# 落地：脚钉在刚踩到的地方，直到下次被拉得太远。
			foot_l = goal_l
			foot_r = goal_r
			_fabrik(true, hip_l, foot_l)
			_fabrik(false, hip_r, foot_r)

var _legs : Array = []

# =============================== Springs ===============================
## 惯性链，移植自参考项目的 CSpringChain。用在触角和尾须上。
##
## 每一节只做三件事：
##   1. 惯性：保持上一帧的速度继续往前冲（damping）
##   2. 弹性：被往"沿父节点方向、定长"的理想位置拽（stiffness）
##   3. 长度约束：和父节点始终保持固定距离
##
## 不直接算角度，所以整条链永远是被"拖着"走的：头一转，末端过几帧才跟上，
## 中间自然甩出一条弧。这就是触角那种软塌塌的感觉，用正弦摆动是做不出来的。
class SpringChain:
	var pos := PackedVector2Array()
	var prev := PackedVector2Array()
	var local := PackedVector2Array()
	var lens := PackedFloat32Array()
	var stiffness : float = 0.5
	var damping : float = 0.35
	var ready : bool = false

	## pts 是"锚点局部坐标"：x 沿身体前方，y 沿体侧。它同时充当
	## "理想姿态"—— 每个节点每帧都会被拉回这里，所以触角不会像
	## 一根被忽略的绳子那样永久拖在身后。
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

	## 每帧三步：
	##   1. 算出每个节点在"头部坐标系"里的理想位置（随头一起转）
	##   2. 惯性：沿用上一帧的速度，所以头一转，末端会晚几帧才跟上
	##   3. 弹性 + 长度约束：拉回理想位置，并保证每一节定长
	##
	## 之前的版本只做了"保持上一帧方向"，没有回位项 —— 虫子一直往前爬，
	## 触角就会被永久甩到身后，再也回不到身前。必须有个目标点把它拽回来。
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

var _antennae : Array = []   # 头前两根，各一条 SpringChain
var _cerci : Array = []      # 尾端两根

## 触角 9 节、尾须 8 节。参考工程里是 7 节，但它那对触角短得像眉毛；
## 真实蜈蚣的触角是体长的三分之一到一半，必须拉长才像。
const ANTENNA_NODES : int = 9
const CERCI_NODES : int = 8

func _rebuild_springs() -> void:
	_antennae.clear()
	_cerci.clear()
	var hw : float = body_radius * head_width_scale
	var unit : float = segment_spacing / 9.0
	var aseg : float = 11.0 * unit * antenna_scale
	var cseg : float = 13.0 * unit * cerci_scale

	# 触角：从头部两侧向前外方张出去，每节再收回一点点，
	# 整条因此是一道向前张开的弧，不是两根直棍。
	# 本地坐标 x = 身体前方，y = 身体右侧。
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var pts := PackedVector2Array()
		var p : Vector2 = Vector2(-hw * 0.18, sf * hw * 0.55)
		pts.append(p)
		var ang : float = deg_to_rad(58.0)
		for i in range(1, ANTENNA_NODES):
			p += Vector2(cos(ang), sf * sin(ang)) * aseg
			pts.append(p)
			ang = maxf(deg_to_rad(24.0), ang - deg_to_rad(3.5))
		var sc := SpringChain.new()
		sc.setup(pts, antenna_stiffness, antenna_damping)
		_antennae.append(sc)

	# 尾须：从尾端向后外方拖出去，同样分节、同样会被甩弯。
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var pts := PackedVector2Array()
		var p : Vector2 = Vector2(-segment_spacing * 0.3, sf * hw * 0.42)
		pts.append(p)
		var ang : float = deg_to_rad(148.0)
		for i in range(1, CERCI_NODES):
			p += Vector2(cos(ang), sf * sin(ang)) * cseg
			pts.append(p)
			ang = maxf(deg_to_rad(120.0), ang - deg_to_rad(4.0))
		var sc := SpringChain.new()
		sc.setup(pts, antenna_stiffness, antenna_damping)
		_cerci.append(sc)

func _update_springs() -> void:
	if _antennae.is_empty():
		_rebuild_springs()
	var dir : Vector2 = Vector2.from_angle(heading)
	for sc in _antennae:
		sc.update(points[0], dir)
	# 尾须挂在最后一节的位置上，朝向是身体后方向
	var tail_dir : Vector2 = _tangent_at(points.size() - 1)
	for sc in _cerci:
		sc.update(points[points.size() - 1], tail_dir)


## 按当前几何重建所有腿。身体瞬移（reset）或节数变了才需要调。
func _rebuild_legs() -> void:
	_legs.clear()
	var s : float = leg_size * segment_spacing
	var fwd : float = leg_hip_forward * segment_spacing
	var n : int = maxi(0, segment_count - 2)
	for i in range(1, n + 1):
		var lp := LegPair.new()
		lp.body_index = i
		var tg : Vector2 = _tangent_at(i)
		var nrm : Vector2 = tg.orthogonal()
		var half : float = _width_at(i) * 0.92
		var c : Vector2 = points[i]
		lp.setup(c - nrm * half + tg * fwd, c + nrm * half + tg * fwd,
			-nrm, nrm, tg, s)
		_legs.append(lp)

func _update_legs(delta: float) -> void:
	if _legs.size() != maxi(0, segment_count - 2):
		_rebuild_legs()
	var s : float = leg_size * segment_spacing
	var fwd : float = leg_hip_forward * segment_spacing
	var reach : float = s * leg_reach
	var trigger : float = step_trigger * s * 3.0
	var lift : float = leg_lift * segment_spacing
	var prev : LegPair = null
	for lp in _legs:
		var i : int = lp.body_index
		if i >= points.size():
			break
		var c : Vector2 = points[i]
		var tg : Vector2 = _tangent_at(i)
		var nrm : Vector2 = tg.orthogonal()
		var half : float = _width_at(i) * 0.92
		# 理想落点：体侧外侧 reach 处，前后不偏 —— 和参考工程的 point2 一致。
		# 髋点则往前偏 fwd，于是髋在前、脚在后侧，腿自然朝后伸。
		var out : float = half + reach
		lp.update(delta, c - nrm * half + tg * fwd, c + nrm * half + tg * fwd,
			c - nrm * out, c + nrm * out,
			prev, trigger, step_speed, lift)
		prev = lp

# =============================== Drawing ===============================
## 纯线稿。整只虫只有白线，没有填充、没有贴图：
##   头板是一块圆板，身体是等宽的圆角方块，节间留缝；
##   腿是"髋-膝-踝-尖"的折线，三段：股节 / 胫节 / 跗节；
##   触角/尾须是分节折线，每个节点一个小圆点。
func _draw() -> void:
	if points.size() < 2:
		return
	_build_heat()
	# 遮挡多边形跟热轮廓同源：身体挡光，罐顶天光在身后拖出影子。
	_ensure_occluder()
	_occluder.occluder.polygon = heat_outline
	_draw_legs()
	_draw_springs()
	_draw_plates()

## 每个角的采样点数。3 段已经圆得很干净了，再多就是浪费。
const BOX_CORNER_STEPS : int = 3

## 身体分节。每节一个沿切线摆正的圆角方块。
##
## 为什么留缝而不是叠瓦：直线爬的时候缝宽是匀的，一转弯内侧的缝被压窄、
## 外侧被撑开，身体弯了多少一眼就读出来了 —— 不用额外画脊线。
func _draw_plates() -> void:
	var half_len : float = segment_spacing * (1.0 - plate_gap) * 0.5
	for i in points.size():
		var c : Vector2 = points[i]
		# 白门槛：照亮区（>80%）才画甲板白线，暗区交给红线感应。
		var lit : float = _lit(c)
		if lit <= WHITE_LIT_MIN:
			continue
		var tg : Vector2 = _tangent_at(i)
		var nrm : Vector2 = tg.orthogonal()
		var hl : float = half_len
		var hw : float = _width_at(i) * 1.04
		var rr : float = minf(hl, hw) * plate_round
		if i == 0:
			# 头板：一块略扁的圆板，比后面的背板大一圈。
			# 圆角拉到接近 1 就成椭圆了，不用另外写一套采样。
			hw = _width_at(0) * 1.02
			hl = hw * 0.92 * head_length_scale
			rr = minf(hl, hw) * 0.98
		var poly := _round_box(c, tg, nrm, hl, hw, rr)
		poly.append(poly[0])
		draw_polyline(poly, Color(1, 1, 1, ghost_line.a * lit * plate_line_boost),
			ghost_line_width, false)

## 一个圆角方块：四个角各用一段圆弧代替尖角，全部换算回本地坐标。
func _round_box(c: Vector2, tg: Vector2, nrm: Vector2, hl: float, hw: float,
		r: float) -> PackedVector2Array:
	var rr : float = clampf(r, 0.0, minf(hl, hw) * 0.999)
	var corners : Array = [
		Vector2(hl - rr, hw - rr), Vector2(-hl + rr, hw - rr),
		Vector2(-hl + rr, -hw + rr), Vector2(hl - rr, -hw + rr),
	]
	var a0 : Array = [0.0, PI * 0.5, PI, PI * 1.5]
	var pts := PackedVector2Array()
	pts.resize(BOX_CORNER_STEPS * 4)
	var k : int = 0
	for q in 4:
		var cc : Vector2 = corners[q]
		for s in BOX_CORNER_STEPS:
			var a : float = float(a0[q]) + PI * 0.5 * float(s) / float(BOX_CORNER_STEPS)
			var lp : Vector2 = cc + Vector2(cos(a), sin(a)) * rr
			pts[k] = c + tg * lp.x + nrm * lp.y
			k += 1
	return pts

func _draw_springs() -> void:
	for sc in _antennae:
		_stroke_spring(sc.pos)
	for sc in _cerci:
		_stroke_spring(sc.pos)

func _stroke_spring(c: PackedVector2Array) -> void:
	if c.size() < 2:
		return
	var n : float = float(c.size() - 1)
	var cols := PackedColorArray()
	cols.resize(c.size())
	for i in c.size():
		cols[i] = _wcol(c[i], 0.42 + 0.55 * (float(i) / n))
	draw_polyline_colors(c, cols, ghost_line_width * 0.85, false)
	# 每一节末端一个小圆点：分节感全靠这些点撑起来，不画就只是一根线。
	for i in range(1, c.size()):
		draw_circle(c[i], maxf(0.5, ghost_line_width * 0.60), _wcol(c[i], 0.42 + 0.55 * (float(i) / n)))

func _draw_legs() -> void:
	for lp in _legs:
		_stroke_leg(lp.chain_l)
		_stroke_leg(lp.chain_r)

## 一条腿 = 三个节点连成的三段折线，每个节点一个小圆点。
## 参考工程就是 DrawLine 逐段 + DrawPoint 逐点，这里照做。
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

# =============================== Heat data ===============================
## 给 AimOverlay 的热成像用的原始数据，每帧跟着绘制一起更新，
## 保证红线永远和真正画出来的肢体重合。
func _build_heat() -> void:
	var n : int = points.size()
	heat_outline.clear()
	for i in n:
		var c : Vector2 = points[i]
		var nrm : Vector2 = _tangent_at(i).orthogonal()
		heat_outline.append(c - nrm * _width_at(i) * 0.92)
	for i in range(n - 1, -1, -1):
		var c2 : Vector2 = points[i]
		var nrm2 : Vector2 = _tangent_at(i).orthogonal()
		heat_outline.append(c2 + nrm2 * _width_at(i) * 0.92)

	heat_leg_chains.clear()
	heat_leg_slots = _legs.size() * 2
	for lp in _legs:
		heat_leg_chains.append_array(PackedVector2Array(lp.chain_l))
		heat_leg_chains.append_array(PackedVector2Array(lp.chain_r))

# =============================== Helpers ===============================
## 第 i 节的前进方向。头尾各用单侧差分。
func _tangent_at(i: int) -> Vector2:
	var a : int = clampi(i - 1, 0, points.size() - 1)
	var b : int = clampi(i + 1, 0, points.size() - 1)
	var v : Vector2 = points[a] - points[b]
	if v.length() < 0.0001:
		return Vector2.from_angle(heading)
	return v.normalized()

## 第 i 节的半宽。整条身体等宽 —— 头板和尾板一样大，不收成锥子。
## 唯头板略宽一点（head_width_scale），因为真实的头板本来就更宽。
func _width_at(i: int) -> float:
	var w : float = body_radius
	if i == 0:
		w *= head_width_scale
	return w

