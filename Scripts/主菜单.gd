extends Control

## 主菜单。
## 背景（棕纸）和标题字是两套 Parallax2D 图层，鼠标移动时会产生轻微视差。
## 这里负责按当前分辨率把它们整体缩放：任何屏幕比例都铺满，不露黑边。
##
## 键盘：上下键在三个选项之间移动预选，回车 / 空格开始，Esc 退出。
## 预选的按钮会压暗底色、套一圈金色粗边、整体放大一点，左侧浮出一个来回轻晃的箭头。

const BG_SPRITE_SCALE    := Vector2(0.5975142, 0.62271965)
const TITLE_SPRITE_SCALE := Vector2(0.46735322, 0.40638956)
const BG_POS             := Vector2(20.281307, 22.843754)
const TITLE_POS          := Vector2(431.59375, -1.390625)
## 标题投影相对标题本体的偏移（右下），随屏幕缩放一起放大。
const SHADOW_OFFSET      := Vector2(24.0, 26.0)

## 铺满之后再放大一点，保持原本 2x 构图（标题偏右上）。
const ART_ZOOM : float = 1.55

## 预选时放大到多少。1.0 = 不放大。
const MOSS_SCRIPT   := preload("res://Scripts/MossBorder.gd")
const FOCUS_SCALE   : float = 1.07
## 箭头贴在按钮左侧多远（负数 = 往左）。
const ARROW_OFFSET  : float = -46.0
## 箭头左右晃动的幅度与频率。
const ARROW_GLIDE   : float = 6.0
const ARROW_SPEED   : float = 7.5

@onready var art          : Node2D   = $Art
@onready var bg           : Sprite2D = $Art/Background/Sprite2D
@onready var title_art    : Sprite2D = $Art/TitleLayer/Sprite2D2
@onready var title_shadow : Sprite2D = $Art/TitleLayer/TitleShadow

@onready var menu_box       : CenterContainer = $Menu
@onready var settings_layer : CanvasLayer = $Settings

@onready var start_button   : Button = $Menu/Box/StartButton
@onready var options_button : Button = $Menu/Box/OptionsButton
@onready var quit_button    : Button = $Menu/Box/QuitButton

## 设置弹层里的控件（结构与暂停菜单的设置页一致）。
@onready var set_music_vol   : HSlider     = $Settings/Root/Center/Panel/Content/MusicRow/MusicSlider
@onready var set_sfx_vol     : HSlider     = $Settings/Root/Center/Panel/Content/SfxRow/SfxSlider
@onready var set_fullscreen  : CheckButton = $Settings/Root/Center/Panel/Content/FullscreenCheck
@onready var set_res_down    : Button      = $Settings/Root/Center/Panel/Content/ResRow/ResDown
@onready var set_res_value   : Label       = $Settings/Root/Center/Panel/Content/ResRow/ResValue
@onready var set_res_up      : Button      = $Settings/Root/Center/Panel/Content/ResRow/ResUp
@onready var set_lang_en     : Button      = $Settings/Root/Center/Panel/Content/LanguageRow/EnButton
@onready var set_lang_zh     : Button      = $Settings/Root/Center/Panel/Content/LanguageRow/ZhButton
@onready var set_back        : Button      = $Settings/Root/Center/Panel/Content/BackButton

var _leaving : bool = false
## 设置弹层是否开着：开着的时候主菜单的键盘输入全部让位。
var _settings_open : bool = false

## 上一帧的鼠标位置：只有鼠标真的动了，才让 hover 接管焦点。
## 鼠标静止时方向键能自由切换，不被 hover 判定拉回去。
var _last_mouse_pos : Vector2 = Vector2.ZERO
var _mouse_tracked : bool = false
## 初始焦点就位之后才允许播放悬停音效，避免进菜单第一声误响。
var _sound_ready : bool = false
## 设置弹层同理：刚弹出时把焦点给「返回」那一下不响。
var _settings_sound_ready : bool = false

var buttons   : Array[Button] = []
var _arrows   : Array[Label] = []
var _moss     : Array[Control] = []
var _normals  : Array[StyleBox] = []
var _hovers   : Array[StyleBox] = []
var _fonts    : Array[Color] = []
var _pulse    : float = 0.0

func _ready() -> void:
	get_viewport().size_changed.connect(_fit_art)
	_fit_art()

	# 设置弹层复用暂停菜单那套居中面板结构，默认收起，不切场景。
	settings_layer.hide()
	_setup_settings()

	buttons = [start_button, options_button, quit_button]
	for i in buttons.size():
		_setup_button(i)
	# 主按钮按下时放一声「按下」音效。
	start_button.pressed.connect(GameSettings.play_click_sound)
	options_button.pressed.connect(GameSettings.play_click_sound)
	quit_button.pressed.connect(GameSettings.play_click_sound)
	# 等一帧让容器排好版，再把焦点放到第一项，方向键按下去立刻有反应。
	await get_tree().process_frame
	pivot_refresh()
	start_button.grab_focus()
	# 初始焦点不算「悬停」，之后焦点变化才播音效，避免一进菜单就响一声。
	_sound_ready = true

## 布局完成后补算一次支点，缩放才是围绕按钮中心而不是左上角；
## 箭头也按真实按钮高度重新居中。
func pivot_refresh() -> void:
	for i in buttons.size():
		var b : Button = buttons[i]
		b.pivot_offset = b.size * 0.5
		if i < _arrows.size():
			_arrows[i].position.y = (b.size.y - 64.0) * 0.5
		if i < _moss.size():
			_moss[i].call("rebuild")

## 键盘入口：方向键（上下）在选项间移动选中，回车 / 空格触发「当前选中项」，
## 等同于用鼠标左键点击那个按钮；Esc 退出。
## 用 _input 而不是 _unhandled_input，这样按钮就算拿了焦点也抢不走这几个键。
func _input(event: InputEvent) -> void:
	if _leaving:
		return
	# 设置弹层开着时，回车 / Esc 都归它处理，别在这儿把游戏开起来。
	if _settings_open:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close_settings()
		return
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			get_viewport().set_input_as_handled()
			# 回车 = 点击当前选中的按钮（和鼠标左键一个效果）。
			_activate_focused()
		KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_quit_pressed()

## 触发当前持有焦点的按钮：就是「点一下」它。没有焦点时默认点 START。
func _activate_focused() -> void:
	var owner : Control = get_viewport().gui_get_focus_owner()
	if owner is Button:
		owner.pressed.emit()
	else:
		start_button.pressed.emit()

## 把两层美术按「覆盖整个视口」的倍率缩放，两层用同一个倍率，
## 所以不管屏幕多宽多窄，构图关系都和设计稿一致。
func _fit_art() -> void:
	var view : Vector2 = get_viewport_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	if bg.texture == null:
		return

	var base : Vector2 = bg.texture.get_size() * BG_SPRITE_SCALE
	var k : float = maxf(view.x / base.x, view.y / base.y) * ART_ZOOM

	art.position = view * 0.5
	bg.position = BG_POS * k
	bg.scale = BG_SPRITE_SCALE * k
	title_art.position = TITLE_POS * k
	title_art.scale = TITLE_SPRITE_SCALE * k
	# 投影跟标题同缩放，只多一个固定方向的位移，像光从左上来。
	title_shadow.position = (TITLE_POS + SHADOW_OFFSET) * k
	title_shadow.scale = TITLE_SPRITE_SCALE * k

## 给一个按钮挂焦点监听、上下循环邻居、还有左侧那个箭头。
func _setup_button(i: int) -> void:
	var b : Button = buttons[i]
	var n : int = buttons.size()

	# 记住原始样式，失焦时原样还回去（否则会掉回引擎默认灰按钮）。
	_normals.append(b.get_theme_stylebox("normal"))
	_hovers.append(b.get_theme_stylebox("hover"))
	_fonts.append(b.get_theme_color("font_color"))

	# 上下键在三个选项之间绕圈，不会跑到别的控件上去。
	b.focus_neighbor_top = b.get_path_to(buttons[(i - 1 + n) % n])
	b.focus_neighbor_bottom = b.get_path_to(buttons[(i + 1) % n])

	b.focus_entered.connect(_on_focus_changed.bind(b, true))
	b.focus_exited.connect(_on_focus_changed.bind(b, false))
	# 鼠标悬停不再只认按钮本体，改由 _process 按「整行水平范围」判定，
	# 见 _update_hover_by_mouse()。

	# 苔藓：自己会铺满按钮并外扩一圈，长在边框那条带上。
	var m : Control = MOSS_SCRIPT.new()
	b.add_child(m)
	# 每个按钮用不同种子，三片苔藓长得不一样。
	m.seed_value = 20261017 + i * 733
	_moss.append(m)

	var a : Label = Label.new()
	a.text = ">"
	a.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.add_theme_font_override("font", b.get_theme_font("font"))
	a.add_theme_font_size_override("font_size", 58)
	a.add_theme_color_override("font_color", Color(1.0, 0.85, 0.46, 1.0))
	a.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	a.add_theme_constant_override("outline_size", 4)
	a.position = Vector2(ARROW_OFFSET, (b.custom_minimum_size.y - 64.0) * 0.5)
	a.modulate = Color(1.0, 1.0, 1.0, 0.0)
	b.add_child(a)
	_arrows.append(a)

func _on_focus_changed(b: Button, on: bool) -> void:
	var i : int = buttons.find(b)
	if i < 0:
		return
	b.pivot_offset = b.size * 0.5

	if on:
		# 悬停 / 焦点落到选项上时放一声（初始焦点静音）。
		if _sound_ready:
			GameSettings.play_hover_sound()
		# 压暗底色 + 金色粗边 + 外发光：白字对比更强，也比 hover 明显得多。
		var sb := StyleBoxFlat.new()
		# 内容边距与普通态一致，按钮整体尺寸保持不变，不会跳。
		sb.content_margin_left = 30.0
		sb.content_margin_right = 30.0
		sb.content_margin_top = 10.0
		sb.content_margin_bottom = 10.0
		sb.bg_color = Color(0.23, 0.185, 0.125, 1.0)
		sb.border_color = Color(1.0, 0.84, 0.44, 1.0)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(10)
		sb.shadow_color = Color(1.0, 0.72, 0.30, 0.40)
		sb.shadow_size = 16
		sb.anti_aliasing = true
		b.add_theme_stylebox_override("normal", sb)
		# hover 也一起换掉，否则鼠标压在上面时暗底会被亮底盖回去。
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", Color(1.0, 0.93, 0.74, 1.0))
	else:
		b.add_theme_stylebox_override("normal", _normals[i])
		b.add_theme_stylebox_override("hover", _hovers[i])
		b.add_theme_color_override("font_color", _fonts[i])

	var tw := b.create_tween()
	tw.set_trans(Tween.TRANS_BACK if on else Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE * (FOCUS_SCALE if on else 1.0), 0.16)

	# 苔藓同步爬上来 / 缩回去。
	if i < _moss.size():
		_moss[i].call("grow", on)

func _process(delta: float) -> void:
	_pulse += delta
	for i in _arrows.size():
		var a : Label = _arrows[i]
		var on : bool = buttons[i].has_focus()
		var al : float = a.modulate.a
		al = move_toward(al, 1.0 if on else 0.0, delta * 6.0)
		# 整体写入 Color，避免只改分量时读不到改动。
		a.modulate = Color(1.0, 1.0, 1.0, al)
		if on:
			a.position.x = ARROW_OFFSET + sin(_pulse * ARROW_SPEED) * ARROW_GLIDE
		elif al <= 0.001:
			a.position.x = ARROW_OFFSET

	# 鼠标悬停：按整行水平范围判定选中，不只是按钮本体那块矩形。
	_update_hover_by_mouse()

## 鼠标悬停命中：只要鼠标落在某个选项所在的那条水平带内（不限左右），
## 就选中该选项；移出菜单区域则把控制权交还给键盘焦点。
## 关键：只有鼠标真的移动了才接管焦点——鼠标静止时方向键自由切换，
## 不会被鼠标停在别处按钮上的判定范围拉回去。
func _update_hover_by_mouse() -> void:
	if _settings_open or _leaving:
		return
	var mp : Vector2 = get_viewport().get_mouse_position()
	# 鼠标没动就交还键盘，别抢焦点（否则方向键切过去又被 hover 拉回来）。
	if _mouse_tracked and mp.distance_to(_last_mouse_pos) < 1.0:
		return
	_last_mouse_pos = mp
	_mouse_tracked = true
	for i in buttons.size():
		var b : Button = buttons[i]
		var r : Rect2 = b.get_global_rect()
		# 水平范围放大到整个视口宽度，垂直仍按按钮本体的上下边界。
		var band := Rect2(Vector2(0.0, r.position.y), Vector2(get_viewport_rect().size.x, r.size.y))
		if band.has_point(mp):
			if not b.has_focus():
				b.grab_focus()
			return

## 「开始游戏」= 开下一关。进度由 Progress 记着：
## 第一关通关后进第二关，最后一关通关后绕回第一关，循环。
func _on_start_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	var next : String = Progress.next_level_scene()
	if next == "":
		next = "res://Scenes/关卡.tscn"
	get_tree().change_scene_to_file(next)

func _on_options_pressed() -> void:
	if _leaving or _settings_open:
		return
	# 不切场景：设置菜单直接盖在主界面上。
	_open_settings()

func _open_settings() -> void:
	_settings_open = true
	# 按钮留在原处（主界面要看得见），但压暗并禁用：
	# 既点不动，方向键也不会把焦点跑到弹层背后去。
	_set_menu_enabled(false)
	# 先同步控件状态，再弹出，避免一打开就触发一次写盘 / 切全屏。
	_sync_settings()
	_settings_sound_ready = false
	settings_layer.show()
	await get_tree().process_frame
	set_back.grab_focus()
	# 焦点落定之后才让设置项响，第一下静音。
	_settings_sound_ready = true

func _close_settings() -> void:
	if not _settings_open:
		return
	_settings_open = false
	settings_layer.hide()
	_set_menu_enabled(true)
	await get_tree().process_frame
	pivot_refresh()
	options_button.grab_focus()

func _on_settings_closed() -> void:
	_close_settings()

## 弹层开着时主菜单按钮整体退到后面：半透明 + 不可交互。
func _set_menu_enabled(on: bool) -> void:
	menu_box.modulate = Color(1.0, 1.0, 1.0, 1.0) if on else Color(1.0, 1.0, 1.0, 0.35)
	for b in buttons:
		b.disabled = not on

## 设置弹层控件的初始化与信号连接（与暂停菜单设置页一致）。
func _setup_settings() -> void:
	set_music_vol.value = GameSettings.music_volume
	set_sfx_vol.value = GameSettings.sfx_volume
	set_fullscreen.button_pressed = GameSettings.fullscreen
	_sync_settings()

	set_music_vol.value_changed.connect(func(v: float) -> void: GameSettings.set_music_volume(v))
	set_sfx_vol.value_changed.connect(func(v: float) -> void: GameSettings.set_sfx_volume(v))
	set_fullscreen.toggled.connect(func(on: bool) -> void:
		GameSettings.set_fullscreen(on)
		_sync_settings())
	set_res_down.pressed.connect(func() -> void:
		GameSettings.step_resolution(-1)
		_sync_settings())
	set_res_up.pressed.connect(func() -> void:
		GameSettings.step_resolution(1)
		_sync_settings())
	set_lang_en.pressed.connect(func() -> void:
		GameSettings.set_language("en")
		_sync_settings())
	set_lang_zh.pressed.connect(func() -> void:
		GameSettings.set_language("zh")
		_sync_settings())
	set_back.pressed.connect(_close_settings)
	# 设置弹层里所有可点控件按下时也放一声。
	for c in [set_fullscreen, set_res_down, set_res_up, set_lang_en, set_lang_zh, set_back]:
		c.pressed.connect(GameSettings.play_click_sound)
	# 设置弹层里每一项拿到焦点（鼠标悬停 / 方向键切换）都放悬停音。
	for c in _settings_controls():
		c.focus_entered.connect(_on_settings_hover)
	GameSettings.language_changed.connect(_sync_settings)
	GameSettings.display_changed.connect(_sync_settings)

## 设置弹层里所有能拿焦点的控件（含两个音量滑块）。
func _settings_controls() -> Array:
	return [set_music_vol, set_sfx_vol, set_fullscreen,
		set_res_down, set_res_up, set_lang_en, set_lang_zh, set_back]

## 设置项拿到焦点时放悬停音。刚打开弹层时那一次抢占焦点不响，
## 否则会和「按下选项」的音效叠在一起。
func _on_settings_hover() -> void:
	if _settings_sound_ready:
		GameSettings.play_hover_sound()

## 把设置弹层的控件状态同步到 GameSettings（分辨率、语言、全屏）。
func _sync_settings() -> void:
	if set_res_value == null:
		return
	set_music_vol.set_value_no_signal(GameSettings.music_volume)
	set_sfx_vol.set_value_no_signal(GameSettings.sfx_volume)
	set_res_value.text = GameSettings.resolution_label()
	set_fullscreen.set_pressed_no_signal(GameSettings.fullscreen)
	set_lang_en.set_pressed_no_signal(GameSettings.language == "en")
	set_lang_zh.set_pressed_no_signal(GameSettings.language == "zh")
	var enabled : bool = not GameSettings.fullscreen
	set_res_down.disabled = not enabled
	set_res_up.disabled = not enabled
	set_res_value.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.4)

func _on_quit_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().quit()
