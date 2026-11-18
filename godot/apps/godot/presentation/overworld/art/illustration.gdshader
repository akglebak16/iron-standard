shader_type canvas_item;
render_mode unshaded;
uniform vec3 sunlight = vec3(1.0);
uniform float shadow_slope = 0.32;
uniform float night = 0.0;
uniform vec2 cast_dir = vec2(.16,.12);
varying vec2 quad;
varying vec2 ground;
varying float landscape;
varying float shadow;
varying float has_windows;
void vertex() {
	quad = vec2(step(0.0,VERTEX.x),step(-.01,VERTEX.y));
	ground = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
	landscape = step(COLOR.b,.65);
	shadow = step(COLOR.a, .5);
	has_windows = step(COLOR.g,.75);
	if (shadow > .5) {
		float height=max(-VERTEX.y,0.0)*COLOR.r;
		// Place the projection inside the sprite's ground footprint. A city's
		// front wall covers the base while its towers cast beyond the far edge.
		VERTEX=vec2(VERTEX.x*.93, height*(.21+cast_dir.y*.45))+vec2(height*cast_dir.x,0.0);
	}
}
void fragment() {
	vec4 art = texture(TEXTURE,UV);
	if (shadow<.5 && art.a < .07) discard;
	vec3 ink = art.rgb * sunlight;
	if (landscape>.5 && shadow<.5) {
		float edge=min(quad.x,1.0-quad.x);
		float breakup=.017*(sin(ground.y*.093+sin(ground.x*.065))+sin(ground.x*.12));
		art.a*=smoothstep(.0,.082,edge+breakup)*smoothstep(0.,.14,1.-quad.y+breakup);
		float far_plane=(1.-smoothstep(110.,610.,ground.y))*.13;
		ink=mix(ink,vec3(.50,.46,.42)*sunlight,far_plane);
	}
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
	// The contact shadow occupies the footprint. Its taper follows the sun
	// without duplicating roofs or treetops upside down in the ground.
	float contact=1.-smoothstep(.32,1.,length((quad-vec2(.5,.56))*vec2(2.,2.15)));
	COLOR = shadow > .5 ? vec4(.12,.14,.10,contact*.26*(1.0-night)) : vec4(ink,art.a);
}
