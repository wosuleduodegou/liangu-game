extends CanvasLayer

## 屏幕左边的气泡通知（Autoload 名：Toast）。
##
## 任何脚本里都能直接调，不需要先拿节点：
##
##   Toast.push("你咬断了一条腿")
##   Toast.good("TRAIT UNLOCKED")        # 绿：正面
##   Toast.warn("STAMINA LOW")           # 黄：警告
##   Toast.danger("LIMB DESTROYED")      # 红：危险
##   Toast.push("+3 VENOM", "good", "venom")   # 同 key 不堆叠，原地续命换字
##   Toast.kill("ANT")                   # 击杀播报：击杀蚂蚁 ×3 · 剩余 6
##
## 表现：贴着屏幕左边缘，新气泡从下往上浮出来，旧的被顶上去；
## 到点自己淡出，腾位置时整条栈平滑上移，不会跳。
##
## 文本会自动走一次 tr()，所以直接写英文 key 就行，切中文时自动出中文。

signal pushed(text: String, kind: String)

# ------------------------------- 布局 -------------------------------
const LAYER := 95            # 在玩法/状态页(90)之上，菜单(100)之下
const MAX_STACK := 5         # 同时最多几条，超了最早那条提前退场
const STACK_GAP := 10.0      # 气泡之间的竖直间距
const TOP_GUARD := 8.0       # 栈顶最少留出的上边距（防止叠太高被裁字）
const MIN_WIDTH := 150.0
const MAX_WIDTH := 380.0     # 超过就换行，不会横着长满半屏
const STRIPE := 5.0          # 左侧色条宽度
const SEP := 12.0            # 色条与文字的间距
const PAD_RIGHT := 18.0      # 右内边距
const PAD_V := 12.0          # 上下内边距
const RADIUS := 10           # 右侧圆角（左侧贴屏，直角）
const FONT_SIZE := 22

## 还算「活物」的分组。蛇自己不在里面，所以击杀数 + 剩余数 = 开局总数。
const ENEMY_GROUPS : PackedStringArray = ["ant", "centipede", "toad"]

# ------------------------------- 时序 -------------------------------
const POP_IN := 0.34         # 浮出来的时长
const POP_RISE := 34.0       # 从低多少像素处往上浮
const SHIFT_TIME := 0.22     # 被顶上去的滑动时长
const FADE_OUT := 0.30       # 淡出时长
const BASE_LIFE := 2.8       # 基础停留
const CHAR_LIFE := 0.045     # 每多一个字多停多久
const LIFE_MIN := 2.0
const LIFE_MAX := 6.5

# ------------------------------- 配色 -------------------------------
## 左侧色条：区分消息性质，其余部分保持陶土底 + 暖米色描边。
const KIND_COLORS := {
	"info": Color(0.78, 0.72, 0.56),
	"good": Color(0.58, 0.84, 0.34),
	"warn": Color(0.88, 0.68, 0.26),
	"danger": Color(0.82, 0.28, 0.20),
}
const BG := Color(0.125, 0.105, 0.085, 0.96)
const BORDER := Color(0.63, 0.556, 0.44, 0.52)
const TEXT_COLOR := Color(0.95, 0.90, 0.78)

## 栈底落在屏幕的哪个高度（从顶部量）：0 = 最顶，0.5 = 竖直居中，1 = 最底。
## 默认 0.62：单条时略低于中线，叠到四五条时整组大致落在左侧正中。
var anchor_ratio : float = 0.62:
	set(value):
		anchor_ratio = clampf(value, 0.0, 1.0)
		if _root != null:
			_restack()

## 在 anchor_ratio 基础上再上下挪几像素（正数往下）。想让栈沉到左下角就用负值。
var anchor_offset : float = 0.0:
	set(value):
		anchor_offset = value
		if _root != null:
			_restack()

## 每条形如 {panel, stripe, label, key, token, target}
var _items : Array[Dictionary] = []
## 本局各生物的击杀数。同种合并成一条气泡，免得捕猎碾一片时刷屏。
var _kill_counts : Dictionary = {}
var _root : Control
var _font : Font


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "Stack"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	get_viewport().size_changed.connect(func() -> void: _restack())
	# 换场景时把旧气泡收掉，免得上一关的话飘到下一关上。
	if get_tree().has_signal("scene_changed"):
		get_tree().connect("scene_changed", _on_scene_changed)
	# 切语言时把已经挂着的击杀气泡重拼，不然会停在旧语言上。
	var gs : Node = get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_signal("language_changed"):
		gs.connect("language_changed", _on_language_changed)


# ----------------------------- 对外接口 -----------------------------

## 推一条通知。kind: info / good / warn / danger。
## key 非空时，同 key 的气泡不会重复堆叠，而是原地改字并重新计时。
func push(text: String, kind: String = "info", key: String = "") -> void:
	var body : String = tr(text)
	if body.strip_edges() == "":
		return

	# 同 key：复用原来那个气泡，换字 + 续命，位置不动。
	if key != "":
		for e in _items:
			if String(e.get("key", "")) == key and is_instance_valid(e.get("panel")):
				_refresh(e, body, kind)
				return

	var entry := _make_entry(body, kind, key)
	_push_entry(entry, body, kind)


## 新条目进栈 + 浮入 + 开始计时（push 和 kill 共用）。
func _push_entry(entry: Dictionary, body: String, kind: String = "info") -> void:
	_items.append(entry)
	pushed.emit(body, kind)

	# 超出上限：最老的那条先退场（从 _items 摘掉，后面重排会自动补位）。
	while _items.size() > MAX_STACK:
		var old : Dictionary = _items[0]
		_items.remove_at(0)
		_fade_out(old, 0.16)

	await get_tree().process_frame
	var panel : Control = entry.get("panel")
	# 同一帧连推太多时，这条可能已经被 MAX_STACK 顶掉并开始退场了，
	# 那就别再让它浮进来（否则会和淡出抢同一批属性）。
	if not is_instance_valid(panel) or not _items.has(entry):
		return
	# 这一帧容器算完高度，收口一次尺寸，再开始排位置。
	_fit_height(panel)
	_restack(panel)
	_pop_in(entry)
	_start_life(entry, body)


func info(text: String, key: String = "") -> void:
	push(text, "info", key)


func good(text: String, key: String = "") -> void:
	push(text, "good", key)


func warn(text: String, key: String = "") -> void:
	push(text, "warn", key)


func danger(text: String, key: String = "") -> void:
	push(text, "danger", key)


## 击杀播报。feed_name 传英文 key（ANT / CENTIPEDE / TOAD），切中文自动出中文。
## 同一种生物共用一条气泡：原地把数字改大 + 续命，不会一秒钟刷出五六条。
## 文本尾部带「· 剩余 N」，让玩家知道还差几只；场上清空时显示「清场完毕」。
func kill(feed_name: String) -> void:
	if feed_name.strip_edges() == "":
		return
	var n : int = int(_kill_counts.get(feed_name, 0)) + 1
	_kill_counts[feed_name] = n
	var left : int = alive_count()

	# 剩余数只挂在最新这一条上。否则三个种类各显示一遍「剩余 4」，
	# 并排看着像重复的 bug，读起来也吵。
	for e in _items:
		var f : String = String(e.get("feed", ""))
		if f != "" and f != feed_name:
			e["left"] = -1
			_set_text(e, _kill_body(f, int(_kill_counts.get(f, 1)), -1))

	var key : String = "kill:" + feed_name
	# 同 key 已挂着就原地改字；顺便记下是哪一种、剩几只，切语言时好重拼。
	for e in _items:
		if String(e.get("key", "")) == key and is_instance_valid(e.get("panel")):
			e["feed"] = feed_name
			e["left"] = left
			_refresh(e, _kill_body(feed_name, n, left), "good")
			return

	var body : String = _kill_body(feed_name, n, left)
	var entry := _make_entry(body, "good", key)
	entry["feed"] = feed_name
	entry["left"] = left
	_push_entry(entry, body, "good")


## 「击杀蚂蚁 ×3 · 剩余 6」/「KILLED ANT ×3 · 6 LEFT」的文本。
## 计数 > 1 才显示；left < 0 表示不知道剩多少，就不写尾巴。
## 中文不加空格（击杀蚂蚁），英文才需要（KILLED ANT）。
func _kill_body(feed_name: String, n: int, left: int = -1) -> String:
	var zh : bool = TranslationServer.get_locale().begins_with("zh")
	var body : String = "%s%s%s" % [tr("KILLED"), "" if zh else " ", tr(feed_name)]
	if n > 1:
		body = "%s ×%d" % [body, n]
	if left == 0:
		body = "%s · %s" % [body, tr("ALL CLEAR")]
	elif left > 0:
		# 模板走翻译表：key 是英文语序 "4 LEFT"，中文映射成 "剩余 4"。
		body = "%s · %s" % [body, tr("%d LEFT") % left]
	return body


## 场上还剩多少活物。死了 / 正在消失的都不算，所以最后一只倒下时返回 0。
func alive_count() -> int:
	var n : int = 0
	var tree := get_tree()
	if tree == null:
		return 0
	for g in ENEMY_GROUPS:
		for node in tree.get_nodes_in_group(g):
			if not is_instance_valid(node) or node.is_queued_for_deletion():
				continue
			if node.has_method("is_dead") and bool(node.call("is_dead")):
				continue
			n += 1
	return n


## 当前某种生物已经报了几条（调试 / 结算用）。
func kill_count(feed_name: String) -> int:
	return int(_kill_counts.get(feed_name, 0))


## 清掉击杀计数（换关时自动调用，也可以手动重置）。
func reset_kills() -> void:
	_kill_counts.clear()


## 立刻清空（淡出，不是瞬删）。
func clear() -> void:
	for e in _items:
		_fade_out(e, 0.15)
	_items.clear()


## 按比例指定栈底的位置（从顶部量）：0 = 最顶，0.5 = 竖直居中，1 = 最底。
## Toast.set_anchor_ratio(0.92) 就是「沉到左下角往上长」。
func set_anchor_ratio(ratio: float) -> void:
	anchor_ratio = ratio


# ----------------------------- 构建气泡 -----------------------------

func _make_entry(text: String, kind: String, key: String) -> Dictionary:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style())

	var y := _font_get()
	var text_w : float = y.get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var width : float = clampf(
		text_w + STRIPE + SEP + PAD_RIGHT + 2.0, MIN_WIDTH, MAX_WIDTH)
	panel.custom_minimum_size.x = width

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(SEP))
	panel.add_child(row)

	# 左侧色条：贴屏那一侧，读起来像从屏幕边上拉出来的标签。
	var stripe := ColorRect.new()
	stripe.color = KIND_COLORS.get(kind, KIND_COLORS["info"])
	stripe.custom_minimum_size = Vector2(STRIPE, 0.0)
	stripe.size_flags_vertical = Control.SIZE_FILL
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stripe)

	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", y)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.custom_minimum_size.x = width - STRIPE - SEP - PAD_RIGHT
	row.add_child(label)

	_root.add_child(panel)
	return {
		"panel": panel,
		"stripe": stripe,
		"label": label,
		"key": key,
		"token": 0,
		"target": Vector2.ZERO,
	}


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG
	sb.border_color = BORDER
	sb.set_border_width_all(1)
	# 左侧贴着屏幕边缘，所以只给右侧圆角。
	sb.corner_radius_top_left = 0
	sb.corner_radius_bottom_left = 0
	sb.corner_radius_top_right = RADIUS
	sb.corner_radius_bottom_right = RADIUS
	sb.shadow_color = Color(0.0, 0.0, 0.0, 0.38)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(3.0, 4.0)
	# 色条自己顶到最左边，所以左内边距留 0。
	sb.content_margin_left = 0.0
	sb.content_margin_right = PAD_RIGHT
	sb.content_margin_top = PAD_V
	sb.content_margin_bottom = PAD_V
	return sb


func _font_get() -> Font:
	if _font == null:
		var gs := get_node_or_null("/root/GameSettings")
		if gs != null and gs.has_method("ui_font"):
			_font = gs.call("ui_font") as Font
	if _font == null:
		_font = ThemeDB.fallback_font
	return _font


## 长句换行后高度会变，进树一帧后用实测高度收口（涨了缩了都要跟）。
## 只往大调是不行的：换字/换语言后宽度变宽，原本折成两行的会回到一行，
## 高度必须跟着收回去，否则气泡会一直胖着。
func _fit_height(panel: Control) -> void:
	var need : float = panel.get_combined_minimum_size().y
	if need > 1.0 and absf(panel.size.y - need) > 0.5:
		panel.size.y = need


# ----------------------------- 排位置 -----------------------------

## 从下往上排：最新的在最下面，越老越靠上。
## except 是刚加进来那条，它自己走浮入动画，这里先不挪它。
func _restack(except: Control = null) -> void:
	# 先摘掉已经不存在的（场景重载、外部释放之类），否则会留出空档。
	for i in range(_items.size() - 1, -1, -1):
		if not is_instance_valid(_items[i].get("panel")):
			_items.remove_at(i)
	var y := _view_height() * anchor_ratio + anchor_offset
	# 叠得太高会顶出屏幕：宁可整体往下压，也不裁掉字。
	var total : float = 0.0
	for e in _items:
		var p : Control = e.get("panel")
		if is_instance_valid(p):
			_fit_height(p)
			total += p.size.y
	if _items.size() > 1:
		total += STACK_GAP * float(_items.size() - 1)
	if y - total < TOP_GUARD:
		y = TOP_GUARD + total
	for i in range(_items.size() - 1, -1, -1):
		var e : Dictionary = _items[i]
		var panel : Control = e.get("panel")
		if not is_instance_valid(panel):
			continue
		y -= panel.size.y
		e["target"] = Vector2(0.0, y)
		if panel != except:
			_move_to(panel, e["target"], SHIFT_TIME)
		y -= STACK_GAP


## 浮入动画与「被顶上去」的位移动画会抢 position / modulate 的同一条属性，
## 重排或退场前先把浮入那支停掉并把状态归位，否则会僵在半透明 / 半个缩放。
func _kill_pop(panel: Control) -> void:
	if not panel.has_meta("pop_tw"):
		return
	var tw = panel.get_meta("pop_tw")
	if tw is Tween and (tw as Tween).is_valid():
		(tw as Tween).kill()
	panel.remove_meta("pop_tw")
	panel.modulate.a = 1.0
	panel.scale = Vector2.ONE


func _pop_in(e: Dictionary) -> void:
	var panel : Control = e.get("panel")
	var target : Vector2 = e.get("target")
	panel.pivot_offset = Vector2(0.0, panel.size.y * 0.5)
	panel.position = Vector2(target.x, target.y + POP_RISE)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.94, 0.94)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position", target, POP_IN)
	tw.tween_property(panel, "scale", Vector2.ONE, POP_IN)
	tw.tween_property(panel, "modulate:a", 1.0, POP_IN * 0.55)
	panel.set_meta("pop_tw", tw)


func _move_to(panel: Control, target: Vector2, dur: float) -> void:
	_kill_pop(panel)
	if panel.has_meta("move_tw"):
		var old = panel.get_meta("move_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "position", target, dur)
	panel.set_meta("move_tw", tw)


# ----------------------------- 生命周期 -----------------------------

## 每个条目一个 token：被同 key 续命后，老的计时器回来会发现自己过期了。
func _start_life(e: Dictionary, text: String) -> void:
	var life : float = clampf(
		BASE_LIFE + float(text.length()) * CHAR_LIFE, LIFE_MIN, LIFE_MAX)
	var token : int = int(e.get("token", 0)) + 1
	e["token"] = token
	await get_tree().create_timer(life, true).timeout
	if int(e.get("token", -1)) != token:
		return
	if not is_instance_valid(e.get("panel")):
		return
	_drop(e, FADE_OUT)


func _refresh(e: Dictionary, text: String, kind: String) -> void:
	var stripe : ColorRect = e.get("stripe")
	if is_instance_valid(stripe):
		stripe.color = KIND_COLORS.get(kind, KIND_COLORS["info"])
	_set_text(e, text)
	# 续命：让之前那次计时作废，重新排一次。
	_start_life(e, text)
	pushed.emit(text, kind)


## 只换文字（宽度跟着重算、重排），不碰停留计时。
func _set_text(e: Dictionary, text: String) -> void:
	var label : Label = e.get("label")
	var panel : Control = e.get("panel")
	if not is_instance_valid(panel):
		return
	if not is_instance_valid(label):
		return
	label.text = text
	# 换字了，宽度也要跟着重算，不然长句会挤成一条或留一大块空白。
	var width : float = clampf(_font_get().get_string_size(
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		+ STRIPE + SEP + PAD_RIGHT + 2.0, MIN_WIDTH, MAX_WIDTH)
	panel.custom_minimum_size.x = width
	label.custom_minimum_size.x = width - STRIPE - SEP - PAD_RIGHT
	# 宽度变了要等容器重排一次，否则量到的是「还没放宽」时折行的旧高度。
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(panel):
		return
	_fit_height(panel)
	_restack()


func _drop(e: Dictionary, dur: float) -> void:
	var idx := _items.find(e)
	if idx >= 0:
		_items.remove_at(idx)
	_fade_out(e, dur)
	_restack()


func _fade_out(e: Dictionary, dur: float) -> void:
	var panel : Control = e.get("panel")
	if not is_instance_valid(panel):
		return
	e["token"] = -999
	_kill_pop(panel)
	if panel.has_meta("move_tw"):
		var old = panel.get_meta("move_tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(panel, "modulate:a", 0.0, dur)
	tw.tween_property(panel, "position:y", panel.position.y - 12.0, dur)
	tw.tween_property(panel, "scale", Vector2(0.96, 0.96), dur)
	tw.chain().tween_callback(panel.queue_free)


func _on_scene_changed() -> void:
	for e in _items.duplicate():
		_fade_out(e, 0.08)
	_items.clear()
	reset_kills()


func _on_language_changed(_code: String) -> void:
	for e in _items:
		var feed : String = String(e.get("feed", ""))
		if feed != "":
			_set_text(e, _kill_body(
				feed, int(_kill_counts.get(feed, 1)), int(e.get("left", -1))))


# ----------------------------- 杂项 -----------------------------

func _view_height() -> float:
	var size_y : float = _root.size.y
	if size_y < 1.0:
		size_y = get_viewport().get_visible_rect().size.y
	if size_y < 1.0:
		size_y = 1080.0
	return size_y
