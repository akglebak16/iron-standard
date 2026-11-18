shader_type canvas_item;
render_mode unshaded;
uniform sampler2D meadow : source_color, repeat_enable, filter_linear_mipmap;
uniform vec3 sunlight = vec3(1.0);
uniform sampler2D terrain : repeat_disable, filter_linear;
uniform vec2 sun_dir = vec2(-.6,-.8);
varying vec2 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy; }
void fragment() {
	vec3 base = COLOR.rgb;
	vec2 uv = world / vec2(2560.0,1600.0);
	vec4 field = texture(terrain,uv);
	float height = field.r;
	vec2 texel = vec2(1.0/320.0,1.0/200.0);
	vec2 gradient = vec2(texture(terrain,uv+vec2(texel.x,0)).r-texture(terrain,uv-vec2(texel.x,0)).r,
		texture(terrain,uv+vec2(0,texel.y)).r-texture(terrain,uv-vec2(0,texel.y)).r);
	float light = clamp(-dot(gradient,sun_dir)*3.7,-.145,.135);
	float grain = texture(meadow,world/315.0).g;
	if (base.b > base.r) {
		float depth=clamp((.50-field.b)*2.0,0.0,1.0);
		bool sea=base.r<.12;
		base=mix(vec3(.22,.43,.43),vec3(.065,.235,.29),sea?smoothstep(0.0,.82,depth):.28);
		float phase=world.y*.19+world.x*.019+3.2*sin(world.x*.014+world.y*.011)+field.a*1.8;
		float streak_mask=texture(meadow,world/vec2(117.0,62.0)).g;
		float strokes=pow(max(0.0,sin(phase)),14.0)*smoothstep(.35,.69,streak_mask)*smoothstep(.4,.75,field.a);
		float shoal=(1.0-smoothstep(.02,.23,depth))*pow(max(0.0,cos(depth*70.0+4.0*grain)),12.0);
		base+=vec3(.055,.09,.09)*strokes + (sea ? vec3(.05,.06,.049)*shoal : vec3(0.0));
	} else if (abs(base.r-base.g) < 0.055) {
		vec3 pigment = texture(meadow, world / vec2(435.0,350.0)).rgb;
		float woodland=smoothstep(.45,.73,field.g);
		vec3 soil=mix(vec3(.63,.56,.265),vec3(.41,.47,.235),woodland);
		soil=mix(soil,vec3(.58,.44,.32),smoothstep(.37,.70,height));
		float ledge=smoothstep(.035,.10,length(gradient));
		float bands=abs(fract(height*13.0+grain*.35)-.5);
		base=mix(soil*(.78+.43*pigment.g),pigment*vec3(.95,.96,.85),.36)+light*vec3(.77,.66,.49)
			-vec3(.055,.05,.035)*ledge*(1.0-smoothstep(.012,.075,bands));
	} else {
		base *= .90 + .20*grain + light*.35;
		if (abs(base.r-.55)<.045 && base.g<.45)
			base *= .84 + .16 * smoothstep(.03,.12,fract(world.x/9.0));
	}
	COLOR = vec4(base * sunlight, COLOR.a);
}
