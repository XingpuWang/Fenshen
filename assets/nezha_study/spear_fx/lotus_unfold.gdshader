shader_type canvas_item;
render_mode unshaded;

uniform vec4 atlas_region;
uniform vec2 calyx;
uniform float unfolding = 1.0;
uniform float consumed = 0.0;
uniform float heat = 0.0;
uniform int surface = 0;
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 pigment = texture(TEXTURE, UV);
	vec2 uv = (UV - atlas_region.xy) / atlas_region.zw;
	vec2 ray = uv - calyx;
	// Reveal along the painted veins. The near, downturned petals lag behind the far corolla.
	float grain = (pigment.r - pigment.g) * 0.05;
	float distance_from_heart = length(ray * vec2(1.0, 0.85)) + grain;
	float written = 1.0 - smoothstep(unfolding * 1.42 - 0.06, unfolding * 1.42 + 0.045, distance_from_heart);
	float split = smoothstep(-0.045, 0.055, uv.y - calyx.y + 0.12 * ray.x + 0.06);
	float cover = surface == 1 ? 1.0 - split : (surface == 2 ? split : 1.0);
	float ash = smoothstep(consumed - 0.10, consumed + 0.025, distance_from_heart + 0.14);
	float vein = smoothstep(0.30, 0.89, pigment.g);
	vec3 light = mix(pigment.rgb, vec3(1.0, 0.96, 0.77), heat * vein * 0.37);
	COLOR = vec4(light * tint.rgb, pigment.a * written * ash * cover * tint.a);
}
