@tool
class_name Snake
extends Node2D

# ============================================================
# Controllable procedural snake character.
#
# Proportions follow a SUBADULT SHARP-NOSED VIPER (Deinagkistrodon acutus,
# "five-step snake"): roughly 60 cm total length against a 3 cm mid-body
# diameter, i.e. a length / thickness ratio around 21:1, a wedge shaped head
# noticeably wider than the neck, dark dorsal blotches with pale edges and a
# vertical-slit pupil. Tune everything from the inspector.
#
# The head advances along a heading plus a sine wiggle; every body segment
# follows the previous one at a fixed spacing (follow the leader).
#
# control_mode :
#   0 Wander        - drifts around on its own
#   1 Follow Mouse  - head chases the cursor
#   2 Keyboard      - WASD only (player character)
#   3 External      - driven by your own code through the API below
#
# Keyboard extras :
#   WASD            - crawl (release to glide to a stop)
#   Left Shift      - sprint (drains stamina)
#   E               - enter hunt mode for 3 s: the snake speeds up and every other
#                     animal slows down. A countdown bar floats above the head.
#                     Anything the body sweeps over dies on contact; touching a
#                     centipede or a toad ends hunt mode and starts a 3 s digest,
#                     during which E is ignored (same bar counts it down).
#   G / H / T       - debug: hurt self / heal self / grant temp trait
#
# Passive : hold still for 1 s and the snake fades out — other creatures stop
#   noticing it (no fleeing, no alarm) until it moves again. Any attack, aim or
#   hunt start breaks the stealth instantly.
#
# Public API :
#   steer_toward(dir) / move_toward_point(global_pos) / set_control_mode(m)
#   set_speed(v) / get_head_global_position() / get_body_points()
#   add_trait(dict) / remove_trait(id) / get_attack() / get_speed_multiplier()
#   damage_segment(i, amount, sever) / restore_segment(i) / heal(amount)
#   get_integrity() / get_segment_counts() / reset_body()
# ============================================================

enum Part { HEALTHY, INJURED, SEVERED }

signal health_changed(value: float, max_value: float)
signal stamina_changed(value: float, max_value: float)
signal venom_changed(value: float, max_value: float)
## 一次咬击结算完毕：是否命中、造成多少伤害、命中点与注入的毒素量。
signal bite_landed(hit: bool, damage: float, at_position: Vector2, poison: float)
signal segment_state_changed(index: int, state: int)
signal died

# ------------------------------- Identity -------------------------------
@export_group("Identity")

## Name printed on the status page and in the creature slot list.
@export var display_name : String = "SHARP-NOSED VIPER"

## Small subtitle under the name on the status page.
@export var species_name : String = "Deinagkistrodon acutus"

# ------------------------------- Look -------------------------------
@export_group("Look")

## 整体透明度倍率：1.0 = 正常，0.3 = 只留三成。
## 过场（比如通关页）用它把蛇压淡，不影响玩法逻辑。
@export_range(0.0, 1.0, 0.01) var alpha_scale : float = 1.0

## 是否画蛇头旁边的 HUD（捕猎/消化倒计时条、E 键提示、饥饿等状态）。
## 过场 / CG 里关掉，只留一条干净的蛇。
@export var show_hud : bool = true

## 静止后是否进入隐匿（整体变淡）。过场 / CG 里关掉：
## 蛇站着不动也保持你设定的 alpha_scale，不会自己淡下去。
@export var allow_stealth : bool = true

# ------------------------------- Body shape -------------------------------
@export_group("Body Shape")

## Number of body segments. More segments = smoother body, slightly more cost.
@export_range(8, 200, 1) var segment_count : int = 92

## Distance between two neighbouring segments (px). Length = count * spacing.
@export_range(2.0, 40.0, 0.1, "suffix:px") var segment_spacing : float = 6.6

## Maximum body radius, measured at the thickest point (about 1/3 down the body).
@export_range(2.0, 40.0, 0.5, "suffix:px") var body_radius : float = 15.0

## Radius at the very tip of the tail. Real vipers taper to about 1/12 of the body.
@export_range(0.4, 20.0, 0.1, "suffix:px") var tail_radius : float = 2.6

## Neck thickness as a fraction of body_radius. The head is wider than this.
@export_range(0.3, 1.2, 0.01) var neck_ratio : float = 0.85

## Head length as a multiple of body diameter (body_radius * 2).
@export_range(0.6, 3.0, 0.05) var head_length_scale : float = 1.5

## Head width as a multiple of body diameter. Viper heads are wider than the neck.
@export_range(0.6, 2.5, 0.05) var head_width_scale : float = 1.3

# ------------------------------- Ghost look -------------------------------
@export_group("Ghost Look")

## 外轮廓线。纯度 100% 的白线，整个实体只有线，没有面。
@export var ghost_line : Color = Color(1.0, 1.0, 1.0, 0.96)

## 内部结构线（脊背、骨点、关节）。比外轮廓暗一档，只做层次，不做体积。
@export var ghost_inner : Color = Color(1.0, 1.0, 1.0, 0.45)

## 头部实心贴图颜色。头是实心的一块白，身体是骨架白线。
@export var head_fill : Color = Color(1.0, 1.0, 1.0, 1.0)

## 轮廓线宽度。
@export_range(0.4, 6.0, 0.1, "suffix:px") var ghost_line_width : float = 1.6

## 骨架模式：不画皮肤外轮廓，画脊柱 + 每节椎骨一对肋骨。
## 参考真实蛇骨骼标本：椎骨一节节串成脊柱，肋骨向后弯的长弧，
## 长度跟体宽走（中段长、脖子短、尾尖更短）。

## 肋骨长度是体宽的多少倍。真实骨骼肋骨略长于体宽。
@export_range(0.5, 2.5, 0.05) var rib_len_scale : float = 1.15

## 肋骨向后弯多少（×肋长）。弯得多才有"撑开的样子"。
@export_range(0.0, 1.0, 0.02) var rib_sweep : float = 0.45

## 每隔多少节椎骨伸出一对肋骨。真实骨骼每节都有，但全画会太密；
## 2~3 既保住骨感又留出呼吸的空隙。
@export_range(1, 6, 1) var rib_step : int = 2

## 椎骨骨点大小（×ghost_line_width 的基准）。
@export_range(0.5, 3.0, 0.05) var vertebra_size : float = 1.4

## 受伤段落的标记色。纯白线稿里唯一的异色，压得很淡。
@export var color_injured : Color = Color(0.95, 0.30, 0.24, 1.0)

## 信子。只留一点点血色，主体仍然是白的。
@export var tongue_color : Color = Color(0.98, 0.62, 0.62)

# ------------------------------- Motion -------------------------------
@export_group("Motion")

## Cruise speed in pixels per second.
@export_range(0.0, 900.0, 5.0, "suffix:px/s") var speed : float = 300.0

## How fast the head weaves left and right.
@export_range(0.0, 8.0, 0.05, "suffix:Hz") var wiggle_frequency : float = 2.2

## Weave amplitude in radians. This is what makes the S shaped trail.
@export_range(0.0, 1.5, 0.01, "suffix:rad") var wiggle_amplitude : float = 0.42

## How hard the wander mode turns randomly.
@export_range(0.0, 6.0, 0.05) var wander_strength : float = 1.2

## Steering responsiveness. Higher turns into the desired heading faster.
@export_range(0.5, 30.0, 0.1) var turn_speed : float = 7.0

## In keyboard mode the snake only crawls while a direction key is held and eases
## to a stop when you let go. This is how fast that throttle moves, in units per
## second (1.0 = full speed). Higher = snappier, lower = more glide.
@export_range(0.5, 40.0, 0.5, "suffix:/s") var throttle_response : float = 9.0

## Keep the head inside the viewport when no play bounds are set.
@export var stay_in_viewport : bool = true

## How the snake is driven.
@export_enum("Wander", "Follow Mouse", "Keyboard", "External") var control_mode : int = 0

# ------------------------------- Sprint -------------------------------
@export_group("Sprint")

## Speed multiplier while holding Left Shift.
@export_range(1.0, 4.0, 0.05, "suffix:x") var sprint_multiplier : float = 1.95

## Stamina pool.
@export_range(10.0, 400.0, 5.0) var max_stamina : float = 100.0

## Stamina burnt per second while sprinting.
@export_range(1.0, 200.0, 1.0, "suffix:/s") var sprint_drain : float = 34.0

## Stamina recovered per second while not sprinting.
@export_range(1.0, 200.0, 1.0, "suffix:/s") var stamina_regen : float = 20.0

# ------------------------------- Bite & venom -------------------------------
@export_group("Bite")

## 锁定半径（世界像素）。按 E 时在这段距离内自动锁最近的一只蜈蚣。
@export_range(20.0, 600.0, 1.0, "suffix:px") var bite_range : float = 86.0

## 咬击弧光的张角。现在只影响挥咬特效，**不再参与命中判定**。
@export_range(20.0, 360.0, 1.0, "suffix:deg") var bite_arc_deg : float = 96.0

## Seconds between two bites.
@export_range(0.05, 5.0, 0.01, "suffix:s") var bite_cooldown : float = 0.55

## Short forward lunge when the bite fires, so the strike reads as a snap
## instead of a stationary laser. 1.0 = no lunge.
@export_range(1.0, 4.0, 0.05, "suffix:x") var bite_lunge : float = 2.1

## How long the lunge lasts.
@export_range(0.05, 0.6, 0.01, "suffix:s") var bite_lunge_time : float = 0.17

@export_group("Venom")

## Venom gland capacity. Drawn as its own gauge on the status page.
@export_range(10.0, 400.0, 5.0) var max_venom : float = 100.0

## Venom spent per bite. A bite without enough venom still lands, it is just a
## dry bite: less damage, little or no poison.
@export_range(0.0, 200.0, 1.0) var venom_cost : float = 26.0

## Venom the gland refills per second.
@export_range(0.0, 60.0, 0.5, "suffix:/s") var venom_regen : float = 5.5

## Poison damage per second at a full venom bite.
@export_range(0.0, 60.0, 0.5, "suffix:/s") var poison_dps : float = 7.0

## How long the poison keeps working.
@export_range(0.5, 20.0, 0.1, "suffix:s") var poison_duration : float = 4.5

# ------------------------------- Heat sense -------------------------------
# 蝮蛇靠颊窝感热，黑暗中看不见形，只能"看"到一团模糊的热影。
@export_group("Heat Sense")

## 热感应能感知到多远。超出这个距离就完全看不见了。
@export_range(0.0, 1200.0, 10.0, "suffix:px") var heat_range : float = 700.0

## 移动速度参考值：达到这个速度时热成像几乎全糊成一团。
@export_range(20.0, 600.0, 5.0, "suffix:px/s") var heat_motion_ref : float = 240.0

## 盯着同一只目标多久，热影就会稳定成形（越久越清晰）。
@export_range(0.1, 6.0, 0.05, "suffix:s") var heat_focus_time : float = 0.9

# ------------------------------- Vitals -------------------------------
@export_group("Vitals")

## Maximum health.
@export_range(1.0, 1000.0, 1.0) var max_health : float = 100.0

## Damage added by a bite before trait bonuses.
@export_range(0.0, 500.0, 0.5) var base_attack : float = 12.0

## 饿死开关：>0 时饱食度归零就每秒扣这么多血，直到饿死。0 = 不会饿死。
@export_range(0.0, 50.0, 0.5, "suffix:/s") var starve_dps : float = 0.0
## 饿死/死亡后是否留下尸体（由关卡接管画蓝黑色尸体）。false 时照旧淡出消失。
@export var leave_corpse : bool = false

## Grant the two starter traits (one buff, one debuff) on spawn.
@export var starter_traits : bool = true

## Enable the G / H / T self test keys.
@export var debug_keys : bool = true

# ------------------------------- Bounds & editor -------------------------------
@export_group("Bounds")

## Clamp / bounce the head inside the play area (air walls) instead of the viewport.
@export var use_play_bounds : bool = false

## Shape of the play area. The arena is the inscribed circle of the level, the
## rectangle is a plain box (used by the editor preview).
@export_enum("Rectangle", "Circle") var bounds_shape : int = 1

## Centre of the circular arena, in world space.
@export var bounds_center : Vector2 = Vector2(2500, 2500)

## Radius of the circular arena, in world space. Keep it a little smaller than
## half the map so the body never pokes through the wall.
@export_range(64.0, 12000.0, 1.0, "suffix:px") var bounds_radius : float = 500.0

## World rectangle, only used when bounds_shape is Rectangle.
@export var play_bounds : Rect2 = Rect2(0, 0, 1920, 1080)

# ------------------------------- Vision (pit viper eyes) -------------------------------
@export_group("Vision")

## How far this snake can actually see, in world pixels. Everything past it fades
## to black. Smaller = blinder. Only the SnakeVision filter in the level reads it.
## Kept in step with the camera zoom so the lit disc looks the same on screen.
@export_range(20.0, 900.0, 1.0, "suffix:px") var vision_radius : float = 45.0

## Width of the fade ring, as a fraction of vision_radius (0 = hard edge).
@export_range(0.0, 1.5, 0.05) var vision_softness : float = 0.9

## How black the far side of the screen gets. 1 = pitch black.
@export_range(0.0, 1.0, 0.01) var vision_darkness : float = 1.0

## First slow beat of the fade ends here: this much shade right outside the disc.
@export_range(0.0, 1.0, 0.01) var vision_near_shade : float = 0.06

## Fast middle beat ends here: this much shade at mid_u of the fade ring.
@export_range(0.0, 1.0, 0.01) var vision_mid_shade : float = 0.80

## Where the fast middle beat takes over, as a fraction of the fade ring.
## Smaller = the long dark ramp starts sooner and covers more of the picture.
@export_range(0.0, 1.0, 0.01) var vision_near_u : float = 0.15

## Where the fast middle beat hands back to the slow tail. Bigger = the dark ramp
## is longer, so more of the screen sits in the readable mid-grey zone.
@export_range(0.0, 1.0, 0.01) var vision_mid_u : float = 0.85

## Gain on the lit disc around the head. Below 1 takes the glare off the bright
## centre; the far side is left alone, so near and far get closer in brightness.
@export_range(0.2, 2.0, 0.01) var vision_brightness : float = 0.82

## Colour saturation of the whole picture. Snakes are dichromats, so keep it low.
@export_range(0.0, 1.5, 0.05) var vision_saturation : float = 0.32

## Peripheral blur, in screen pixels. Grows towards the edge of the lit circle.
@export_range(0.0, 8.0, 0.1, "suffix:px") var vision_blur : float = 1.6

## Faint colour cast. Slightly blue-green for a snake's dichromatic eye.
@export var vision_tint : Color = Color(0.93, 1.0, 0.97)

@export_group("Editor Preview")

## Draw the resting pose, dimension lines and measurements in the 2D editor.
@export var show_editor_gizmos : bool = true

## Gizmo line and text colour.
@export var gizmo_color : Color = Color(0.45, 0.82, 1.0, 0.9)

## Pixels per centimetre, only used for the realistic readout in the gizmo text.
## The level is scaled so the body is 1.2 m long: ~600 px / 120 cm = 5.
@export_range(1.0, 40.0, 0.5) var px_per_cm : float = 5.0

# ------------------------------- Runtime state -------------------------------
var points              : PackedVector2Array = []
var head_pos            : Vector2 = Vector2.ZERO
var heading             : float   = 0.0
var facing              : float   = 0.0
var external_direction  : float   = 0.0
var t                   : float   = 0.0

var health    : float = 100.0
var stamina   : float = 100.0
var venom     : float = 100.0
## 作为猎物被打死之后置上。玩家操控的那条蛇永远不会走到这一步。
var _dead     : bool  = false
## 当前实际移动速度（px/s）。热感应用它判断"蛇越慢，热影越清楚"。
var speed_now : float = 0.0
var is_sprinting : bool = false
var exhausted    : bool = false
var traits       : Array[Dictionary] = []
var part_state   : PackedByteArray = PackedByteArray()

# ------------------------------ Aim / bite state ------------------------------
## 瞄准中：蛇停下，等着左键确认。
var aiming : bool = false
## 瞄准方向（弧度）。锁定时自动指向锁定点，没有目标就停在当前朝向。
var aim_angle : float = 0.0
## 当前锁定的目标（蜈蚣）。瞄准时自动锁射程内最近的一只，左键必中。
var lock_target : Node = null
## 锁定点：目标身上离蛇头最近的那个骨节，世界坐标，每帧刷新。
var lock_point : Vector2 = Vector2.ZERO
## 冷却剩余秒数。
var bite_cd : float = 0.0
## 冲刺 / 突进的剩余时间。
var lunge_time : float = 0.0
## 挥咬特效：剩余时间、方向、命中点、伤害，供 Overlay 读取。
var bite_fx_time : float = 0.0
var _shot_debug : bool = false
var bite_fx_dir : float = 0.0
var bite_fx_hit : bool = false
var bite_fx_point : Vector2 = Vector2.ZERO
var bite_fx_damage : float = 0.0
var bite_fx_poison : float = 0.0
## 最近一次咬击是否命中，给 HUD 显示 HIT / MISS。
var last_bite_hit : bool = false
var last_bite_time : float = -999.0

var _rng : RandomNumberGenerator = RandomNumberGenerator.new()
var _editor_sig : String = ""
## 0..1 crawl throttle. Only keyboard mode drives it, so releasing W A S D lets
## the snake glide to a stop instead of freezing mid-slither.
var _throttle : float = 0.0
## Internal: lets tooling render the editor preview outside the editor
## (used for docs / screenshots). Not exported on purpose.
var _preview_override : bool = false

func _is_preview() -> bool:
	return _preview_override or Engine.is_editor_hint()

@onready var head_area  : Area2D           = $HeadArea
@onready var head_shape : CollisionShape2D = $HeadArea/HeadShape
## 代谢组件（可选）。存在时接管饱食度、虚弱、耐力上限和冲刺加成。
@onready var metab = get_node_or_null("Metabolism")

# =============================== Lifecycle ===============================
func _ready() -> void:
	# 编辑器里不建身体：外观重做期间没有预览姿态可摆。
	if _is_preview():
		return

	add_to_group("snake")
	# 蛇是玩家本体：不管场景多黑（CanvasModulate 纯黑）都要看得见，
	# 用 unshaded 材质把自己从环境光里摘出去。
	if material == null:
		var m := CanvasItemMaterial.new()
		m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		material = m
	_rng.randomize()
	heading = _rng.randf_range(0.0, TAU)
	external_direction = heading
	head_pos = Vector2.ZERO
	health = max_health
	stamina = get_max_stamina()
	venom = max_venom
	_apply_head_collision()
	points.resize(segment_count)
	part_state.resize(segment_count)
	for i in segment_count:
		part_state[i] = Part.HEALTHY
	reset_body()
	if starter_traits:
		_grant_starter_traits()

func _apply_head_collision() -> void:
	if head_shape and head_shape.shape is CircleShape2D:
		head_shape.shape.radius = head_width() * 0.5

func _grant_starter_traits() -> void:
	# One buff, one debuff, both permanent: gives the status page content
	# to show from the very first second.
	add_trait({
		"id": "venom_gland",
		"name": "Venom Gland",
		"desc": "Fangs carry venom. +4 ATK.",
		"debuff": false,
		"duration": -1.0,
		"atk": 4.0,
		"speed": 1.0,
	})
	add_trait({
		"id": "cold_blood",
		"name": "Cold Blood",
		"desc": "Sluggish in the cold. -12% speed.",
		"debuff": true,
		"duration": -1.0,
		"atk": 0.0,
		"speed": 0.88,
	})

func _unhandled_input(event: InputEvent) -> void:
	if _is_preview() or control_mode != 2:
		return

	# ---- hunt mode: E toggles, speeds the snake up and slows prey down
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_E:
				toggle_hunt()
				get_viewport().set_input_as_handled()
				return
			KEY_G:
				if debug_keys:
					apply_random_damage(1)
			KEY_H:
				if debug_keys:
					heal(25.0)
					if not part_state.is_empty():
						restore_segment(_rng.randi_range(0, part_state.size() - 1))
			KEY_T:
				if debug_keys:
					add_trait({
						"id": "adrenaline",
						"name": "Adrenaline",
						"desc": "Burst of speed from panic. +25% speed.",
						"debuff": false,
						"duration": 12.0,
						"atk": 2.0,
						"speed": 1.25,
					})

	if not aiming:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			fire_bite()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_aim()
			get_viewport().set_input_as_handled()

## Esc 走 _input：瞄准时先退出瞄准，别让暂停菜单抢走这一下。
func _input(event: InputEvent) -> void:
	if _is_preview() or not aiming:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_aim()
		get_viewport().set_input_as_handled()

# =============================== Hunt mode ===============================
## 捕猎模式开关。按 E 进入，持续 HUNT_DURATION 秒：蛇加速到 1.1 倍，
## 其它动物全场减速到 0.7 倍。
func toggle_hunt() -> void:
	# 已经在捕猎中就不响应，等这根倒计时条自己走完。
	if Snake.hunt_mode:
		return
	# 消化期按 E 也没用：得等胃里那口咽完。
	if Snake.is_digesting():
		return
	Snake.set_hunt(true)
	# 进捕猎模式时清掉瞄准残留（瞄准已被捕猎模式替代）。
	cancel_aim()

## 捕猎模式是否开启。
func is_hunting() -> bool:
	return Snake.hunt_mode

## 蛇头那根竖条的比例（0~1）：捕猎读剩余捕猎时间，消化读剩余消化时间。
## 两者共用同一根条子，同一时刻只会有一个在走。
func hunt_ratio() -> float:
	if Snake.hunt_mode:
		return clampf(Snake.hunt_left / maxf(0.01, HUNT_DURATION), 0.0, 1.0)
	if Snake.is_digesting():
		return clampf(Snake.digest_left / maxf(0.01, DIGEST_DURATION), 0.0, 1.0)
	return 0.0

## 头边竖条此刻该不该出现。
func gauge_active() -> bool:
	return Snake.hunt_mode or Snake.is_digesting()

## 每帧给捕猎计时。走完自动退出，猎物速度也一起恢复。
## 只让玩家那条蛇计时：hunt_mode 是静态量，多一条蛇就会一起扣。
func _tick_hunt(delta: float) -> void:
	if not Snake.hunt_mode or control_mode != 2:
		return
	Snake.hunt_left = maxf(0.0, Snake.hunt_left - delta)
	if Snake.hunt_left <= 0.0:
		Snake.set_hunt(false)
		return
	_tick_hunt_touch()

## 每帧给消化计时。走完清零，E 键恢复可用。
## 同样只让玩家那条蛇计时。
func _tick_digest(delta: float) -> void:
	if Snake.digest_left <= 0.0 or control_mode != 2:
		return
	Snake.digest_left = maxf(0.0, Snake.digest_left - delta)

# =============================== Hunt touch ===============================
## 捕猎期间的"沿途碾压"：蛇身扫过的位置，谁被压到就直接死。
## 命中值给到远超任何生物血量的伤害，走 take_damage 自带的死亡流程
## （蜈蚣 / 蟾蜍 / 蚂蚁都有 _die() + 淡出，不用另写一套）。
const HUNT_KILL_DAMAGE : float = 100000.0

## 判定半径相对于蛇身的额外外扩量。
const HUNT_TOUCH_PAD : float = 5.0

func _tick_hunt_touch() -> void:
	var prey : Array = []
	for g in ["centipede", "toad", "ant"]:
		for n in get_tree().get_nodes_in_group(g):
			if not is_instance_valid(n):
				continue
			if n.has_method("is_dead") and bool(n.call("is_dead")):
				continue
			prey.append(n)
	if prey.is_empty():
		return

	# 蛇身采样：从蛇头到尾，每隔几节取一点，覆盖整条经过的路径。
	var stride : int = maxi(1, int(ceil(body_radius / maxf(1.0, segment_spacing))))
	var body_pts : PackedVector2Array = PackedVector2Array()
	var i : int = 0
	var n_pts : int = points.size()
	while i < n_pts:
		body_pts.append(to_global(points[i]))
		i += stride
	var reach : float = body_radius + HUNT_TOUCH_PAD
	var reach2 : float = reach * reach
	var head_g : Vector2 = to_global(head_pos)

	for p in prey:
		var hit : bool = false
		var lp = p.get("points")
		if lp is PackedVector2Array and not (lp as PackedVector2Array).is_empty():
			for q in lp:
				if _dist2_to_body(body_pts, p.to_global(q)) <= reach2:
					hit = true
					break
		else:
			hit = _dist2_to_body(body_pts, p.global_position) <= reach2
		if not hit:
			continue
		if p.has_method("take_damage"):
			p.call("take_damage", HUNT_KILL_DAMAGE, head_g)
		# 蜈蚣 / 蟾蜍算"捕到了"：收工，捕猎立刻结束，转成消化读秒。
		if p.is_in_group("centipede") or p.is_in_group("toad"):
			Snake.set_hunt(false)
			Snake.start_digest()
			return

## 一个点离蛇身采样链最近的距离平方（只比距离，不算开方）。
func _dist2_to_body(body_pts: PackedVector2Array, p: Vector2) -> float:
	var best : float = INF
	for q in body_pts:
		var d : float = p.distance_squared_to(q)
		if d < best:
			best = d
	return best

# =============================== Stealth ===============================
## 静止隐匿：连着 1 秒不动，其它动物就感觉不到蛇——逃跑、警觉、
## "蛇贴脸就提前跳走"这些反应全部失效。
## 一动、举头瞄准、进捕猎、咬到东西，立刻暴露。
const STILL_HIDE_TIME : float = 1.0
## 算作"静止"的速度上限（px/s）。节流是软衰减，速度不会精确归零。
const STILL_SPEED_EPS : float = 6.0
## 隐匿时的不透明度，以及淡入淡出用的时长。
const HIDDEN_ALPHA : float = 0.62
const HIDDEN_FADE : float = 0.28

## 是否已经被其它动物"感知不到"。
## 注意不能叫 hidden：CanvasItem 已经有 hidden 属性，重名会编译不过。
var stealthed : bool = false
## 已经连续静止了多久。
var _still_time : float = 0.0
## 上一帧的头部位置，用来算真实位移速度。
var _still_anchor : Vector2 = Vector2.INF

## 其它动物感知蛇之前先问这个：true = 感觉不到蛇的存在。
func is_stealthed() -> bool:
	return stealthed

func _tick_hidden(delta: float) -> void:
	# 用头部实际位移算速度，而不是读 speed_now：被外力推动、
	# 被墙弹回来也算"动了"，不会白送一次隐匿。
	var actual_speed : float = 0.0
	if _still_anchor != Vector2.INF:
		actual_speed = head_pos.distance_to(_still_anchor) / maxf(delta, 0.0001)
	_still_anchor = head_pos

	# 任何主动暴露的动作都会把计时清零。
	var exposed : bool = actual_speed > STILL_SPEED_EPS \
		or aiming or Snake.hunt_mode \
		or lunge_time > 0.0 or bite_fx_time > 0.0
	# allow_stealth = false（过场 / CG）时永远不隐匿，也不累计静止时间。
	if exposed or not allow_stealth:
		_still_time = 0.0
		stealthed = false
	else:
		_still_time += delta
		if _still_time >= STILL_HIDE_TIME:
			stealthed = true

	# 视觉：藏住了整体淡下去，玩家一眼就能看出"现在没被察觉"。
	# alpha_scale 是外部给的整体透明度倍率（过场用），默认 1.0 不影响玩法。
	var want : float = (HIDDEN_ALPHA if stealthed else 1.0) * alpha_scale
	if not is_equal_approx(modulate.a, want):
		modulate.a = move_toward(modulate.a, want, delta / HIDDEN_FADE)

# =============================== Aim / bite ===============================
## 进入 / 退出瞄准。按下就直接锁上射程内最近的一只蜈蚣，不用自己对角度。
func toggle_aim() -> void:
	if aiming:
		cancel_aim()
		return
	if bite_cd > 0.0:
		return
	aiming = true
	# 停下时别再滑行：把节流清掉，瞄准才是"原地举头"。
	_throttle = 0.0
	refresh_lock()
	if not has_lock():
		aim_angle = heading

func cancel_aim() -> void:
	aiming = false
	lock_target = null

## 当前锁定是否有效（目标还在、还没死）。
func has_lock() -> bool:
	if lock_target == null or not is_instance_valid(lock_target):
		return false
	if lock_target.has_method("is_dead") and bool(lock_target.call("is_dead")):
		return false
	return true

## 自动锁定：射程内离蛇头最近的骨节，**不看角度**。锁上了就一定能咬到。
## 返回 false 表示范围内没有目标。
func refresh_lock() -> bool:
	var head_g : Vector2 = to_global(head_pos)
	var best_node : Node = null
	var best_point : Vector2 = head_g
	var best_dist : float = bite_range

	for node in get_tree().get_nodes_in_group("centipede"):
		if not is_instance_valid(node):
			continue
		if node.has_method("is_dead") and bool(node.call("is_dead")):
			continue
		var pts = node.get("points")
		if pts == null:
			continue
		for i in pts.size():
			var wp : Vector2 = node.to_global(pts[i])
			var d : float = head_g.distance_to(wp)
			if d < best_dist:
				best_dist = d
				best_node = node
				best_point = wp

	lock_target = best_node
	lock_point = best_point
	if best_node != null:
		aim_angle = (best_point - head_g).angle()
	return best_node != null

## 给瞄准方向（世界坐标点）。锁定模式下不再由鼠标驱动，接口留着给外部脚本用。
func set_aim_point(global_point: Vector2) -> void:
	var head_g : Vector2 = to_global(head_pos)
	var v : Vector2 = global_point - head_g
	if v.length_squared() > 1.0:
		aim_angle = v.angle()

## 左键确认：锁定了就一定咬中，没锁定就是空咬。
func fire_bite() -> void:
	if not aiming:
		return
	if bite_cd > 0.0:
		return

	aiming = false
	bite_cd = bite_cooldown
	# 咬的瞬间再刷一次，防止目标刚跑出射程。
	refresh_lock()
	var locked : bool = has_lock()

	var head_g : Vector2 = to_global(head_pos)
	var dir : Vector2 = Vector2.from_angle(aim_angle)
	if locked:
		dir = (lock_point - head_g).normalized()
		if dir.length_squared() < 0.01:
			dir = Vector2.from_angle(aim_angle)
		aim_angle = dir.angle()

	# 咬的时候整条蛇朝目标一甩，视觉上才像"扑"出去。
	heading = aim_angle
	external_direction = aim_angle
	facing = aim_angle
	lunge_time = bite_lunge_time

	# 毒素不够就是干咬：伤害打折，几乎不留毒。
	var inject : float = 1.0
	if venom_cost > 0.01:
		inject = clampf(venom / venom_cost, 0.0, 1.0)
	var spend : float = minf(venom, venom_cost)
	venom = maxf(0.0, venom - spend)
	venom_changed.emit(venom, max_venom)

	var result : Dictionary
	if locked:
		result = _bite_locked(inject)
	else:
		result = {"hit": false, "damage": 0.0, "at": head_g + dir * bite_range * 0.6, "poison": 0.0}

	var hit : bool = bool(result.get("hit", false))
	var dmg : float = float(result.get("damage", 0.0))
	var at : Vector2 = result.get("at", head_g + dir * bite_range * 0.5)
	var applied_poison : float = float(result.get("poison", 0.0))

	bite_fx_time = 0.42
	bite_fx_dir = aim_angle
	bite_fx_hit = hit
	bite_fx_point = at
	bite_fx_damage = dmg
	bite_fx_poison = applied_poison
	last_bite_hit = hit
	last_bite_time = t
	lock_target = null
	bite_landed.emit(hit, dmg, at, applied_poison)

## 锁定命中：锁上了就直接结算，没有角度判定、也没有距离衰减。
func _bite_locked(inject: float) -> Dictionary:
	var head_g : Vector2 = to_global(head_pos)
	var base : float = get_attack() * lerpf(0.55, 1.0, inject)
	var applied_poison : float = poison_dps * inject

	if lock_target.has_method("take_damage"):
		lock_target.call("take_damage", base, head_g, applied_poison, poison_duration)
	return {"hit": true, "damage": base, "at": lock_point, "poison": applied_poison}

func is_aim_ready() -> bool:
	return bite_cd <= 0.0

func get_venom_ratio() -> float:
	return clampf(venom / maxf(1.0, max_venom), 0.0, 1.0)

## 移动强度：0 = 完全静止，1 ≈ 正常爬行，2 = 冲刺。热成像按它反着算清晰度。
func motion_ratio() -> float:
	return clampf(speed_now / maxf(1.0, heat_motion_ref), 0.0, 2.0)

func _process(delta: float) -> void:
	if _is_preview():
		return
	t += delta
	if metab:
		metab.tick(delta, is_sprinting)
		_tick_starve(delta)
		# 饿瘦了耐力池会缩水，当前耐力不能超过新上限。
		stamina = minf(stamina, get_max_stamina())
		_sync_hunger()
	_tick_bite(delta)
	_tick_hunt(delta)
	_tick_digest(delta)
	_tick_traits(delta)
	_move_head(delta)
	_follow_body()
	_tick_hidden(delta)
	if head_area:
		head_area.position = points[0]
	queue_redraw()

# =============================== Bite timers ===============================
func _tick_bite(delta: float) -> void:
	# 毒腺缓慢合成，跑一段路才回得满。
	if venom < max_venom:
		venom = minf(max_venom, venom + venom_regen * delta)
		venom_changed.emit(venom, max_venom)

	if bite_cd > 0.0:
		bite_cd = maxf(0.0, bite_cd - delta)
	if lunge_time > 0.0:
		lunge_time = maxf(0.0, lunge_time - delta)
	if bite_fx_time > 0.0:
		bite_fx_time = maxf(0.0, bite_fx_time - delta)

	if aiming:
		# 每帧重锁：锁定点跟着目标动，跑出射程就自动丢掉。
		refresh_lock()

# =============================== Movement ===============================
func _move_head(delta: float) -> void:
	var spd : float = speed * get_speed_multiplier()
	# 捕猎模式：蛇整体提速，逼近猎物。
	if Snake.hunt_mode:
		spd *= HUNT_SNAKE_SPEED_MULT
	# 消化期：一口吞下去肚子沉，爬得慢一点。
	if Snake.is_digesting():
		spd *= DIGEST_SPEED_MULT
	var wf  : float = wiggle_frequency
	## Fraction of cruise speed actually used this frame (keyboard mode only).
	var crawl : float = 1.0

	if control_mode == 2:
		# 瞄准中想走开：按 WASD 直接退出瞄准，不用先按 E。
		if aiming and _read_keyboard().length() > 0.1:
			cancel_aim()
		if aiming:
			# 瞄准时原地举头不动，方向跟着鼠标走，等左键确认。
			_throttle = 0.0
			crawl = 0.0
			is_sprinting = false
			_regen_stamina(delta)
			heading = lerp_angle(heading, aim_angle, clampf(turn_speed * 1.6 * delta, 0.0, 1.0))
		else:
			var d : Vector2 = _read_keyboard()
			var moving : bool = d.length() > 0.1
			if moving:
				external_direction = d.angle()
			# No key held = no forward motion. The throttle eases to zero so the stop
			# reads as the snake settling down, not as hitting a wall.
			_throttle = move_toward(_throttle, 1.0 if moving else 0.0, throttle_response * delta)
			crawl = _throttle
			_update_sprint(moving and Input.is_key_pressed(KEY_SHIFT), delta)
			heading = lerp_angle(heading, external_direction, clampf(turn_speed * delta, 0.0, 1.0))
	elif control_mode == 0:
		is_sprinting = false
		_regen_stamina(delta)
		heading += _rng.randf_range(-1.0, 1.0) * wander_strength * delta
	elif control_mode == 1:
		is_sprinting = false
		_regen_stamina(delta)
		var hp  : Vector2 = to_global(head_pos)
		var tgt : Vector2 = get_global_mouse_position()
		if tgt.distance_to(hp) > 4.0:
			var desired : float = (tgt - hp).angle()
			heading = lerp_angle(heading, desired, clampf(turn_speed * delta, 0.0, 1.0))
	else:
		is_sprinting = false
		_regen_stamina(delta)
		heading = lerp_angle(heading, external_direction, clampf(turn_speed * delta, 0.0, 1.0))

	if is_sprinting:
		# 越饿冲刺越猛：饱食度低时冲刺倍率反而往上抬，是那种拼命一窜的感觉。
		spd *= sprint_multiplier * (float(metab.sprint_bonus()) if metab else 1.0)
		wf  *= 1.35

	# 咬击的突进：短促一段，结束后立刻回到正常节流。
	if lunge_time > 0.0:
		var k : float = lunge_time / maxf(0.01, bite_lunge_time)
		spd *= bite_lunge
		wf  *= 1.6
		crawl = maxf(crawl, 0.55 + 0.45 * k)

	spd *= crawl

	var move_angle : float = heading + sin(t * wf) * wiggle_amplitude
	# Standing still: swap the full weave for a slow head sway so the snake looks
	# like it is sniffing the ground instead of twitching in place.
	if crawl < 0.999:
		var idle_sway : float = sin(t * 1.1) * wiggle_amplitude * 0.35
		move_angle = lerpf(move_angle, heading + idle_sway, 1.0 - crawl)
	facing = move_angle
	head_pos += Vector2.from_angle(move_angle) * spd * delta
	speed_now = spd

	# Wall bounce: use the level arena when provided, else the viewport.
	# External control mode is expected to clamp positions itself.
	if control_mode != 3 and (use_play_bounds or stay_in_viewport):
		var wp : Vector2 = to_global(head_pos)
		var bounced : bool = false

		if use_play_bounds and bounds_shape == 1:
			# Circular arena: reflect the heading around the inward normal.
			var off : Vector2 = wp - bounds_center
			var rad : float = maxf(16.0, bounds_radius)
			if off.length() > rad:
				var n : Vector2 = off.normalized()
				wp = bounds_center + n * rad
				var d : Vector2 = Vector2.from_angle(heading)
				d -= 2.0 * d.dot(n) * n          # mirror against the wall normal
				heading = d.angle()
				bounced = true
		else:
			var rect : Rect2 = play_bounds if use_play_bounds else get_viewport_rect()
			if wp.x < rect.position.x or wp.x > rect.end.x:
				heading = PI - heading
				wp.x = clampf(wp.x, rect.position.x, rect.end.x)
				bounced = true
			if wp.y < rect.position.y or wp.y > rect.end.y:
				heading = -heading
				wp.y = clampf(wp.y, rect.position.y, rect.end.y)
				bounced = true

		if bounced:
			head_pos = to_local(wp)

	points[0] = head_pos

func _follow_body() -> void:
	for i in range(1, points.size()):
		var to_prev : Vector2 = points[i] - points[i - 1]
		var dist : float = to_prev.length()
		if dist < 0.0001:
			to_prev = Vector2.from_angle(heading)
			dist = 1.0
		points[i] = points[i - 1] + (to_prev / dist) * segment_spacing

func _read_keyboard() -> Vector2:
	# 只认 WASD。方向键不再参与操控，避免和以后的界面导航打架。
	var ix : float = 0.0
	var iy : float = 0.0
	if Input.is_key_pressed(KEY_A): ix -= 1.0
	if Input.is_key_pressed(KEY_D): ix += 1.0
	if Input.is_key_pressed(KEY_W): iy -= 1.0
	if Input.is_key_pressed(KEY_S): iy += 1.0
	return Vector2(ix, iy)

# =============================== Sprint / stamina ===============================
## 耐力上限。饿到极限时池子只剩不到一半，所以饿蛇冲刺撑不了多久。
func get_max_stamina() -> float:
	if metab == null:
		return max_stamina
	return max_stamina * float(metab.stamina_cap_mult())

func _update_sprint(sprint_held: bool, delta: float) -> void:
	var cap : float = get_max_stamina()
	if stamina <= 0.5:
		exhausted = true
	if exhausted and stamina >= cap * 0.3:
		exhausted = false

	var wants : bool = sprint_held and not exhausted
	if wants:
		is_sprinting = true
		stamina = maxf(0.0, stamina - sprint_drain * delta)
		if stamina <= 0.5:
			exhausted = true
			is_sprinting = false
	else:
		is_sprinting = false
		_regen_stamina(delta)
	stamina_changed.emit(stamina, cap)

func _regen_stamina(delta: float) -> void:
	var cap : float = get_max_stamina()
	if stamina < cap:
		stamina = minf(cap, stamina + stamina_regen * delta)
		stamina_changed.emit(stamina, cap)

# =============================== Stats ===============================
func get_attack() -> float:
	var a : float = base_attack
	for tr in traits:
		a += float(tr.get("atk", 0.0))
	return a

func get_speed_multiplier() -> float:
	var m : float = 1.0
	for tr in traits:
		m *= float(tr.get("speed", 1.0))
	# 饿着肚子游不动。
	if metab:
		m *= float(metab.speed_mult())
	# Missing body parts slow the snake down.
	m *= lerpf(1.0, 0.72, 1.0 - get_integrity())
	return m

## 吃东西。以后接食物 / 啃尸体直接调这个。
func feed(amount: float) -> void:
	if metab:
		metab.feed(amount)

## 饱食度太低时挂一个「饥饿」debuff 到特质列表，状态页能直接看到。
## 实际的速度 / 耐力修正走 Metabolism，trait 里 speed 保持 1.0，不要重复相乘。
func _sync_hunger() -> void:
	if metab == null:
		return
	var weak : bool = bool(metab.is_weak())
	if weak and not has_trait("starving"):
		add_trait({
			"id": "starving",
			"name": "Starving",
			"desc": "Empty belly. Slow crawl and thin stamina, but a desperate burst when sprinting.",
			"debuff": true,
			"duration": -1.0,
			"atk": -2.0,
			"speed": 1.0,
		})
	elif not weak and has_trait("starving"):
		remove_trait("starving")

## 0..1 body integrity: healthy segments count 1, wounded 0.5, eaten 0.
func get_integrity() -> float:
	if part_state.is_empty():
		return 1.0
	var score : float = 0.0
	for v in part_state:
		if v == Part.HEALTHY:
			score += 1.0
		elif v == Part.INJURED:
			score += 0.5
	return score / float(part_state.size())

func get_segment_counts() -> Dictionary:
	var out := {"healthy": 0, "injured": 0, "eaten": 0, "total": part_state.size()}
	for v in part_state:
		if v == Part.HEALTHY:
			out["healthy"] += 1
		elif v == Part.INJURED:
			out["injured"] += 1
		else:
			out["eaten"] += 1
	return out

func heal(amount: float) -> void:
	health = minf(max_health, health + maxf(0.0, amount))
	health_changed.emit(health, max_health)

func damage_segment(index: int, amount: float = 6.0, sever: bool = false) -> void:
	if index < 0 or index >= part_state.size():
		return
	if sever:
		if part_state[index] != Part.SEVERED:
			part_state[index] = Part.SEVERED
			health = maxf(0.0, health - maxf(amount, 8.0) * 1.6)
			segment_state_changed.emit(index, Part.SEVERED)
	else:
		if part_state[index] == Part.HEALTHY:
			part_state[index] = Part.INJURED
			segment_state_changed.emit(index, Part.INJURED)
		health = maxf(0.0, health - amount)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		died.emit()

## 通用受伤入口。签名和蜈蚣 / 蚂蚁 / 蟾蜍保持一致，
## 关卡脚本可以一视同仁地对所有猎物调用，不用为"蛇当敌人"写特例。
## 蛇本身没有分节受伤的玩法，这里只扣总血量。
func take_damage(amount: float, from_global: Vector2 = Vector2.ZERO,
		poison: float = 0.0, poison_time: float = 0.0) -> float:
	if _dead:
		return 0.0
	var dealt : float = minf(health, maxf(0.0, amount))
	health = maxf(0.0, health - maxf(0.0, amount))
	# 毒直接折算成一次总伤：蛇没有单独的毒计时，也不该为它造一套。
	if poison > 0.0 and poison_time > 0.0:
		health = maxf(0.0, health - poison * poison_time * 0.5)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		_die_as_prey()
	return dealt

## 饿死：饱食度归零后持续掉血，直到饿死（走 _die_as_prey）。
var starved_out : bool = false

func _tick_starve(delta: float) -> void:
	if starve_dps <= 0.0 or metab == null or _dead:
		return
	if float(metab.get("satiety")) <= 0.0:
		starved_out = true
		take_damage(starve_dps * delta)

func is_dead() -> bool:
	return _dead

## 作为猎物被打死（第二关那条蛇）：停掉逻辑，淡出，从场上消失。
func _die_as_prey() -> void:
	if _dead:
		return
	_dead = true
	Snake.set_hunt(false)
	set_process(false)
	died.emit()
	if not is_inside_tree():
		queue_free()
		return
	var tw : Tween = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 1.1)
	tw.tween_callback(queue_free)

func restore_segment(index: int) -> void:
	if index < 0 or index >= part_state.size():
		return
	if part_state[index] != Part.HEALTHY:
		part_state[index] = Part.HEALTHY
		segment_state_changed.emit(index, Part.HEALTHY)

func apply_random_damage(count: int = 1) -> void:
	if part_state.is_empty():
		return
	for _i in count:
		var idx : int = _rng.randi_range(0, part_state.size() - 1)
		if _rng.randf() < 0.4:
			damage_segment(idx, 10.0, true)
		else:
			damage_segment(idx, 7.0, false)

# =============================== Traits ===============================
## trait = { id, name, desc, debuff: bool, duration: float (-1 = permanent),
##           atk: float, speed: float (multiplier) }
func add_trait(tdef: Dictionary) -> void:
	var id : String = String(tdef.get("id", ""))
	var t_copy : Dictionary = tdef.duplicate(true)
	t_copy["left"] = float(t_copy.get("duration", -1.0))
	for i in traits.size():
		if String(traits[i].get("id", "")) == id:
			traits[i] = t_copy
			return
	traits.append(t_copy)

func remove_trait(id: String) -> void:
	for i in range(traits.size() - 1, -1, -1):
		if String(traits[i].get("id", "")) == id:
			traits.remove_at(i)

func has_trait(id: String) -> bool:
	for tr in traits:
		if String(tr.get("id", "")) == id:
			return true
	return false

func _tick_traits(delta: float) -> void:
	if traits.is_empty():
		return
	for i in range(traits.size() - 1, -1, -1):
		var left : float = float(traits[i].get("left", -1.0))
		if left < 0.0:
			continue
		left -= delta
		if left <= 0.0:
			traits.remove_at(i)
		else:
			traits[i]["left"] = left

# =============================== Utility ===============================
## Lay the body out in a straight line behind the head. Starting from a stack
## of coincident points would make the follow-the-leader chain fold up into an
## accordion, so this is used on spawn / teleport.
func reset_body() -> void:
	head_pos = Vector2.ZERO
	var back : Vector2 = -Vector2.from_angle(heading)
	for i in points.size():
		points[i] = back * segment_spacing * float(i)
	if head_area:
		head_area.position = points[0]

## Coiled spawn pose: the nose stays on the origin and the rest of the body
## spirals inwards behind it, like a real viper resting in a jar. Needed in the
## small arena, because the body (1.2 m) is longer than the arena radius (1 m) and
## a straight unroll would push the tail straight through the wall.
func reset_body_coiled(face_dir: float) -> void:
	if points.is_empty():
		return
	var span : float = float(maxi(1, points.size() - 1)) * segment_spacing
	# Distance between neighbouring coils, wide enough not to overlap.
	var pitch : float = maxf(body_radius * 2.2, segment_spacing * 2.0)
	var a : float = pitch / TAU
	var th_max : float = sqrt(maxf(2.0 * span / a, 0.0001))
	var phase : float = face_dir - th_max

	for i in points.size():
		var s_to_tail : float = span - float(i) * segment_spacing
		var th : float = sqrt(maxf(2.0 * s_to_tail / a, 0.0))
		var ang : float = th + phase
		# Slightly oval, and the outer coils a touch looser: a perfect circle of
		# evenly spaced rings reads like a mosquito coil, not a resting viper.
		var r : float = a * th * (1.0 + 0.16 * th / th_max)
		points[i] = Vector2(cos(ang) * r, sin(ang) * r * 0.78)

	# Slide the whole coil so the nose lands on the origin again.
	var off : Vector2 = points[0]
	for i in points.size():
		points[i] -= off
	points[0] = Vector2.ZERO

	head_pos = Vector2.ZERO
	heading = face_dir
	facing = face_dir
	external_direction = face_dir
	if head_area:
		head_area.position = points[0]

func head_length() -> float:
	return body_radius * 2.0 * head_length_scale

func head_width() -> float:
	return body_radius * 2.0 * head_width_scale

## Total nose-to-tail length in pixels.
func total_length() -> float:
	return float(maxi(1, segment_count - 1)) * segment_spacing + head_length()

## Body radius at a normalised position, 0 = neck, 1 = tail tip.
func radius_at(f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	if f < 0.22:
		return body_radius * lerpf(neck_ratio, 1.0, smoothstep(0.0, 0.22, f))
	if f <= 0.5:
		return body_radius
	var t2 : float = (f - 0.5) / 0.5
	# 尾巴最低保住 1/3 体宽：骨头到尾尖也是一节一节的锥骨，不是一根针。
	var tail_min : float = body_radius * 0.34
	return maxf(lerpf(body_radius, tail_radius, pow(t2, 1.7)), tail_min)

## 第一节能从头顶楔子底下露出来的体节。体表轮廓和热感应轮廓都从这一节起算，
## 两边的收细规则才对得上。
func _body_first_index() -> int:
	var n : int = points.size()
	var cut : float = head_length() * 0.62
	var d : Vector2 = Vector2.from_angle(facing)
	var i : int = 0
	while i < n - 1:
		var rel : Vector2 = points[i] - points[0]
		if rel.length() >= cut or rel.dot(d) > 0.0:
			break
		i += 1
	return i

# =============================== Light ===============================
## 黑暗里只看得到红线骨架，有光照才看得见白线（体表）。
##
## 光源只有一个：蛇头周围那一小圈，也就是视野圈。SnakeVision 每帧把中心
## 和半径写进这两个静态量，实体画白线时按每个点到中心的距离衰减 alpha。
## light_radius <= 0 表示场景里没有视觉系统（编辑器预览、单体贴图），白线全亮。
static var light_center : Vector2 = Vector2.ZERO
static var light_radius : float = 0.0

## 纯黑模式：光照全丢、黑暗 100%。开启时所有"别的实体"（蜈蚣）的白骨架
## 一律不显形，只剩 AimOverlay 的红线感应。蛇自己是 unshaded，不受影响。
static var dark_mode : bool = false

static func set_dark(on: bool) -> void:
	dark_mode = on

## 捕猎模式：按 E 进入，持续 HUNT_DURATION 秒。蛇加速，其它动物
## （蜈蚣/蚂蚁/蟾蜍）全场减速，营造"猎人逼近、猎物慢动作"的压迫感。
static var hunt_mode : bool = false

## 捕猎模式剩余秒数。归零就自动退出。
static var hunt_left : float = 0.0

## 捕猎模式能持续多久（秒）。
const HUNT_DURATION : float = 3.0

## 捕猎模式下蛇的速度倍率。
const HUNT_SNAKE_SPEED_MULT : float = 1.1

## 捕猎模式下其它动物的速度倍率（减速）。
const HUNT_PREY_SLOW_MULT : float = 0.7

## 消化期：捕到蜈蚣 / 蟾蜍之后要咽下去的那几秒，期间不能再开捕猎。
## 和捕猎同样用头边那根竖条读秒，玩家一眼能看出"还差多久能再出手"。
static var digest_left : float = 0.0

## 消化期长度（秒）。
const DIGEST_DURATION : float = 3.0

## 消化期蛇的速度倍率：刚吞下东西，爬得比平时慢。
const DIGEST_SPEED_MULT : float = 0.8

static func set_hunt(on: bool) -> void:
	hunt_mode = on
	# 开启即把倒计时灌满；关闭（含自然耗尽）就清空，条子才不会残留。
	hunt_left = HUNT_DURATION if on else 0.0

## 是否正在消化（这期间按 E 没反应）。
static func is_digesting() -> bool:
	return digest_left > 0.0

## 开始一次消化。倒计时灌满，走完自动结束。
static func start_digest() -> void:
	digest_left = DIGEST_DURATION

## 白线可见范围的倍率。光圈（视觉暗场 shader）由 vision_radius 直接驱动，
## 白线的可见性则用 vision_radius 再乘这个倍率，两者拆开：
## 想"看得更远"就调大这个，光圈/暗场大小完全不动。
static var light_visibility_scale : float = 2.0

static func set_light(center: Vector2, radius: float) -> void:
	light_center = center
	light_radius = radius

## 某个世界坐标受到的照度，1 = 全亮，0 = 全黑。
## 白线的衰减半径 = light_radius * light_visibility_scale，比光圈更远。
static func light_at(world_pos: Vector2) -> float:
	if dark_mode:
		return 0.0
	if light_radius <= 0.5:
		return 1.0
	var d : float = world_pos.distance_to(light_center)
	var r : float = light_radius * light_visibility_scale
	return 1.0 - smoothstep(r * 0.55, r * 1.05, d)

## 本地坐标版本的照度。
func light_local(p: Vector2) -> float:
	return Snake.light_at(to_global(p))

# =============================== Drawing ===============================
## 仿照蜈蚣那套程序化动画做的蛇：同样只有白线、没有填充没有贴图，
## 同样靠光照（蛇头视野圈）决定白线哪里可见、哪里只剩下 AimOverlay 的骨骼红线。
##
##   * 身体是一条 follow-the-leader 的骨链，转弯时自然甩出 S 形轨迹
##   * 体表沿左右两条边缘描出外轮廓，宽度随 radius_at 从脖子收到尾尖
##   * 头是五步蛇（尖吻蝮）的楔形头：明显比脖子宽、钝吻、竖瞳、颊窝、鼻孔
##   * 张嘴时上颌两半沿"嘴线"向两侧让开，露出毒牙；信子有自己的弹舌节奏
func _draw() -> void:
	if points.is_empty():
		return
	_update_shadow_occluder()
	_draw_body()
	_draw_head()
	_draw_hunt_gauge()
	_draw_hunt_hint()
	if _is_preview():
		_draw_editor_gizmos()

# =============================== Shadow ===============================
## 蛇身的实物投影：遮挡多边形跟 get_heat_outline() 同步，罐顶天光
## 被蛇身挡住，身后拖出影子。不画的时候（编辑器预览）自动闲置。
var _shadow_occ : LightOccluder2D = null

func _update_shadow_occluder() -> void:
	if Engine.is_editor_hint():
		return
	if _shadow_occ == null:
		_shadow_occ = LightOccluder2D.new()
		var poly := OccluderPolygon2D.new()
		poly.closed = true
		_shadow_occ.occluder = poly
		add_child(_shadow_occ)
	_shadow_occ.occluder.polygon = get_heat_outline()

func _draw_body() -> void:
	var n : int = points.size()
	if n < 2:
		return
	var use_state : bool = part_state.size() == n
	var first : int = _body_first_index()

	# ---- 脊柱：椎骨一节节串成链 ----
	# 每节一颗骨点（头尾小、中段大），节间一根短棒。断节处不画。
	for i in range(first, n):
		if use_state and part_state[i] == Part.SEVERED:
			continue
		var f : float = float(i) / float(maxi(1, n - 1))
		var r : float = radius_at(f)
		var c : Vector2 = points[i]
		var col := _surface_col(c, 0.95)
		# 椎骨：骨点大小跟体宽走，但压在一个小范围里，中段才不会鼓成珠串
		var vr : float = ghost_line_width * vertebra_size * lerpf(0.7, 1.25, r / body_radius)
		draw_circle(c, maxf(0.55, vr), col)
		# 椎间棒：连到下一节（下一节是断口就不连）
		if i + 1 < n and not (use_state and part_state[i + 1] == Part.SEVERED):
			var c2 : Vector2 = points[i + 1]
			draw_line(c, c2, _surface_col((c + c2) * 0.5, 0.82), ghost_line_width * 0.85, false)

	# ---- 肋骨：每 rib_step 节伸出一对向后弯的长弧 ----
	# 弧从椎骨出发，先向外撑、再向后收，像真实肋骨那样"包着"身体。
	# 长度跟 radius_at 走：脖子短、中段长、尾尖几乎没了 —— 骨架自己的体型。
	var drawn : int = 0
	for i in range(first, n):
		if use_state and part_state[i] == Part.SEVERED:
			continue
		if drawn % rib_step != 0:
			drawn += 1
			continue
		drawn += 1
		var f : float = float(i) / float(maxi(1, n - 1))
		var rib_len : float = radius_at(f) * rib_len_scale
		# 脖子前几对肋骨短一截：真实骨骼靠近头骨的肋骨是收着的，
		# 不收的话第一对肋骨会一直顶到头骨上。
		rib_len *= lerpf(0.40, 1.0, smoothstep(0.0, 0.12, f))
		if rib_len < 1.6:
			continue
		var tan : Vector2 = _chain_tangent(i)
		var nrm : Vector2 = tan.orthogonal()
		var back : Vector2 = -tan
		var c : Vector2 = points[i]
		for side in [-1.0, 1.0]:
			var sf : float = float(side)
			# 二次贝塞尔：根在椎骨，控制点向外撑，尖端向后收
			var root : Vector2 = c
			var tip : Vector2 = c + nrm * (sf * rib_len) + back * (rib_len * rib_sweep)
			var ctl : Vector2 = c + nrm * (sf * rib_len * 0.78) + back * (rib_len * rib_sweep * 0.15)
			var pts := PackedVector2Array()
			for k in 5:
				var t : float = float(k) / 4.0
				var q1 : Vector2 = root.lerp(ctl, t)
				var q2 : Vector2 = ctl.lerp(tip, t)
				pts.append(q1.lerp(q2, t))
			# 沿弧逐点取光照，伸进光圈的部分才亮
			var cols := PackedColorArray()
			cols.resize(5)
			for k in 5:
				cols[k] = _surface_col(pts[k], 0.80)
			draw_polyline_colors(pts, cols, ghost_line_width * 0.82, false)

	# 伤口：骨架上唯一的一点血色。
	if use_state:
		for k in range(n - 1, first - 1, -1):
			if part_state[k] != Part.INJURED:
				continue
			_draw_wound(points[k], radius_at(float(k) / float(maxi(1, n - 1))))

## 骨链上第 i 节的切线。
func _chain_tangent(i: int) -> Vector2:
	var n : int = points.size()
	var tan : Vector2
	if i <= 0:
		tan = points[1] - points[0]
	elif i >= n - 1:
		tan = points[n - 1] - points[n - 2]
	else:
		tan = points[i + 1] - points[i - 1]
	if tan.length_squared() < 0.0001:
		tan = Vector2.from_angle(facing)
	return tan.normalized()

## 体表白线在某个本地坐标上的颜色（含照度）。mult 用来给肋环压暗一档。
func _surface_col(p: Vector2, mult: float = 1.0) -> Color:
	# 躯体保持纯白、不受光照影响。mult 只用来区分内部层次（椎间棒/肋骨淡一点）。
	return Color(ghost_line.r, ghost_line.g, ghost_line.b, ghost_line.a * mult)

func _draw_wound(p : Vector2, rad: float) -> void:
	var lt : float = light_local(p)
	if lt < 0.02:
		return
	var d    : Vector2 = Vector2.from_angle(facing)
	var perp : Vector2 = Vector2(-d.y, d.x)
	var a : Vector2 = p + perp * rad * 0.62 + d * rad * 0.18
	var b : Vector2 = p - perp * rad * 0.62 - d * rad * 0.18
	draw_line(a, b, Color(color_injured.r, color_injured.g, color_injured.b, 0.40 * lt),
		maxf(1.2, rad * 0.20), true)
	# 一点渗出来的血，压在裂口边上
	draw_circle(p + perp * rad * 0.30, maxf(1.0, rad * 0.11),
		Color(color_injured.r, color_injured.g, color_injured.b, 0.22 * lt))

## 五步蛇（尖吻蝮）的头。
##
## 一个真正会动的楔形头，全部是程序算的：
##   * 上颌左右两半沿"嘴线"向两侧让开，让开的量从下颌关节往吻端逐渐加大
##     —— 这就是张嘴。咬击那一下最大，之后 0.42 秒收回。
##   * 让开的缝里露出两颗向内弯的毒牙。
##   * 头骨风格：不画眼睛和鼻孔——参考真·蝮蛇头骨，就是头骨板、
##     下颌骨、两根向内弯的长毒牙。张嘴时下颌骨独立往前探出。
##   * 信子有自己的弹舌节奏（弹一下、停一下、再小弹一下），张嘴时不吐。
##
## 关键：让开是"沿嘴线平移"，不是整块旋转。旋转会让头的后半段甩开，
## 脖子那里裂成两片；平移只让前端张开，头始终连在脖子上。
func _draw_head() -> void:
	var h : Vector2 = points[0]
	var d : Vector2 = Vector2.from_angle(facing)
	var perp : Vector2 = d.orthogonal()
	var hl : float = head_length()
	var half : float = head_width() * 0.5

	# 张嘴程度：突进和咬击特效的包络取大的那个，再压成 0~1。
	var strike : float = maxf(clampf(bite_fx_time / 0.42, 0.0, 1.0), clampf(lunge_time / 0.17, 0.0, 1.0))
	strike = smoothstep(0.0, 0.40, strike)
	# 静止时也有极轻的呼吸开合，头才不会像一块板。
	var breath : float = 0.030 + 0.030 * sin(t * 1.5)
	var jaw : float = clampf(strike * 0.40 + breath * (1.0 - strike), 0.0, 0.55)
	# 两半让开的实际距离（像素）。
	var gap : float = jaw * half * 0.85

	# 头跟着身体轻轻晃，不是钉死在轴上的。
	h += perp * (sin(t * 2.1) * half * 0.045)

	# 剖面：[沿头轴的位置(×头长), 半宽(×头宽的一半)]
	# 后段先撑到和脖子齐平（衔接处不能有台阶），随后鼓出毒腺（"铲形"），
	# 再收到钝吻。前半段别鼓：鼓了就成鱼头，直着收才像蝮蛇。
	var prof : Array = [
		[-0.52, 0.66], [-0.46, 0.80], [-0.40, 0.92], [-0.33, 0.98],
		[-0.25, 1.00], [-0.15, 1.00], [-0.05, 0.96], [0.06, 0.89],
		[0.18, 0.78], [0.30, 0.66], [0.42, 0.52], [0.52, 0.36],
		[0.60, 0.10],
	]
	if gap < 1.2:
		# 嘴基本闭着：整颗头是一个多边形，先填实心白，再描一圈边。
		var poly : PackedVector2Array = _head_closed(h, d, perp, hl, half, prof)
		draw_colored_polygon(poly, head_fill)
		poly.append(poly[0])
		draw_polyline(poly, ghost_line, ghost_line_width, false)
	else:
		# 张嘴：两半各自填实心白 + 描外沿，中间让开的空隙透出背景。
		for side in [-1.0, 1.0]:
			var sf : float = float(side)
			var pts : PackedVector2Array = _head_half(h, d, perp, hl, half, prof, sf, gap)
			# 两半合起来（内缘嘴线 + 外沿）是一个可填的多边形
			var body := PackedVector2Array()
			for k in _HEAD_STEPS + 1:
				body.append(pts[k])
			# 外沿必须倒着走（吻端→后脑）：pts 里外沿是按 k=STEPS..0 存的，
			# 顺着取会和内缘同方向，多边形成蝴蝶结，三角剖分必挂。
			for k in range(_HEAD_STEPS + 1, pts.size()):
				body.append(pts[k])
			draw_colored_polygon(body, head_fill)
			# 只描外沿，嘴线留在轮廓的缺口里。
			var edge := PackedVector2Array()
			for k in range(_HEAD_STEPS + 1, pts.size()):
				edge.append(pts[k])
			draw_polyline(edge, ghost_line, ghost_line_width, false)
			# 后缘封口：不封的话张开的半边在后脑会齐刷刷断掉
			draw_line(edge[edge.size() - 1], pts[0], ghost_line, ghost_line_width, false)

	# ---- 下颌骨：头骨照片里那根独立的弯骨 ----
	# 平俯视图里它是夹在上颌两半中间的一根窄长骨板：
	# 后端挂在下颌关节上不动，前端随张嘴往前下方（沿头轴）探出去。
	# 闭嘴时整根收进上颌轮廓里，所以只在张嘴时露出来。
	if gap > 0.8:
		var jaw_amt : float = clampf((gap - 0.8) / (half * 0.6), 0.0, 1.0)
		# 下颌骨的剖面：后端窄（关节）、中段最宽、前端收成尖。
		var jprof : Array = [
			[-0.10, 0.30], [0.02, 0.38], [0.14, 0.40], [0.26, 0.34],
			[0.38, 0.24], [0.50, 0.12], [0.58, 0.025],
		]
		# 前端随张嘴往前伸（蛇吞咬时下颌会前移），整体宽度是上颌的一半左右。
		var jw : float = half * 0.52
		var jext : float = hl * (0.10 + 0.16 * jaw_amt)
		var jaw_poly := PackedVector2Array()
		var jn : int = jprof.size()
		for k in jn:   # 左缘：从关节往吻端
			var jp : Array = jprof[k]
			jaw_poly.append(h + d * (hl * float(jp[0]) + jext * (float(jp[0]) + 0.10) / 0.68) + perp * (float(jp[1]) * jw))
		for k in range(jn - 1, -1, -1):   # 右缘：倒着回来
			var jp2 : Array = jprof[k]
			jaw_poly.append(h + d * (hl * float(jp2[0]) + jext * (float(jp2[0]) + 0.10) / 0.68) - perp * (float(jp2[1]) * jw))
		draw_colored_polygon(jaw_poly, head_fill * Color(1, 1, 1, 0.88))
		var jedge := PackedVector2Array(jaw_poly)
		jedge.append(jaw_poly[0])
		draw_polyline(jedge, ghost_line, ghost_line_width * 0.85, false)

	# ---- 毒牙：上颌前端两根向内弯的长钩子（头骨照片那对） ----
	if gap > 0.6:
		var fang_amt : float = clampf((gap - 0.6) / (half * 0.25), 0.0, 1.0)
		var fang_len : float = hl * (0.30 + 0.14 * fang_amt)
		for side in [-1.0, 1.0]:
			var sf : float = float(side)
			# 牙根埋在吻端两侧的上颌里
			var root : Vector2 = _head_point(h, d, perp, hl, 0.40, 0.30, half, sf, gap)
			# 牙尖向内前方弯：先沿头轴伸出去，再往中线收
			var tip : Vector2 = _head_point(h, d, perp, hl, 0.40, 0.30, half, sf, gap) \
				+ d * fang_len + perp * (-half * 0.34 * sf)
			var mid : Vector2 = root.lerp(tip, 0.5) + perp * (half * 0.10 * sf)
			var fcol := Color(0.06, 0.06, 0.07, 0.40 + 0.60 * fang_amt)
			draw_polyline(PackedVector2Array([root, mid, tip]), fcol,
				maxf(1.0, half * 0.058), false)
			draw_circle(tip, maxf(0.8, half * 0.028), fcol)

	# ---- 信子：嘴闭着时才吐，从吻端的缺口里伸出来 ----
	var tg : float = _tongue_amount()
	if tg > 0.01 and gap < 0.55:
		var base : Vector2 = h + d * (hl * 0.56)
		var tl : float = head_width() * (0.20 + 0.52 * tg)
		var tip : Vector2 = base + d * tl
		var col := Color(tongue_color.r, tongue_color.g, tongue_color.b, 0.18 + 0.62 * tg)
		var tw : float = maxf(1.0, head_width() * 0.042)
		draw_line(base, tip, col, tw, true)
		var fork : float = head_width() * 0.20 * tg
		draw_line(tip, tip + (d + perp * 0.62).normalized() * fork, col, tw * 0.85, true)
		draw_line(tip, tip + (d - perp * 0.62).normalized() * fork, col, tw * 0.85, true)

# =============================== Hunt gauge ===============================
## 蛇头右侧那根倒计时条：竖着立，从下往上消耗。
## 竖直方向固定在屏幕轴上（不跟朝向转），剩余量永远"从底往上"读，
## 蛇头朝哪一边都不影响判读。
func _draw_hunt_gauge() -> void:
	if not show_hud or not gauge_active() or points.is_empty():
		return
	var k : float = hunt_ratio()
	var h : Vector2 = points[0]
	var w : float = maxf(7.0, body_radius * 0.42)
	var hgt : float = maxf(46.0, head_length() * 1.6)
	# 立在头右侧：横向让开半个头宽，纵向条子中心对齐头心。
	var x0 : float = h.x + head_width() * 0.55 + 12.0
	var y_bottom : float = h.y + hgt * 0.5
	var track := Rect2(Vector2(x0, y_bottom - hgt), Vector2(w, hgt))

	# 最后三分之一开始闪，提醒"要没了"。
	var pulse : float = 1.0
	if k < 0.34:
		pulse = 0.55 + 0.45 * absf(sin(t * 9.0))

	# 空槽不填色：剩余量之外整段透明，只留一圈极淡的轮廓交代条的边界。
	# 剩余量：纯白，从底往上长。
	if k > 0.0:
		var fill_h : float = hgt * k
		draw_rect(Rect2(Vector2(x0, y_bottom - fill_h), Vector2(w, fill_h)),
			Color(1.0, 1.0, 1.0, 0.96 * pulse))
	draw_rect(track, Color(1.0, 1.0, 1.0, 0.22 * pulse), false, 1.0)
	# 前沿一道小横钩，读数终点更明确。
	draw_line(Vector2(x0 - w * 0.55, y_bottom - hgt * k),
		Vector2(x0 + w * 1.55, y_bottom - hgt * k),
		Color(1.0, 1.0, 1.0, 0.95 * pulse), 1.8, true)

	# 条子右边标出这根条子在数什么：捕猎 / 消化。两段视觉完全一样，
	# 全靠这两个字区分，玩家才知道按 E 没反应是因为还在咽。
	var font : Font = _hint_font_get()
	if font != null:
		var label : String = tr("DIGEST") if Snake.is_digesting() else tr("HUNT")
		# 汉字压到 18 以下、缩到 1280 宽窗口里就糊成一团了。
		var fs : int = 18
		var lsz : Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var lx : float = x0 + w + 9.0
		# 垂直居中于条子中点：get_string_size 给的是行高，baseline 要往下挪约 0.36 行。
		var ly : float = y_bottom - hgt * 0.5 + lsz.y * 0.36
		# 暗底衬：压在浅色背景或蛇身上时也能读清。压得很淡，别成一块补丁。
		draw_rect(Rect2(Vector2(lx - 3.0, ly - lsz.y * 0.76),
			Vector2(lsz.x + 6.0, lsz.y * 0.98)),
			Color(0.03, 0.03, 0.04, 0.26 * pulse))
		draw_string(font, Vector2(lx, ly), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 1.0, 0.92 * pulse))

# =============================== Hunt hint ===============================
## 没在捕猎时，蛇头左侧挂一条键位提示：方框里一个 E，旁边小字"捕猎模式"。
## 位置跟头走，但不跟朝向旋转——方块和文字始终横平竖直，才读得快。
var _hint_font : Font = null

## 提示用的字体：优先拿 GameSettings 里挂好中文回退的那支。
func _hint_font_get() -> Font:
	if _hint_font != null:
		return _hint_font
	var gs = get_node_or_null("/root/GameSettings")
	if gs != null and gs.has_method("cjk_font"):
		_hint_font = gs.call("cjk_font") as Font
	if _hint_font == null:
		_hint_font = load("res://Assets/字体/南西油墨宋.ttf") as Font
	if _hint_font == null:
		_hint_font = ThemeDB.fallback_font
	return _hint_font

func _draw_hunt_hint() -> void:
	# 捕猎 / 消化中让位给倒计时条，避免两条 UI 挤在同一个头旁边；
	# 消化期也不能开捕猎，挂个 E 提示反而误导。
	if not show_hud or gauge_active() or points.is_empty() or control_mode != 2:
		return
	var font : Font = _hint_font_get()
	if font == null:
		return

	var h : Vector2 = points[0]
	var box : float = maxf(26.0, body_radius * 1.7)
	var gap : float = 9.0
	var text : String = tr("HUNT MODE")
	# 汉字笔画密，字号压到 12 以下会糊成一团，下限拉到 15。
	var fs : int = int(maxf(15.0, box * 0.62))

	# 方块贴着头的左侧，垂直略高于头心。
	var box_right : float = h.x - head_width() * 0.55 - gap
	var box_top : float = h.y - box * 0.5 - head_width() * 0.30
	var r := Rect2(Vector2(box_right - box, box_top), Vector2(box, box))

	# 半透明底衬：压在蛇身或骨头上时也能读清。
	draw_rect(r.grow(3.0), Color(0.03, 0.03, 0.04, 0.42))
	draw_rect(r, Color(1.0, 1.0, 1.0, 0.88), false, 1.6)
	# 键位字母居中。
	var e_sz : Vector2 = font.get_string_size("E", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(r.position.x + (box - e_sz.x) * 0.5,
		r.position.y + (box + e_sz.y * 0.72) * 0.5),
		"E", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 1.0, 0.95))

	# 小字在方块左边，右对齐贴着方框。
	var t_sz : Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var baseline : float = r.position.y + (box + t_sz.y * 0.72) * 0.5
	var tx : float = r.position.x - gap - t_sz.x
	draw_string(font, Vector2(tx, baseline),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 1.0, 1.0, 0.90))

# 头形采样的范围与密度。S0 是后脑（收进脖子），S1 是吻端。
const _HEAD_S0 : float = -0.52
const _HEAD_S1 : float = 0.60
const _HEAD_STEPS : int = 22

## 闭合状态的整颗头：左半边正着走、右半边倒着回来，一个多边形。
func _head_closed(h: Vector2, d: Vector2, perp: Vector2, hl: float,
		half: float, prof: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in _HEAD_STEPS + 1:
		var s : float = lerpf(_HEAD_S0, _HEAD_S1, float(k) / float(_HEAD_STEPS))
		pts.append(h + d * (hl * s) + perp * (_head_profile(s, prof) * half))
	for k in range(_HEAD_STEPS, -1, -1):
		var s : float = lerpf(_HEAD_S0, _HEAD_S1, float(k) / float(_HEAD_STEPS))
		pts.append(h + d * (hl * s) - perp * (_head_profile(s, prof) * half))
	return pts

## 张开时的单侧上颌：内缘是"嘴线"（s 越靠前让得越开），外缘是头的外轮廓。
func _head_half(h: Vector2, d: Vector2, perp: Vector2, hl: float, half: float,
		prof: Array, side: float, gap: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in _HEAD_STEPS + 1:
		var s : float = lerpf(_HEAD_S0, _HEAD_S1, float(k) / float(_HEAD_STEPS))
		pts.append(h + d * (hl * s) + perp * _jaw_offset(s, side, gap))
	for k in range(_HEAD_STEPS, -1, -1):
		var s : float = lerpf(_HEAD_S0, _HEAD_S1, float(k) / float(_HEAD_STEPS))
		# 外沿骨厚至少 half*0.08：嘴张得再大，吻端外轮廓也不能被嘴线反超
		# （反超了多边形自交，三角剖分直接失败，半边变成透明）。
		var w : float = _jaw_offset(s, side, gap) \
			+ side * maxf(_head_profile(s, prof) * half, half * 0.08)
		pts.append(h + d * (hl * s) + perp * w)
	return pts

## 张嘴时每侧沿嘴线让开的距离。下颌关节附近为 0，越靠吻端越大，
## 所以头不会从脖子那里裂开，只有前端张开。
func _jaw_offset(s: float, side: float, gap: float) -> float:
	return side * gap * smoothstep(0.05, 0.60, s)

## 头上的一个特征点：沿轴的位置 s、离轴的距离 wf（×半宽）。
func _head_point(h: Vector2, d: Vector2, perp: Vector2, hl: float, s: float,
		wf: float, half: float, side: float, gap: float) -> Vector2:
	return h + d * (hl * s) + perp * (half * wf * side + _jaw_offset(s, side, gap))

## 剖面曲线求值。控制点之间用 Catmull-Rom 插值，而不是直线连——
## 直线连出来的头是有棱有角的"砖头"，插值之后才是肉长出来的曲线。
func _head_profile(s: float, prof: Array) -> float:
	var n : int = prof.size()
	if s <= float(prof[0][0]):
		return float(prof[0][1])
	for k in range(1, n):
		var s1 : float = float(prof[k][0])
		if s <= s1:
			var s0 : float = float(prof[k - 1][0])
			var t : float = clampf((s - s0) / maxf(0.0001, s1 - s0), 0.0, 1.0)
			var p0 : float = float(prof[maxi(0, k - 2)][1])
			var p1 : float = float(prof[k - 1][1])
			var p2 : float = float(prof[k][1])
			var p3 : float = float(prof[mini(n - 1, k + 1)][1])
			return _catmull(p0, p1, p2, p3, t)
	return float(prof[n - 1][1])

func _catmull(p0: float, p1: float, p2: float, p3: float, t: float) -> float:
	var t2 : float = t * t
	var t3 : float = t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)

## 弹舌节奏：快速弹出 → 停一下 → 收回，过一会儿再小的弹一次。
## 用周期函数写，不存状态，所以暂停/恢复也不会乱。
func _tongue_amount() -> float:
	var ph : float = fposmod(t, 2.6)
	if ph < 0.12:
		return smoothstep(0.0, 0.12, ph)
	if ph < 0.26:
		return 1.0
	if ph < 0.40:
		return 1.0 - smoothstep(0.26, 0.40, ph)
	var ph2 : float = ph - 1.45
	if ph2 > 0.0 and ph2 < 0.24:
		return sin(ph2 / 0.24 * PI) * 0.55
	return 0.0

# =============================== Editor gizmos ===============================
func _draw_editor_gizmos() -> void:
	if not show_editor_gizmos:
		return
	var font : Font = ThemeDB.fallback_font
	if font == null:
		return
	var col : Color = gizmo_color
	var dim : Color = Color(gizmo_color, gizmo_color.a * 0.75)
	var fs : int = 14

	var span : float = float(maxi(1, segment_count - 1)) * segment_spacing
	var left : float = -span * 0.5
	var right : float = span * 0.5
	var length_px : float = total_length()
	var dia : float = body_radius * 2.0
	var ratio : float = length_px / maxf(1.0, dia)

	# measurement bar under the body
	var ybar : float = body_radius + 56.0
	draw_line(Vector2(left, ybar), Vector2(right, ybar), col, 1.5, true)
	draw_line(Vector2(left, ybar - 8), Vector2(left, ybar + 8), col, 1.5, true)
	draw_line(Vector2(right, ybar - 8), Vector2(right, ybar + 8), col, 1.5, true)
	draw_line(Vector2(right, ybar), Vector2(right + head_length() * 0.56, ybar), dim, 1.0, true)

	var length_cm : float = length_px / maxf(0.01, px_per_cm)
	draw_string(font, Vector2(left, ybar + 24),
		"LENGTH %.0f px  ~ %.1f cm" % [length_px, length_cm],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	# diameter marker on the left
	var dx : float = left - 34.0
	draw_line(Vector2(dx, -body_radius), Vector2(dx, body_radius), col, 1.5, true)
	draw_line(Vector2(dx - 6, -body_radius), Vector2(dx + 6, -body_radius), col, 1.5, true)
	draw_line(Vector2(dx - 6, body_radius), Vector2(dx + 6, body_radius), col, 1.5, true)
	draw_string(font, Vector2(dx - 96, 4),
		"DIA %.0f px" % dia, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	draw_string(font, Vector2(dx - 96, 22),
		"~ %.1f cm" % (dia / maxf(0.01, px_per_cm)), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)

	# headline readout
	var top : float = -body_radius - 66.0
	draw_string(font, Vector2(left, top),
		"SUBADULT SHARP-NOSED VIPER", HORIZONTAL_ALIGNMENT_LEFT, -1, fs + 2, col)
	draw_string(font, Vector2(left, top + 22),
		"L/D %.1f   SEGMENTS %d   SPACING %.1f px   HEAD %.0f x %.0f px" % [
			ratio, segment_count, segment_spacing, head_width(), head_length()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)

	# head / tail markers
	draw_string(font, Vector2(right + head_length() * 0.56 + 10.0, -body_radius - 6.0),
		"HEAD", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)
	draw_string(font, Vector2(left - 12.0, body_radius + 30.0),
		"TAIL", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, dim)

	# play area, when the level drives the snake with air walls
	if use_play_bounds:
		var bc : Color = Color(col, 0.55)
		if bounds_shape == 1:
			_dashed_circle(to_local(bounds_center), bounds_radius, bc)
			draw_string(font, to_local(bounds_center) + Vector2(-bounds_radius, -bounds_radius - 8.0),
				"PLAY ARENA  r = %d px" % int(bounds_radius),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, bc)
		else:
			var p0 : Vector2 = to_local(play_bounds.position)
			var p1 : Vector2 = to_local(play_bounds.end)
			var r := Rect2(p0, p1 - p0).abs()
			_dashed_rect(r, bc)
			draw_string(font, r.position + Vector2(8, 22),
				"PLAY BOUNDS", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, bc)

func _dashed_circle(c: Vector2, radius: float, col: Color) -> void:
	var seg : int = maxi(32, int(radius * 0.12))
	seg = mini(seg, 240)
	var prev : Vector2 = c + Vector2(radius, 0.0)
	for i in range(1, seg + 1):
		var a : float = TAU * float(i) / float(seg)
		var p : Vector2 = c + Vector2.from_angle(a) * radius
		if i % 2 == 0:
			draw_line(prev, p, col, 1.5, true)
		prev = p

func _dashed_rect(r: Rect2, c: Color) -> void:
	var corners : Array[Vector2] = [
		r.position,
		Vector2(r.end.x, r.position.y),
		r.end,
		Vector2(r.position.x, r.end.y),
	]
	for i in corners.size():
		_dashed_line(corners[i], corners[(i + 1) % corners.size()], c, 1.5)

func _dashed_line(a: Vector2, b: Vector2, c: Color, w: float) -> void:
	var total : float = a.distance_to(b)
	var dir : Vector2 = (b - a) / maxf(0.001, total)
	var step : float = 16.0
	var pos : float = 0.0
	while pos < total:
		var seg_end : float = minf(pos + step * 0.55, total)
		draw_line(a + dir * pos, a + dir * seg_end, c, w, true)
		pos += step

# =============================== Public API ===============================
func steer_toward(dir: Vector2) -> void:
	if dir.length() > 0.001:
		external_direction = dir.angle()

func move_toward_point(target_global: Vector2) -> void:
	var local_target : Vector2 = to_local(target_global)
	if local_target.distance_to(points[0]) > 4.0:
		external_direction = (local_target - points[0]).angle()

func set_control_mode(m: int) -> void:
	control_mode = clampi(m, 0, 3)

func set_speed(v: float) -> void:
	speed = max(0.0, v)

func get_head_global_position() -> Vector2:
	return to_global(points[0])

## 热感应用的自身轮廓（本地坐标，闭合多边形）。
## 沿左右两条边缘各走一遍、再反着接回来，中间是空的 —— 画出来就是"透明 + 描边"。
func get_heat_outline() -> PackedVector2Array:
	var n : int = points.size()
	if n < 2:
		return PackedVector2Array()

	var left := PackedVector2Array()
	var right := PackedVector2Array()
	left.resize(n)
	right.resize(n)

	# 和 _draw_body 用同一套收细规则，热感应的白轮廓才和实体完全重合。
	var first : int = _body_first_index()

	for i in n:
		var f : float = float(i) / float(maxi(1, n - 1))
		var r : float = radius_at(f)
		var k : int = i - first
		if k >= 0 and k < 3:
			r *= lerpf(0.55, 1.0, float(k) / 3.0)
		var tan : Vector2
		if i == 0:
			tan = (points[1] - points[0])
		elif i == n - 1:
			tan = (points[n - 1] - points[n - 2])
		else:
			tan = (points[i + 1] - points[i - 1])
		if tan.length_squared() < 0.0001:
			tan = Vector2.from_angle(heading)
		var nrm : Vector2 = tan.normalized().orthogonal()
		left[i] = points[i] + nrm * r
		right[i] = points[i] - nrm * r

	var out := PackedVector2Array()
	out.append_array(left)
	for i in range(n - 1, -1, -1):
		out.append(right[i])
	out.append(left[0])
	return out

func get_body_points() -> PackedVector2Array:
	var out : PackedVector2Array = []
	out.resize(points.size())
	for i in points.size():
		out[i] = to_global(points[i])
	return out
