shader_type canvas_item;
render_mode unshaded;

// What the world looks like through this snake's eyes. Full screen post pass:
//   1) heavy desaturation, with a faint blue-green cast (pit vipers are dichromats)
//   2) blur that grows towards the edge of the lit circle (bad peripheral vision)
//   3) a small disc around the head stays clear, the rest fades out in three beats:
//      slow -> fast -> slow, so the darkness creeps up on you instead of slamming shut
//
// The uniforms are driven every frame by SnakeVision.gd from the snake's
// Vision export group, so tuning the snake tunes the filter.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform vec2  center = vec2(0.5);          // head position on screen, in UV
uniform float aspect = 1.77778;            // viewport width / height
uniform float radius = 0.14;               // clear disc radius, unit = screen height
uniform float softness = 0.6;              // fade ring width, relative to radius
uniform float saturation = 0.32;
uniform float blur_amount = 1.6;           // in screen pixels
uniform vec3  tint = vec3(0.93, 1.0, 0.97);
uniform float inner_dim = 0.18;            // gentle dimming towards the disc edge
// Overall gain on the lit disc. < 1 takes the glare off the bright centre without
// touching the far side, which keeps the contrast between near and far flatter.
uniform float brightness = 0.82;

// 0 = nothing left to see (pure black), 1 = untouched. 0.8 keeps a readable 20%.
uniform float darkness = 0.8;
uniform float near_shade = 0.06;           // shading where the slow first beat ends
uniform float mid_shade = 0.80;            // shading where the fast middle beat ends
uniform float near_u = 0.15;               // where the middle beat starts (0..1)
uniform float mid_u = 0.85;                // where the middle beat ends (0..1)

uniform bool  filter_on = true;

// Built-ins like SCREEN_UV only exist inside fragment(), so the caller passes
// the pixel size in (1 / viewport height) instead of reading it here.
vec3 blurred(vec2 uv, float px, float inv_h) {
	float b = px * inv_h;
	vec3 c = texture(screen_tex, uv).rgb * 0.36;
	c += texture(screen_tex, uv + vec2( b, 0.0)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(-b, 0.0)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(0.0,  b)).rgb * 0.16;
	c += texture(screen_tex, uv + vec2(0.0, -b)).rgb * 0.16;
	return c;
}

// Three-beat falloff along u (0 at the edge of the clear disc, 1 at the far end).
// Each beat is a smoothstep, so every join is flat: slow, fast, slow.
// near_u / mid_u set how much of the ring the fast middle beat owns.
float falloff(float u) {
	float a = min(near_u, mid_u - 0.001);
	if (u < a) {
		return mix(0.0, near_shade, smoothstep(0.0, max(a, 0.001), u));
	}
	if (u < mid_u) {
		return mix(near_shade, mid_shade, smoothstep(a, mid_u, u));
	}
	return mix(mid_shade, 1.0, smoothstep(mid_u, 1.0, u));
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;

	if (filter_on) {
		vec2 d = (SCREEN_UV - center) * vec2(aspect, 1.0);
		float dist = length(d);
		float outer = max(radius * (1.0 + softness), radius + 0.001);
		float u = clamp((dist - radius) / (outer - radius), 0.0, 1.0);

		col = blurred(SCREEN_UV, blur_amount * (0.25 + u), SCREEN_PIXEL_SIZE.y);

		float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
		col = mix(vec3(lum), col, saturation) * tint;

		// Take some glare off the lit disc only; the far side is left alone.
		col *= mix(brightness, 1.0, smoothstep(0.0, 0.45, u));
		col *= 1.0 - inner_dim * smoothstep(0.0, radius, dist);
		col = mix(col, vec3(0.0), falloff(u) * darkness);
	}

	COLOR = vec4(col, 1.0);
}
