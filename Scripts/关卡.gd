extends Node2D

## Level root: random spawn for the snake, camera follows the head, and a lamp
## that sits on the snake so the jar interior stays readable.
##
## The arena is the level's inscribed circle (see Snake.bounds_* and
## ArenaVignette). Esc opens the pause menu, Space opens the status page
## (both handle input in their own CanvasLayer scripts).

@export var follow_speed : float = 8.0
## Camera zoom. Bigger = the map feels closer and less of the arena is on screen.
@export_range(0.5, 8.0, 0.05) var camera_zoom : float = 4.0
@export var random_spawn : bool = true
## Keep the spawn away from the air walls so you never start facing a corner.
@export var spawn_margin : float = 85.0
## Torch rides just above the snake's head.
@export var torch_offset : Vector2 = Vector2(0, -6)
## Subtle candle wobble so the lamp does not look like a flat gradient.
@export var torch_flicker : bool = true
## 蜈蚣出生点至少要离蛇头这么远，免得一开局就贴脸。
@export var centipede_spawn_gap : float = 170.0
## 天光半径：罐顶那盏灯照亮的范围（世界像素）。白骨架只在照亮区显示。
@export var lamp_radius : float = 700.0

@onready var snake = $Snake
@onready var cam : Camera2D = $Camera2D
@onready var torch : PointLight2D = $Torch

## 开场黑屏：进关先黑 1.0 秒再淡入（够读完正中那句话）。
@export var intro_black_time : float = 1.0
## 黑屏结束后淡出的时长。
@export var intro_fade_time : float = 0.4
## 黑屏正中那句话的字号（按 1920 宽的设计分辨率算）。
@export var intro_line_font_size : int = 44

## 黑屏期间居中的那句话：整局的目标，一句话说清。
## 英文本身就是 key，切中文时由 Translations.gd 查表。
const INTRO_LINE := "KILL EVERYTHING BUT YOU"

## 场上算作“要清掉的东西”的分组：蚂蚁、蜈蚣、蟾蜍。
## 蛇自己不算，所以清空这三个分组 = 通关。
const ENEMY_GROUPS := ["ant", "centipede", "toad"]

## 清场检测的间隔：每帧遍历分组太浪费，四分之一秒一次够用。
@export var clear_check_interval : float = 0.25
## 清场后先定住多久，再开始渐黑（给玩家一点“打完了”的实感）。
@export var clear_hold_time : float = 1.1
## 渐黑时长，黑透之后切场景。
@export var clear_fade_time : float = 0.6
## 通关后要去的场景。
@export var clear_scene_path : String = "res://Scenes/第一关通关.tscn"
## 玩家（蛇）死后回哪个场景。
@export var death_scene_path : String = "res://Scenes/主菜单.tscn"

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _torch_energy : float = 1.0
var _t : float = 0.0
var centipedes : Array[Node2D] = []

var _intro_rect : ColorRect
var _intro_text : Label
var _intro_layer : CanvasLayer
var _intro_elapsed : float = 0.0
var _intro_done : bool = false

var _enemy_total : int = 0
var _check_t : float = 0.0
var _clearing : bool = false
var _clear_t : float = 0.0
var _clear_layer : CanvasLayer
var _clear_rect : ColorRect

## 玩家死亡：一旦置位，关卡逻辑全部停摆，只走死亡黑幕 → 回主菜单。
var _player_dead : bool = false
var _dead_layer : CanvasLayer
var _dead_rect : ColorRect

func _ready() -> void:
	_rng.randomize()
	# 纯黑模式：背景贴图盖不到的地方露引擎默认清屏色（0.3 灰），
	# 统一压成黑，跟 100% 黑暗保持一致。
	RenderingServer.set_default_clear_color(Color(0, 0, 0, 1))
	if cam:
		cam.zoom = Vector2(camera_zoom, camera_zoom)
	if torch:
		_torch_energy = torch.energy
		# 天光钉在罐子中心，不再跟着蛇头跑。
		torch.global_position = snake.bounds_center if snake else global_position
	if snake and random_spawn:
		randomize_spawn()
	scatter_centipedes()
	# 记下开场时场上有多少活物。为 0 的关卡不参与清场判定，
	# 否则一进关就直接跳通关页。
	_enemy_total = _count_enemies()
	if snake and cam:
		cam.global_position = snake.get_head_global_position()
		cam.reset_smoothing()
	# 光照全丢：纯黑模式，别的实体只剩红线感应，蛇自己 unshaded 仍可见。
	Snake.set_dark(true)
	# 蛇被打死时走「死亡 → 回主菜单」，不让它冻在原地。
	if snake and snake.has_signal("died"):
		snake.connect("died", Callable(self, "_on_player_died"))
	_start_intro_fade()

## 开场黑屏：盖一层最顶层的全屏黑，等 intro_black_time 后淡出。
## 放在独立的 CanvasLayer（layer 高位）里，保证盖住 Vision 滤镜和 UI。
func _start_intro_fade() -> void:
	_intro_layer = CanvasLayer.new()
	_intro_layer.layer = 100
	add_child(_intro_layer)
	_intro_rect = ColorRect.new()
	_intro_rect.color = Color(0.0, 0.0, 0.0, 1.0)
	_intro_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(_intro_rect)

	# 黑幕上再压一句话，整屏居中。挂在黑幕之后，所以一定盖在纯黑之上；
	# 不接收鼠标，免得挡住黑幕那层用来锁输入的 STOP。
	_intro_text = Label.new()
	_intro_text.text = tr(INTRO_LINE)
	_intro_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_text.set_anchors_preset(Control.PRESET_FULL_RECT)
	_intro_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_text.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.94))
	_intro_text.add_theme_font_size_override("font_size", intro_line_font_size)
	var font : Font = _ui_font()
	if font != null:
		_intro_text.add_theme_font_override("font", font)
	_intro_layer.add_child(_intro_text)

	_intro_elapsed = 0.0
	_intro_done = false
	# 开场那一下先锁住输入，免得黑屏期间蛇已经动了。
	get_tree().paused = true
	# 注意：暂停时普通 Timer 不跑，必须 process_always 才能当黑屏的秒表。
	var timer : SceneTreeTimer = get_tree().create_timer(intro_black_time, true)
	await timer.timeout
	# 黑屏结束，恢复输入，开始淡出。
	get_tree().paused = false
	_intro_done = true

## Drop the snake at a random spot inside the arena, facing anywhere.
func randomize_spawn() -> void:
	if snake == null:
		return

	var p : Vector2
	if _is_circular_arena():
		# Uniform inside a disc: radius goes with sqrt(u), not u.
		var c : Vector2 = snake.bounds_center
		var r : float = maxf(40.0, float(snake.bounds_radius) - spawn_margin)
		var a : float = _rng.randf_range(0.0, TAU)
		p = c + Vector2.from_angle(a) * (r * sqrt(_rng.randf()))
	else:
		var rect : Rect2 = snake.play_bounds if snake.use_play_bounds else Rect2(0, 0, 5000, 5000)
		var m : float = minf(spawn_margin, minf(rect.size.x, rect.size.y) * 0.35)
		p = Vector2(
			_rng.randf_range(rect.position.x + m, rect.end.x - m),
			_rng.randf_range(rect.position.y + m, rect.end.y - m))

	snake.global_position = p
	var heading : float
	if _is_circular_arena():
		# Nose points away from the middle so the body unrolls *inwards*: the snake
		# is 1.2 m and the arena only 1 m in radius, so a body laid out towards the
		# wall would stick straight through it. +-40 degrees keeps the tail inside.
		heading = (p - Vector2(snake.bounds_center)).angle() + _rng.randf_range(-0.7, 0.7)
	else:
		heading = _rng.randf_range(0.0, TAU)
	snake.heading = heading
	snake.facing = heading
	snake.external_direction = heading
	if _is_circular_arena():
		snake.reset_body_coiled(heading)
	else:
		snake.reset_body()
	if cam:
		cam.global_position = snake.get_head_global_position()
		cam.reset_smoothing()

## 把场景里的蜈蚣随机撒在场地内圈，每条朝向随机，身体从头部往后铺开。
## 出生半径压在半个场地以内，就算身体往后甩也不会穿到墙外。
func scatter_centipedes() -> void:
	centipedes.clear()
	for node in get_tree().get_nodes_in_group("centipede"):
		var c : Node2D = node as Node2D
		if c:
			centipedes.append(c)
	if centipedes.is_empty() or not _is_circular_arena():
		return

	var center : Vector2 = snake.bounds_center
	var rmax : float = maxf(80.0, float(snake.bounds_radius) * 0.5)
	var head : Vector2 = snake.get_head_global_position()
	var placed : Array[Vector2] = []

	for c in centipedes:
		var best : Vector2 = center
		var best_score : float = -1.0
		for _try in 24:
			var p : Vector2 = center + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * (rmax * sqrt(_rng.randf()))
			# 既要躲开蛇，也别和已经放下的另一条叠在一块。
			var score : float = p.distance_to(head)
			for q in placed:
				score = minf(score, p.distance_to(q))
			if score > best_score:
				best_score = score
				best = p
			if best_score >= centipede_spawn_gap:
				break
		c.global_position = best
		placed.append(best)
		c.call("reset_body_heading", _rng.randf_range(0.0, TAU))

func _is_circular_arena() -> bool:
	if snake == null or not snake.use_play_bounds:
		return false
	return int(snake.bounds_shape) == 1

func _process(delta: float) -> void:
	if _player_dead:
		return
	if is_instance_valid(snake) and cam:
		var target : Vector2 = snake.get_head_global_position()
		cam.global_position = cam.global_position.lerp(target, clampf(follow_speed * delta, 0.0, 1.0))

	# 光照全丢：白线可见性由纯黑模式接管，火把不再摇曳。

	# 开场黑屏淡出。文字跟着黑幕一起走，不留残影。
	if not _intro_done:
		return
	if is_instance_valid(_intro_rect) and _intro_rect.color.a > 0.0:
		_intro_elapsed += delta
		var a : float = 1.0 - clampf(_intro_elapsed / maxf(0.001, intro_fade_time), 0.0, 1.0)
		_intro_rect.color = Color(0.0, 0.0, 0.0, a)
		if is_instance_valid(_intro_text):
			# 文字退得比黑幕快得多：黑幕还剩六成时字已经淡完。
			# 否则半透明的字会压在刚浮出来的蛇和骨架上，糊成一团。
			_intro_text.modulate.a = clampf((a - 0.60) / 0.40, 0.0, 1.0)
		if a <= 0.0:
			_intro_rect.visible = false
			_intro_rect.queue_free()
			if is_instance_valid(_intro_text):
				_intro_text.visible = false
				_intro_text.queue_free()
			_intro_layer.queue_free()

	_tick_clear(delta)

## 清场判定 + 通关交接。
## 场上活物归零后先冻住蛇、定一拍，再渐黑切到通关场景。
func _tick_clear(delta: float) -> void:
	if _clearing:
		_clear_t += delta
		if _clear_rect != null:
			var k : float = clampf((_clear_t - clear_hold_time) / maxf(0.001, clear_fade_time), 0.0, 1.0)
			_clear_rect.color = Color(0.0, 0.0, 0.0, k)
			if k >= 1.0:
				_clearing = false
				get_tree().change_scene_to_file(clear_scene_path)
		return
	if _enemy_total <= 0:
		# 开场没数到活物的话再补数一次：万一实体是在 _ready 之后才进组的。
		_enemy_total = _count_enemies()
		if _enemy_total <= 0:
			return
	_check_t += delta
	if _check_t < clear_check_interval:
		return
	_check_t = 0.0
	if _count_enemies() == 0:
		_begin_clear()

## 场上还没死的活物数量。已死但这一帧还没被 free 的也要排除，
## 否则死亡动画那几帧会算成“还活着”，通关要晚半秒。
func _count_enemies() -> int:
	var n : int = 0
	for group_name in ENEMY_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(node):
				continue
			if node.is_queued_for_deletion():
				continue
			if node.has_method("is_dead") and bool(node.call("is_dead")):
				continue
			n += 1
	return n

## 开始通关交接：接手所有输入（黑幕吃掉点击），把蛇定住，别让它在渐黑里继续爬。
func _begin_clear() -> void:
	_clearing = true
	_clear_t = 0.0
	# 清场时绝不能是暂停状态，否则这个 paused 会跟着带进通关 CG。
	get_tree().paused = false
	# 本关已过：把进度推到下一关，主菜单下次「开始游戏」直接开下一关。
	# 放在清场这一刻而不是 CG 结束，是为了玩家中途退出也不丢进度。
	var p : Node = get_node_or_null("/root/Progress")
	if p != null and p.has_method("advance_from"):
		p.call("advance_from", scene_file_path)
	if is_instance_valid(snake):
		snake.set_process(false)
		snake.set_physics_process(false)
	_clear_layer = CanvasLayer.new()
	_clear_layer.layer = 120
	add_child(_clear_layer)
	_clear_rect = ColorRect.new()
	_clear_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_clear_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_clear_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_clear_layer.add_child(_clear_rect)

# =============================== Player death ===============================
## 蛇被打死：停掉整关，压黑 + 「YOU DIED」，然后回主菜单。
## 和通关一样不能带着暂停走，否则玩家会卡在黑屏里。
func _on_player_died() -> void:
	if _player_dead:
		return
	_player_dead = true
	_clearing = false
	_death_sequence()

func _death_sequence() -> void:
	get_tree().paused = false
	_dead_layer = CanvasLayer.new()
	_dead_layer.layer = 120
	add_child(_dead_layer)
	_dead_rect = ColorRect.new()
	_dead_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	_dead_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_dead_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dead_layer.add_child(_dead_rect)

	var label := Label.new()
	label.text = tr("YOU DIED")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.82, 0.95))
	label.add_theme_font_size_override("font_size", intro_line_font_size)
	var font : Font = _ui_font()
	if font != null:
		label.add_theme_font_override("font", font)
	label.modulate.a = 0.0
	_dead_layer.add_child(label)

	await get_tree().create_timer(0.5, true).timeout
	var t : float = 0.0
	while t < 1.8:
		await get_tree().process_frame
		t += get_process_delta_time()
		_dead_rect.color = Color(0.0, 0.0, 0.0, clampf(t / 1.2, 0.0, 1.0))
		label.modulate.a = clampf((t - 0.5) / 0.6, 0.0, 1.0)
	get_tree().paused = false
	get_tree().change_scene_to_file(death_scene_path)

## 界面文字用的字体：优先 GameSettings 里挂好中文回退的那支（南西油墨宋）。
func _ui_font() -> Font:
	var gs = get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("cjk_font"):
		var f : Font = gs.call("cjk_font") as Font
		if f != null:
			return f
	return ThemeDB.fallback_font
