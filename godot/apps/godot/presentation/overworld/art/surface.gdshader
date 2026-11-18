shader_type canvas_item;
render_mode unshaded;
uniform sampler2D meadow : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D foothills : source_color, repeat_enable, filter_linear_mipmap;
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
		float estuary=smoothstep(.54,.72,field.b);
		vec3 shallows=vec3(.14,.33,.37);
		base=mix(shallows,vec3(.077,.276,.32),sea?smoothstep(.0,.32,depth):0.);
		if (!sea) base=mix(shallows,vec3(.19,.40,.40),estuary);
		float phase=world.y*.19+world.x*.019+3.2*sin(world.x*.014+world.y*.011)+field.a*1.8;
		float streak_mask=texture(meadow,world/vec2(117.0,62.0)).g;
		if (!sea) phase=world.x*.31+world.y*.012+3.7*sin(world.y*.022);
		float strokes=pow(max(0.0,sin(phase)),14.0)*smoothstep(.35,.69,streak_mask)*smoothstep(.4,.75,field.a);
		float shoal=(1.0-smoothstep(.02,.23,depth))*pow(max(0.0,cos(depth*70.0+4.0*grain)),12.0);
		base+=vec3(.055,.09,.09)*strokes + (sea ? vec3(.05,.06,.049)*shoal : vec3(0.0));
	} else if (abs(base.r-base.g) < 0.055) {
		vec3 pigment = texture(meadow, world / vec2(435.0,350.0)).rgb;
		// World-locked illustrated ledges and cobbles bridge the plain and foothills.
		// Modulate their local contrast independently of the biome pigment.
		vec2 bank_uv=world/vec2(585.,424.)+vec2(field.a*.17,height*.24);
		vec3 banks=texture(foothills,bank_uv).rgb;
		float woodland=smoothstep(.45,.73,field.g);
		vec3 soil=mix(vec3(.63,.56,.265),vec3(.41,.47,.235),woodland);
		soil=mix(soil,vec3(.58,.44,.32),smoothstep(.37,.70,height));

		float bands=abs(fract(height*8.0+grain*.83+field.a*.52)-.5);
		// Broken marks follow the lit and lee edges of a fold.
		float fleck=texture(meadow,world/vec2(102.,58.)).r;
		float scarp=smoothstep(.01,.053,length(gradient))*smoothstep(.30,.54,fleck);
		base=mix(soil*(.78+.43*pigment.g),pigment*vec3(.95,.96,.85),.36)+light*vec3(1.05,.88,.59)
			-vec3(.072,.053,.034)*scarp*smoothstep(.48,.67,field.a)*(1.0-smoothstep(.012,.1,bands));
		vec3 bank_pigment=banks*mix(vec3(1.10,1.09,.98),vec3(.76,.94,.77),woodland);
		float bank_cover=(.54+.28*smoothstep(.16,.44,height))*(1.-.36*woodland);
		base=mix(base,bank_pigment+light*vec3(.88,.76,.52),bank_cover);
		// Occasional sunlit stones sit in exposed ground. Their two faces share
		// the direction of illumination used for the larger rolling slopes.
		vec2 cell=floor(world/vec2(26.,16.));
		float pick=fract(sin(dot(cell,vec2(41.7,113.3)))*4375.31);
		vec2 spot=fract(world/vec2(26.,16.))-.24-.52*vec2(pick,fract(pick*41.3));
		float stone=1.-smoothstep(.05,.14,length(spot*vec2(1.,1.6)));
		float exposure=smoothstep(.49,.77,field.a)*(1.-woodland)*step(.79,pick);
		base+=stone*exposure*(dot(spot,sun_dir)>0.?vec3(.13,.11,.067):-vec3(.12,.10,.05));
	} else {
		base *= .90 + .20*grain + light*.35;
		if (abs(base.r-.55)<.045 && base.g<.45)
			base *= .84 + .16 * smoothstep(.03,.12,fract(world.x/9.0));
	}
	COLOR = vec4(base * sunlight, COLOR.a);
}
