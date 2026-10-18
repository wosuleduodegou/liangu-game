shader_type canvas_item;

uniform float blur_radius : hint_range(0.0, 10.0) = 2.0;

void fragment() {
	vec4 sum = vec4(0.0);
	float count = 0.0;
	for(float x = -blur_radius; x <= blur_radius; x += 1.0) {
		for(float y = -blur_radius; y <= blur_radius; y += 1.0) {
			sum += texture(TEXTURE, UV + vec2(x, y) * TEXTURE_PIXEL_SIZE);
			count += 1.0;
		}
	}
	COLOR = sum / count;
}
