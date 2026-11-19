shader_type canvas_item;
render_mode unshaded;

varying vec4 stroke;

void vertex() {
	stroke = COLOR;
}

float gold(vec4 pigment) {
	return pigment.a * smoothstep(.33,.80,pigment.g) * smoothstep(.65,.92,pigment.r);
}

void fragment() {
	vec4 pigment = texture(TEXTURE, UV);
	// Spread the light of the drawn gold veins by a few pixels. Cap the UV
	// footprint at the tapered tip so the sample stays in this atlas cell.
	vec2 limit = 10.0*TEXTURE_PIXEL_SIZE;
	vec2 dx = clamp(2.25*dFdx(UV), -limit, limit);
	vec2 dy = clamp(2.25*dFdy(UV), -limit, limit);
	float fringe = .25*(gold(texture(TEXTURE,UV+dx)) + gold(texture(TEXTURE,UV-dx))
		+ gold(texture(TEXTURE,UV+dy)) + gold(texture(TEXTURE,UV-dy)));
	float heat = gold(pigment);
	vec3 lit = pigment.rgb + (1.0-pigment.rgb) * (vec3(.15,.30,.20)*heat + vec3(.14,.16,.045)*fringe);
	float haze = (1.0-pigment.a)*fringe*.49;
	float coverage = pigment.a+haze;
	vec3 ink = (lit*pigment.a + vec3(1.0,.57,.13)*haze)/max(.0001,coverage);
	COLOR = vec4(ink*stroke.rgb, coverage*stroke.a);
}
