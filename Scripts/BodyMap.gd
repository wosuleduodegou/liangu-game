extends Control

## Body map: draws the whole creature coiled in an S (or laid out straight),
## colouring every segment by its state (healthy / injured / eaten).
## Pure custom drawing, so one script keeps working at any panel size and for
## any follow-the-leader creature (snake now, maggot later).

enum Part { HEALTHY, INJURED, SEVERED }
enum Shape { S_COIL, STRAIGHT }

## How the body is posed inside the panel.
@export var shape : Shape = Shape.S_COIL
@export var spine_color   : Color = Color(0.42, 0.36, 0.30, 0.75)
@export var healthy_color : Color = Color(0.40, 0.80, 0.45)
@export var injured_color : Color = Color(0.85, 0.28, 0.20)
@export var eaten_color   : Color = Color(0.42, 0.10, 0.08)
@export var frame_color   : Color = Color(0.62, 0.55, 0.44, 0.55)
@export var text_color    : Color = Color(0.90, 0.87, 0.80, 1.0)

## Normalised anchor points of the S pose (0..1 inside the drawing rect).
const ANCHORS_S := [
	Vector2(0.17, 0.12), Vector2(0.48, 0.09), Vector2(0.78, 0.22),
	Vector2(0.84, 0.38), Vector2(0.58, 0.48), Vector2(0.30, 0.55),
	Vector2(0.16, 0.70), Vector2(0.34, 0.86), Vector2(0.70, 0.90),
]
const ANCHORS_LINE := [
	Vector2(0.10, 0.50), Vector2(0.35, 0.50), Vector2(0.65, 0.50), Vector2(0.90, 0.50),
]

var snake = null

func _process(_delta: float) -> void:
	if snake == null or not is_instance_valid(snake):
		snake = get_tree().get_first_node_in_group("snake")
	queue_redraw()

func _draw() -> void:
	var w : float = size.x
	var h : float = size.y
	if w < 40.0 or h < 40.0:
		return

	var font : Font = get_theme_default_font()

	# --- inner frame -------------------------------------------------
	draw_rect(Rect2(1, 1, w - 2, h - 2), Color(0.07, 0.06, 0.05, 0.55), true)
	draw_rect(Rect2(1, 1, w - 2, h - 2), frame_color, false, 2.0)

	# --- geometry ----------------------------------------------------
	var pad : float = 14.0
	# Keep the pose roughly square so it never stretches into a noodle.
	var map_h : float = minf(h * 0.66, (w - pad * 2.0) * 0.92)
	var map_rect := Rect2(pad, pad + 4.0, w - pad * 2.0, map_h)

	if snake == null or not is_instance_valid(snake):
		if font:
			draw_string(font, Vector2(w * 0.5 - 46.0, map_rect.get_center().y), tr("NO SIGNAL"),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.7, 0.65, 0.6, 1.0))
		return

	var n : int = int(snake.points.size())
	if n < 2:
		return
	var states : PackedByteArray = snake.part_state
	var has_states : bool = states.size() == n

	var max_r : float = clampf(minf(map_rect.size.x, map_rect.size.y) * 0.058, 5.0, 18.0)
	var pts : PackedVector2Array = _sample_body(map_rect, n, max_r)

	# --- soft shadow: one smooth stroke behind the whole body ---------
	var shadow := PackedVector2Array()
	shadow.resize(n)
	for i in n:
		shadow[i] = pts[i] + Vector2(0.0, 3.0)
	draw_polyline(shadow, Color(0, 0, 0, 0.30), max_r * 1.9, true)

	# --- segments, tail first so the head sits on top -----------------
	for i in range(n - 1, -1, -1):
		var f : float = float(i) / float(n - 1)
		var p : Vector2 = pts[i]
		var r : float = _radius_at(i, n, max_r)
		var st : int = states[i] if has_states else Part.HEALTHY

		match st:
			Part.SEVERED:
				# hollow dashed ring + cross = bitten off
				draw_circle(p, r, Color(0.05, 0.04, 0.04, 0.75))
				_dashed_ring(p, r + 1.0, eaten_color, 2.0)
				var k : float = r * 0.55
				draw_line(p + Vector2(-k, -k), p + Vector2(k, k), eaten_color, 2.0)
				draw_line(p + Vector2(-k, k), p + Vector2(k, -k), eaten_color, 2.0)
			Part.INJURED:
				draw_circle(p, r * 0.92, injured_color.darkened(0.15))
				draw_arc(p, r * 0.92, 0.0, TAU, 24, Color(1, 0.72, 0.6, 0.85), 1.5, true)
				var d : Vector2 = Vector2(0.72, -0.69) * r * 0.7
				draw_line(p - d, p + d, Color(0.18, 0.03, 0.02, 0.95), 2.4)
			_:
				# no outline: overlapping discs merge into one smooth body
				draw_circle(p, r, healthy_color.darkened(0.05) if f > 0.55 else healthy_color)


	# --- segment ticks, every few segments, short and dim --------------
	var tick_step : int = 5
	if n > 140:
		tick_step = 20
	elif n > 70:
		tick_step = 10
	var i2 : int = tick_step
	while i2 < n - 1:
		var p : Vector2 = pts[i2]
		var nrm : Vector2 = _normal_at(pts, i2)
		var r : float = _radius_at(i2, n, max_r)
		draw_line(p + nrm * (r + 2.0), p + nrm * (r + 7.0), Color(0.6, 0.55, 0.48, 0.45), 1.4)
		i2 += tick_step

	# --- head marker --------------------------------------------------
	var hp : Vector2 = pts[0]
	var hd : Vector2 = (pts[0] - pts[mini(1, n - 1)]).normalized()
	var hr : float = _radius_at(0, n, max_r) * 1.12
	draw_circle(hp, hr, healthy_color.darkened(0.12))
	draw_arc(hp, hr, 0.0, TAU, 28, Color(1, 1, 1, 0.55), 1.6, true)
	var hp_n : Vector2 = Vector2(-hd.y, hd.x)
	if font:
		for s in [-1.0, 1.0]:
			var ep : Vector2 = hp + hd * hr * 0.35 + hp_n * hr * 0.42 * s
			draw_circle(ep, hr * 0.20, Color.WHITE)

	# --- head / tail labels -------------------------------------------
	if font:
		var hs : String = tr("HEAD")
		var hw : float = font.get_string_size(hs, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(font, hp + Vector2(-hw * 0.5, -hr - 10.0), hs,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, text_color)
		var tp : Vector2 = pts[n - 1]
		var ts : String = tr("TAIL")
		draw_string(font, tp + Vector2(12.0, 6.0), ts,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(text_color, 0.8))

	# --- damage report + legend, below the pose -----------------------
	var sep_y : float = map_rect.end.y + 10.0
	draw_line(Vector2(14.0, sep_y), Vector2(w - 14.0, sep_y),
		Color(0.62, 0.55, 0.44, 0.28), 1.0)

	var legend_y : float = h - 14.0
	if font:
		var lx : float = 18.0
		for entry in [
			[healthy_color, "INTACT"],
			[injured_color, "WOUNDED"],
			[eaten_color, "EATEN"],
		]:
			draw_circle(Vector2(lx + 5.0, legend_y - 6.0), 5.5, entry[0])
			draw_string(font, Vector2(lx + 15.0, legend_y), tr(String(entry[1])),
				HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(text_color, 0.85))
			lx += 20.0 + font.get_string_size(tr(String(entry[1])), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x

		if sep_y + 76.0 < legend_y - 26.0:
			_draw_report(font, n, states, has_states, sep_y + 30.0, legend_y - 30.0)

func _draw_report(font: Font, n: int, states: PackedByteArray, has_states: bool,
		top: float, bottom: float) -> void:
	draw_string(font, Vector2(16.0, top - 6.0), tr("DAMAGE REPORT"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.82, 0.77, 0.65))

	var entries : Array = []
	for i in n:
		var st : int = states[i] if has_states else Part.HEALTHY
		if st == Part.SEVERED:
			entries.append([i, "EATEN", eaten_color])
		elif st == Part.INJURED:
			entries.append([i, "WOUNDED", injured_color])

	if entries.is_empty():
		draw_string(font, Vector2(16.0, top + 20.0), tr("NO DAMAGE RECORDED"),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.5, 0.43))
		return

	var row_h : float = 21.0
	var cols : int = 2
	var avail : float = bottom - top
	var max_rows : int = int(maxf(1.0, floorf(avail / row_h)))
	var col_w : float = (size.x - 32.0) / float(cols)
	var shown : int = 0

	for idx in entries.size():
		var c : int = idx % cols
		var r : int = int(idx / cols)
		if r >= max_rows:
			break
		var e : Array = entries[idx]
		var p := Vector2(18.0 + col_w * float(c), top + 18.0 + row_h * float(r))
		var head_txt : String = tr("SEG %02d") % int(e[0])
		draw_string(font, p, head_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.72, 0.67, 0.57))
		var head_w : float = font.get_string_size(head_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x
		draw_string(font, p + Vector2(maxf(70.0, head_w + 14.0), 0.0), tr(String(e[1])),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, e[2])
		shown += 1

	if shown < entries.size():
		var p := Vector2(18.0 + col_w, top + 18.0 + row_h * float(max_rows) - row_h)
		draw_string(font, p, tr("+%d MORE") % (entries.size() - shown),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.55, 0.47))

# ---------------------------------------------------------------------
# Pose helpers
# ---------------------------------------------------------------------

## Maps the creature's n segments onto the pose inside rect, evenly spaced by
## arc length so the coils never bunch up.
func _sample_body(rect: Rect2, n: int, max_r: float) -> PackedVector2Array:
	var inner := rect.grow(-max_r * 0.9)
	if inner.size.x <= 4.0 or inner.size.y <= 4.0:
		inner = rect
	var anchors : Array = ANCHORS_S if shape == Shape.S_COIL else ANCHORS_LINE

	# upsampled spline, already mapped into the rect
	var raw := PackedVector2Array()
	var steps : int = 420
	var last : int = anchors.size() - 1
	for s in steps:
		var u : float = float(s) / float(steps - 1) * float(last)
		var seg : int = mini(int(floor(u)), last - 1)
		var t : float = u - float(seg)
		var p0 : Vector2 = anchors[maxi(seg - 1, 0)]
		var p1 : Vector2 = anchors[seg]
		var p2 : Vector2 = anchors[mini(seg + 1, last)]
		var p3 : Vector2 = anchors[mini(seg + 2, last)]
		var t2 : float = t * t
		var t3 : float = t2 * t
		var q : Vector2 = 0.5 * (
			(2.0 * p1)
			+ (-p0 + p2) * t
			+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
			+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
		)
		raw.append(inner.position + Vector2(q.x * inner.size.x, q.y * inner.size.y))

	# cumulative arc length, then resample evenly
	var cum := PackedFloat32Array()
	cum.resize(raw.size())
	cum[0] = 0.0
	for i in range(1, raw.size()):
		cum[i] = cum[i - 1] + raw[i].distance_to(raw[i - 1])
	var total : float = cum[cum.size() - 1]

	var out := PackedVector2Array()
	out.resize(n)
	var k : int = 0
	for i in n:
		var target : float = total * float(i) / float(maxi(1, n - 1))
		while k < raw.size() - 2 and cum[k + 1] < target:
			k += 1
		var span : float = cum[k + 1] - cum[k]
		var f : float = 0.0 if span <= 0.00001 else (target - cum[k]) / span
		out[i] = raw[k].lerp(raw[k + 1], clampf(f, 0.0, 1.0))
	return out

## Segment radius, taken from the creature's own taper when it exposes one.
func _radius_at(i: int, n: int, max_r: float) -> float:
	var f : float = float(i) / float(maxi(1, n - 1))
	var rel : float = _shape_thickness(f)
	if snake != null and is_instance_valid(snake) and snake.has_method("radius_at"):
		var ref : float = maxf(0.001, float(snake.radius_at(0.35)))
		rel = clampf(float(snake.radius_at(f)) / ref, 0.05, 1.0)
	return max_r * rel

## Fallback taper if the creature does not expose radius_at().
func _shape_thickness(f: float) -> float:
	if f < 0.22:
		return lerpf(0.74, 1.0, f / 0.22)
	elif f < 0.60:
		return lerpf(1.0, 0.86, (f - 0.22) / 0.38)
	return lerpf(0.86, 0.16, pow((f - 0.60) / 0.40, 0.8))

func _normal_at(pts: PackedVector2Array, i: int) -> Vector2:
	var a : Vector2 = pts[maxi(i - 1, 0)]
	var b : Vector2 = pts[mini(i + 1, pts.size() - 1)]
	var d : Vector2 = (b - a).normalized()
	return Vector2(-d.y, d.x)

func _dashed_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	var segs : int = 18
	for s in segs:
		if s % 2 == 1:
			continue
		var a0 : float = TAU * float(s) / float(segs)
		var a1 : float = TAU * float(s + 1) / float(segs)
		draw_arc(center, radius, a0, a1, 4, color, width, true)
