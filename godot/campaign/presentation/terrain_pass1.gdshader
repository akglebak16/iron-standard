shader_type canvas_item;
// Pass 1 of the ground painter: elevation and terrain type of every sample.
// R,G = elevation in 16 bits, B = type / 255.
#include "res://campaign/presentation/terrain_common.gdshaderinc"
uniform float step_px = 2.0;
void fragment() {
	vec2 px = floor(FRAGCOORD.xy);
	float x = px.x * step_px;
	float y = px.y * step_px;
	float e = elevation(x, y);
	int t = terrain(x, y, e);
	float q = clamp((e + 0.5) / 2.0, 0.0, 1.0) * 65535.0;
	float hi = floor(q / 256.0);
	float lo = floor(q - hi * 256.0);
	COLOR = vec4(hi / 255.0, lo / 255.0, float(t) / 255.0, 1.0);
}
