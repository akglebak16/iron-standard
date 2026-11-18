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
	if (bio == 1) return t == 2 ? hexc(169., 188., 174.) : t == 3 ? hexc(193., 203., 205.) : t == 4 ? hexc(162., 152., 110.) : hexc(217., 226., 228.);
	if (bio == 2) return t == 2 ? hexc(140., 138., 64.) : t == 3 ? hexc(165., 145., 82.) : t == 4 ? hexc(162., 152., 110.) : hexc(176., 159., 88.);
	if (bio == 3) return t == 2 ? hexc(112., 128., 65.) : t == 3 ? hexc(185., 154., 98.) : t == 4 ? hexc(162., 152., 110.) : hexc(205., 176., 120.);
	return t == 2 ? hexc(112., 128., 65.) : t == 3 ? hexc(161., 152., 88.) : t == 4 ? hexc(162., 152., 110.) : hexc(168., 164., 92.);
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
		float shelf = smoothstep(0.16, 0.332, e);
		c = mix(vec3(28., 78., 85.), vec3(62., 117., 112.), shelf);
		float swell = y * 0.16 + sin(x * 0.024 + y * 0.012) + noise(3,x/54.,y/32.) * 2.3;
		float ink = smoothstep(0.92,1.0,cos(swell)) * smoothstep(0.54,0.74,noise(2,x/78.,y/31.));
		c += ink * vec3(13.,19.,15.);
	} else {
		c = land_color(t, biome(x, y));
	}
	float il = p.x > 0 ? elev_at(p + ivec2(-1, 0)) : e;
	float ir = p.x < w - 1 ? elev_at(p + ivec2(1, 0)) : e;
	float iu = p.y > 0 ? elev_at(p + ivec2(0, -1)) : e;
	float idn = p.y < h - 1 ? elev_at(p + ivec2(0, 1)) : e;
	float sh = t == 0 ? 0.0 : ((il - ir) + (iu - idn)) * 3.2;
	float n = (noise(3, x / 22.0, y / 22.0) - 0.5) * 18.0 + (noise(3, x / 6.0 + 40.0, y / 6.0) - 0.5) * 6.0;
	if (t == 0) sh = (noise(3, x / 40.0 + 9.0, y / 40.0) - 0.5) * 0.16;
	vec3 col = clamp(c + vec3(n, n, n * 0.8) + sh * 90.0, 0.0, 255.0);
	if (t == 0) {
		bool near1 = (p.x < w - 1 && type_at(p + ivec2(1, 0)) != 0) || (p.y < h - 1 && type_at(p + ivec2(0, 1)) != 0) || (p.x > 0 && type_at(p + ivec2(-1, 0)) != 0) || (p.y > 0 && type_at(p + ivec2(0, -1)) != 0);
		if (near1) {
			col = vec3(221., 205., 155.);
		} else if (p.x > 2 && p.y > 2 && p.x < w - 3 && p.y < h - 3 && (type_at(p + ivec2(2, 0)) != 0 || type_at(p + ivec2(-2, 0)) != 0 || type_at(p + ivec2(0, 2)) != 0 || type_at(p + ivec2(0, -2)) != 0 || type_at(p + ivec2(3, 0)) != 0 || type_at(p + ivec2(-3, 0)) != 0)) {
			col = mix(col,vec3(111.,158.,145.),0.48);
		}
	} else {
		bool sea = (p.x < w - 1 && type_at(p + ivec2(1, 0)) == 0) || (p.y < h - 1 && type_at(p + ivec2(0, 1)) == 0) || (p.x > 0 && type_at(p + ivec2(-1, 0)) == 0) || (p.y > 0 && type_at(p + ivec2(0, -1)) == 0);
		if (sea) col = vec3(168.,144.,92.);
	}
	COLOR = vec4(floor(col) / 255.0, 1.0);
}
