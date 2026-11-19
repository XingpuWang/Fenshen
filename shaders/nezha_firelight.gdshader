shader_type canvas_item;
render_mode unshaded;

uniform float dusk : hint_range(0.0,1.0) = 0.0;
uniform float sweep_glow : hint_range(0.0,1.0) = 0.0;
uniform float strike_glow : hint_range(0.0,1.0) = 0.0;
uniform vec2 caster_ground;
uniform vec2 strike_ground;
uniform vec2 flame_center;
uniform float blade_height = 0.0;

float light_pool(vec2 delta, vec2 radius) {
	vec2 q = delta / radius;
	return exp(-dot(q,q)*2.3);
}

void fragment() {
	vec3 paint = COLOR.rgb;
	float value = dot(paint,vec3(.25,.58,.17));
	// Keep the sand brushwork and hill silhouettes visible under the fire.
	vec3 twilight = vec3(.075,.061,.104) + vec3(.40,.37,.46)*value + .27*(paint-vec3(value));
	vec3 base = mix(paint,twilight,dusk);
	vec2 p = UV / TEXTURE_PIXEL_SIZE;
	// A high blade casts a broad, faint patch. The air flash and its reflection
	// on the sand have separate positions; the point of impact is above ground.
	float lift = smoothstep(22.0,185.0,blade_height);
	vec2 spread = mix(vec2(76.0,15.0),vec2(153.0,34.0),lift);
	float sweep = light_pool(p-caster_ground,spread) * sweep_glow * mix(.54,.13,lift);
	float strike = light_pool(p-strike_ground,vec2(104.0,19.0)) * strike_glow * .57;
	float sand = .39+.61*smoothstep(.19,.83,value);
	vec3 reflected = (vec3(.84,.31,.072)*sweep + vec3(1.0,.47,.14)*strike)*sand;
	float haze = light_pool(p-flame_center,vec2(59.0,43.0)) * (.15*sweep_glow+.26*strike_glow);
	COLOR.rgb = base + (1.0-base)*(reflected + vec3(.89,.27,.046)*haze);
}
