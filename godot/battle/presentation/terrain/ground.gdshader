shader_type canvas_item;
render_mode unshaded;

uniform vec2 arena_size;
uniform vec2 seed_offset;
uniform vec4 base_color : source_color;
uniform vec4 light_color : source_color;
uniform vec4 shade_color : source_color;
uniform vec4 dirt_color : source_color;
uniform vec4 stone_color : source_color;
uniform vec4 tuft_color : source_color;
uniform vec4 flower_color : source_color;
uniform vec3 road; // Phase, amplitude and center in world units.
uniform float road_slope;
uniform bool snowy;
uniform bool dry;

const float BROAD_SCALE = 240.0;
const float PATCH_SCALE = 63.0;
const float GRAIN_SCALE = 4.0;
const float ROAD_SHOULDER = 56.0;
const float ROAD_HALF_WIDTH = 33.0;
const vec2 STONE_GRID = vec2(14.0, 10.0);
const float RUT_OFFSET = 17.0;
const float DETAIL_GRID = 15.0;
const float STONE_DETAIL_CHANCE = 0.04;
const float FLOWER_DETAIL_CHANCE = 0.075;
const float TUFT_DETAIL_CHANCE = 0.46;
const vec3 WATER_COLOR = vec3(0.22, 0.28, 0.29);
const vec3 SNOW_LIGHT = vec3(0.955, 0.975, 0.985);

varying vec2 world_point;

float hash_point(vec2 point) {
	vec3 mixed = fract(vec3(point.xyx) * 0.1031);
	mixed += dot(mixed, mixed.yzx + 33.33);
	return fract((mixed.x + mixed.y) * mixed.z);
}

float value_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 fraction = fract(point);
	vec2 ease = fraction * fraction * (3.0 - 2.0 * fraction);
	return mix(mix(hash_point(cell), hash_point(cell + vec2(1.0, 0.0)), ease.x),
		mix(hash_point(cell + vec2(0.0, 1.0)), hash_point(cell + vec2(1.0)), ease.x), ease.y);
}

void vertex() {
	world_point = VERTEX;
}

void fragment() {
	vec2 point = world_point;
	vec2 seeded = point + seed_offset;
	float broad = value_noise(seeded / BROAD_SCALE);
	float patch = value_noise(seeded / PATCH_SCALE);
	float grain = value_noise(seeded / GRAIN_SCALE);
	vec3 land = mix(shade_color.rgb, light_color.rgb, broad);
	land = mix(base_color.rgb, land, 0.68);
	land = mix(land, dirt_color.rgb, smoothstep(0.65, 0.87, patch) * 0.7);
	land *= mix(0.94, 1.06, grain);

	if (snowy) {
		float drift = value_noise(seeded / vec2(98.0, 34.0));
		land = mix(land, SNOW_LIGHT, smoothstep(0.48, 0.86, drift) * 0.61);
	} else if (dry) {
		float cracks = value_noise(seeded / vec2(31.0, 15.0));
		land *= 1.0 - (1.0 - smoothstep(0.0, 0.025, abs(cracks - 0.5))) * smoothstep(0.52, 0.84, patch) * 0.19;
	} else {
		float lowland = value_noise(seeded / vec2(122.0, 54.0));
		land = mix(land, WATER_COLOR, smoothstep(0.84, 0.94, lowland) * 0.63);
	}

	float road_y = road.z + sin(point.x / 330.0 + road.x) * road.y
		+ sin(point.x / 120.0 + road.x * 2.0) * 34.0 + (point.x - arena_size.x * 0.5) * road_slope;
	float distance_to_road = abs(point.y - road_y);
	float shoulder = 1.0 - smoothstep(ROAD_HALF_WIDTH, ROAD_SHOULDER, distance_to_road + (patch - 0.5) * 19.0);
	land = mix(land, dirt_color.rgb, shoulder * 0.84);
	float paving = 1.0 - smoothstep(ROAD_HALF_WIDTH - 6.0, ROAD_HALF_WIDTH + 6.0, distance_to_road + (grain - 0.5) * 8.0);
	vec2 stone_point = vec2(point.x, point.y - road_y) / STONE_GRID;
	stone_point.x += mod(floor(stone_point.y), 2.0) * 0.5;
	float stone_shade = hash_point(floor(stone_point) + seed_offset);
	vec2 cell = abs(fract(stone_point) - 0.5) * 2.0;
	float mortar = smoothstep(0.72, 0.97, length(cell * vec2(0.84, 0.86)));
	vec3 stone = stone_color.rgb * mix(0.79, 1.13, stone_shade) * mix(1.0, 0.68, mortar);
	float rut = 1.0 - smoothstep(1.0, 4.0, abs(distance_to_road - RUT_OFFSET));
	land = mix(land, stone * (1.0 - 0.14 * rut), paving * 0.83);

	vec2 detail_point = seeded / DETAIL_GRID;
	vec2 detail_cell = floor(detail_point);
	float detail_kind = hash_point(detail_cell);
	vec2 jitter = vec2(hash_point(detail_cell + vec2(1.0, 0.0)), hash_point(detail_cell + vec2(0.0, 1.0)));
	vec2 detail = fract(detail_point) - mix(vec2(0.24), vec2(0.76), jitter);
	float clear_ground = 1.0 - shoulder;
	if (detail_kind < STONE_DETAIL_CHANCE) {
		float rock = 1.0 - smoothstep(0.10, 0.20, length(detail * vec2(1.0, 1.6)));
		vec3 rock_color = snowy ? mix(stone_color.rgb, SNOW_LIGHT, 0.68) : stone_color.rgb;
		land = mix(land, rock_color, rock * clear_ground * 0.75);
	} else if (!snowy && detail_kind < FLOWER_DETAIL_CHANCE) {
		float blossoms = min(length(detail), length(detail + vec2(0.13, 0.10)));
		land = mix(land, flower_color.rgb, (1.0 - smoothstep(0.025, 0.07, blossoms)) * clear_ground * 0.65);
	} else if (detail_kind < TUFT_DETAIL_CHANCE && patch < 0.72) {
		float stalk = min(abs(detail.x + detail.y * 0.35), abs(abs(detail.x) + detail.y * 0.73));
		float tip = smoothstep(-0.38, -0.20, detail.y) * (1.0 - smoothstep(-0.03, 0.02, detail.y));
		land = mix(land, tuft_color.rgb, (1.0 - smoothstep(0.018, 0.05, stalk)) * tip * clear_ground * 0.58);
	}
	float corner = length((UV - 0.5) * 1.4142);
	COLOR = vec4(land * mix(1.04, 0.82, corner), 1.0);
}
