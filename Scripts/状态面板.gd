extends CanvasLayer

## Status page (SPACE): traits / buffs / debuffs on the left, vitals in the
## middle, and the unrolled body map on the right with limb integrity.
## Opens as an overlay and pauses the game while it is visible.

const MODE_NAMES := ["WANDER", "MOUSE", "KEYBOARD", "EXTERNAL"]

@onready var root           : Control       = $Root
@onready var stage          : Control       = $Root/Stage
@onready var frame          : PanelContainer = $Root/Stage/Frame
@onready var traits_list    : VBoxContainer = $Root/Stage/Frame/Body/Columns/Left/Scroll/TraitsList
@onready var hp_bar         : ProgressBar   = $Root/Stage/Frame/Body/Columns/Mid/HpBar
@onready var hp_value       : Label         = $Root/Stage/Frame/Body/Columns/Mid/HpRow/HpValue
@onready var atk_value      : Label         = $Root/Stage/Frame/Body/Columns/Mid/AtkRow/AtkValue
@onready var atk_base       : Label         = $Root/Stage/Frame/Body/Columns/Mid/AtkBase
@onready var stam_bar       : ProgressBar   = $Root/Stage/Frame/Body/Columns/Mid/StamBar
@onready var stam_value     : Label         = $Root/Stage/Frame/Body/Columns/Mid/StamRow/StamValue
@onready var sat_bar        : ProgressBar   = $Root/Stage/Frame/Body/Columns/Mid/SatBar
@onready var sat_value      : Label         = $Root/Stage/Frame/Body/Columns/Mid/SatRow/SatValue
@onready var venom_bar      : ProgressBar   = $Root/Stage/Frame/Body/Columns/Mid/VenomBar
@onready var venom_value    : Label         = $Root/Stage/Frame/Body/Columns/Mid/VenomRow/VenomValue
@onready var speed_value    : Label         = $Root/Stage/Frame/Body/Columns/Mid/SpeedRow/SpeedValue
@onready var mode_value     : Label         = $Root/Stage/Frame/Body/Columns/Mid/ModeRow/ModeValue
@onready var state_value    : Label         = $Root/Stage/Frame/Body/Columns/Mid/StateRow/StateValue
@onready var body_map       = $Root/Stage/Frame/Body/Columns/Right/BodyMap
@onready var name_lbl       : Label         = $Root/Stage/Frame/Body/Columns/Right/RightTitle
@onready var name_sub       : Label         = $Root/Stage/Frame/Body/Columns/Right/NameSub
@onready var integrity_lbl  : Label         = $Root/Stage/Frame/Body/Columns/Right/IntegrityLabel
@onready var integrity_det  : Label         = $Root/Stage/Frame/Body/Columns/Right/IntegrityDetail
@onready var slot_list      : VBoxContainer = $Root/Stage/Frame/Body/Columns/Slots/SlotList

## How many playable slots the roster shows. Slot 01 is the creature you are
## driving right now; the rest are reserved for future playables (maggot etc).
const SLOT_COUNT : int = 3

## 设计尺寸（1920x1080 下的面板大小）与四周留白。
const BASE_STAGE := Vector2(1792.0, 984.0)
const STAGE_MARGIN := Vector2(64.0, 48.0)

# Untyped on purpose: the panel talks to the snake through duck typing, so it
# keeps working even if the character script is renamed or replaced.
var snake = null
var _traits_sig : String = ""
var _slots_sig : String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("status_panel")
	root.hide()
	_bind_snake()
	# 静态表头（生命 / 攻击 / 体征…）先记下英文原文并按当前语言铺一遍。
	GameSettings.refresh_ui_text(self)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()

## 这一页信息密度很高，屏幕比例一变（比如 4:3 或超宽）列就会挤。
## 做法：把整块面板按「设计尺寸」摆好，再整体等比缩放到视口内，
## 所以任何分辨率下排版关系都不变，不会串行 / 溢出。
func _fit_stage() -> void:
	var view : Vector2 = get_viewport().get_visible_rect().size
	if view.x <= 1.0 or view.y <= 1.0:
		return
	var need : Vector2 = frame.get_combined_minimum_size()
	var target := Vector2(
		maxf(BASE_STAGE.x, need.x + 8.0),
		maxf(BASE_STAGE.y, need.y + 8.0))
	var k : float = minf(1.0, minf(
		(view.x - STAGE_MARGIN.x * 2.0) / target.x,
		(view.y - STAGE_MARGIN.y * 2.0) / target.y))
	stage.size = target
	stage.pivot_offset = Vector2.ZERO
	stage.scale = Vector2(k, k)
	stage.position = (view - target * k) * 0.5

func _bind_snake() -> void:
	snake = get_tree().get_first_node_in_group("snake")
	if body_map:
		body_map.snake = snake

func is_open() -> bool:
	return root.visible

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		# Do not stack on top of the pause menu.
		var pm = get_tree().get_first_node_in_group("pause_menu")
		if pm and pm.is_open():
			return
		toggle()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and root.visible:
		close()
		get_viewport().set_input_as_handled()

func toggle() -> void:
	if root.visible:
		close()
	else:
		open()

func open() -> void:
	if snake == null or not is_instance_valid(snake):
		_bind_snake()
	_traits_sig = ""
	_slots_sig = ""
	_set_hud_visible(false)
	root.show()
	get_tree().paused = true
	_refresh()

func close() -> void:
	root.hide()
	_set_hud_visible(true)
	get_tree().paused = false

func _set_hud_visible(on: bool) -> void:
	for node in get_tree().get_nodes_in_group("hud"):
		if node is CanvasLayer:
			(node as CanvasLayer).visible = on
		elif node is CanvasItem:
			(node as CanvasItem).visible = on

func _process(_delta: float) -> void:
	if not root.visible:
		return
	if snake == null or not is_instance_valid(snake):
		_bind_snake()
		if snake == null:
			return
	_refresh()

func _refresh() -> void:
	hp_bar.max_value = snake.max_health
	hp_bar.value = snake.health
	hp_value.text = "%d / %d" % [int(round(snake.health)), int(round(snake.max_health))]

	var atk : float = snake.get_attack()
	var bonus : float = atk - snake.base_attack
	atk_value.text = "%d" % int(round(atk))
	atk_base.text = tr("BASE %d  +  TRAITS %s%d") % [
		int(round(snake.base_attack)),
		"+" if bonus >= 0.0 else "",
		int(round(bonus)),
	]

	# 耐力条按「当前 / 上限」显示：饿瘦了上限会缩水，只看百分比会看不出原因。
	var stam_cap : float = snake.max_stamina
	if snake.has_method("get_max_stamina"):
		stam_cap = snake.get_max_stamina()
	var stam_now : float = minf(snake.stamina, stam_cap)
	stam_bar.max_value = maxf(1.0, stam_cap)
	stam_bar.value = stam_now
	stam_value.text = "%d / %d" % [int(round(stam_now)), int(round(stam_cap))]

	# 饱食度：越饿越红，虚弱的来源。
	var metab = snake.get("metab")
	var has_metab : bool = metab != null and is_instance_valid(metab)
	var weak : bool = has_metab and bool(metab.is_weak())
	if has_metab:
		var sat_pct : float = float(metab.ratio()) * 100.0
		sat_bar.max_value = 100.0
		sat_bar.value = sat_pct
		sat_value.text = "%d%%" % int(round(sat_pct))
		sat_value.add_theme_color_override("font_color",
			Color(1.0, 0.55, 0.35) if weak else Color(0.8, 0.9, 0.6))
	else:
		sat_bar.value = 0.0
		sat_value.text = "--"

	# 毒素槽：独立于耐力的一条资源，咬一口掉一段，毒腺慢慢补回来。
	var venom_cap : float = 100.0
	var venom_now : float = 0.0
	var venom_cost : float = 0.0
	if snake.get("max_venom") != null:
		venom_cap = maxf(1.0, float(snake.max_venom))
	if snake.get("venom") != null:
		venom_now = clampf(float(snake.venom), 0.0, venom_cap)
	if snake.get("venom_cost") != null:
		venom_cost = float(snake.venom_cost)
	venom_bar.max_value = venom_cap
	venom_bar.value = venom_now
	venom_value.text = "%d / %d" % [int(round(venom_now)), int(round(venom_cap))]
	# 不够一次咬的量就转橙红，提示这一口会是干咬。
	venom_value.add_theme_color_override("font_color",
		Color(1.0, 0.58, 0.36) if venom_now < venom_cost else Color(0.66, 0.95, 0.45))

	var spd : String = "%d" % int(round(snake.speed * snake.get_speed_multiplier()))
	if snake.is_sprinting:
		spd += "  " + tr("SPRINT")
	speed_value.text = spd
	mode_value.text = tr(MODE_NAMES[clampi(int(snake.control_mode), 0, 3)])

	var counts : Dictionary = snake.get_segment_counts()
	var state_key : String = "NORMAL"
	if snake.health <= 0.0:
		state_key = "DEAD"
	elif snake.health <= snake.max_health * 0.3:
		state_key = "CRITICAL"
	elif int(counts.get("eaten", 0)) > 0:
		state_key = "MAIMED"
	elif int(counts.get("injured", 0)) > 0:
		state_key = "WOUNDED"
	elif snake.exhausted:
		state_key = "EXHAUSTED"
	elif weak:
		state_key = "WEAK"
	state_value.text = tr(state_key)

	var intact : int = int(counts.get("total", 0)) - int(counts.get("eaten", 0))
	var pct : float = snake.get_integrity() * 100.0
	integrity_lbl.text = tr("LIMB INTEGRITY   %5.1f%%") % pct
	integrity_det.text = tr("%d / %d SEGMENTS INTACT      WOUNDED %d      EATEN %d") % [
		intact,
		int(counts.get("total", 0)),
		int(counts.get("injured", 0)),
		int(counts.get("eaten", 0)),
	]
	integrity_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.45, 0.4) if snake.get_integrity() < 0.75 else Color(0.95, 0.85, 0.62))

	_refresh_identity()
	_refresh_slots(counts)
	_rebuild_traits()

## Creature name shown above the body map, plus the species under it.
func _refresh_identity() -> void:
	name_lbl.text = tr(_display_name())

	var species : String = ""
	if snake != null and is_instance_valid(snake):
		var v = snake.get("species_name")
		if v != null:
			species = String(v).strip_edges()
	var base : String = tr("S-COILED BODY MAP")
	name_sub.text = base if species == "" else "%s   /   %s" % [base, species]

func _display_name() -> String:
	if snake == null or not is_instance_valid(snake):
		return "UNKNOWN CREATURE"
	var v = snake.get("display_name")
	if v == null:
		return "CREATURE"
	var nm : String = String(v).strip_edges()
	return nm.to_upper() if nm != "" else "CREATURE"

## Roster of playable creatures. Slot 01 is the one being controlled, the rest
## are placeholders so the layout already has room for the next characters.
func _refresh_slots(counts: Dictionary) -> void:
	var hp_txt : String = tr("HP %d / %d") % [int(round(snake.health)), int(round(snake.max_health))]
	var seg_txt : String = tr("%d SEGMENTS") % int(counts.get("total", 0))
	var nm : String = tr(_display_name())
	var sig : String = "%s|%s|%s|%s" % [nm, hp_txt, seg_txt, GameSettings.language]
	if sig == _slots_sig:
		return
	_slots_sig = sig

	for child in slot_list.get_children():
		child.queue_free()

	for idx in SLOT_COUNT:
		slot_list.add_child(_make_slot(idx, nm, hp_txt, seg_txt))

func _make_slot(idx: int, nm: String, hp_txt: String, seg_txt: String) -> Control:
	var active : bool = idx == 0

	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	if active:
		sb.bg_color = Color(0.13, 0.20, 0.14, 0.75)
		sb.border_color = Color(0.45, 0.85, 0.5)
	else:
		sb.bg_color = Color(0.14, 0.12, 0.10, 0.55)
		sb.border_color = Color(0.45, 0.40, 0.34)
	sb.border_width_left = 6
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	row.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	row.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)

	var tag := Label.new()
	tag.text = tr("SLOT %02d") % (idx + 1)
	tag.add_theme_color_override("font_color", Color(0.62, 0.57, 0.48))
	tag.add_theme_font_size_override("font_size", 16)
	head.add_child(tag)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)

	var state_l := Label.new()
	state_l.text = tr("ACTIVE") if active else tr("EMPTY")
	state_l.add_theme_color_override("font_color",
		Color(0.55, 0.95, 0.58) if active else Color(0.55, 0.50, 0.43))
	state_l.add_theme_font_size_override("font_size", 16)
	head.add_child(state_l)

	var name_l := Label.new()
	name_l.text = nm if active else tr("UNASSIGNED")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.add_theme_color_override("font_color",
		Color(0.96, 0.92, 0.82) if active else Color(0.55, 0.50, 0.43))
	name_l.add_theme_font_size_override("font_size", 24)
	vb.add_child(name_l)

	var detail := Label.new()
	detail.text = ("%s      %s" % [hp_txt, seg_txt]) if active else tr("RESERVED FOR THE NEXT PLAYABLE")
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_color_override("font_color",
		Color(0.78, 0.73, 0.64) if active else Color(0.50, 0.46, 0.40))
	detail.add_theme_font_size_override("font_size", 16)
	vb.add_child(detail)

	return row

func _rebuild_traits() -> void:
	var parts : PackedStringArray = []
	for entry in snake.traits:
		parts.append("%s:%d" % [String(entry.get("id", "")), int(ceil(float(entry.get("left", -1.0))))])
	var sig : String = "|".join(parts) + "@" + GameSettings.language
	if sig == _traits_sig:
		return
	_traits_sig = sig

	for child in traits_list.get_children():
		child.queue_free()

	if snake.traits.is_empty():
		var empty := Label.new()
		empty.text = tr("NO ACTIVE TRAITS")
		empty.add_theme_color_override("font_color", Color(0.55, 0.5, 0.43))
		empty.add_theme_font_size_override("font_size", 22)
		traits_list.add_child(empty)
		return

	for entry in snake.traits:
		traits_list.add_child(_make_trait_row(entry))

func _make_trait_row(tr_name: Dictionary) -> Control:
	var debuff : bool = bool(tr_name.get("debuff", false))

	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.30, 0.10, 0.08, 0.55) if debuff else Color(0.11, 0.26, 0.14, 0.6)
	sb.border_width_left = 7
	sb.border_color = Color(0.88, 0.32, 0.24) if debuff else Color(0.45, 0.85, 0.5)
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	row.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	row.add_child(vb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)

	var tag := Label.new()
	tag.text = tr("DEBUFF") if debuff else tr("BUFF")
	tag.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.36) if debuff else Color(0.55, 0.95, 0.58))
	tag.add_theme_font_size_override("font_size", 17)
	head.add_child(tag)

	var name_l := Label.new()
	name_l.text = tr(String(tr_name.get("name", "UNKNOWN")))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82))
	name_l.add_theme_font_size_override("font_size", 25)
	head.add_child(name_l)

	var left : float = float(tr_name.get("left", -1.0))
	var time_l := Label.new()
	time_l.text = tr("PERM") if left < 0.0 else tr("%ds") % int(ceil(left))
	time_l.add_theme_color_override("font_color",
		Color(0.68, 0.62, 0.52) if left < 0.0 else Color(1.0, 0.82, 0.4))
	time_l.add_theme_font_size_override("font_size", 20)
	head.add_child(time_l)

	var desc := Label.new()
	desc.text = tr(String(tr_name.get("desc", "")))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.78, 0.73, 0.64))
	desc.add_theme_font_size_override("font_size", 18)
	vb.add_child(desc)

	return row
