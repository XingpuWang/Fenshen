shader_type canvas_item;
render_mode unshaded;

uniform float strength : hint_range(0.0,1.0);
uniform vec2 light_origin;
uniform float light_range = 215.0;
varying vec2 to_flame;
varying vec2 canvas_ray;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX,0.0,1.0)).xy;
	to_flame = light_origin-world;
	canvas_ray = (CANVAS_MATRIX * vec4(to_flame,0.0,0.0)).xy;
}

void fragment() {
	// Look outwards towards the actual flame along the gilded silhouette.
	vec2 ray = canvas_ray / max(1.0,length(canvas_ray));
	vec2 toward = ray.x*dFdx(UV) + ray.y*dFdy(UV);
	float lit_edge = 1.0 - texture(TEXTURE, UV + 1.15 * toward).a;
	float gilt = smoothstep(0.27,0.79,dot(COLOR.rgb,vec3(0.33,0.55,0.12)));
	float normalized_distance = length(to_flame)/max(1.0,light_range);
	float reflected = strength * (0.70 * lit_edge + 0.48 * gilt)/(1.0+2.8*normalized_distance*normalized_distance);
	COLOR.rgb += (1.0-COLOR.rgb) * vec3(1.0,0.55,0.19) * reflected;
}
