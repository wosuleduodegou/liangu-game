extends CanvasLayer

## 暂停菜单：继续游戏 / 设置 / 返回主菜单（不保存进度）
## 场景挂在关卡下，process_mode = ALWAYS，所以暂停后仍然能响应。
## 语言、音量、全屏统一走 GameSettings（Autoload）。

const MENU_SCENE := "res://Scenes/主菜单.tscn"

## 按键说明。留空 = 用场景里写好的那句（第一关的键位）。
## 别的关卡换了操作，在实例化这个场景时覆盖这一项就行。
@export_multiline var hint_text : String = ""

@onready var root        : Control        = $Root
@onready var hints       : Label          = $Root/Hints
@onready var main_box    : VBoxContainer  = $Root/Center/MainBox
@onready var panel       : Control        = $Root/SettingsPanel
@onready var resume_btn  : Button         = $Root/Center/MainBox/ResumeButton
@onready var settings_btn: Button         = $Root/Center/MainBox/SettingsButton
@onready var menu_btn    : Button         = $Root/Center/MainBox/MenuButton

@onready var music_vol   : HSlider        = $Root/SettingsPanel/Center/Panel/Content/MusicRow/MusicSlider
@onready var sfx_vol     : HSlider        = $Root/SettingsPanel/Center/Panel/Content/SfxRow/SfxSlider
@onready var fullscreen  : CheckButton    = $Root/SettingsPanel/Center/Panel/Content/FullscreenCheck
@onready var res_down    : Button         = $Root/SettingsPanel/Center/Panel/Content/ResRow/ResDown
@onready var res_value   : Label          = $Root/SettingsPanel/Center/Panel/Content/ResRow/ResValue
@onready var res_up      : Button         = $Root/SettingsPanel/Center/Panel/Content/ResRow/ResUp
@onready var lang_en     : Button         = $Root/SettingsPanel/Center/Panel/Content/LanguageRow/EnButton
@onready var lang_zh     : Button         = $Root/SettingsPanel/Center/Panel/Content/LanguageRow/ZhButton
@onready var back_btn    : Button         = $Root/SettingsPanel/Center/Panel/Content/BackButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	root.hide()

	# 先同步控件状态，再连信号，避免初始化时触发一次写盘 / 切全屏
	music_vol.value = GameSettings.music_volume
	sfx_vol.value = GameSettings.sfx_volume
	fullscreen.button_pressed = GameSettings.fullscreen
	_sync_language()
	_sync_display()
	# 静态文本先记下英文原文并按当前语言铺一遍，切语言时才翻得回来。
	GameSettings.refresh_ui_text(self)
	_apply_hint()

	resume_btn.pressed.connect(_on_resume)
	settings_btn.pressed.connect(_on_settings)
	menu_btn.pressed.connect(_on_menu)
	back_btn.pressed.connect(_on_back)
	# 按下音效：三个主按钮 + 设置页所有可点控件。
	for b in [resume_btn, settings_btn, menu_btn, back_btn, fullscreen, res_down, res_up, lang_en, lang_zh]:
		b.pressed.connect(GameSettings.play_click_sound)
	music_vol.value_changed.connect(_on_music_volume_changed)
	sfx_vol.value_changed.connect(_on_sfx_volume_changed)
	fullscreen.toggled.connect(_on_fullscreen_toggled)
	res_down.pressed.connect(_on_resolution.bind(-1))
	res_up.pressed.connect(_on_resolution.bind(1))
	lang_en.pressed.connect(_on_language.bind("en"))
	lang_zh.pressed.connect(_on_language.bind("zh"))
	GameSettings.language_changed.connect(_on_language_changed)
	GameSettings.display_changed.connect(_sync_display)
	# 主按钮 + 设置页每一项：拿到焦点（悬停 / 方向键）时放一声。
	for b in [resume_btn, settings_btn, menu_btn,
			music_vol, sfx_vol, fullscreen,
			res_down, res_up, lang_en, lang_zh, back_btn]:
		b.focus_entered.connect(_on_button_hover)

func is_open() -> bool:
	return root.visible

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		# The status page owns Esc while it is open.
		var sp = get_tree().get_first_node_in_group("status_panel")
		if sp and sp.is_open():
			return
		if panel.visible:
			_on_back()
		else:
			toggle()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if root.visible:
		resume()
	else:
		open_menu()

func open_menu() -> void:
	root.show()
	panel.hide()
	main_box.show()
	hints.show()
	get_tree().paused = true
	_sync_language()
	resume_btn.grab_focus()

func resume() -> void:
	root.hide()
	hints.hide()
	get_tree().paused = false

func _on_resume() -> void:
	resume()

func _on_settings() -> void:
	main_box.hide()
	# 进设置页就把按键说明收起来，别和设置项抢视线。
	hints.hide()
	panel.show()
	_sync_language()
	# 焦点交给设置页第一项，方向键进去就能直接调。
	music_vol.grab_focus()

func _on_back() -> void:
	panel.hide()
	main_box.show()
	hints.show()
	resume_btn.grab_focus()

func _on_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)

func _on_music_volume_changed(v: float) -> void:
	GameSettings.set_music_volume(v)

func _on_sfx_volume_changed(v: float) -> void:
	GameSettings.set_sfx_volume(v)

## 主按钮悬停 / 焦点切换时放一声。
func _on_button_hover() -> void:
	GameSettings.play_hover_sound()

func _on_fullscreen_toggled(on: bool) -> void:
	GameSettings.set_fullscreen(on)
	_sync_display()

func _on_resolution(delta: int) -> void:
	GameSettings.step_resolution(delta)
	_sync_display()

## 分辨率只在窗口模式下可调，全屏时把这一行灰掉。
func _sync_display() -> void:
	if res_value == null:
		return
	res_value.text = GameSettings.resolution_label()
	fullscreen.set_pressed_no_signal(GameSettings.fullscreen)
	var enabled : bool = not GameSettings.fullscreen
	res_down.disabled = not enabled
	res_up.disabled = not enabled
	res_value.modulate = Color(1, 1, 1, 1) if enabled else Color(1, 1, 1, 0.4)

func _on_language(code: String) -> void:
	GameSettings.set_language(code)
	_sync_language()

func _on_language_changed(_code: String) -> void:
	_sync_language()

func _sync_language() -> void:
	lang_en.set_pressed_no_signal(GameSettings.language == "en")
	lang_zh.set_pressed_no_signal(GameSettings.language == "zh")
	_apply_hint()

## 按键说明：有覆盖就用覆盖的那句，否则保留场景里写好的。
func _apply_hint() -> void:
	if hint_text.strip_edges() == "":
		return
	hints.text = tr(hint_text)
