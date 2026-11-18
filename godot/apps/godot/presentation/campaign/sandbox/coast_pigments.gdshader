shader_type canvas_item;
// Small pigment corrections sampled from the approved bay and meadow, in sRGB compatibility rendering.
void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	float water = smoothstep(0.04, 0.18, min(c.g,c.b) - c.r);
	float grass = smoothstep(0.12, 0.31, min(c.r,c.g) - c.b) * (1.0-water);
	c += water * vec3(0.081,-0.004,-0.016) + grass * vec3(-0.035,-0.012,0.055);
	COLOR = vec4(c,1.);
}
