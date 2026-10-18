@tool
extends Node2D

## 中华蟾蜍（Bufo gargarizans）的程序化角色，极简白线稿。
##
## 和蛇 / 蜈蚣 / 蚂蚁一样，全部在 _draw() 里现画，只有白线，没有填充和贴图。
## 蟾蜍的辨识度不靠细节，靠这四样：
##   * 蹲坐的矮胖轮廓——前窄后宽，趴在地上像块石头
##   * 头顶两只高突的大眼（俯视是两个圆）
##   * 眼后的耳后腺（parotoid gland）——两个长椭圆隆起，蟾蜍独有的标志
##   * 背部疣粒——程序化撒的固定小凸起，位置用固定种子，每次都一样
##
## 动作只有一种：停、蹲、跳、落、再停。蟾蜍不走路，它跳。
## 跳跃时后腿从折叠的 Z 形一下蹬直，落地压扁一下再摊回蹲姿；
## 停在原地时靠呼吸微微起伏，偶尔眨一下眼。
##
## 尺寸基准沿用项目约定：1 米 = 500px。默认体长 60px，
## 也就是一只 12cm 上下的大蟾蜍，比蚂蚁大一号、比蜈蚣小一号。

# ------------------------------- Identity -------------------------------
@export_group("Identity")

@export var display_name : String = "Bufo gargarizans"

# ------------------------------- Body shape -------------------------------
@export_group("Body Shape")

## 体长（吻端到尾端）。
@export_range(20.0, 200.0, 1.0, "suffix:px") var body_length : float = 60.0

## 体宽（最宽处，在后半身）。蹲坐的蟾蜍比站着宽。
@export_range(14.0, 160.0, 1.0, "suffix:px") var body_width : float = 46.0

## 轮廓采样段数。越多越圆滑。
@export_range(16, 96, 2) var body_steps : int = 48

# ------------------------------- Head -------------------------------
@export_group("Head")

## 眼睛半径。蟾蜍的眼又大又凸，是整只身上最醒目的两个圆。
@export_range(1.0, 16.0, 0.25, "suffix:px") var eye_radius : float = 5.4

## 眼睛在体长方向的位置（0.5 = 正中，1 = 吻端）。
@export_range(0.50, 0.95, 0.01) var eye_offset : float = 0.86

## 眼睛横向张开的程度（相对该处半宽，1.0 = 正好贴在轮廓上）。
@export_range(0.2, 1.2, 0.01) var eye_spread : float = 0.82

## 口裂宽度（横贯吻端的弧，相对该处半宽）。
@export_range(0.3, 1.0, 0.01) var mouth_width : float = 0.96

## 耳后腺（眼后的长椭圆隆起）长度，相对体长。
@export_range(0.0, 0.35, 0.005) var parotoid_length : float = 0.115

## 耳后腺厚度，相对体长。
@export_range(0.0, 0.12, 0.002) var parotoid_thickness : float = 0.034

# ------------------------------- Warts -------------------------------
@export_group("Warts")

## 背部疣粒数量。0 就是一只光背蟾蜍。
@export_range(0, 60, 1) var wart_count : int = 20

## 疣粒最大半径。
@export_range(0.3, 6.0, 0.1, "suffix:px") var wart_size : float = 1.5

## 疣粒分布随机种子。固定值保证每次生成的疣粒长在同一个地方。
@export_range(0, 9999, 1) var wart_seed : int = 20261018

# ------------------------------- Ghost look -------------------------------
@export_group("Ghost Look")

@export var ghost_line : Color = Color(1.0, 1.0, 1.0, 0.96)

@export var ghost_inner : Color = Color(1.0, 1.0, 1.0, 0.45)

@export_range(0.4, 5.0, 0.1, "suffix:px") var ghost_line_width : float = 3.0

# ------------------------------- Legs -------------------------------
@export_group("Legs")

## 大腿（股）长度倍率，相对体长。
@export_range(0.05, 0.40, 0.005) var thigh_scale : float = 0.20

## 小腿（胫）长度倍率，相对体长。
@export_range(0.05, 0.40, 0.005) var shank_scale : float = 0.22

## 足长倍率，相对体长。蟾蜍的足长而扁，后足带蹼。
@export_range(0.05, 0.45, 0.005) var foot_scale : float = 0.26

## 后足趾数。
@export_range(3, 6, 1) var hind_toes : int = 5

## 前足趾数。
@export_range(2, 5, 1) var front_toes : int = 4

# ------------------------------- Motion -------------------------------
@export_group("Motion")

@export_enum("Wander", "Follow Mouse", "External") var control_mode : int = 0

## 一次跳跃的水平距离（正前方，正着跳）。调它就能改跳多远。
@export_range(20.0, 400.0, 5.0, "suffix:px") var hop_distance : float = 88.0

## 跳跃的滞空时间。越短越急。
@export_range(0.15, 1.2, 0.01, "suffix:s") var hop_time : float = 0.42

## 转向的角速度（弧度/秒）。越大转身越快。
@export_range(1.0, 12.0, 0.5, "suffix:rad/s") var turn_speed : float = 6.0

## 目标方向与当前朝向夹角小于这个角度（弧度）就直接跳，不单独转身。
@export_range(0.0, 1.0, 0.01, "suffix:rad") var min_turn_angle : float = 0.10

## 起跳前的蓄力（下蹲）时间。
@export_range(0.0, 1.0, 0.01, "suffix:s") var crouch_time : float = 0.20

## 跳跃时身体的拉伸幅度（1.0 = 拉长一倍）。越大腾空时越细长。
@export_range(0.0, 1.0, 0.02) var stretch_scale : float = 0.42

## 落地后的压缩恢复时间。
@export_range(0.0, 0.8, 0.01, "suffix:s") var land_time : float = 0.16

## 两次跳跃之间的趴伏时间下限。
@export_range(0.0, 6.0, 0.05, "suffix:s") var rest_min : float = 0.55

## 两次跳跃之间的趴伏时间上限。
@export_range(0.0, 8.0, 0.05, "suffix:s") var rest_max : float = 1.60

## 外部控制时由外部脚本写入的朝向（弧度）。
@export var external_direction : float = 0.0

## 躲避蛇：蛇头进入这个距离（世界像素）就立刻跳走。
@export_range(0.0, 900.0, 5.0, "suffix:px") var fear_range : float = 240.0

## 逃跑时一次跳多远（倍率）。
@export_range(1.0, 3.0, 0.05) var flee_hop_boost : float = 1.55

## 逃跑时趴伏时间缩短到原来的多少。
@export_range(0.05, 1.0, 0.01) var flee_rest_scale : float = 0.22

# ------------------------------- Legs -------------------------------
@export_group("Legs")

## 趴着不动时把四肢收起来藏进身下，动起来（蓄力 / 腾空 / 落地）才显形。
@export var hide_legs_when_still : bool = true

## 四肢显隐的过渡时间。0 = 瞬间切换。
@export_range(0.0, 0.6, 0.01, "suffix:s") var leg_fade_time : float = 0.10

## 收起时腿朝根部缩到多小（1 = 只淡出不缩，0 = 完全缩进关节）。
@export_range(0.0, 1.0, 0.01) var leg_tuck_scale : float = 0.42

## 静止多久之后才开始收腿。逃跑时趴伏很短，有这段延迟腿就不会反复闪现。
@export_range(0.0, 1.0, 0.01, "suffix:s") var leg_hide_delay : float = 0.20

# ------------------------------- Vitals -------------------------------
@export_group("Vitals")

@export_range(1.0, 3000.0, 1.0) var max_health : float = 88.0
@export_range(0.0, 3.0, 0.05) var poison_resist : float = 1.35
@export_range(0.2, 5.0, 0.1, "suffix:s") var death_fade : float = 1.4
## 饿死开关：>0 时饱食度归零就每秒扣这么多血，直到饿死。0 = 不会饿死。
@export_range(0.0, 50.0, 0.5, "suffix:/s") var starve_dps : float = 0.0
## 饿死/死亡后是否留下尸体（由关卡接管画蓝黑色尸体）。false 时照旧淡出消失。
@export var leave_corpse : bool = false
## 消化剩余秒数：>0 时蟾蜍趴着不动、不能吃（吞完猎物后由关卡设置）。
var digest_left : float = 0.0

# ------------------------------- Bounds -------------------------------
@export_group("Bounds")

@export var stay_in_viewport : bool = false
@export var use_play_bounds : bool = true
@export_enum("Rectangle", "Circle") var bounds_shape : int = 1
@export var bounds_center : Vector2 = Vector2(2500, 2500)
@export_range(64.0, 12000.0, 1.0, "suffix:px") var bounds_radius : float = 470.0
@export var play_bounds : Rect2 = Rect2(0, 0, 1920, 1080)

# ------------------------------- Runtime state -------------------------------
enum State { REST, TURN, CROUCH, AIR, LAND }

var points : PackedVector2Array = []      # [吻端, 中心, 尾端]，本地坐标
var heading : float = 0.0
var t : float = 0.0

var _state : int = State.REST
var _state_t : float = 0.0
var _rest_wait : float = 0.8

var _hop_from : Vector2 = Vector2.ZERO
var _hop_to : Vector2 = Vector2.ZERO
var _hop_len : float = 0.0

## 转向：转到目标角 _turn_to，方向 _turn_sign（±1）。
var _turn_to : float = 0.0
var _turn_sign : float = 1.0

## 姿态：0 = 蹲伏折叠，1 = 后腿蹬直。空气里从 0 冲到 1，落地收回。
var _leg_extend : float = 0.0
## 四肢显隐：0 = 完全收起（趴着不动），1 = 完全显形（在动）。
var leg_alpha : float = 0.0
## 静止了多久，用来延迟收腿。
var _still_t : float = 0.0
## 体型挤压：<1 压扁（蓄力 / 落地），>1 拉伸（腾空）。
var _squash : float = 1.0
## 呼吸相位。
var _breath : float = 0.0
## 眨眼：1 = 完全闭眼，0 = 睁着。
var _blink : float = 0.0
var _blink_wait : float = 2.0

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var metab = null

## 热成像用：本帧每条腿的折线（本地坐标），每条腿 4 个点：髋/膝/踝/尖。
var heat_leg_chains : PackedVector2Array = PackedVector2Array()
var heat_leg_slots : int = 0
## 热成像用：整只蟾蜍的外轮廓（本地坐标，多个不相连的闭合圈首尾相接）。
var heat_outline : PackedVector2Array = PackedVector2Array()
## 热成像用：每个闭合圈的点数，供上层按圈绘制。
var heat_body_loops : PackedInt32Array = PackedInt32Array()
## 热成像用：身体几何中心（本地坐标）。整只蟾蜍的红线判定就取这一个点。
var heat_center : Vector2 = Vector2.ZERO

var health : float = 88.0
var _hurt : float = 0.0
var _poison_time : float = 0.0
var _poison_dps : float = 0.0
var _dead : bool = false
var _death_time : float = 0.0

const WHITE_LIT_MIN : float = 0.80

func _ready() -> void:
	_wart_rng = RandomNumberGenerator.new()
	_wart_rng.seed = wart_seed
	metab = get_node_or_null("Metabolism")
	health = max_health
	if Engine.is_editor_hint():
		_build_warts()
		return
	add_to_group("toad")
	_rng.randomize()
	_rest_wait = _rng.randf_range(rest_min, rest_max)
	_blink_wait = _rng.randf_range(1.5, 4.0)
	_rebuild_points()
	_build_warts()

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
	_breath += delta
	# 消化中：刚吞下猎物，趴着不动，等读秒走完（由关卡写 digest_left）。
	if digest_left > 0.0:
		digest_left = maxf(0.0, digest_left - delta)
		_tick_blink(delta)
		_tick_leg_fade(delta)
		_rebuild_points()
		queue_redraw()
		return
	_tick_blink(delta)
	_tick_state(delta)
	_tick_leg_fade(delta)
	# 身体朝向跟跳跃方向一致：只有转向时 heading 在变，其余时刻朝前。
	rotation = heading
	_rebuild_points()
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
	_poison_time = 0.0
	_report_kill()


## 击杀播报：交给全局 Toast 弹一条左侧气泡。
## 编辑器里（@tool）没有 autoload，这里静默跳过。
func _report_kill() -> void:
	var toast : Node = get_node_or_null("/root/Toast")
	if toast != null and toast.has_method("kill"):
		toast.call("kill", "TOAD")

func _tick_combat(delta: float) -> void:
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta * 5.0)
	if _dead:
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

# =============================== State machine ===============================
## 蟾蜍不走路：趴一会儿 → 蹲下蓄力 → 腾空 → 落地压一下 → 再趴。
func _tick_state(delta: float) -> void:
	_state_t += delta
	match _state:
		State.REST:
			_leg_extend = move_toward(_leg_extend, 0.0, delta * 4.0)
			_squash = lerpf(_squash, 1.0, clampf(delta * 6.0, 0.0, 1.0))
			# 蛇贴脸就提前结束趴伏，立刻转向跳走。
			if _snake_menace() > 0.0:
				_rest_wait = 0.0
			if _state_t >= _rest_wait:
				_begin_turn()
		State.TURN:
			_turn_step(delta)
		State.CROUCH:
			var k : float = clampf(_state_t / maxf(0.01, crouch_time), 0.0, 1.0)
			# 蓄力只是把腿折得更紧（0 = 折到位），不要拉成负值，否则会反向撑出去。
			_leg_extend = lerpf(_leg_extend, 0.0, clampf(delta * 10.0, 0.0, 1.0))
			_squash = lerpf(1.0, 0.90, k)
			if k >= 1.0:
				_state = State.AIR
				_state_t = 0.0
		State.AIR:
			var ka : float = clampf(_state_t / maxf(0.01, hop_time), 0.0, 1.0)
			# 平面位移：世界坐标直接插值到落点。
			global_position = _hop_from.lerp(_hop_to, ka)
			# 腾空高度只用来做姿态，俯视下不改变平面位置。
			var h : float = sin(ka * PI)
			_leg_extend = lerpf(0.0, 1.0, clampf(ka * 2.2, 0.0, 1.0))
			# 跳跃拉伸：起跳蹬腿瞬间快速拉长、滞空保持、落地前收回。
			# pow(h,0.6) 让上升沿更陡，起跳阶段就冲到接近峰值，更有"蹬出去"的劲。
			_squash = 1.0 + stretch_scale * pow(h, 0.6)
			if ka >= 1.0:
				global_position = _hop_to
				_state = State.LAND
				_state_t = 0.0
		State.LAND:
			var kl : float = clampf(_state_t / maxf(0.01, land_time), 0.0, 1.0)
			_leg_extend = lerpf(1.0, 0.0, kl)
			_squash = lerpf(0.88, 1.0, kl)
			if kl >= 1.0:
				_state = State.REST
				_state_t = 0.0
				_rest_wait = _rng.randf_range(rest_min, rest_max)
				# 刚被吓过就少趴一会儿，随时准备再跳。
				if _snake_menace() > 0.0:
					_rest_wait *= flee_rest_scale
				elif _last_flee:
					_rest_wait *= flee_rest_scale * 2.0

## 四肢显隐：趴着不动时收进身下，蓄力 / 腾空 / 落地才露出来。
func _tick_leg_fade(delta: float) -> void:
	if not hide_legs_when_still:
		leg_alpha = 1.0
		return
	# 只要离开了 REST，或腿还在蹬 / 收的过程里，就算"在动"。
	if _state == State.REST and absf(_leg_extend) <= 0.02:
		_still_t += delta
	else:
		_still_t = 0.0
	var want : float = 1.0 if _still_t < leg_hide_delay else 0.0
	if leg_fade_time <= 0.0:
		leg_alpha = want
	else:
		leg_alpha = move_toward(leg_alpha, want, delta / leg_fade_time)

## 蛇头离得有多近：0 = 不在恐惧范围内，1 = 贴脸。
func _snake_menace() -> float:
	if fear_range <= 0.0:
		return 0.0
	var snake : Node = get_tree().get_first_node_in_group("snake")
	if snake == null or not is_instance_valid(snake) or not (snake is Node2D):
		return 0.0
	# 蛇静止藏住了：蟾蜍感觉不到它，不会提前跳走。
	if snake.has_method("is_stealthed") and bool(snake.call("is_stealthed")):
		return 0.0
	var sp = snake.get("points")
	if sp == null or sp.size() == 0:
		return 0.0
	var d : float = global_position.distance_to(snake.to_global(sp[0]))
	if d > fear_range:
		return 0.0
	return clampf(1.0 - d / fear_range, 0.0, 1.0)

var _last_flee : bool = false

## 趴伏结束：先转向，再起跳。目标是"只能正着跳"——
## 跳的方向必须和当前朝向一致，所以这里先转好身，再进蓄力。
func _begin_turn() -> void:
	var dir : float = _pick_direction()
	var menace : float = _snake_menace()
	_last_flee = menace > 0.0

	# 目标方向与当前朝向的夹角（带符号，走最短弧）。
	var delta : float = wrapf(dir - heading, -PI, PI)
	if absf(delta) <= min_turn_angle:
		# 夹角太小，不用专门转身，直接起跳。
		_begin_crouch(heading)
		return

	# 进入转向：记录目标角度，转到目标方向。
	_turn_to = heading + delta
	_turn_sign = signf(delta)
	_state = State.TURN
	_state_t = 0.0

## 每帧推进转向：heading 平滑转到目标角，身体（rotation）同步。
func _turn_step(delta: float) -> void:
	_leg_extend = move_toward(_leg_extend, 0.0, delta * 4.0)
	_squash = lerpf(_squash, 1.0, clampf(delta * 6.0, 0.0, 1.0))

	var step : float = turn_speed * delta
	# 朝目标方向转，转到位就停，别转过头。
	var remain : float = wrapf(_turn_to - heading, -PI, PI)
	if absf(remain) <= step or _turn_sign * remain <= 0.0:
		heading = _turn_to
		_begin_crouch(heading)
		return
	heading = wrapf(heading + _turn_sign * step, -PI, PI)

## 选好落点、定好朝向，进入蓄力。dir 已经和当前朝向一致（正着跳）。
func _begin_crouch(dir: float) -> void:
	var menace : float = _snake_menace()
	_last_flee = menace > 0.0

	var dist : float = hop_distance
	if _last_flee:
		dist *= flee_hop_boost * (1.0 + menace * 0.5)
	dist *= _rng.randf_range(0.85, 1.15)
	# 捕猎模式：蛇逼近时蟾蜍也减速，跳得近一点。
	if Snake.hunt_mode:
		dist *= Snake.HUNT_PREY_SLOW_MULT

	_hop_from = global_position
	# 只朝当前朝向（heading）正着跳，不侧跳、不倒跳。
	_hop_to = global_position + Vector2.from_angle(dir) * dist
	_hop_to = _clamp_to_bounds(_hop_to)
	_hop_len = _hop_from.distance_to(_hop_to)

	heading = dir
	_state = State.CROUCH
	_state_t = 0.0
	_squash = 1.0

## 挑一个跳的方向：逃蛇 > 外部控制 > 追鼠标 > 随便跳。
func _pick_direction() -> float:
	var menace : float = _snake_menace()
	if menace > 0.0:
		var snake : Node = get_tree().get_first_node_in_group("snake")
		var sp = snake.get("points")
		if sp != null and sp.size() > 0:
			var away : Vector2 = global_position - snake.to_global(sp[0])
			if away.length() > 1.0:
				# 加一点随机摆动，别跳得像尺子画出来的直线。
				return away.angle() + _rng.randf_range(-0.35, 0.35)
		return heading + PI + _rng.randf_range(-0.35, 0.35)
	match control_mode:
		1:
			var to_mouse : Vector2 = get_global_mouse_position() - global_position
			if to_mouse.length() > 4.0:
				return to_mouse.angle() + _rng.randf_range(-0.2, 0.2)
		2:
			return external_direction
	# Wander：小幅摆动地往前跳，偶尔掉头。
	var d : float = heading + _rng.randf_range(-0.9, 0.9)
	if _rng.randf() < 0.18:
		d += PI
	return d

## 落点不能出场地。
func _clamp_to_bounds(p: Vector2) -> Vector2:
	if use_play_bounds and bounds_shape == 1:
		var off : Vector2 = p - bounds_center
		var rad : float = maxf(16.0, bounds_radius)
		if off.length() > rad:
			return bounds_center + off.normalized() * rad
	elif use_play_bounds or stay_in_viewport:
		var rect : Rect2 = play_bounds if use_play_bounds else get_viewport_rect()
		p.x = clampf(p.x, rect.position.x, rect.end.x)
		p.y = clampf(p.y, rect.position.y, rect.end.y)
	return p

func _tick_blink(delta: float) -> void:
	if _blink > 0.0:
		_blink = maxf(0.0, _blink - delta * 7.0)
		return
	_blink_wait -= delta
	if _blink_wait <= 0.0:
		_blink = 1.0
		_blink_wait = _rng.randf_range(1.6, 5.0)

func _rebuild_points() -> void:
	var hl : float = body_length * 0.5
	if points.size() != 3:
		points.resize(3)
	points[0] = Vector2(hl * 0.98, 0.0)
	points[1] = Vector2.ZERO
	points[2] = Vector2(-hl * 0.98, 0.0)

# =============================== Light ===============================
func _lit(p: Vector2) -> float:
	return Snake.light_at(to_global(p))

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

# =============================== Warts ===============================
## 背部疣粒：固定种子撒点，落在身体轮廓内，越靠后越密。
var _warts : Array = []
var _wart_rng : RandomNumberGenerator = RandomNumberGenerator.new()

func _build_warts() -> void:
	_warts.clear()
	if wart_count <= 0:
		return
	# 抖动网格：疣粒大致成排，但每一颗位置都带随机偏移，不是整齐的棋盘。
	var hl : float = body_length * 0.5
	var cols : int = maxi(2, int(ceil(sqrt(float(wart_count) * 1.6))))
	var rows : int = maxi(1, int(ceil(float(wart_count) / float(cols))))
	var made : int = 0
	for r in rows:
		for c in cols:
			if made >= wart_count:
				break
			var ju : float = _wart_rng.randf_range(-0.36, 0.36)
			var jv : float = _wart_rng.randf_range(-0.36, 0.36)
			# 只长在背部（后半身），吻端和眼睛那块留干净。
			var u : float = lerpf(-0.86, 0.26, (float(c) + 0.5 + ju) / float(cols))
			var v : float = lerpf(-0.86, 0.86, (float(r) + 0.5 + jv) / float(rows))
			var x : float = signf(u) * pow(absf(u), 1.18) * hl
			var rr : float = wart_size * _wart_rng.randf_range(0.60, 1.0)
			_warts.append({"p": Vector2(x, v * _half_width_at(u) * 0.80),
				"r": rr, "a": _wart_rng.randf_range(0.32, 0.55)})
			made += 1

## 给定纵向位置 u ∈ [-1, 1]（-1 尾，+1 吻），返回该处的半宽。
## 宽度包络：蹲坐的蟾蜍前窄后宽，吻端收、臀部撑。
func _width_env(u: float) -> float:
	var hw : float = body_width * 0.5
	var front : float = maxf(0.0, u)
	var back : float = maxf(0.0, -u)
	# 颈部轻轻一收，头和身子才分得开（蟾蜍没有脖子，但这里是视觉分界）。
	var neck : float = 1.0 - 0.055 * exp(-pow((u - 0.30) / 0.17, 2.0))
	return hw * (1.0 - 0.10 * front * front) * (1.0 + 0.07 * back * back) * neck

## 该 x 处轮廓实际给出的半宽（再乘椭圆的收缩项，就是轮廓上的 y）。
func _half_width_at(u: float) -> float:
	return _width_env(u) * sqrt(maxf(0.0, 1.0 - u * u))

# =============================== Geometry ===============================
## 俯视的身体轮廓：一圈闭合折线（本地坐标，+X 朝前）。
## 卵形包络 —— 前端略钝、后端撑开，是"趴在地上的一坨"。
func _body_outline() -> PackedVector2Array:
	var hl : float = body_length * 0.5
	var out := PackedVector2Array()
	var squash_w : float = 1.0 + (1.0 - _squash) * 0.55
	var squash_l : float = 1.0 + (_squash - 1.0) * 0.45
	var breath : float = 1.0 + 0.018 * sin(_breath * 2.4)
	for k in body_steps:
		var a : float = TAU * float(k) / float(body_steps)
		var u : float = cos(a)
		var v : float = sin(a)
		# 指数 >1 让吻端和尾端更"钝"一些，不是尖椭圆。
		var up : float = signf(u) * pow(absf(u), 1.18)
		var w : float = _width_env(u) * breath * squash_w
		out.append(Vector2(up * hl * squash_l, v * w))
	return out

## 眼睛位置（本地）。贴在该处轮廓上，眼球稍微鼓出体外一点。
func _eye_center(side: float) -> Vector2:
	var hl : float = body_length * 0.5
	var u : float = clampf(eye_offset * 2.0 - 1.0, 0.0, 1.0)
	var x : float = signf(u) * pow(absf(u), 1.18) * hl
	return Vector2(x, side * _half_width_at(u) * eye_spread)

## 耳后腺中心与朝向（本地）。从眼后沿体侧向后，微微向外斜。
func _parotoid(side: float) -> Dictionary:
	var e : Vector2 = _eye_center(side)
	var c : Vector2 = e + Vector2(-body_length * 0.19, side * body_length * 0.004)
	return {"c": c, "ang": PI - side * 0.06}

# =============================== Legs ===============================
## 四条腿：前肢短、撑在肩前；后肢折叠成 Z 形，蹲着的时候膝比背还高。
## 每条腿四个点：髋 / 膝 / 踝 / 足尖。热感应按四段逐段判定。
func _leg_chains() -> Array:
	var L : float = body_length
	var hl : float = L * 0.5
	var chains : Array = []
	for side in [-1.0, 1.0]:
		var sf : float = float(side)

		# ---- 前肢：肩点在体侧偏前，短而粗，朝前外撑住前半身 ----
		var u_sh : float = 0.45
		var sh : Vector2 = Vector2(signf(u_sh) * pow(absf(u_sh), 1.18) * hl,
			sf * _half_width_at(u_sh) * 0.95)
		var out_v : Vector2 = Vector2(0.0, sf)
		var fwd_v : Vector2 = Vector2(1.0, 0.0)
		# 肘外撑，前臂折向前，手落在吻端两侧的地面上。
		var elbow : Vector2 = sh + (out_v * 0.12 + fwd_v * 0.04) * L
		var wrist : Vector2 = sh + (out_v * 0.06 + fwd_v * 0.16) * L
		var toe : Vector2 = sh + (out_v * 0.04 + fwd_v * 0.24) * L
		# 跳起来时前肢往前探一点，落地时收回来撑地。
		var ext : float = _leg_extend
		elbow += fwd_v * (0.03 * L * ext)
		wrist += fwd_v * (0.06 * L * ext)
		toe += fwd_v * (0.09 * L * ext)
		chains.append({"pts": PackedVector2Array([sh, elbow, wrist, toe]),
			"side": sf, "hind": false})

		# ---- 后肢：髋 / 膝（外后，蹲时向外撑）/ 踝（内收回来）/ 足尖（朝后外）----
		var u_hip : float = -0.40
		var hip : Vector2 = Vector2(signf(u_hip) * pow(absf(u_hip), 1.18) * hl,
			sf * _half_width_at(u_hip) * 0.95)
		var back_v : Vector2 = Vector2(-1.0, 0.0)
		# 蹲姿（ext=0）：蛙腿的 Z 形 —— 股骨贴体侧往前，膝顶在体侧中部；
		# 胫骨向后退，足再向后外伸出去。膝在前，是蹲坐青蛙的标志。
		var knee_c : Vector2 = hip + (out_v * 0.06 + fwd_v * 0.09) * L
		var ankle_c : Vector2 = hip + (out_v * 0.03 + back_v * 0.05) * L
		var toe_c : Vector2 = hip + (out_v * 0.11 + back_v * 0.14) * L
		# 蹬直（ext=1）：股骨折向后，膝滑到体侧后方，整条腿甩成一条弧。
		var knee_e : Vector2 = hip + (out_v * 0.06 + back_v * 0.18) * L
		var ankle_e : Vector2 = hip + (out_v * 0.04 + back_v * 0.36) * L
		var toe_e : Vector2 = hip + (out_v * 0.10 + back_v * 0.52) * L
		var k : float = clampf(_leg_extend, 0.0, 1.0)
		var kneep : Vector2 = knee_c.lerp(knee_e, k)
		var anklep : Vector2 = ankle_c.lerp(ankle_e, k)
		var toep : Vector2 = toe_c.lerp(toe_e, k)
		chains.append({"pts": PackedVector2Array([hip, kneep, anklep, toep]),
			"side": sf, "hind": true})
	return chains

# =============================== Drawing ===============================
func _draw() -> void:
	if Engine.is_editor_hint():
		if points.size() != 3:
			_rebuild_points()
			_build_warts()
	_build_heat()
	_ensure_occluder()
	_occluder.occluder.polygon = heat_outline

	var chains : Array = _leg_chains()
	for c in chains:
		_draw_leg(c)
	_draw_body()
	_draw_mouth()
	_draw_parotoids()
	_draw_eyes()
	_draw_warts()

## 身体：一圈轮廓。不填充，靠轮廓读体积。
func _draw_body() -> void:
	var pts : PackedVector2Array = _body_outline()
	var col : Color = _wcol(Vector2.ZERO, ghost_line.a)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, col, ghost_line_width, false)

## 吻端两个鼻孔：两小段短弧。蟾蜍的嘴在背面几乎看不见，画鼻孔更准也更干净。
func _draw_mouth() -> void:
	var hl : float = body_length * 0.5
	for side in [-1.0, 1.0]:
		var sf : float = float(side)
		var c := Vector2(hl * 0.74, sf * body_length * 0.045)
		var pts := PackedVector2Array()
		for k in 7:
			var a : float = PI * 0.15 + PI * 0.70 * float(k) / 6.0
			pts.append(c + Vector2(cos(a) * body_length * 0.022,
				sin(a) * body_length * 0.016))
		draw_polyline(pts, _wcol(c, ghost_inner.a * 1.25), ghost_line_width * 0.7, false)

## 耳后腺：眼后两条长椭圆隆起。蟾蜍独有的标志，一定要有。
func _draw_parotoids() -> void:
	if parotoid_length <= 0.0:
		return
	for side in [-1.0, 1.0]:
		var p : Dictionary = _parotoid(float(side))
		var c : Vector2 = p["c"]
		var ang : float = p["ang"]
		var dir : Vector2 = Vector2.from_angle(ang)
		var nrm : Vector2 = dir.orthogonal()
		var hl : float = body_length * parotoid_length
		var hw : float = body_length * parotoid_thickness
		var pts := PackedVector2Array()
		for k in 21:
			var a : float = TAU * float(k) / 20.0
			pts.append(c + dir * (cos(a) * hl) + nrm * (sin(a) * hw))
		draw_polyline(pts, _wcol(c, ghost_line.a * 0.86), ghost_line_width * 0.9, false)

## 眼睛：两个大圆 + 一条眼睑弧。眨眼时压成一条横线。
func _draw_eyes() -> void:
	for side in [-1.0, 1.0]:
		var c : Vector2 = _eye_center(float(side))
		var r : float = eye_radius
		var open : float = 1.0 - _blink * 0.94
		var pts := PackedVector2Array()
		for k in 17:
			var a : float = TAU * float(k) / 16.0
			pts.append(c + Vector2(cos(a) * r, sin(a) * r * open))
		draw_polyline(pts, _wcol(c, ghost_line.a), ghost_line_width * 1.05, false)
		if open > 0.35:
			# 瞳孔：横置一小段，两栖动物夜间是横瞳。
			var pup := PackedVector2Array([
				c + Vector2(-r * 0.26, 0.0), c + Vector2(r * 0.26, 0.0),
			])
			draw_polyline(pup, _wcol(c, ghost_inner.a * 1.1), ghost_line_width * 0.55, false)

## 背部疣粒：一圈小凸起 + 一个更小的内点，读起来是"鼓出来的"。
func _draw_warts() -> void:
	for w in _warts:
		var p : Vector2 = w["p"]
		var r : float = float(w["r"])
		var a : float = float(w["a"])
		draw_circle(p, r, _wcol(p, a), false, ghost_line_width * 0.6, false)
		draw_circle(p, r * 0.36, _wcol(p, a * 1.2))

## 一条腿：股 / 胫 / 跗三段 + 关节小点 + 足趾。
## 静止时 leg_alpha 掉到 0，整条腿同时淡出并朝根部缩进身下。
func _draw_leg(c: Dictionary) -> void:
	# 编辑器里始终显示，方便摆参数。
	var la : float = 1.0 if Engine.is_editor_hint() else leg_alpha
	if la <= 0.02:
		return
	var pts : PackedVector2Array = c["pts"]
	var sf : float = float(c["side"])
	var hind : bool = bool(c["hind"])
	var root : Vector2 = pts[0]
	var sc : float = lerpf(leg_tuck_scale, 1.0, la)
	if sc < 0.999:
		var tucked := PackedVector2Array()
		for p in pts:
			tucked.append(root + (p - root) * sc)
		pts = tucked
	var a0 : float = (0.66 if hind else 0.60) * la
	var a1 : float = (0.86 if hind else 0.80) * la
	var a2 : float = (0.88 if hind else 0.84) * la
	# 蟾蜍的腿粗短，比身体轮廓线再粗一档，不然像蜘蛛腿。
	draw_line(pts[0], pts[1], _wcol(pts[1], a0), ghost_line_width * 1.55, false)
	draw_line(pts[1], pts[2], _wcol(pts[2], a1), ghost_line_width * 1.62, false)
	draw_line(pts[2], pts[3], _wcol(pts[3], a2), ghost_line_width * 1.45, false)
	for i in range(1, 4):
		draw_circle(pts[i], maxf(0.6, ghost_line_width * 0.72) * sc, _wcol(pts[i], 0.95 * la))
	# 足趾：从足尖点扇形散开。后足五趾（带蹼），前足四趾。
	var n : int = hind_toes if hind else front_toes
	var base : Vector2 = pts[2]
	var tip : Vector2 = pts[3]
	# 趾朝前进方向：前足朝前外、后足朝后外。若沿踝→足尖画，会看成"举手"。
	var dir : Vector2 = (Vector2(-0.90, sf * 0.36) if hind else Vector2(0.90, sf * 0.40)).normalized()
	var nrm : Vector2 = dir.orthogonal()
	var toe_len : float = body_length * (0.062 if hind else 0.042) * sc
	var spread : float = (0.95 if hind else 0.75) * sf
	for i in n:
		var k : float = float(i) / float(maxi(1, n - 1))
		var ang : float = lerpf(-spread, spread, k)
		var d : Vector2 = dir.rotated(ang)
		var tp : Vector2 = tip + d * toe_len
		draw_line(tip, tp, _wcol(tp, 0.82 * la), ghost_line_width * 0.62, false)
		draw_circle(tp, maxf(0.32, ghost_line_width * 0.38) * sc, _wcol(tp, 0.95 * la))
	# 趾根之间一道弧，把几根趾连成一只"脚掌"。
	if n >= 3:
		var web := PackedVector2Array()
		for i in 7:
			var kk : float = float(i) / 6.0
			var ang2 : float = lerpf(-spread, spread, kk)
			var d2 : Vector2 = dir.rotated(ang2)
			web.append(tip + d2 * toe_len * 0.42)
		draw_polyline(web, _wcol(tip, 0.62 * la), ghost_line_width * 0.55, false)

# =============================== Heat data ===============================
func _build_heat() -> void:
	heat_center = Vector2.ZERO
	heat_outline.clear()
	heat_body_loops.clear()

	# 身体主轮廓（一个闭合圈）。
	var body : PackedVector2Array = _body_outline()
	heat_outline.append_array(body)
	heat_body_loops.append(body.size())

	# 两只眼睛各一圈。
	for side in [-1.0, 1.0]:
		var c : Vector2 = _eye_center(float(side))
		var r : float = eye_radius
		var n : int = 16
		for k in n:
			var a : float = TAU * float(k) / float(n)
			heat_outline.append(c + Vector2(cos(a) * r, sin(a) * r))
		heat_body_loops.append(n)

	# 两条耳后腺各一圈。
	if parotoid_length > 0.0:
		for side in [-1.0, 1.0]:
			var p : Dictionary = _parotoid(float(side))
			var c2 : Vector2 = p["c"]
			var dir : Vector2 = Vector2.from_angle(float(p["ang"]))
			var nrm : Vector2 = dir.orthogonal()
			var hl : float = body_length * parotoid_length
			var hw : float = body_length * parotoid_thickness
			var n2 : int = 14
			for k in n2:
				var a2 : float = TAU * float(k) / float(n2)
				heat_outline.append(c2 + dir * (cos(a2) * hl) + nrm * (sin(a2) * hw))
			heat_body_loops.append(n2)

	# 四腿：每腿 4 个点，逐段判定。收起时同步缩到根部，免得红线停在空气里。
	heat_leg_chains.clear()
	var chains : Array = _leg_chains()
	heat_leg_slots = chains.size()
	var tuck : float = lerpf(leg_tuck_scale, 1.0, leg_alpha)
	for c3 in chains:
		var lp : PackedVector2Array = c3["pts"]
		var root : Vector2 = lp[0]
		for p in lp:
			heat_leg_chains.append(root + (p - root) * tuck)
