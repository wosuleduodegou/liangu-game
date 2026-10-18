shader_type canvas_item;

// 标题美术的投影。
//
// 只用自身贴图的 alpha：先做一圈模糊 + 加粗，再把结果填成深墨色、整体压成
// 半透明。看起来就是标题把影子落在背后的纸上，而标题原本的花色完全不参与，
// 所以阴影始终是一团均匀的暗色，不会把字描成两层。
//
// 偏移由节点位置负责（主菜单脚本里跟着标题一起缩放），这里只做形状。

uniform vec4  shadow_color : source_color = vec4(0.05, 0.035, 0.02, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.44;
// 模糊半径，按贴图像素算。贴图越大，这个值要跟着放大。
uniform float blur_px : hint_range(0.0, 32.0) = 8.0;
// 把 alpha 抬粗，避免大字阴影中间发空、边缘断裂。
uniform float thickness : hint_range(0.0, 4.0) = 1.35;

void fragment() {
	vec2 t = TEXTURE_PIXEL_SIZE * blur_px;
	vec2 o = t * 0.72;

	float a = texture(TEXTURE, UV).a * 0.24;
	a += (texture(TEXTURE, UV + vec2( t.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(-t.x, 0.0)).a
		+ texture(TEXTURE, UV + vec2(0.0,  t.y)).a
		+ texture(TEXTURE, UV + vec2(0.0, -t.y)).a) * 0.11;
	a += (texture(TEXTURE, UV + vec2( o.x,  o.y)).a
		+ texture(TEXTURE, UV + vec2(-o.x,  o.y)).a
		+ texture(TEXTURE, UV + vec2( o.x, -o.y)).a
		+ texture(TEXTURE, UV + vec2(-o.x, -o.y)).a) * 0.06;

	a = clamp(a * thickness, 0.0, 1.0);
	COLOR = vec4(shadow_color.rgb, a * opacity * shadow_color.a);
}
