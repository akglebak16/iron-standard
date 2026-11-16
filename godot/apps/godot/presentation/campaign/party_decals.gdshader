shader_type canvas_item;

varying float decal;

void vertex() {
	decal = 1.0 - step(0.01, abs(COLOR.a - 0.5));
}

void fragment() {
	if (decal > 0.5) {
		float original_alpha = COLOR.a * 2.0;
		COLOR = vec4(COLOR.rgb / max(original_alpha, 0.001), original_alpha);
	}
}
