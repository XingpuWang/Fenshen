shader_type canvas_item;
render_mode unshaded;

// The upper fifth contains the cord, buckle and seeds of the hanging folds.
uniform vec2 hem_offset;
uniform vec2 edge_lift;

void vertex() {
	float free_length = smoothstep(0.19, 1.0, UV.y);
	float outer_fold = smoothstep(0.08, 0.94, UV.x);
	VERTEX += free_length * free_length * hem_offset;
	VERTEX.y -= free_length * mix(edge_lift.x, edge_lift.y, outer_fold);
}
