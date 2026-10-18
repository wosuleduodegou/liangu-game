extends Node2D

## 咬击（E + 左键）的锁定指示器与命中反馈。
##
## 为什么单独做一层：蛇的视野后处理会把光圈以外压成全黑，如果指示器跟着
## 蛇画在世界层，锁定圈就整段消失，玩家根本不知道能咬多远。这一层挂在
## CanvasLayer 上、画在滤镜之上，属于 UI 层。
##
## 全屏坐标绘制：世界点先过 get_canvas_transform() 换成屏幕像素，半径乘上
## 相机缩放。这样相机 zoom 怎么调、镜头怎么跟，指示器都跟蛇头严丝合缝。
##
## 它只读蛇的状态，不改任何东西：aiming / has_lock() / lock_point /
## bite_fx_* 都是公开的。

const FONT : Font = preload("res://Assets/字体/Piedra-Regular.ttf")

## 提示文字（没有目标 / 毒液）用的字体：Piedra 没有汉字，中文会变方块，
## 所以这几个词走 GameSettings 里挂好了中文回退的那支。伤害数字仍用 Piedra。
var _word_font : Font = null

func _word_font_get() -> Font:
	if _word_font != null:
		return _word_font
	var gs = get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("cjk_font"):
		_word_font = gs.call("cjk_font") as Font
	if _word_font == null:
		_word_font = FONT
	return _word_font


const FX_TIME : float = 0.42

## 毒量充足 / 不足时的主色。
const COL_READY := Color(0.72, 0.95, 0.38)
const COL_DRY := Color(0.88, 0.36, 0.28)
const COL_MISS := Color(0.74, 0.72, 0.68)
## 射程内没有目标时的提示色。
const COL_IDLE := Color(0.92, 0.86, 0.66)
## 热感应：蛇是"透明白线 + 实心白贴图头"，敌人靠近时才隐隐现出一圈红线。
const COL_HEAT_EDGE := Color(0.93, 0.94, 0.90)
const COL_HEAT_SELF := Color(1.0, 0.24, 0.16)
## 热感应红线的主色：只在敌人身上、靠近时才显形。
const COL_HEAT_ENEMY := Color(1.0, 0.22, 0.14)

var snake : Node = null
## 锁定建立的一瞬间，用来做"圈从外往里收"的动画。
var _lock_born : float = -1.0
var _was_locked : bool = false

## 热感应：当前"盯着"的那只目标，以及盯了多久。
var _focus_bug : Node = null
var _focus_t : float = 0.0

## 红线感应周期（秒）：一个周期内红线亮起再熄灭。
@export var red_cycle_time : float = 0.7
## 剩余敌人 ≤ 这个数时增强红线：更快闪烁、更亮、更常亮，帮玩家找最后几只。
@export var heat_boost_below : int = 2
## 增强强度上限（0~1）：剩 1 只时打到这个值，剩 2 只时约为一半。
@export_range(0.0, 1.0, 0.01) var heat_boost_strength : float = 1.0

## 这一帧算出来的增强量，_line_state / _stroke_outline / _draw_leg_seg 直接读，
## 免得把参数一路传下去。
var _boost : float = 0.0

## 多久没捕到猎物就弹方向提示（秒）。
@export var hint_after : float = 10.0
## 距上次击杀的累计秒数（随 delta 累加，暂停时自动停）。
var _since_kill : float = 0.0
## 上一帧的存活数，用来检测「有猎物被打死」的那一帧。
var _prev_alive : int = -1

func _ready() -> void:
	_find_snake()

func _find_snake() -> void:
	snake = get_tree().get_first_node_in_group("snake")

func _process(delta: float) -> void:
	if snake == null or not is_instance_valid(snake):
		_find_snake()
	if snake == null or not is_instance_valid(snake) or not (snake is Node2D):
		return
	var locked : bool = bool(snake.aiming) and bool(snake.has_lock())
	if locked and not _was_locked:
		_lock_born = Time.get_ticks_msec() * 0.001
	_was_locked = locked

	# 盯着同一只目标的时间越久，热影越稳定成形；换了目标就清零重来。
	var f : Node = _pick_focus()
	if f != null and f == _focus_bug:
		_focus_t = minf(_focus_t + delta, float(snake.heat_focus_time))
	else:
		_focus_t = 0.0
	_focus_bug = f

	# 方向提示计时：有猎物被打死就清零，否则累加。
	var alive : int = _alive_count()
	if _prev_alive >= 0 and alive < _prev_alive:
		_since_kill = 0.0
	else:
		_since_kill += delta
	_prev_alive = alive

	queue_redraw()

## 所有可被热感应/锁定的实体：蜈蚣 + 蚂蚁 + 蟾蜍。
func _all_bugs() -> Array:
	var out : Array = []
	for b in get_tree().get_nodes_in_group("centipede"):
		out.append(b)
	for b in get_tree().get_nodes_in_group("ant"):
		out.append(b)
	for b in get_tree().get_nodes_in_group("toad"):
		out.append(b)
	return out

## 场上还没死的敌人数量（和清场判定同口径：排除已死 / 待删）。
func _alive_count() -> int:
	var n : int = 0
	for g in ["ant", "centipede", "toad"]:
		for node in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node.has_method("is_dead") and bool(node.call("is_dead")):
				continue
			n += 1
	return n

## 剩余越少，增强越强：剩 heat_boost_below 只给一半，剩 1 只打满。
## 超过阈值或已经清空则不做任何增强。
func _heat_boost(alive: int) -> float:
	if alive <= 0 or alive > heat_boost_below:
		return 0.0
	var t : float = float(heat_boost_below - alive + 1) / float(heat_boost_below)
	return clampf(t * heat_boost_strength, 0.0, 1.0)

## 离蛇头最近的一只活猎物（不限方向、不限距离）。
func _nearest_bug() -> Node:
	if snake == null or not is_instance_valid(snake) or not (snake is Node2D):
		return null
	if snake.points.size() == 0:
		return null
	var head_g : Vector2 = snake.to_global(snake.points[0])
	var best : Node = null
	var best_d : float = 1e20
	for bug in _all_bugs():
		if not is_instance_valid(bug) or not (bug is Node2D):
			continue
		if bug.has_method("is_dead") and bool(bug.call("is_dead")):
			continue
		var pts = bug.get("points")
		if pts == null or pts.size() == 0:
			continue
		var d : float = head_g.distance_to(bug.to_global(pts[0]))
		if d < best_d:
			best_d = d
			best = bug
	return best

## 当前最受注意的目标：瞄准锁定优先，否则是正前方最近的、在感知范围内的那只。
func _pick_focus() -> Node:
	if bool(snake.aiming) and bool(snake.has_lock()):
		return snake.lock_target
	if snake.points.size() == 0:
		return null
	var head_g : Vector2 = snake.to_global(snake.points[0])
	var hd : float = float(snake.heading)
	var reach : float = float(snake.heat_range)
	var best : Node = null
	var best_d : float = 1e20
	for bug in _all_bugs():
		if not is_instance_valid(bug) or not (bug is Node2D):
			continue
		if bug.has_method("is_dead") and bool(bug.call("is_dead")):
			continue
		var pts = bug.get("points")
		if pts == null or pts.size() == 0:
			continue
		var v : Vector2 = bug.to_global(pts[0]) - head_g
		var d : float = v.length()
		if d > reach:
			continue
		if d > 4.0 and absf(angle_difference(hd, v.angle())) > deg_to_rad(70.0):
			continue
		if d < best_d:
			best_d = d
			best = bug
	return best

func _draw() -> void:
	if snake == null or not is_instance_valid(snake):
		return
	if not (snake is Node2D):
		return
	var pts = snake.points
	if pts == null or pts.size() == 0:
		return

	var xf : Transform2D = get_viewport().get_canvas_transform()
	var zoom : float = maxf(0.001, absf(xf.get_scale().x))
	var head : Vector2 = xf * snake.to_global(pts[0])

	# 热感应垫在最底下：先有热影，再谈锁定和挥咬。
	_draw_heat(xf, zoom)

	# 太久没捕到猎物时，屏幕边缘给个指向最近猎物的箭头。
	if _since_kill > hint_after:
		_draw_prey_hint(xf)

	if snake.aiming:
		if snake.has_lock():
			_draw_lock(head, zoom, xf)
		else:
			_draw_idle(head, zoom)
	if snake.bite_fx_time > 0.0:
		_draw_fx(head, zoom, xf)

# ------------------------------- 热感应 -------------------------------
## 红线感应：照亮区（光照 >80%）里直接看到白骨架；暗处靠红线"逐渐感应"。
##
## 规则：
##   * 0.7 秒一个周期（red_cycle_time），周期内红线亮起再熄灭一次。
##   * 每一根线（身体每段轮廓线、每条腿的股/胫/跗三段）各自独立判定：
##     这个周期亮不亮，是上个周期结束时掷骰子决定的，不是每帧乱闪。
##   * 亮起的概率由两点控制：
##       - 蛇头到这根线中点的距离（越近概率越高，成反比）
##       - 蛇当前的速度（越快概率越小，冲刺时几乎感应不到）
##   * 照亮区里的骨架不画红线——白骨架已经在那儿了，红线只补暗处。
func _draw_heat(xf: Transform2D, zoom: float) -> void:
	var now : float = Time.get_ticks_msec() * 0.001
	var head_g : Vector2 = snake.to_global(snake.points[0])
	var heat_r : float = float(snake.heat_range)
	# 蛇速：motion_ratio 0=静止 ~2=冲刺。越快概率越小。
	var walk : float = clampf(float(snake.motion_ratio()), 0.0, 2.0)
	var speed_f : float = 1.0 - clampf(walk * 0.45, 0.0, 0.85)
	# 剩余敌人 ≤ 阈值时增强红线：更频繁、更明显。
	_boost = _heat_boost(_alive_count())
	# 周期随增强变短（最快约 0.45 倍），同一个包络下闪烁更频繁。
	var cycle_time : float = lerpf(red_cycle_time, red_cycle_time * 0.45, _boost)
	# 周期与包络：一个周期内红线先亮起、再熄灭。
	var phase : float = fmod(now / cycle_time, 1.0)
	# 亮起很快（0 → 0.10 就到位），熄灭慢（0.62 → 1.0）。
	var env : float = smoothstep(0.0, 0.10, phase) * (1.0 - smoothstep(0.62, 1.0, phase))
	var cycle : int = int(now / cycle_time)
	var rng : RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = cycle * 7919

	for bug in _all_bugs():
		if not is_instance_valid(bug) or not (bug is Node2D):
			continue
		if bug.has_method("is_dead") and bool(bug.call("is_dead")):
			continue
		var pts = bug.get("points")
		if pts == null or pts.size() < 2:
			continue
		var outline = bug.get("heat_outline")
		if outline == null or outline.size() < 2:
			continue
		var bug_id : int = bug.get_instance_id()
		var is_ant : bool = bug.is_in_group("ant")
		var is_toad : bool = bug.is_in_group("toad")

		if is_toad:
			_draw_heat_toad(bug, pts, outline, xf, zoom, head_g, heat_r, speed_f, env, cycle, rng)
		elif is_ant:
			_draw_heat_ant(bug, pts, outline, xf, zoom, head_g, heat_r, speed_f, env, cycle, rng)
		else:
			_draw_heat_centipede(bug, pts, outline, xf, zoom, head_g, heat_r, speed_f, env, cycle, rng)

## 蜈蚣：身体左右缘每一段轮廓线、每条腿三段，各自独立判定。
func _draw_heat_centipede(bug: Node, pts, outline, xf: Transform2D, zoom: float,
		head_g: Vector2, heat_r: float, speed_f: float, env: float,
		cycle: int, rng: RandomNumberGenerator) -> void:
	var n : int = pts.size()
	var bug_id : int = bug.get_instance_id()

	# ---- 身体：左右缘每一段轮廓线各自独立判定 ----
	for i in range(n - 1):
		var li0 : int = i
		var li1 : int = i + 1
		var lmid : Vector2 = (bug.to_global(outline[li0]) + bug.to_global(outline[li1])) * 0.5
		var lkey : int = bug_id * 4096 + i
		var lst : Dictionary = _line_state(lkey, lmid, head_g, heat_r, speed_f, cycle, rng)
		if lst["on"]:
			var a : float = lst["a"] * env
			var pl := PackedVector2Array([
				xf * bug.to_global(outline[li0]), xf * bug.to_global(outline[li1]),
			])
			_stroke_outline(pl, COL_HEAT_ENEMY, a, 2.6)
		var ri0 : int = n + (n - 1 - i)
		var ri1 : int = n + (n - 1 - (i + 1))
		var rmid : Vector2 = (bug.to_global(outline[ri0]) + bug.to_global(outline[ri1])) * 0.5
		var rkey : int = bug_id * 4096 + 4096 + i
		var rst : Dictionary = _line_state(rkey, rmid, head_g, heat_r, speed_f, cycle, rng)
		if rst["on"]:
			var a2 : float = rst["a"] * env
			var pr := PackedVector2Array([
				xf * bug.to_global(outline[ri0]), xf * bug.to_global(outline[ri1]),
			])
			_stroke_outline(pr, COL_HEAT_ENEMY, a2, 2.6)

	# ---- 腿：每只脚的股/胫/跗三段，各自独立判定 ----
	_draw_heat_legs(bug, xf, head_g, heat_r, speed_f, env, cycle, rng)

	# ---- 头部热源 ----
	var head_on : Dictionary = _line_state(bug_id * 4096, bug.to_global(pts[0]), head_g, heat_r, speed_f, cycle, rng)
	if head_on["on"]:
		var ha : float = head_on["a"] * env
		var hp : Vector2 = xf * bug.to_global(pts[0])
		draw_circle(hp, maxf(3.0, zoom * 2.0), Color(COL_HEAT_ENEMY.r, COL_HEAT_ENEMY.g, COL_HEAT_ENEMY.b, ha * 0.25))
		draw_circle(hp, maxf(1.8, zoom * 1.2), Color(COL_HEAT_ENEMY.r, COL_HEAT_ENEMY.g, COL_HEAT_ENEMY.b, ha * 0.8))

## 蚂蚁：球形身体（头/胸/腹三个椭圆）用几何中心一个点判定，亮则整只一起亮，
## 不亮则整只身体不画红线。腿仍然逐段判定。
func _draw_heat_ant(bug: Node, pts, outline, xf: Transform2D, zoom: float,
		head_g: Vector2, heat_r: float, speed_f: float, env: float,
		cycle: int, rng: RandomNumberGenerator) -> void:
	var bug_id : int = bug.get_instance_id()
	# 判定点 = 整只蚂蚁的几何中心（世界坐标）。
	var center_local : Vector2 = bug.get("heat_center")
	var center_w : Vector2 = bug.to_global(center_local)

	# 身体：一个点判定，用专门的 key（id*4096+16384），亮的周期内整只身体一起亮。
	var body_st : Dictionary = _line_state(bug_id * 4096 + 16384, center_w, head_g, heat_r, speed_f, cycle, rng)
	if body_st["on"]:
		var ba : float = body_st["a"] * env
		# 三个椭圆轮廓是 heat_outline 里连续 60 个点（3×20），闭合画。
		var steps : int = 20
		for e in 3:
			var start : int = e * steps
			var ep := PackedVector2Array()
			for k in steps:
				ep.append(xf * bug.to_global(outline[start + k]))
			ep.append(xf * bug.to_global(outline[start]))
			_stroke_outline(ep, COL_HEAT_ENEMY, ba, 2.6)

	# 腿：逐段判定。
	_draw_heat_legs(bug, xf, head_g, heat_r, speed_f, env, cycle, rng)

	# 身体中心补一团淡热源。
	if body_st["on"]:
		var ba2 : float = body_st["a"] * env
		var cp : Vector2 = xf * center_w
		draw_circle(cp, maxf(2.5, zoom * 1.6), Color(COL_HEAT_ENEMY.r, COL_HEAT_ENEMY.g, COL_HEAT_ENEMY.b, ba2 * 0.22))
		draw_circle(cp, maxf(1.5, zoom * 1.0), Color(COL_HEAT_ENEMY.r, COL_HEAT_ENEMY.g, COL_HEAT_ENEMY.b, ba2 * 0.7))

## 蟾蜍：圆胖的一整只，身体用几何中心一个点判定，亮则所有闭合圈（身体/双眼/
## 耳后腺）一起亮；四条腿仍然逐段判定。
func _draw_heat_toad(bug: Node, pts, outline, xf: Transform2D, zoom: float,
		head_g: Vector2, heat_r: float, speed_f: float, env: float,
		cycle: int, rng: RandomNumberGenerator) -> void:
	var bug_id : int = bug.get_instance_id()
	var center_local : Vector2 = bug.get("heat_center")
	var center_w : Vector2 = bug.to_global(center_local)

	var body_st : Dictionary = _line_state(bug_id * 4096 + 20480, center_w, head_g, heat_r, speed_f, cycle, rng)
	if body_st["on"]:
		var ba : float = body_st["a"] * env
		var loops = bug.get("heat_body_loops")
		if loops != null:
			var idx : int = 0
			for n in loops:
				var ni : int = int(n)
				if ni <= 1 or idx + ni > outline.size():
					break
				var ep := PackedVector2Array()
				for k in ni:
					ep.append(xf * bug.to_global(outline[idx + k]))
				ep.append(xf * bug.to_global(outline[idx]))
				_stroke_outline(ep, COL_HEAT_ENEMY, ba, 2.6)
				idx += ni

		# 身体中心补一团淡热源。
		var cp : Vector2 = xf * center_w
		draw_circle(cp, maxf(3.5, zoom * 2.4), Color(COL_HEAT_ENEMY.r, COL_HEAT_ENEMY.g, COL_HEAT_ENEMY.b, ba * 0.22))
		draw_circle(cp, maxf(2.0, zoom * 1.4), Color(COL_HEAT_ENEMY.r, COL_HEAT_ENEMY.g, COL_HEAT_ENEMY.b, ba * 0.7))

	# 腿：逐段判定。
	_draw_heat_legs(bug, xf, head_g, heat_r, speed_f, env, cycle, rng)

## 腿的逐段红线判定，蜈蚣和蚂蚁共用。
func _draw_heat_legs(bug: Node, xf: Transform2D, head_g: Vector2, heat_r: float,
		speed_f: float, env: float, cycle: int, rng: RandomNumberGenerator) -> void:
	var bug_id : int = bug.get_instance_id()
	var chains = bug.get("heat_leg_chains")
	var slots : int = int(bug.get("heat_leg_slots"))
	if chains == null or slots <= 0:
		return
	# 有些生物（蟾蜍）静止时会把腿收起来，红线跟着一起淡掉，别让红线悬在空气里。
	var leg_a = bug.get("leg_alpha")
	var fade : float = 1.0 if leg_a == null else float(leg_a)
	if fade <= 0.04:
		return
	for k in slots:
		var i0 : int = k * 4
		if i0 + 3 >= chains.size():
			break
		var b : Vector2 = xf * bug.to_global(chains[i0])
		var kn : Vector2 = xf * bug.to_global(chains[i0 + 1])
		var an : Vector2 = xf * bug.to_global(chains[i0 + 2])
		var ft : Vector2 = xf * bug.to_global(chains[i0 + 3])
		var mid0 : Vector2 = (bug.to_global(chains[i0]) + bug.to_global(chains[i0 + 1])) * 0.5
		var s0 : Dictionary = _line_state(bug_id * 4096 + 8192 + k * 3 + 0, mid0, head_g, heat_r, speed_f, cycle, rng)
		var mid1 : Vector2 = (bug.to_global(chains[i0 + 1]) + bug.to_global(chains[i0 + 2])) * 0.5
		var s1 : Dictionary = _line_state(bug_id * 4096 + 8192 + k * 3 + 1, mid1, head_g, heat_r, speed_f, cycle, rng)
		var mid2 : Vector2 = (bug.to_global(chains[i0 + 2]) + bug.to_global(chains[i0 + 3])) * 0.5
		var s2 : Dictionary = _line_state(bug_id * 4096 + 8192 + k * 3 + 2, mid2, head_g, heat_r, speed_f, cycle, rng)
		var lw : float = 2.0
		_draw_leg_seg(b, kn, s0["on"], s0["a"] * env * fade, COL_HEAT_ENEMY, lw)
		_draw_leg_seg(kn, an, s1["on"], s1["a"] * env * fade, COL_HEAT_ENEMY, lw * 0.85)
		_draw_leg_seg(an, ft, s2["on"], s2["a"] * env * fade, COL_HEAT_ENEMY, lw * 0.8)

## 一根线的判定：返回 {on, a}。on 是本周期是否亮（掷骰结果，跨帧稳定），
## a 是亮度底数（不含 env 包络，调用方自己乘 env）。
func _line_state(key: int, wp: Vector2, head_g: Vector2, heat_r: float,
		speed_f: float, cycle: int, rng: RandomNumberGenerator) -> Dictionary:
	# 照亮区：白骨架已经在显形，红线不画。
	if Snake.light_at(wp) > 0.80:
		return {"on": false, "a": 0.0}
	var d : float = head_g.distance_to(wp)
	# 距离反比：贴脸几乎必亮，到感知边缘仍保留一点基础概率，别整片熄灭。
	var dist_f : float = clampf(1.0 - d / maxf(1.0, heat_r * 1.6), 0.0, 1.0)
	# 增强时抬高最低概率，并削弱速度惩罚，红线就更常亮。
	var floor_p : float = lerpf(0.12, 0.55, _boost)
	var spd : float = lerpf(speed_f, 1.0, _boost)
	var prob : float = clampf(floor_p + 0.82 * dist_f, 0.0, 1.0) * spd
	var st : Dictionary = _red_state.get(key, {})
	if st.is_empty() or int(st.get("cycle", -1)) != cycle:
		st = {"cycle": cycle, "on": rng.randf() < prob}
		_red_state[key] = st
	return {"on": bool(st["on"]), "a": lerpf(0.18, 0.55, _boost) + 0.45 * dist_f}

## 画一段腿线：亮了先铺淡光晕再压实线，暗了整段跳过。
func _draw_leg_seg(p0: Vector2, p1: Vector2, on: bool, a: float, col: Color, lw: float) -> void:
	if not on:
		return
	var w : float = lw * lerpf(1.0, 1.45, _boost)
	draw_line(p0, p1, Color(col.r, col.g, col.b, a * 0.20), w + 4.0, false)
	draw_line(p0, p1, Color(col.r, col.g, col.b, a), w, false)

## 每根线的红线状态变量：key = 线序号，值 = {cycle, on}。
## key 编码：低 12 位保留，bit 12 起分段。身体左缘 = id*4096+i，
## 右缘 = id*4096+4096+i，腿 = id*4096+8192+k*3+segidx。
var _red_state : Dictionary = {}

## 描边：先铺一圈更宽更淡的光晕，再压一条细实线。中间一直是空的。
func _stroke_outline(pts: PackedVector2Array, col: Color, alpha: float, width: float) -> void:
	if pts.size() < 2:
		return
	var w : float = width * lerpf(1.0, 1.45, _boost)
	draw_polyline(pts, Color(col.r, col.g, col.b, alpha * 0.16), w + 5.0, true)
	draw_polyline(pts, Color(col.r, col.g, col.b, alpha), w, true)

# ------------------------------- 猎物方向提示 -------------------------------
## 太久没捕到猎物时，屏幕边缘弹一个指向最近猎物的箭头，帮玩家找回方向。
## 只有猎物跑到屏幕外才显示（在屏幕里自己就能看见，不需要箭头）。
func _draw_prey_hint(xf: Transform2D) -> void:
	var bug : Node = _nearest_bug()
	if bug == null or not (bug is Node2D):
		return
	var pts = bug.get("points")
	if pts == null or pts.size() == 0:
		return
	var target : Vector2 = xf * bug.to_global(pts[0])
	var vp : Rect2 = get_viewport().get_visible_rect()
	var center : Vector2 = vp.size * 0.5
	# 猎物在屏幕内就直接看得到，不画边缘箭头。
	if vp.has_point(target):
		return
	var dir : Vector2 = target - center
	if dir.length() < 1.0:
		return
	var dirn : Vector2 = dir.normalized()
	# 沿中心→目标方向，取与留边矩形的交点，把箭头钉在屏幕边缘。
	var half : Vector2 = vp.size * 0.5 - Vector2(64.0, 64.0)
	var base : Vector2 = center + dir * _edge_scale(dir, half)

	# 脉冲：一亮一暗，落在全黑背景里也一眼能瞄到。
	var now : float = Time.get_ticks_msec() * 0.001
	var a : float = 0.6 + 0.4 * (0.5 + 0.5 * sin(now * 6.0))
	var col : Color = Color(1.0, 0.78, 0.22)   # 亮金，和红线 / 毒绿区分开

	var tip : Vector2 = base + dirn * 30.0
	var back : Vector2 = base - dirn * 10.0
	var perp : Vector2 = Vector2(-dirn.y, dirn.x)
	var wing : float = 20.0
	# 先铺深色描边，再压亮色实线，亮暗背景都读得清。
	for p0 in [back + perp * wing, back - perp * wing]:
		draw_line(p0, tip, Color(0.02, 0.02, 0.02, a * 0.75), 9.0, true)
	for p0 in [back + perp * wing, back - perp * wing]:
		draw_line(p0, tip, Color(col.r, col.g, col.b, a), 5.0, true)
	# 尾部一条短横杠当箭头底座。
	draw_line(back + perp * wing, back - perp * wing, Color(0.02, 0.02, 0.02, a * 0.75), 8.0, true)
	draw_line(back + perp * wing, back - perp * wing, Color(col.r, col.g, col.b, a), 4.5, true)

## 求从中心出发、沿 dir 方向到留边矩形边界的缩放系数。
func _edge_scale(dir: Vector2, half: Vector2) -> float:
	var s : float = 1e20
	if absf(dir.x) > 0.0001:
		s = minf(s, half.x / absf(dir.x))
	if absf(dir.y) > 0.0001:
		s = minf(s, half.y / absf(dir.y))
	return s

func _jitter(i: int, now: float, amp: float) -> Vector2:
	if amp <= 0.01:
		return Vector2.ZERO
	return Vector2(sin(now * 11.0 + float(i) * 1.7), cos(now * 9.3 + float(i) * 2.1)) * amp

# ------------------------------- 锁定目标 -------------------------------
func _draw_lock(head: Vector2, zoom: float, xf: Transform2D) -> void:
	var ready : bool = float(snake.venom) >= float(snake.venom_cost)
	var main : Color = COL_READY if ready else COL_DRY
	var tp : Vector2 = xf * Vector2(snake.lock_point)

	var now : float = Time.get_ticks_msec() * 0.001
	# 锁定圈刚出现时从 2.4 倍收到 1 倍，像"砰"一下扣上去。
	var age : float = clampf(now - _lock_born, 0.0, 0.22)
	var pop : float = lerpf(2.4, 1.0, ease(age / 0.22, 0.35))
	var r : float = maxf(20.0, zoom * 11.0) * pop

	# 1. 蛇头到目标的牵引线：起点实、靠目标虚，像根毒丝。
	var seg : int = 24
	for i in seg:
		if i % 2 == 1:
			continue
		var f0 : float = float(i) / float(seg)
		var f1 : float = float(i + 1) / float(seg)
		var la : float = lerpf(0.85, 0.30, f0)
		draw_line(head.lerp(tp, f0), head.lerp(tp, f1),
			Color(0.02, 0.02, 0.02, la * 0.55), 4.4, true)
		draw_line(head.lerp(tp, f0), head.lerp(tp, f1),
			Color(main.r, main.g, main.b, la), 2.2, true)

	# 2. 先铺一圈暗底，浅色蜈蚣背上也读得清。
	draw_arc(tp, r, 0.0, TAU, 48, Color(0.03, 0.03, 0.02, 0.45), 7.0, true)
	draw_arc(tp, r * 0.62, 0.0, TAU, 36, Color(0.03, 0.03, 0.02, 0.30), 5.0, true)

	# 3. 目标处的锁定环：外环四段缺口 + 反向内环，都在慢慢转。
	var spin : float = now * 1.7
	for k in 4:
		var a0 : float = spin + float(k) * TAU * 0.25
		draw_arc(tp, r, a0, a0 + 1.02, 20, Color(main.r, main.g, main.b, 0.95), 3.2, true)
		var b0 : float = -spin * 1.35 + float(k) * TAU * 0.25
		draw_arc(tp, r * 0.62, b0, b0 + 0.78, 14, Color(1.0, 1.0, 1.0, 0.55), 2.0, true)

	# 4. 四角括号，锁得更"硬"。
	var g : float = r * 1.58
	var arm : float = r * 0.5
	var bc := Color(main.r, main.g, main.b, 0.95)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var corner : Vector2 = tp + Vector2(g * sx, g * sy)
			draw_line(corner, corner - Vector2(arm * sx, 0.0), Color(0.02, 0.02, 0.02, 0.5), 5.2, true)
			draw_line(corner, corner - Vector2(0.0, arm * sy), Color(0.02, 0.02, 0.02, 0.5), 5.2, true)
			draw_line(corner, corner - Vector2(arm * sx, 0.0), bc, 2.6, true)
			draw_line(corner, corner - Vector2(0.0, arm * sy), bc, 2.6, true)

	# 5. 中心锚点
	draw_circle(tp, maxf(2.6, zoom * 1.1), Color(main.r, main.g, main.b, 0.95))

	# 6. 伤害预览，浮在圈上方，先垫暗描边
	var inject : float = clampf(float(snake.venom) / maxf(1.0, float(snake.venom_cost)), 0.0, 1.0)
	var dmg : String = "%d" % int(round(float(snake.get_attack()) * lerpf(0.55, 1.0, inject)))
	var dpos : Vector2 = tp + Vector2(-16.0, -g - 12.0)
	draw_string(FONT, dpos + Vector2(2.0, 2.0), dmg,
		HORIZONTAL_ALIGNMENT_CENTER, 32.0, 20, Color(0.02, 0.02, 0.02, 0.75))
	draw_string(FONT, dpos, dmg,
		HORIZONTAL_ALIGNMENT_CENTER, 32.0, 20, Color(main.r, main.g, main.b, 0.95))

	# 7. 蛇头这端：一个小准星，标出咬击起点。
	draw_circle(head, 3.2, Color(main.r, main.g, main.b, 0.9))
	draw_arc(head, r * 0.42, 0.0, TAU, 20, Color(main.r, main.g, main.b, 0.35), 1.6, true)

# ------------------------------- 没有目标 -------------------------------
func _draw_idle(head: Vector2, zoom: float) -> void:
	var now : float = Time.get_ticks_msec() * 0.001
	var pulse : float = 0.5 + 0.5 * sin(now * 4.0)
	var r : float = maxf(18.0, zoom * 8.0)
	var a : float = 0.45 + 0.30 * pulse
	var c := Color(COL_IDLE.r, COL_IDLE.g, COL_IDLE.b, a)
	var dark := Color(0.03, 0.03, 0.02, a * 0.45)

	# 深浅两层描边：地面亮的时候暗线托底，画面全黑的时候亮线浮出来。
	draw_arc(head, r, 0.0, TAU, 32, dark, 5.0, true)
	draw_arc(head, r, 0.0, TAU, 32, c, 2.2, true)
	draw_arc(head, r * 0.5, 0.0, TAU, 22, dark, 3.6, true)
	draw_arc(head, r * 0.5, 0.0, TAU, 22, Color(c.r, c.g, c.b, c.a * 0.7), 1.6, true)

	# 四个小刻线，像个空准星。
	for k in 4:
		var ang : float = float(k) * TAU * 0.25 + now * 0.7
		draw_line(head + Vector2.from_angle(ang) * (r * 0.5),
			head + Vector2.from_angle(ang) * r, dark, 3.6, true)
		draw_line(head + Vector2.from_angle(ang) * (r * 0.5),
			head + Vector2.from_angle(ang) * r, c, 1.8, true)

	var txt := tr("NO TARGET")
	var tpos : Vector2 = head + Vector2(-44.0, -r - 14.0)
	draw_string(_word_font_get(), tpos + Vector2(2.0, 2.0), txt,
		HORIZONTAL_ALIGNMENT_CENTER, 88.0, 17, Color(0.02, 0.02, 0.02, a * 0.85))
	draw_string(_word_font_get(), tpos, txt, HORIZONTAL_ALIGNMENT_CENTER, 88.0, 17, c)

# ------------------------------- 挥咬特效 -------------------------------
func _draw_fx(head: Vector2, zoom: float, xf: Transform2D) -> void:
	var p : float = 1.0 - float(snake.bite_fx_time) / FX_TIME
	var reach : float = float(snake.bite_range) * zoom
	var half : float = deg_to_rad(float(snake.bite_arc_deg)) * 0.5
	var dir : float = float(snake.bite_fx_dir)
	var hit : bool = bool(snake.bite_fx_hit)
	var point : Vector2 = xf * Vector2(snake.bite_fx_point)

	# 1. 挥过去的弧光：从左侧扫到右侧，很快，收得也快。
	var sweep_t : float = clampf(p / 0.35, 0.0, 1.0)
	var a_now : float = lerpf(dir - half, dir + half, sweep_t)
	var sweep_alpha : float = (1.0 - sweep_t) * 0.6
	var sweep := _arc_points(head, reach * 0.92, dir - half, a_now, 24)
	for i in range(sweep.size() - 1):
		var k : float = float(i) / float(maxi(1, sweep.size() - 2))
		draw_line(sweep[i], sweep[i + 1],
			Color(1.0, 0.96, 0.78, sweep_alpha * (0.3 + 0.7 * k)), 3.0, true)

	# 2. 命中 / 落空
	if hit:
		var t : float = clampf(p / 0.55, 0.0, 1.0)
		var rr : float = lerpf(4.0, maxf(22.0, 12.0 * zoom), t)
		var ra : float = (1.0 - t) * 0.9
		draw_circle(point, 3.0 * zoom, Color(1.0, 0.55, 0.30, ra))
		draw_arc(point, rr, 0.0, TAU, 30, Color(1.0, 0.70, 0.32, ra), 2.6, true)
		draw_arc(point, rr * 0.6, 0.0, TAU, 26, Color(0.80, 1.0, 0.45, ra * 0.8), 1.8, true)

		# 伤害数字上浮
		var rise : float = p * 46.0
		var na : float = 1.0 - smoothstep(0.6, 1.0, p)
		var txt : String = "%d" % int(round(float(snake.bite_fx_damage)))
		var dpos : Vector2 = point + Vector2(-10.0, -30.0 - rise)
		# 先垫一层暗色描边，落在亮背景上也读得清。
		draw_string(FONT, dpos + Vector2(2, 2), txt,
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 30, Color(0.05, 0.03, 0.02, na * 0.8))
		draw_string(FONT, dpos, txt,
			HORIZONTAL_ALIGNMENT_CENTER, 40.0, 30, Color(1.0, 0.86, 0.42, na))
		if float(snake.bite_fx_poison) > 0.05:
			draw_string(_word_font_get(), point + Vector2(-10.0, -12.0 - rise * 0.8), tr("VENOM"),
				HORIZONTAL_ALIGNMENT_CENTER, 52.0, 15, Color(0.66, 1.0, 0.45, na * 0.9))
	else:
		# 空咬：射程内没目标，咬了个空，画个灰叉。
		var ca : float = 1.0 - smoothstep(0.4, 1.0, p)
		var s : float = 12.0
		var c := Color(COL_MISS.r, COL_MISS.g, COL_MISS.b, ca * 0.9)
		draw_line(point + Vector2(-s, -s), point + Vector2(s, s), Color(0.02, 0.02, 0.02, ca * 0.5), 5.0, true)
		draw_line(point + Vector2(-s, s), point + Vector2(s, -s), Color(0.02, 0.02, 0.02, ca * 0.5), 5.0, true)
		draw_line(point + Vector2(-s, -s), point + Vector2(s, s), c, 3.0, true)
		draw_line(point + Vector2(-s, s), point + Vector2(s, -s), c, 3.0, true)
		var txt := tr("NO TARGET")
		draw_string(_word_font_get(), point + Vector2(-44.0, -22.0) + Vector2(2, 2), txt,
			HORIZONTAL_ALIGNMENT_CENTER, 88.0, 16, Color(0.02, 0.02, 0.02, ca * 0.8))
		draw_string(_word_font_get(), point + Vector2(-44.0, -22.0), txt,
			HORIZONTAL_ALIGNMENT_CENTER, 88.0, 16, c)

# ------------------------------- 几何工具 -------------------------------
func _arc_points(center: Vector2, radius: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a : float = lerpf(a0, a1, float(i) / float(steps))
		pts.append(center + Vector2.from_angle(a) * radius)
	return pts
