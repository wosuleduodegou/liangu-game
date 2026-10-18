extends Node

## 通用「代谢」组件：饱食度 / 虚弱 / 冲刺修正。
##
## 挂到任何角色（蛇、蜈蚣……）下面，宿主每帧调 tick(delta, 是否在冲刺)，
## 再去读这几个倍率，自己决定怎么用：
##
##   speed_mult()        巡航速度倍率 —— 饿了会掉
##   stamina_cap_mult()  耐力上限倍率 —— 饿到极限时池子只剩一半
##   sprint_bonus()      冲刺倍率附加 —— 越饿冲得越快（回光返照）
##
## 组件本身不碰宿主的任何属性，所以同一套规则能套在不同生物上，
## 谁强谁弱只差参数。

signal satiety_changed(ratio: float)
signal fed(amount: float)
signal became_weak(is_weak: bool)

@export_group("饱食度")
## 饱食度上限。满值开局。
@export_range(1.0, 400.0, 1.0) var max_satiety : float = 100.0
## 每秒自然消耗。0.35 的话大约五分钟见底，够玩一局又不至于全程饥饿。
@export_range(0.0, 20.0, 0.05, "suffix:/s") var drain_rate : float = 0.35
## 低于这个比例开始虚弱（0.3 = 三成以下）。
@export_range(0.0, 1.0, 0.01) var weak_threshold : float = 0.30
## 虚弱到极限时巡航速度的倍率。
@export_range(0.3, 1.0, 0.01) var weak_speed_mult : float = 0.78

@export_group("冲刺")
## 冲刺时额外消耗的饱食度，跑一趟更饿。
@export_range(0.0, 20.0, 0.05, "suffix:/s") var sprint_satiety_cost : float = 1.6
## 饿到极限时，耐力池只剩原来的多少倍。
@export_range(0.2, 1.0, 0.01) var starved_stamina_mult : float = 0.45
## 饿到极限时冲刺速度的额外加成（0.4 = 再快四成）。
@export_range(0.0, 1.5, 0.01) var starved_sprint_bonus : float = 0.40

var satiety : float = 100.0

var _weak : bool = false

func _ready() -> void:
	satiety = max_satiety
	_weak = is_weak()

# ------------------------------- 查询 -------------------------------
## 0..1 的饱食度比例。
func ratio() -> float:
	return clampf(satiety / maxf(1.0, max_satiety), 0.0, 1.0)

func is_weak() -> bool:
	return ratio() < weak_threshold

## 虚弱时的巡航速度倍率。阈值以上恒为 1，往下平滑掉到 weak_speed_mult。
func speed_mult() -> float:
	var r : float = ratio()
	if r >= weak_threshold:
		return 1.0
	var k : float = r / maxf(0.001, weak_threshold)
	return lerpf(weak_speed_mult, 1.0, k)

## 耐力上限倍率。用开方让中段掉得慢一点，真饿到底才砍半。
func stamina_cap_mult() -> float:
	return lerpf(starved_stamina_mult, 1.0, sqrt(ratio()))

## 冲刺倍率附加。满饱食是 1.0，饿到底 = 1 + starved_sprint_bonus。
func sprint_bonus() -> float:
	return 1.0 + starved_sprint_bonus * (1.0 - ratio())

# ------------------------------- 每帧 -------------------------------
func tick(delta: float, sprinting: bool = false) -> void:
	var rate : float = drain_rate + (sprint_satiety_cost if sprinting else 0.0)
	if rate > 0.0 and satiety > 0.0:
		satiety = maxf(0.0, satiety - rate * delta)
		satiety_changed.emit(ratio())

	var now_weak : bool = is_weak()
	if now_weak != _weak:
		_weak = now_weak
		became_weak.emit(_weak)

## 吃东西。以后接食物 / 啃尸体直接调这个。
func feed(amount: float) -> void:
	if amount <= 0.0:
		return
	satiety = clampf(satiety + amount, 0.0, max_satiety)
	fed.emit(amount)
	satiety_changed.emit(ratio())
	var now_weak : bool = is_weak()
	if now_weak != _weak:
		_weak = now_weak
		became_weak.emit(_weak)
