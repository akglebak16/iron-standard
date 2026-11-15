shader_type canvas_item;
// Pass 2 of the ground painter: colours, relief shading and surf, like paintTerrain() in src/05b_worldart.js.
#include "res://apps/godot/presentation/campaign/terrain_common.gdshaderinc"
uniform sampler2D samples : filter_nearest, repeat_disable;
uniform float step_px = 2.0;
uniform ivec2 size = ivec2(2600, 1700);

vec3 hexc(float r, float g, float b) { return vec3(r, g, b); }

float elev_at(ivec2 p) {
	vec4 s = texelFetch(samples, p, 0) * 255.0;
	return (s.x * 256.0 + s.y) / 65535.0 * 2.0 - 0.5;
}
int type_at(ivec2 p) {
	return int(floor(texelFetch(samples, p, 0).z * 255.0 + 0.5));
}
vec3 land_color(int t, int bio) {
	if (bio == 1) return t == 2 ? hexc(169., 188., 174.) : t == 3 ? hexc(193., 203., 205.) : t == 4 ? hexc(133., 127., 114.) : hexc(217., 226., 228.);
	if (bio == 2) return t == 2 ? hexc(140., 138., 64.) : t == 3 ? hexc(165., 145., 82.) : t == 4 ? hexc(133., 127., 114.) : hexc(176., 159., 88.);
	if (bio == 3) return t == 2 ? hexc(75., 106., 44.) : t == 3 ? hexc(185., 154., 98.) : t == 4 ? hexc(133., 127., 114.) : hexc(205., 176., 120.);
	return t == 2 ? hexc(75., 106., 44.) : t == 3 ? hexc(134., 136., 74.) : t == 4 ? hexc(133., 127., 114.) : hexc(106., 130., 57.);
}
void fragment() {
	ivec2 p = ivec2(floor(FRAGCOORD.xy));
	float x = float(p.x) * step_px;
	float y = float(p.y) * step_px;
	int w = size.x;
	int h = size.y;
	float e = elev_at(p);
	int t = type_at(p);
	vec3 c;
	if (t == 0) {
		float m = clamp((e - 0.1) / 0.2, 0.0, 1.0);
		if (e > 0.27) c = vec3(76., 122., 134.);
		else c = vec3(mix(47. - 8., 47., m), mix(85. - 10., 85., m), mix(104. - 8., 104., m));
	} else {
		c = land_color(t, biome(x, y));
	}
	float il = p.x > 0 ? elev_at(p + ivec2(-1, 0)) : e;
	float ir = p.x < w - 1 ? elev_at(p + ivec2(1, 0)) : e;
	float iu = p.y > 0 ? elev_at(p + ivec2(0, -1)) : e;
	float idn = p.y < h - 1 ? elev_at(p + ivec2(0, 1)) : e;
	float sh = t == 0 ? 0.0 : ((il - ir) + (iu - idn)) * 3.2;
	float n = (noise(3, x / 22.0, y / 22.0) - 0.5) * 30.0 + (noise(3, x / 6.0 + 40.0, y / 6.0) - 0.5) * 14.0;
	if (t == 0) sh = (noise(3, x / 40.0 + 9.0, y / 40.0) - 0.5) * 0.16;
	vec3 col = clamp(c + vec3(n, n, n * 0.8) + sh * 90.0, 0.0, 255.0);
	if (t == 0) {
		bool near1 = (p.x < w - 1 && type_at(p + ivec2(1, 0)) != 0) || (p.y < h - 1 && type_at(p + ivec2(0, 1)) != 0) || (p.x > 0 && type_at(p + ivec2(-1, 0)) != 0) || (p.y > 0 && type_at(p + ivec2(0, -1)) != 0);
		if (near1) {
			col = vec3(205., 205., 180.);
		} else if (p.x > 2 && p.y > 2 && p.x < w - 3 && p.y < h - 3 && (type_at(p + ivec2(2, 0)) != 0 || type_at(p + ivec2(-2, 0)) != 0 || type_at(p + ivec2(0, 2)) != 0 || type_at(p + ivec2(0, -2)) != 0 || type_at(p + ivec2(3, 0)) != 0 || type_at(p + ivec2(-3, 0)) != 0)) {
			col = col * 0.55 + vec3(205., 214., 205.) * 0.45;
		}
	} else {
		bool sea = (p.x < w - 1 && type_at(p + ivec2(1, 0)) == 0) || (p.y < h - 1 && type_at(p + ivec2(0, 1)) == 0) || (p.x > 0 && type_at(p + ivec2(-1, 0)) == 0) || (p.y > 0 && type_at(p + ivec2(0, -1)) == 0);
		if (sea) col = c * 0.55 + vec3(166., 151., 102.) * 0.45;
	}
	COLOR = vec4(floor(col) / 255.0, 1.0);
}
