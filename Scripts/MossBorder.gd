class_name MossBorder
extends Control

## 沿按钮边框整片蔓延的苔藓（纯程序化绘制，无贴图）。
##
## 用法：new() 出来挂到按钮下面，它会自己铺满按钮并向外扩一圈；
## 容器排好版后调用 rebuild()，之后 grow(true / false) 控制铺开与收回。
##
## 生长不是逐个斑块冒出来，而是一整片连续的苔藓从边框顶部某点
## 向两侧同时推进、最后绕满一圈。边缘是毛刺状起伏，内部是深浅不一的绿，
## 深浅之间是顶点色插值，所以没有"一片片叶子"的断口。

## 苔藓带的总厚度（像素，跨在边框上，向外多、向内少）。
@export_range(6.0, 48.0, 0.5) var band : float = 26.0
## 从无到铺满一圈需要多少秒。
@export_range(0.05, 2.0, 0.01) var grow_time : float = 0.52
## 收回需要多少秒。
@export_range(0.05, 1.0, 0.01) var fade_time : float = 0.16
## 随机种子。换个数就是另一片苔藓。
@export var seed_value : int = 20261017

## 苔藓本体色的三档，按周长噪声在两两之间插值。
const DEEP := Color(0.08, 0.13, 0.05, 0.97)
const MID := Color(0.16, 0.24, 0.09, 0.96)
const LIT := Color(0.31, 0.38, 0.15, 0.92)
## 垂到按钮底部的苔藓会沉成这个偏蓝的墨色，形成自上而下的色相偏移。
const COLD := Color(0.05, 0.075, 0.135, 0.97)
## 苔藓底下渗开的那层暗绿水痕。
const WET := Color(0.08, 0.13, 0.05, 0.34)
const MOLD_LIGHT := Color(0.74, 0.77, 0.63, 0.50)
const MOLD_DARK := Color(0.09, 0.11, 0.07, 0.72)
const FIBER_COLOR := Color(0.58, 0.68, 0.42, 0.30)

var _progress : float = 0.0
var _target : float = 0.0
var _rect : Rect2 = Rect2()

# 沿周长的一圈采样点（首尾重合），全部是局部坐标 / 标量，绘制时直接用。
var _pts := PackedVector2Array()
var _nrms := PackedVector2Array()
var _ts := PackedFloat32Array()   # 周长参数 0..1
var _us := PackedFloat32Array()   # 相对起点的有符号偏移 -0.5..0.5
var _outs := PackedFloat32Array() # 外沿偏移
var _inns := PackedFloat32Array() # 内沿偏移
var _deps := PackedFloat32Array() # 绕满后向按钮正面（内部）侵蚀的深度
var _cols := PackedColorArray()   # 该点的主体颜色

var _mold : Array[Dictionary] = []
var _fibers : Array[Dictionary] = []

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 自己铺满父按钮并外扩一圈，父级只要 add_child 就行。
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var pad : float = band + 6.0
	offset_left = -pad
	offset_top = -pad
	offset_right = pad
	offset_bottom = pad
	set_process(false)
	resized.connect(_on_resized)

func _on_resized() -> void:
	if size.x > 20.0 and size.y > 20.0:
		rebuild()

## 按当前尺寸重新生成整片苔藓（布局变化后要再调一次）。
func rebuild() -> void:
	var inset : float = band + 4.0
	if size.x <= inset * 2.0 + 8.0 or size.y <= inset * 2.0 + 8.0:
		return
	_rect = Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0)

	_pts.clear()
	_nrms.clear()
	_ts.clear()
	_us.clear()
	_outs.clear()
	_inns.clear()
	_deps.clear()
	_cols.clear()
	_mold.clear()
	_fibers.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var per : float = 2.0 * (_rect.size.x + _rect.size.y)
	var count : int = clampi(int(per / 3.0), 48, 900)
	var origin : float = 0.16  # 从顶边偏左开始爬
	var ph0 : float = rng.randf() * TAU
	var ph1 : float = rng.randf() * TAU
	var ph2 : float = rng.randf() * TAU
	var ph3 : float = rng.randf() * TAU

	# 生成 count + 1 个点，s 从 0 到 1，首尾落在同一位置，绕满时能无缝闭合。
	for i in count + 1:
		var s : float = float(i) / float(count)
		var t : float = fposmod(origin + s, 1.0)
		var edge : Dictionary = _edge_info(_rect, t)
		var p : Vector2 = edge["p"]
		var nrm : Vector2 = edge["n"]

		# 低频决定整条苔藓哪段厚哪段薄，高频做边缘毛刺。
		var thick : float = 0.66 + 0.24 * sin(t * TAU * 2.0 + ph0) + 0.13 * sin(t * TAU * 5.0 + ph1)
		var rough : float = 0.46 * sin(t * TAU * 11.0 + ph2) + 0.32 * sin(t * TAU * 23.0 + ph3) + 0.22 * sin(t * TAU * 47.0 + ph0)
		var wb : float = band * clampf(thick, 0.25, 1.22) * (1.0 + 0.16 * rough)

		_pts.append(p)
		_nrms.append(nrm)
		_ts.append(t)
		_us.append(s - 0.5)
		_outs.append(wb * (0.58 + 0.24 * rough) + 2.0)
		_inns.append(-wb * (0.12 + 0.10 * rough))

		# 绕满之后再往按钮正面（内部）吃进去的深度：低频噪声决定哪一段爬得深。
		# 上限卡在正面可用高度的 34%，不会把按钮文字整个吞掉。
		var deepn : float = (0.5 + 0.36 * sin(t * TAU * 3.0 + ph2 * 2.1) * sin(t * TAU * 7.0 + ph0)
			+ 0.18 * sin(t * TAU * 13.0 + ph3))
		deepn = pow(clampf(deepn, 0.0, 1.0), 2.6)
		# 内沿的细碎齿，幅度压小一点，让低频的"大块深浅"主导形状。
		var jag : float = 1.0 + (0.08 + 0.07 * sin(t * TAU * 5.0 + ph3)) * sin(t * TAU * 41.0 + ph1) \
			+ 0.06 * sin(t * TAU * 89.0 + ph2)
		# 顶边垂得最深（苔藓从上往下漫过来），其余三边收敛些。
		var cap : float = minf(_rect.size.y * (0.26 if nrm == Vector2.UP else 0.10), _rect.size.x * 0.07)
		# 深度直接取上限 × 噪声，不再截断，否则深的几块会被削平成一样高的齿。
		# deepn 接近 0 的段落完全不往正面走，好让金色板面从缺口里透出来。
		_deps.append(cap * clampf(deepn * jag, 0.0, 1.12))

		# 颜色沿周长缓慢过渡：深绿 → 中绿 → 亮黄绿，再回到深绿。
		var m : float = (0.5 + 0.30 * sin(t * TAU * 3.0 + ph1 * 1.7) + 0.20 * sin(t * TAU * 9.0 + ph3)
			+ 0.10 * sin(t * TAU * 27.0 + ph0))
		m = clampf(m, 0.0, 1.0)
		m = pow(m, 1.35)
		var c : Color
		if m < 0.5:
			c = DEEP.lerp(MID, m * 2.0)
		else:
			c = MID.lerp(LIT, (m - 0.5) * 2.0)
		# 自上而下往蓝黑沉：顶部还是苔绿，越靠底部色相越冷越暗。
		var vv : float = clampf((p.y - _rect.position.y) / maxf(_rect.size.y, 1.0), 0.0, 1.0)
		vv = pow(vv, 1.1) * 0.95
		c = Color(lerpf(c.r, COLD.r, vv), lerpf(c.g, COLD.g, vv), lerpf(c.b, COLD.b, vv), c.a)
		_cols.append(c)

	# 霉点：少量小白斑与深色孢子，压在苔藓上。
	var mold_count : int = maxi(8, int(float(count) * 0.10))
	for i in mold_count:
		var s : float = rng.randf()
		var t : float = fposmod(origin + s, 1.0)
		var edge : Dictionary = _edge_info(_rect, t)
		var nrm : Vector2 = edge["n"]
		_mold.append({
			"c": edge["p"] + nrm * rng.randf_range(-0.34, 0.42) * band,
			"r": rng.randf_range(1.0, 2.6),
			"u": absf(s - 0.5),
			"col": MOLD_LIGHT if rng.randf() < 0.6 else MOLD_DARK,
		})

	# 菌丝 / 绒毛：从苔藓外沿往外伸的短线。
	var fiber_count : int = maxi(10, int(float(count) * 0.18))
	for i in fiber_count:
		var s : float = rng.randf()
		var t : float = fposmod(origin + s, 1.0)
		var edge : Dictionary = _edge_info(_rect, t)
		var nrm : Vector2 = edge["n"]
		_fibers.append({
			"a": edge["p"] + nrm * rng.randf_range(0.46, 0.70) * band,
			"d": nrm.rotated(rng.randf_range(-0.9, 0.9)) * rng.randf_range(3.0, 11.0),
			"u": absf(s - 0.5),
		})

	queue_redraw()

## 开始长出来 / 收回。
func grow(on: bool) -> void:
	_target = 1.0 if on else 0.0
	set_process(true)

func is_grown() -> bool:
	return _progress >= 0.999

## 边框上的点与外法线。t 沿左上 → 右 → 下 → 左 顺时针。
func _edge_info(rect: Rect2, t: float) -> Dictionary:
	var w : float = rect.size.x
	var h : float = rect.size.y
	var d : float = fposmod(t, 1.0) * 2.0 * (w + h)
	if d <= w:
		return {"p": rect.position + Vector2(d, 0.0), "n": Vector2.UP}
	d -= w
	if d <= h:
		return {"p": rect.position + Vector2(w, d), "n": Vector2.RIGHT}
	d -= h
	if d <= w:
		return {"p": rect.position + Vector2(w - d, h), "n": Vector2.DOWN}
	d -= w
	return {"p": rect.position + Vector2(0.0, h - d), "n": Vector2.LEFT}

## 推进前沿的收窄系数：1 = 全宽，0 = 收成尖。
## closed 为 1 时不收窄（已经绕满一圈，两端要接上）。
func _taper(i: int, cnt: int, tl: float, closed: float) -> float:
	var d : float = minf(float(i) + 0.5, float(cnt - 1 - i) + 0.5)
	var k : float = clampf(d / maxf(tl, 0.001), 0.0, 1.0)
	k = 1.0 - pow(1.0 - k, 2.2)
	return lerpf(1.0, k, 1.0 - closed)

func _process(delta: float) -> void:
	var speed : float = (1.0 / maxf(grow_time, 0.01)) if _target > _progress else (1.0 / maxf(fade_time, 0.01))
	_progress = move_toward(_progress, _target, speed * delta)
	queue_redraw()
	if is_equal_approx(_progress, _target):
		set_process(false)

func _draw() -> void:
	if _progress <= 0.002 or _pts.is_empty():
		return

	var n : int = _pts.size()
	var reach : float = _progress * 0.5
	# 快绕满时停止端部收窄，让首尾无缝接上。
	var closed : float = clampf((_progress - 0.84) / 0.16, 0.0, 1.0)

	# 可见区间：u 沿周单调（-0.5 → +0.5），所以可见集永远是一段连续弧。
	var lo : int = n
	var hi : int = -1
	for k in n:
		var fr : float = reach + 0.030 * sin(_ts[k] * TAU * 7.0 + 1.7) + 0.017 * sin(_ts[k] * TAU * 19.0 + 4.2)
		if absf(_us[k]) <= fr:
			if k < lo:
				lo = k
			hi = k
	if hi - lo < 2:
		return

	var cnt : int = hi - lo + 1
	var tl : float = clampf(float(cnt) * 0.30, 2.0, 9.0)
	# 绕满边框之后，苔藓继续往按钮正面爬进去（这一段单独推进，晚半拍）。
	var creep : float = smoothstep(0.42, 0.98, _progress)

	var wts := PackedFloat32Array()
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var ocols := PackedColorArray()
	var icols := PackedColorArray()
	wts.resize(cnt)

	for j in cnt:
		var k : int = lo + j
		var w : float = _taper(j, cnt, tl, closed)
		wts[j] = w
		var p : Vector2 = _pts[k]
		var nn : Vector2 = _nrms[k]
		outer.append(p + nn * maxf(_outs[k] * w, 0.0))
		# 内沿 = 边框带的一点点内侵 + 绕满后继续向正面吃的深度。
		var dep : float = _deps[k] * creep * (0.30 + 0.70 * w)
		inner.append(p + nn * (minf(_inns[k] * w, 0.0) - dep))
		ocols.append(_cols[k])
		# 越往正面里面越薄越暗，并且半透——像贴在板面上的一层膜，而不是贴纸。
		var ic : Color = _cols[k].darkened(0.16)
		ic.a *= 0.88
		icols.append(ic)

	# 底层水痕：比苔藓本身再松一圈，边缘就渗进底色里了。
	# 这一层不跟着往正面深处走，否则整个按钮会被罩成一片死绿。
	var wet := PackedVector2Array()
	for j in cnt:
		var k : int = lo + j
		wet.append(_pts[k] + _nrms[k] * (_outs[k] * wts[j] * 1.26 + 3.0))
	for j in range(cnt - 1, -1, -1):
		var k : int = lo + j
		var dep : float = _deps[k] * creep * 0.35
		wet.append(_pts[k] + _nrms[k] * (minf(_inns[k] * wts[j], 0.0) - dep - 2.0))
	draw_colored_polygon(wet, WET)

	# 主体：一条四边形带，拆成三角形一次性提交。
	# 整块多边形在内沿凹进按钮正面后会自交，draw_polygon 的三角剖分直接失败；
	# 逐段 draw_polygon 也会因为拐角处的退化四边形报错，所以走三角形数组。
	var tp := PackedVector2Array()
	var tc := PackedColorArray()
	var ti := PackedInt32Array()
	tp.resize(cnt * 2)
	tc.resize(cnt * 2)
	for j in cnt:
		tp[j * 2] = outer[j]
		tp[j * 2 + 1] = inner[j]
		tc[j * 2] = ocols[j]
		tc[j * 2 + 1] = icols[j]
	ti.resize((cnt - 1) * 6)
	for j in cnt - 1:
		var a : int = j * 2
		var b : int = a + 2
		var c : int = a + 3
		var d : int = a + 1
		ti[j * 6] = a
		ti[j * 6 + 1] = b
		ti[j * 6 + 2] = c
		ti[j * 6 + 3] = a
		ti[j * 6 + 4] = c
		ti[j * 6 + 5] = d
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), ti, tp, tc)

	# 霉点
	for md in _mold:
		var g : float = clampf((reach - float(md["u"])) / 0.06, 0.0, 1.0)
		if g <= 0.0:
			continue
		var col : Color = md["col"]
		col.a *= g
		draw_circle(md["c"], float(md["r"]) * ease(g, 0.6), col)

	# 菌丝
	for fb in _fibers:
		var g : float = clampf((reach - float(fb["u"])) / 0.05, 0.0, 1.0)
		if g <= 0.0:
			continue
		var a : Vector2 = fb["a"]
		var col := FIBER_COLOR
		col.a *= g
		draw_line(a, a + Vector2(fb["d"]) * ease(g, 0.6), col, 1.0, true)
