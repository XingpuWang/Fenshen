shader_type canvas_item;
render_mode unshaded;

// Each vertex is already attached to the rib cage by its scene transform.
// Re-express the hem in pelvis space, keeping the collar seated at the neck.
uniform vec2 hip_origin;
uniform vec2 hip_x = vec2(1.0, 0.0);
uniform vec2 hip_y = vec2(0.0, 1.0);
uniform vec2 near_socket;
uniform vec2 far_socket;
uniform vec2 near_pull;
uniform vec2 far_pull;

float armhole_weight(vec2 at, vec2 socket) {
	vec2 distance_to_seam = (at - socket) / vec2(0.35, 0.26);
	return exp(-dot(distance_to_seam, distance_to_seam));
}

void vertex() {
	vec2 hem = hip_origin + hip_x * UV.x + hip_y * UV.y;
	float waist_weight = smoothstep(0.28, 0.90, UV.y);
	vec2 shoulder_pull = near_pull * armhole_weight(UV, near_socket)
		+ far_pull * armhole_weight(UV, far_socket);
	VERTEX = mix(VERTEX + shoulder_pull, hem, waist_weight);
}
