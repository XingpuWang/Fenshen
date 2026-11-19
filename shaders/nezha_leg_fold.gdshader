shader_type canvas_item;
render_mode unshaded;

uniform int layer;
uniform bool near_leg;
uniform float paint_width;
uniform vec2 hip;
uniform vec2 knee = vec2(0.0, 48.0);
uniform vec2 ankle = vec2(0.0, 93.0);
uniform vec2 boot_axis = vec2(0.0, 1.0);
varying float inside_fold;
varying float flexion;
varying float knee_shadow;

// A rounded joint has one tangent on both sides of the seam.
void round_joint(vec2 pivot, vec2 incoming, vec2 outgoing, float radius, float offset,
		out vec2 center, out vec2 tangent) {
	float t = clamp(0.5+offset/(2.0*radius), 0.0, 1.0);
	vec2 before = pivot-incoming*radius;
	vec2 after = pivot+outgoing*radius;
	center = mix(mix(before, pivot, t), mix(pivot, after, t), t);
	tangent = normalize(mix(incoming, outgoing, t));
}

void vertex() {
	float thigh_length = max(1.0, length(knee-hip));
	float shin_length = max(1.0, length(ankle-knee));
	vec2 thigh_axis = (knee-hip)/thigh_length;
	vec2 shin_axis = (ankle-knee)/shin_length;
	float bend_side = thigh_axis.x*shin_axis.y - thigh_axis.y*shin_axis.x;
	flexion = smoothstep(0.04, 1.40, 1.0-dot(thigh_axis,shin_axis));
	float v = UV.y;
	bool calf = layer == 1;
	float middle = near_leg ? (calf ? 0.54 : 0.56) : (calf ? 0.46 : 0.57);
	middle -= (calf ? (near_leg ? 0.095 : 0.005) : 0.135) * smoothstep(0.15,0.93,v);
	float across = (UV.x-middle)*paint_width;
	inside_fold = 1.0-smoothstep(-0.23,0.18,(UV.x-middle)*sign(bend_side));
	float offset;
	if (calf) {
		// The lotus is the front of the greave. Its lip starts below the kneecap,
		// while the bottom hem disappears into the shoe collar.
		float cap = 1.0-smoothstep(0.19,0.54,v);
		float top = 0.5+2.0*flexion;
		offset = thigh_length + mix(top, 48.7, v)
				+ (shin_length-45.0)*smoothstep(0.17,0.81,v);
		across *= 0.97-cap*(0.10+0.09*flexion);
		across -= sign(bend_side)*cap*flexion*1.0;
		knee_shadow = cap*flexion*(0.22+0.60*inside_fold);
	} else {
		float gathers = smoothstep(0.45,0.74,v)*(1.0-smoothstep(0.80,1.0,v));
		offset = mix(-7.0,57.0,v) + (thigh_length-48.0)*smoothstep(0.14,0.78,v);
		// Inner pleats bunch up behind the knee. The outer cloth wraps the patella.
		offset -= inside_fold*gathers*flexion*4.5;
		across *= 1.0+gathers*flexion*(0.11-0.19*inside_fold);
		knee_shadow = gathers*flexion*inside_fold;
	}
	float knee_radius = min(mix(6.5,16.0,flexion), 0.40*min(thigh_length,shin_length));
	float toe_radius = min(6.0, 0.20*shin_length);
	float knee_distance = offset-thigh_length;
	float ankle_distance = knee_distance-shin_length;
	vec2 center;
	vec2 tangent;
	if (knee_distance < -knee_radius) {
		center = hip+thigh_axis*offset;
		tangent = thigh_axis;
	} else if (knee_distance < knee_radius) {
		round_joint(knee,thigh_axis,shin_axis,knee_radius,knee_distance,center,tangent);
	} else if (ankle_distance < -toe_radius) {
		center = knee+shin_axis*knee_distance;
		tangent = shin_axis;
	} else {
		round_joint(ankle,shin_axis,boot_axis,toe_radius,ankle_distance,center,tangent);
	}
	VERTEX = center + vec2(tangent.y,-tangent.x)*across;
}

void fragment() {
	// Preserve the original silk, red lacquer and worked-gold brushwork.
	COLOR.rgb *= 1.0-0.12*knee_shadow;
	if (layer == 1) {
		float gold_cap = 1.0-smoothstep(0.23,0.42,UV.y);
		COLOR.rgb *= mix(vec3(1.0), vec3(0.97,0.95,0.92), gold_cap);
	} else if (layer == 2) {
		float gathered_edge = smoothstep(0.61,0.73,UV.y)*(1.0-smoothstep(0.94,1.0,UV.y));
		COLOR.a *= gathered_edge*inside_fold*smoothstep(0.10,0.68,flexion);
	}
}
