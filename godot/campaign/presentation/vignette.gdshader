shader_type canvas_item;
// Darkened edges of the map: radial gradient from the end of paintTerrain() in src/05b_worldart.js.
uniform vec2 map_size = vec2(5200.0, 3400.0);
void fragment() {
	vec2 p = UV * map_size;
	float d = length(p - map_size * 0.5);
	float r0 = map_size.y * 0.55;
	float r1 = map_size.x * 0.62;
	float a = clamp((d - r0) / (r1 - r0), 0.0, 1.0) * 0.4;
	COLOR = vec4(8.0 / 255.0, 6.0 / 255.0, 3.0 / 255.0, a);
}
