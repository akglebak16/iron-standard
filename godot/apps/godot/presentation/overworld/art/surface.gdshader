shader_type canvas_item;
render_mode unshaded;
uniform sampler2D meadow : source_color, repeat_enable, filter_linear_mipmap;
uniform vec3 sunlight = vec3(1.0);
varying vec2 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	vec3 base = COLOR.rgb;
	if (base.b > base.r) {
		float phase = world.x * 0.025 + world.y * 0.25 + sin(world.x * 0.013 + world.y * 0.018) * 2.6;
		float ripple = pow(max(0.0, sin(phase)), 17.0) * smoothstep(0.2, 0.88, sin(world.y * 0.07 - world.x * 0.018));
		base = mix(vec3(0.075,0.25,0.29), vec3(0.13,0.34,0.37), base.r * 4.0)
			+ 0.045 * ripple + 0.01 * sin(world.y * .027 + sin(world.x*.016));
	} else if (abs(base.r-base.g) < 0.055) {
		vec3 pigment = texture(meadow, world / vec2(435.0,350.0)).rgb;
		float wash = texture(meadow, world.yx / 1170.0).g;
		base = pigment * vec3(.91,.94,.82) * (0.88 + 0.24 * wash);
	} else {
		base *= .95 + .12 * texture(meadow, world / 210.0).g;
		if (abs(base.r-.55)<.045 && base.g<.45)
			base *= .84 + .16 * smoothstep(.03,.12,fract(world.x/9.0));
	}
	COLOR = vec4(base * sunlight, COLOR.a);
}
