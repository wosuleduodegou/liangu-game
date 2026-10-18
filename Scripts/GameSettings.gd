extends Node

## 全局设置：语言 / 音量 / 全屏。
## 作为 Autoload 常驻（project.godot 里注册为 GameSettings）。
##
## 语言实现方式：
##   英文文本本身就是 key，注册一条 "zh" 的 Translation 到 TranslationServer，
##   切语言时 Control 会自动重新查表（Label/Button 默认 auto_translate）。
## 中文字形：
##   Piedra 只有拉丁字形，所以把「南西油墨宋」挂成它的 fallback，
##   英文字母仍用 Piedra，缺字（中文）自动落到宋体上。

const Settings = preload("res://Scripts/Translations.gd")

const SETTINGS_PATH := "user://settings.cfg"
const FONT_LATIN := "res://Assets/字体/Piedra-Regular.ttf"
const FONT_CJK := "res://Assets/字体/南西油墨宋.ttf"
const LOCALES := ["en", "zh"]

## 界面悬停音效。
const HOVER_SOUND := "res://Assets/音效/悬停.mp3"
## 按下按钮音效（同样属于界面音效，走 SFX 总线）。
const CLICK_SOUND := "res://Assets/音效/an下.mp3"
## 背景音乐（走 Music 总线，全程循环播放）。
const MUSIC_PATH := "res://Assets/音效/背景音乐.mp3"
## 音频总线名：背景音乐 / 界面音效（各挂一条独立总线，音量分开调）。
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"

## 窗口可选的窗口化分辨率。界面本身是按 1920x1080 设计的，
## 靠 project.godot 里的 canvas_items + expand 自动缩放，所以这里只决定窗口大小。
const RESOLUTIONS : Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
]
const MIN_WINDOW := Vector2i(1024, 576)

signal language_changed(code: String)
signal display_changed

## 背景音乐音量（0~100）。
var music_volume : float = 100.0
## 界面音效音量（0~100）。
var sfx_volume : float = 100.0
var fullscreen : bool = false
var language : String = "en"

## 最近一次窗口化时的大小，切回窗口模式时用它还原。
var windowed_size : Vector2i = Vector2i(1600, 900)
var resolution_index : int = 1

var _cjk_font : Font = null
var _ui_font : Font = null
var _had_settings : bool = false
## 界面音效播放器（挂在 SFX 总线上）。悬停与按下各用一只，
## 否则「按下」还没响完就被紧接着的「悬停」抢走播放器、直接被截断。
var _hover_player : AudioStreamPlayer = null
var _click_player : AudioStreamPlayer = null
## 背景音乐播放器（挂在 Music 总线上，常驻、循环）。
var _music_player : AudioStreamPlayer = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_install_translation()
	_install_cjk_fallback()
	_ensure_audio_buses()
	load_settings()
	_apply_audio_volumes()
	_start_music()
	# 首次运行（还没有 settings.cfg）时，按当前屏幕挑一个能放下的窗口大小，
	# 避免在 2K / 4K 屏上固定开 1920x1080 缩在中间。
	if not _had_settings:
		_fit_default_window()
	_apply_display()

# ------------------------------------------------------------------
# 语言
# ------------------------------------------------------------------

func _install_translation() -> void:
	var zh := Translation.new()
	zh.locale = "zh"
	for key in Settings.ZH.keys():
		zh.add_message(key, Settings.ZH[key])
	TranslationServer.add_translation(zh)
	TranslationServer.set_locale("en")

func set_language(code: String) -> void:
	code = code if LOCALES.has(code) else "en"
	language = code
	TranslationServer.set_locale(code)
	# Godot 只在文字写进控件那一下翻一次，切 locale 不会让已有的 Label/Button
	# 重画，所以这里手动把整棵 UI 树刷一遍，否则表头会留在旧语言里。
	if is_inside_tree():
		refresh_ui_text(get_tree().root)
	save_settings()
	language_changed.emit(code)

func toggle_language() -> void:
	set_language("zh" if language == "en" else "en")

func locale_code() -> String:
	return language

## 把一棵 UI 子树里的静态英文文本按当前语言重设。
##
## 做法：第一次遇到某个控件时，如果它的文本正好是字典里的英文原文，
## 就把原文记进 meta（i18n_key），之后每次都按 i18n_key 重设。
## 代码动态拼出来的文字（数值、名字、状态）不在字典里，一律不碰。
func refresh_ui_text(root: Node) -> void:
	if root != null:
		_refresh_text_recursive(root)

func _refresh_text_recursive(n: Node) -> void:
	if n is Label or n is Button or n is RichTextLabel or n is CheckButton \
			or n is CheckBox or n is OptionButton or n is LinkButton:
		_apply_ui_text(n)
	for c in n.get_children():
		_refresh_text_recursive(c)

func _apply_ui_text(n: Node) -> void:
	var cur : String = String(n.get("text"))
	var key : String = String(n.get_meta("i18n_key", ""))
	if key == "":
		if cur == "" or not Settings.ZH.has(cur):
			return
		key = cur
		n.set_meta("i18n_key", key)
	var want : String = key if language == "en" else String(Settings.ZH.get(key, key))
	if cur != want:
		n.set("text", want)

## Pieadra 加中文 fallback：缺字时自动落到南西油墨宋。
func _install_cjk_fallback() -> void:
	_cjk_font = _load_cjk()
	if _cjk_font == null:
		push_warning("CJK font missing: %s" % FONT_CJK)
		return

	var latin := load(FONT_LATIN) as Font
	if latin == null:
		return
	var fallbacks : Array[Font] = []
	for f in latin.fallbacks:
		fallbacks.append(f)
	if not fallbacks.has(_cjk_font):
		fallbacks.append(_cjk_font)
	latin.fallbacks = fallbacks

func _load_cjk() -> Font:
	# 正常情况：编辑器已导入，直接 load 到 FontFile。
	var res = load(FONT_CJK)
	if res is Font:
		return res

	# 兜底：直接从文件读（没生成 .import 时也能跑）。
	var ff := FontFile.new()
	if ff.load_dynamic_font(FONT_CJK) == OK:
		return ff

	# 再兜底：系统里的中文字体。
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "SimHei", "Noto Sans CJK SC",
	])
	return sf

func cjk_font() -> Font:
	return _cjk_font

## 界面通用字体：Piedra 打底、中文挂 fallback。
## 英文仍保持游戏原本的字形，汉字则落到南西油墨宋，不会出方块。
func ui_font() -> Font:
	if _ui_font == null:
		_ui_font = load(FONT_LATIN) as Font
	if _ui_font == null:
		_ui_font = _cjk_font
	return _ui_font

## F11 随时切换全屏，任何界面下都能用（包括暂停时）。
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------
# 音量 / 全屏
# ------------------------------------------------------------------

## 确保存在 Music / SFX 两条音频总线（没有则动态建出来，都挂到 Master 下）。
func _ensure_audio_buses() -> void:
	if AudioServer.get_bus_index(BUS_MUSIC) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS_MUSIC)
		AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_index(BUS_SFX) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS_SFX)
		AudioServer.set_bus_send(i, "Master")

## 把两条总线的实际音量刷一遍（读档后 / 启动时调用）。
func _apply_audio_volumes() -> void:
	_set_bus_volume(BUS_MUSIC, music_volume)
	_set_bus_volume(BUS_SFX, sfx_volume)

func _set_bus_volume(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v / 100.0, 0.0001)))

func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 100.0)
	_set_bus_volume(BUS_MUSIC, music_volume)
	save_settings()

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 100.0)
	_set_bus_volume(BUS_SFX, sfx_volume)
	save_settings()

## 播放界面悬停音效（走 SFX 总线，受界面音效音量控制）。
func play_hover_sound() -> void:
	_hover_player = _play_sfx(HOVER_SOUND, _hover_player)

## 播放按下按钮音效（走 SFX 总线，受界面音效音量控制）。
func play_click_sound() -> void:
	_click_player = _play_sfx(CLICK_SOUND, _click_player)

## 启动背景音乐：常驻播放器 + 循环，走 Music 总线（受音乐音量控制）。
## 放在 autoload 上，整个游戏生命周期只播这一条，切场景不中断。
func _start_music() -> void:
	var s := load(MUSIC_PATH)
	if s == null:
		push_warning("Background music missing: %s" % MUSIC_PATH)
		return
	# mp3 / ogg 等流式音频：打开 loop 属性，让曲子放完自动从头循环。
	if s is AudioStreamMP3:
		(s as AudioStreamMP3).loop = true
	elif s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_music_player = AudioStreamPlayer.new()
	_music_player.stream = s
	_music_player.bus = BUS_MUSIC
	add_child(_music_player)
	_music_player.play()

## 用 SFX 总线上的播放器播放一段界面音效。找不到文件就静默跳过。
func _play_sfx(path: String, player: AudioStreamPlayer) -> AudioStreamPlayer:
	if player == null:
		var s := load(path)
		if s == null:
			return null
		player = AudioStreamPlayer.new()
		player.stream = s
		player.bus = BUS_SFX
		add_child(player)
	elif player.stream == null or player.stream.resource_path != path:
		player.stream = load(path)
	player.play()
	return player

func set_fullscreen(on: bool) -> void:
	if fullscreen == on:
		return
	fullscreen = on
	_apply_display()
	save_settings()
	display_changed.emit()

## 循环切换窗口化分辨率（菜单里点 ◀ / ▶ 按钮）。
func step_resolution(delta: int) -> void:
	resolution_index = wrapi(resolution_index + delta, 0, RESOLUTIONS.size())
	windowed_size = RESOLUTIONS[resolution_index]
	if not fullscreen:
		_apply_windowed_size()
	save_settings()
	display_changed.emit()

func resolution_label() -> String:
	var s : Vector2i = RESOLUTIONS[clampi(resolution_index, 0, RESOLUTIONS.size() - 1)]
	return "%d x %d" % [s.x, s.y]

# ------------------------------------------------------------------
# 窗口 / 分辨率
# ------------------------------------------------------------------

func _apply_display() -> void:
	var win := get_window()
	if win == null:
		return
	win.min_size = MIN_WINDOW
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		_apply_windowed_size()

func _apply_windowed_size() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var usable : Rect2i = DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen())
	var target : Vector2i = windowed_size
	# 绝不让窗口超出可用桌面区域，否则标题栏 / 边框会被屏幕切掉。
	target.x = mini(target.x, maxi(MIN_WINDOW.x, usable.size.x))
	target.y = mini(target.y, maxi(MIN_WINDOW.y, usable.size.y - 48))
	var win := get_window()
	if win:
		win.size = target
	# 夹在屏幕中间，换分辨率后不会跑到屏幕外。
	DisplayServer.window_set_position(Vector2i(
		usable.position.x + (usable.size.x - target.x) / 2,
		usable.position.y + (usable.size.y - target.y) / 2))

## 首次启动：在预设里挑一个当前屏幕放得下的最大分辨率。
func _fit_default_window() -> void:
	var usable : Rect2i = DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen())
	var best : int = 0
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i].x <= usable.size.x and RESOLUTIONS[i].y <= usable.size.y - 48:
			best = i
	resolution_index = best
	windowed_size = RESOLUTIONS[best]

# ------------------------------------------------------------------
# 存取
# ------------------------------------------------------------------

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "language", language)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution_index", resolution_index)
	cfg.set_value("video", "window_width", windowed_size.x)
	cfg.set_value("video", "window_height", windowed_size.y)
	cfg.save(SETTINGS_PATH)

func load_settings() -> void:
	var cfg := ConfigFile.new()
	_had_settings = cfg.load(SETTINGS_PATH) == OK
	if _had_settings:
		# 旧的单「volume」字段兼容：拆成音乐/音效两份。
		music_volume = float(cfg.get_value("audio", "music_volume", 100.0))
		sfx_volume = float(cfg.get_value("audio", "sfx_volume", 100.0))
		fullscreen = bool(cfg.get_value("video", "fullscreen", false))
		language = String(cfg.get_value("ui", "language", "en"))
		resolution_index = int(cfg.get_value("video", "resolution_index", 1))
		var w : int = int(cfg.get_value("video", "window_width", 0))
		var h : int = int(cfg.get_value("video", "window_height", 0))
		if w > 0 and h > 0:
			windowed_size = Vector2i(w, h)
		else:
			# 老版本的配置文件没有窗口尺寸，按当前屏幕重新挑一个。
			_fit_default_window()

	resolution_index = clampi(resolution_index, 0, RESOLUTIONS.size() - 1)
	if not LOCALES.has(language):
		language = "en"
	TranslationServer.set_locale(language)
