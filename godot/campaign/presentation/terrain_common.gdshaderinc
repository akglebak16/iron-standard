// Shared by both ground-painting passes: port of genWorldV2 info()/bz() and makeNoise() from src/05_world.js, src/01_core.js.
uniform sampler2D noise_tab : filter_nearest, repeat_disable;
uniform sampler2D fields : filter_nearest, repeat_disable;
uniform sampler2D carve : filter_nearest, repeat_disable;
const float WW = 5200.0;
const float WH = 3400.0;
const float RES = 10.0;
const ivec2 FSIZE = ivec2(520, 340);
const float LON0 = -14.0;
const float LON1 = 56.0;
const float LAT0 = 31.0;
const float LAT1 = 66.0;

float at(int n, int x, int y) {
	return texelFetch(noise_tab, ivec2(x & 63, (y & 63) + 64 * n), 0).r;
}
float n1(int n, float x, float y) {
	float xf = floor(x);
	float yf = floor(y);
	int xi = int(xf);
	int yi = int(yf);
	float fx = x - xf;
	float fy = y - yf;
	fx = fx * fx * (3.0 - 2.0 * fx);
	fy = fy * fy * (3.0 - 2.0 * fy);
	float a = at(n, xi, yi);
	float b = at(n, xi + 1, yi);
	float c = at(n, xi, yi + 1);
	float d = at(n, xi + 1, yi + 1);
	float top = a + (b - a) * fx;
	float bot = c + (d - c) * fx;
	return top + (bot - top) * fy;
}
float noise(int n, float x, float y) {
	return n1(n, x, y) * 0.55 + n1(n, x * 2.1 + 7.0, y * 2.1 + 3.0) * 0.3 + n1(n, x * 4.3 + 13.0, y * 4.3 + 9.0) * 0.15;
}
vec4 bilin(float x, float y) {
	float u = x / RES - 0.5;
	float v = y / RES - 0.5;
	float fi = floor(u);
	float fj = floor(v);
	float fx = u - fi;
	float fy = v - fj;
	int i = int(fi);
	int j = int(fj);
	ivec2 mx = FSIZE - ivec2(1);
	vec4 a = texelFetch(fields, clamp(ivec2(i, j), ivec2(0), mx), 0);
	vec4 b = texelFetch(fields, clamp(ivec2(i + 1, j), ivec2(0), mx), 0);
	vec4 c = texelFetch(fields, clamp(ivec2(i, j + 1), ivec2(0), mx), 0);
	vec4 d = texelFetch(fields, clamp(ivec2(i + 1, j + 1), ivec2(0), mx), 0);
	return (a * (1.0 - fx) + b * fx) * (1.0 - fy) + (c * (1.0 - fx) + d * fx) * fy;
}
float elevation(float x, float y) {
	vec4 f = bilin(x, y);
	return 0.33 + (f.x - 0.5) * 0.8 + (f.y - 0.5) * 0.3 + (noise(0, x / 240.0, y / 240.0) - 0.5) * 0.2 + (noise(4, x / 60.0, y / 60.0) - 0.5) * 0.16;
}
int biome(float x, float y) {
	float lon0 = LON0 + x / WW * (LON1 - LON0);
	float lat = LAT1 - y / WH * (LAT1 - LAT0);
	float w1 = noise(2, x / 200.0, y / 200.0) - 0.5;
	float w2 = noise(2, x / 330.0 + 9.0, y / 330.0) - 0.5;
	float lon = lon0 + w2 * 7.0;
	if (lat > 40.0 && bilin(x, y).z > 0.82 + w1 * 0.3) return 1;
	if (lat > 61.8 + w2 * 3.2) return 1;
	float al = lat + w1 * 2.4;
	if ((al < 37.4 && lon > -10.0 && lon < 12.5) || al < 36.4 || (lon > -8.5 && lon < -0.2 && al < 38.4) || (lon > 49.0 && al < 43.5) || (lon > 34.0 && al < 37.6)) return 3;
	float ex = (lon - 42.0) / 16.0;
	float ey = (lat - 48.2) / 5.2;
	float hx = (lon - 20.0) / 2.6;
	float hy = (lat - 47.0) / 1.3;
	if (ex * ex + ey * ey < 1.0 + w1 * 0.7 || hx * hx + hy * hy < 1.0 + w1) return 2;
	return 0;
}
int terrain(float x, float y, float e) {
	if (e < 0.33) return 0;
	float m = noise(1, x / 230.0, y / 230.0);
	vec4 f = bilin(x, y);
	float mt = f.z * (0.55 + 0.9 * m);
	if (mt > 0.66 || (m > 0.78 && f.w < 0.2)) {
		int ci = clamp(int(floor(x / 20.0)), 0, 259);
		int cj = clamp(int(floor(y / 20.0)), 0, 169);
		return texelFetch(carve, ivec2(ci, cj), 0).r > 0.5 ? 3 : 4;
	}
	if (mt > 0.34 || m > 0.64) return 3;
	int b = biome(x, y);
	if (b != 3) {
		float lat = LAT1 - y / WH * (LAT1 - LAT0);
		float thr = 0.62 - 0.09 * clamp((lat - 47.0) / 10.0, -1.2, 1.4) + (b == 2 ? 0.14 : 0.0);
		if (noise(2, x / 130.0, y / 130.0) > thr) return 2;
	}
	return 1;
}
