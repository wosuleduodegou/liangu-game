shader_type canvas_item;
render_mode unshaded;

// 阳光穿过尘土：一束从左上角约 15° 斜射进来的光，光柱里漂着缓慢浮动的浮尘。
// 像久未开封的陶罐——光很淡，灰尘肉眼勉强可见，懒洋洋地往左上角飘。
//
// 思路：
//   1) 画一束平行光柱：方向固定（左上→右下，约 15°），用距离光轴的带通 + 轴向上的
//      渐变做出一条有明暗起伏的"光带"。
//   2) 在光柱里铺一层浮尘：用屏幕 UV 做哈希，散出一堆小亮点，每个点带一点
//      布朗抖动，整体再往左上角缓慢漂移（dust_drift），看起来像尘埃在光里浮。
//   3) 整体压得很淡（intensity），只叠亮、不改暗，不会盖掉白线。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec2  aspect = vec2(1.77778, 1.0);   // 屏幕宽高比（宽/高, 1）
uniform float beam_angle = 15.0;             // 光柱与竖直方向的夹角（度），左上→右下
uniform float beam_center = 0.35;            // 光柱中心穿过屏幕的位置（x 方向 0..1，靠近左上）
uniform float beam_width = 0.55;             // 光柱半宽（占屏幕宽的比例）
uniform float beam_soft = 0.6;               // 光柱边缘柔度
uniform float intensity = 0.16;              // 光柱整体强度，越淡越像浮尘
uniform float dust_density = 0.9;            // 浮尘密度
uniform float dust_size = 1.6;               // 单颗浮尘的像素大小
uniform float dust_brightness = 0.5;         // 浮尘亮点强度
uniform vec2  dust_drift = vec2(0.08, 0.05); // 浮尘整体漂移方向（左上），每秒 UV
uniform float time_scale = 1.0;              // 时间流速

// 一个稳定的 2D 哈希，把网格点映射到 [0,1)。
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

// 平滑的伪随机噪声（用来做浮尘的布朗抖动）。
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y);
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	// 光轴方向：竖直向下为基准，往右偏 beam_angle 度（左上角射进来的光往右下走）。
	float ang = radians(beam_angle);
	vec2 dir = vec2(sin(ang), cos(ang));   // 指向右下
	// 光柱中心线：过屏幕左上区域 (beam_center, 0) 沿 dir 方向。
	vec2 p = SCREEN_UV * aspect;           // 修正宽高比，让角度在屏幕上看起来是真的 15°
	vec2 origin = vec2(beam_center * aspect.x, 0.0);
	vec2 rel = p - origin;
	// 到光轴的有符号距离（垂直方向）。
	vec2 nrm = vec2(-dir.y, dir.x);
	float dist = dot(rel, nrm);
	// 沿光轴方向的位置（0 在顶部，越大越靠右下），用来做光带渐变。
	float along = dot(rel, dir);

	// 光带：越靠顶部越亮，往下逐渐散开变淡；横向用带通，边缘柔化。
	float band = exp(-pow(dist / (beam_width * aspect.x), 2.0) * (1.0 - beam_soft));
	float axial = exp(-along * 1.6);       // 顶部亮，往下衰减
	float beam = band * axial * intensity;

	// 浮尘：在光柱里铺一层稀疏的亮点。
	// 用一套慢速漂移的坐标采样噪声，做每个"尘胞"的抖动和位置。
	vec2 cell = p * (1.0 / (dust_size * 0.02));   // 把屏幕切成尘胞
	vec2 drift = dust_drift * TIME * time_scale;
	vec2 wobble = vec2(vnoise(cell * 3.0 + drift), vnoise(cell * 3.0 - drift * 0.7));
	vec2 cid = floor(cell + wobble * 0.4);
	float rnd = hash21(cid);
	// 每个尘胞里取一个随机点，只有 hash 超过阈值的才点亮，稀疏化。
	float thresh = 1.0 - dust_density;
	float present = step(thresh, rnd);
	// 尘点相对胞中心的小偏移 + 时间漂移，让它缓慢往左上飘。
	vec2 off = vec2(hash21(cid + 7.0), hash21(cid + 13.0)) - 0.5;
	vec2 fp = (cid + off) * (dust_size * 0.02) - drift * 0.5;
	float d2 = length((p - fp) * aspect);
	// 一个很小的亮点，带柔和边缘。
	float mote = exp(-d2 * d2 * 2200.0);
	// 浮尘只在光柱里可见（被阳光照亮），再乘一点随时间闪烁。
	float twinkle = 0.75 + 0.25 * sin(TIME * (1.3 + hash21(cid) * 2.0) + hash21(cid + 5.0) * 6.28);
	float dust = present * mote * beam * dust_brightness * twinkle;

	// 只叠亮，不改暗：原画面 + 光柱 + 浮尘，浮尘偏暖白。
	vec3 light = vec3(1.0, 0.97, 0.90);
	col += light * beam;
	col += light * dust;

	COLOR = vec4(col, 1.0);
}
