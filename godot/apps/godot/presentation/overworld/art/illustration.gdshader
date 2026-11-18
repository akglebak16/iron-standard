shader_type canvas_item;
render_mode unshaded;
uniform vec3 sunlight = vec3(1.0);
uniform float shadow_slope = 0.32;
uniform float night = 0.0;
uniform vec2 cast_dir = vec2(.16,.12);
varying float shadow;
varying float has_windows;
void vertex() {
	shadow = step(COLOR.a, .5);
	has_windows = step(COLOR.g,.75);
	if (shadow > .5) {
		float height=max(-VERTEX.y,0.0)*COLOR.r;
		// Place the projection inside the sprite's ground footprint. A city's
		// front wall covers the base while its towers cast beyond the far edge.
		VERTEX=vec2(VERTEX.x,0.0)+height*cast_dir;
	}
}
void fragment() {
	vec4 art = texture(TEXTURE,UV);
	if (art.a < .07) discard;
	vec3 ink = art.rgb * sunlight;
	// A broad pigment gradient approximates the painted face orientation.
	vec2 stride = TEXTURE_PIXEL_SIZE * vec2(6.0, 0.0);
	float slope = dot(texture(TEXTURE, UV-stride).rgb - texture(TEXTURE, UV+stride).rgb,
		vec3(0.30,0.55,0.15));
	ink *= 1.0 + clamp(slope * (shadow_slope-.2), -.18, .18);
	// Four window apertures in the town sprite, expressed in atlas pixels.
	vec2 px = UV / TEXTURE_PIXEL_SIZE;
	float windows = max(max(1.0-smoothstep(1.1,2.8,distance(px,vec2(253,691))),1.0-smoothstep(1.1,2.8,distance(px,vec2(265,699)))),
		max(1.0-smoothstep(1.1,2.8,distance(px,vec2(180,774))),1.0-smoothstep(1.1,2.8,distance(px,vec2(342,794)))));
	ink = mix(ink,vec3(1.0,.75,.30),has_windows*night*windows);
	COLOR = shadow > .5 ? vec4(.12,.14,.10,art.a*.21*(1.0-night)) : vec4(ink,art.a);
}
