shader_type canvas_item;
render_mode unshaded;
// #title: radial-gradient(ellipse at 50% 40%, #0000, #000c 85%).
void fragment() {
	float radius = length((UV - vec2(0.5, 0.4)) / vec2(0.5, 0.6)) / 1.41421356;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(radius / 0.85, 0.0, 1.0) * 0.8);
}
