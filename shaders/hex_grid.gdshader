shader_type canvas_item;
render_mode unshaded;

uniform float hex_radius : hint_range(32.0, 256.0) = 96.0;
uniform float grid_y_scale : hint_range(0.4, 1.0) = 0.70710678118;
uniform float grid_opacity : hint_range(0.0, 1.0) = 0.38;
uniform float line_width_px : hint_range(0.5, 3.0) = 1.0;
uniform vec4 ink_color : source_color = vec4(0.12, 0.18, 0.14, 1.0);
uniform vec4 selection_color : source_color = vec4(1.0, 0.82, 0.32, 1.0);
uniform vec2 selected_hex = vec2(0.0);
uniform vec2 hovered_hex = vec2(0.0);
uniform bool has_selection = false;
uniform bool has_hover = false;
varying vec2 map_position;

// One polygon spans all nine regions. Its local vertices are world coordinates.
void vertex() {
	map_position = VERTEX;
}

vec2 axial_round(vec2 axial) {
	vec3 cube = vec3(axial.x, -axial.x - axial.y, axial.y);
	vec3 rounded = floor(cube + vec3(0.5));
	vec3 delta = abs(rounded - cube);
	if (delta.x > delta.y && delta.x > delta.z) {
		rounded.x = -rounded.y - rounded.z;
	} else if (delta.y > delta.z) {
		rounded.y = -rounded.x - rounded.z;
	} else {
		rounded.z = -rounded.x - rounded.y;
	}
	return rounded.xz;
}

void fragment() {
	const float SQRT3 = 1.7320508075688772;
	vec2 plane = map_position / vec2(1.0, grid_y_scale);
	vec2 axial = vec2(plane.x / SQRT3 - plane.y / 3.0,
		plane.y * 2.0 / 3.0) / hex_radius;
	vec2 cell = axial_round(axial);
	vec2 center = hex_radius * vec2(SQRT3 * (cell.x + cell.y * 0.5), cell.y * 1.5);
	vec2 offset = abs(plane - center);
	float edge_distance = hex_radius * 0.8660254037844386
		- max(offset.x, offset.x * 0.5 + offset.y * 0.8660254037844386);
	float world_pixel = max(length(dFdx(map_position)), length(dFdy(map_position)));
	// Screen-space edge distance keeps diagonal and vertical lines equally thin
	// on the projected grid, including at fractional zoom levels.
	float gradient = max(length(vec2(dFdx(edge_distance), dFdy(edge_distance))), 0.0001);
	float edge_px = edge_distance / gradient;
	float half_line = line_width_px * 0.5;
	float line = 1.0 - smoothstep(max(0.0, half_line - 0.4), half_line + 0.6, edge_px);
	float overview_fade = mix(0.45, 1.0, smoothstep(5.0, 22.0, hex_radius / world_pixel));
	float alpha = line * grid_opacity * overview_fade;
	vec3 rgb = ink_color.rgb;
	bool selected = has_selection && distance(cell, selected_hex) < 0.1;
	bool hovered = has_hover && distance(cell, hovered_hex) < 0.1;
	if (selected) {
		rgb = selection_color.rgb;
		float border = 1.0 - smoothstep(world_pixel * 1.3, world_pixel * 2.3, edge_distance);
		alpha = max(0.16, border * 0.96);
	} else if (hovered) {
		rgb = mix(ink_color.rgb, vec3(0.96, 0.94, 0.73), 0.85);
		alpha = max(alpha, 0.09 + line * 0.42);
	}
	COLOR = vec4(rgb, alpha);
}
