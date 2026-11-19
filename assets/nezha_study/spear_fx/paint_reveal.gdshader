shader_type canvas_item;
render_mode unshaded;

// A stroke writes and lifts along its own brush direction. The annular stroke
// starts at its open left end, passes round the right rim and returns below.
uniform vec4 atlas_region;
uniform float head = 1.16;
uniform float tail = -0.16;
uniform int stroke_flow = 0;
uniform int depth_slice = 0;
varying vec4 ink;

void vertex() {
	ink = COLOR;
}

void fragment() {
	vec2 local = (UV - atlas_region.xy) / atlas_region.zw;
	vec4 paint = texture(TEXTURE, UV);
	float path = local.x;
	if (stroke_flow == 1) {
		path = (atan(local.y - 0.51, local.x - 0.47) + PI) / TAU;
	} else if (stroke_flow == 2) {
		path = 1.0 - local.y;
	} else if (stroke_flow == 3) {
		path = 0.58 * local.x + 0.42 * (1.0 - local.y);
	}
	float edge = path + (1.0 - paint.a) * 0.027 + (paint.r - paint.g) * 0.018;
	float cover = (1.0 - smoothstep(head - 0.10, head + 0.02, edge)) * smoothstep(tail - 0.02, tail + 0.10, edge);
	float near_lip = smoothstep(0.66, 0.74, local.y) * smoothstep(0.085, 0.21, abs(local.x - 0.45));
	if (depth_slice == 1) cover *= 1.0 - near_lip;
	if (depth_slice == 2) cover *= near_lip;
	if (depth_slice == 3) cover *= smoothstep(0.75, 0.88, local.x);
	COLOR = vec4(paint.rgb * ink.rgb, paint.a * ink.a * cover);
}
