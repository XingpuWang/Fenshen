shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0,1.0);
uniform float light_side : hint_range(-1.0,1.0);

void fragment() {
	// Sample one screen pixel towards the flame, even as the painted arm rotates.
	vec2 toward = dFdx(UV) * light_side - dFdy(UV) * 0.65;
	float lit_edge = 1.0 - texture(TEXTURE, UV + 1.15 * toward).a;
	float gilt = smoothstep(0.27,0.79,dot(COLOR.rgb,vec3(0.33,0.55,0.12)));
	float reflected = strength * (0.64 * lit_edge + 0.48 * gilt);
	COLOR.rgb += (1.0-COLOR.rgb) * vec3(1.0,0.55,0.19) * reflected;
}
