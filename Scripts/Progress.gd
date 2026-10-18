extends Node

## 关卡进度（Autoload 名：Progress）。
##
## 主菜单的「开始游戏」永远是「开下一关」：第一次玩是第一关，
## 第一关通关后是第二关……全部通关之后绕回第一关，如此循环。
##
## 关卡顺序只看下面的 LEVELS 数组 —— 以后加第三关，只要建好场景、
## 往数组里 push 一行，主菜单和通关交接会自动认路。
##
## 进度存在 user://progress.cfg，退出游戏再进也不会从头开始。

const SAVE_PATH := "user://progress.cfg"

## 关卡顺序。第一项就是「还没通关过任何关」时开的那关。
const LEVELS : Array[String] = [
	"res://Scenes/关卡.tscn",      # 第一关：蛇
	"res://Scenes/第二关.tscn",    # 第二关：蜈蚣
	"res://Scenes/第三关.tscn",    # 第三关：蚁后（地穴）
	"res://Scenes/第四关.tscn",    # 第四关：人（单臂人偶）
]

## 下一关的下标（0 起）。全通之后会绕回 0。
var next_index : int = 0

func _ready() -> void:
	# 菜单、暂停时的设置都不影响它，但要保证读档早于任何场景。
	process_mode = Node.PROCESS_MODE_ALWAYS
	load_progress()

# ------------------------------------------------------------------
# 查
# ------------------------------------------------------------------

func level_count() -> int:
	return LEVELS.size()

func level_scene(i: int) -> String:
	if LEVELS.is_empty():
		return ""
	return LEVELS[clampi(i, 0, LEVELS.size() - 1)]

## 主菜单「开始游戏」、以及通关 CG 结束时都跳这里。
func next_level_scene() -> String:
	return level_scene(next_index)

## 当前进度是第几关（1 起，给人看的）。
func next_level_number() -> int:
	return next_index + 1

# ------------------------------------------------------------------
# 推进
# ------------------------------------------------------------------

## 本关打完：进度推到下一关，最后一关之后绕回第一关。
## 返回 true 表示刚刚打完的是最后一关（即全部通关、循环回第一关）。
func advance() -> bool:
	if LEVELS.is_empty():
		return false
	next_index = (next_index + 1) % LEVELS.size()
	save_progress()
	return next_index == 0

## 从某一关的场景路径推进一步（关卡脚本清场时用，省得自己记下标）。
func advance_from(scene_path: String) -> bool:
	var i : int = LEVELS.find(scene_path)
	if i >= 0:
		next_index = i
	return advance()

## 重头再来：下次开始游戏回到第一关。
func reset() -> void:
	next_index = 0
	save_progress()

# ------------------------------------------------------------------
# 存档
# ------------------------------------------------------------------

func save_progress() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "next_index", next_index)
	cfg.save(SAVE_PATH)

func load_progress() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		next_index = 0
		return
	next_index = int(cfg.get_value("progress", "next_index", 0))
	if next_index < 0 or next_index >= LEVELS.size():
		next_index = 0
