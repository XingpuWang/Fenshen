shader_type canvas_item;
render_mode unshaded;

uniform float dusk : hint_range(0.0,1.0) = 0.0;
uniform float sweep_glow : hint_range(0.0,1.0) = 0.0;
uniform float strike_glow : hint_range(0.0,1.0) = 0.0;
uniform vec2 caster_ground;
uniform vec2 strike_ground;

float light_pool(vec2 delta, vec2 radius) {
	vec2 q = delta / radius;
	return exp(-dot(q,q)*2.3);
}

void fragment() {
	vec3 paint = COLOR.rgb;
	float value = dot(paint,vec3(.25,.58,.17));
	// Keep the sand brushwork and hill silhouettes visible under the fire.
	vec3 twilight = vec3(.078,.059,.106) + vec3(.42,.34,.43)*value + .20*(paint-vec3(value));
	vec3 base = mix(paint,twilight,dusk);
	vec2 p = UV * vec2(1280.0,720.0);
	float sweep = light_pool(p-caster_ground,vec2(270.0,62.0))*sweep_glow;
	float strike = light_pool(p-strike_ground,vec2(218.0,54.0))*strike_glow;
	vec3 reflected = (vec3(.42,.14,.035)*sweep+vec3(.64,.26,.072)*strike)*(.38+.75*value);
	COLOR.rgb = base + (1.0-base)*reflected;
}
