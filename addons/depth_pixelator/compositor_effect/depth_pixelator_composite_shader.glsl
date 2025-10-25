#[compute]
#version 450

#define MAX_VIEWS 2

#define FLAG_SAMPLE_ALL_LAYERS (1 << 0)

#define FLAG_TEST(flag) ((params.flags & (flag)) != 0)

const float infinity = 1.0 / 0.0;

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(push_constant, std430) uniform Params {
    vec2 raster_size;
	vec2 src_size;
	float pixel_near;
	float pixel_far;
	float pixel_blend;
	float pixel_distance_curve;
	int downsample_buffer_count;
	int downsample_buffer_minimum;
	int downsample_buffer_index;
	int downsample_method;
	int flags;
	int debug_mode;
	int debug_buffer_index;
	int pad_0x3C;
} params;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

//#uniform_buffer
layout(set = 1, binding = 0) uniform sampler2D downsample_color_buffer_0;
layout(set = 1, binding = 1) uniform sampler2D downsample_depth_buffer_0;
layout(set = 1, binding = 2) uniform sampler2D downsample_color_buffer_1;
layout(set = 1, binding = 3) uniform sampler2D downsample_depth_buffer_1;
layout(set = 1, binding = 4) uniform sampler2D downsample_color_buffer_2;
layout(set = 1, binding = 5) uniform sampler2D downsample_depth_buffer_2;
layout(set = 1, binding = 6) uniform sampler2D downsample_color_buffer_3;
layout(set = 1, binding = 7) uniform sampler2D downsample_depth_buffer_3;
layout(set = 1, binding = 8) uniform sampler2D downsample_color_buffer_4;
layout(set = 1, binding = 9) uniform sampler2D downsample_depth_buffer_4;
layout(set = 1, binding = 10) uniform sampler2D downsample_color_buffer_5;
layout(set = 1, binding = 11) uniform sampler2D downsample_depth_buffer_5;
layout(set = 1, binding = 12) uniform sampler2D downsample_color_buffer_6;
layout(set = 1, binding = 13) uniform sampler2D downsample_depth_buffer_6;
layout(set = 1, binding = 14) uniform sampler2D downsample_color_buffer_7;
layout(set = 1, binding = 15) uniform sampler2D downsample_depth_buffer_7;
layout(set = 1, binding = 16) uniform sampler2D downsample_color_buffer_8;
layout(set = 1, binding = 17) uniform sampler2D downsample_depth_buffer_8;
layout(set = 1, binding = 18) uniform sampler2D downsample_color_buffer_9;
layout(set = 1, binding = 19) uniform sampler2D downsample_depth_buffer_9;
layout(set = 1, binding = 20) uniform sampler2D downsample_color_buffer_10;
layout(set = 1, binding = 21) uniform sampler2D downsample_depth_buffer_10;
layout(set = 1, binding = 22) uniform sampler2D downsample_color_buffer_11;
layout(set = 1, binding = 23) uniform sampler2D downsample_depth_buffer_11;
layout(set = 1, binding = 24) uniform sampler2D downsample_color_buffer_12;
layout(set = 1, binding = 25) uniform sampler2D downsample_depth_buffer_12;
layout(set = 1, binding = 26) uniform sampler2D downsample_color_buffer_13;
layout(set = 1, binding = 27) uniform sampler2D downsample_depth_buffer_13;
layout(set = 1, binding = 28) uniform sampler2D downsample_color_buffer_14;
layout(set = 1, binding = 29) uniform sampler2D downsample_depth_buffer_14;
layout(set = 1, binding = 30) uniform sampler2D downsample_color_buffer_15;
layout(set = 1, binding = 31) uniform sampler2D downsample_depth_buffer_15;

// from https://github.com/godotengine/godot/blob/9a1def8da1279f60e86bcdb740c30ac6293e4cc8/servers/rendering/renderer_rd/shaders/scene_data_inc.glsl#L15-L76
struct SceneData {
	highp mat4 projection_matrix;
	highp mat4 inv_projection_matrix;
	highp mat4 inv_view_matrix;
	highp mat4 view_matrix;

	// only used for multiview
	highp mat4 projection_matrix_view[MAX_VIEWS];
	highp mat4 inv_projection_matrix_view[MAX_VIEWS];
	highp vec4 eye_offset[MAX_VIEWS];

	// Used for billboards to cast correct shadows.
	highp mat4 main_cam_inv_view_matrix;

	highp vec2 viewport_size;
	highp vec2 screen_pixel_size;

	// Use vec4s because std140 doesn't play nice with vec2s, z and w are wasted.
	highp vec4 directional_penumbra_shadow_kernel[32];
	highp vec4 directional_soft_shadow_kernel[32];
	highp vec4 penumbra_shadow_kernel[32];
	highp vec4 soft_shadow_kernel[32];

	highp vec2 shadow_atlas_pixel_size;
	highp vec2 directional_shadow_pixel_size;

	uint directional_light_count;
	mediump float dual_paraboloid_side;
	highp float z_far;
	highp float z_near;

	mediump float roughness_limiter_amount;
	mediump float roughness_limiter_limit;
	mediump float opaque_prepass_threshold;
	highp uint flags;

	mediump mat3 radiance_inverse_xform;

	mediump vec4 ambient_light_color_energy;

	mediump float ambient_color_sky_mix;
	highp float fog_density;
	highp float fog_height;
	highp float fog_height_density;

	highp float fog_depth_curve;
	highp float fog_depth_begin;
	highp float fog_depth_end;
	mediump float fog_sun_scatter;

	mediump vec3 fog_light_color;
	mediump float fog_aerial_perspective;

	highp float time;
	highp float taa_frame_count;
	vec2 taa_jitter;

	float emissive_exposure_normalization;
	float IBL_exposure_normalization;
	uint camera_visible_layers;
	float pass_alpha_multiplier;
};

layout(set = 2, binding = 0, std140) uniform SceneDataBlock {
	SceneData data;
	SceneData prev_data;
}
scene;

vec4 uvz_to_cs(vec2 uv, float z) {
	return vec4(uv * 2.0 - 1.0, z, 1.0);
}

vec2 cs_to_uv(vec4 pos_cs) {
	return pos_cs.xy * 0.5 + 0.5;
}

vec3 cs_to_vs(vec4 pos_cs) {
	vec4 pos_vs = scene.data.inv_projection_matrix * pos_cs;
	return pos_vs.xyz / pos_vs.w;
}

vec4 vs_to_cs(vec3 pos_vs) {
	vec4 pos_cs = scene.data.projection_matrix * vec4(pos_vs, 1.0);
	return vec4(pos_cs.xyz / pos_cs.w, pos_cs.w);
}

vec3 vs_to_ws(vec3 pos_vs, float apply_translation) {
	return (scene.data.inv_view_matrix * vec4(pos_vs, apply_translation)).xyz;
}

vec3 vs_to_ws(vec3 pos_vs) {
	return vs_to_ws(pos_vs, 1.0);
}

vec3 ws_to_vs(vec3 pos_ws, float apply_translation) {
	return (scene.data.view_matrix * vec4(pos_ws, apply_translation)).xyz;
}

vec3 ws_to_vs(vec3 pos_ws) {
	return ws_to_vs(pos_ws, 1.0);
}

float cs_to_buf_pos(vec4 pos_cs) {
	vec3 pos_vs = cs_to_vs(pos_cs);
	float frac = pow((-pos_vs.z - params.pixel_near) / (params.pixel_far - params.pixel_near), params.pixel_distance_curve); // Depth along view direction, not world-space distance
	if (frac <= 0.0) {
		return float(params.downsample_buffer_minimum);
	} else if (frac >= 1.0) {
		return float(params.downsample_buffer_count);
	}
	return float(params.downsample_buffer_minimum) + frac * float(params.downsample_buffer_count - params.downsample_buffer_minimum);
}

#define SAMPLE_BUFFER(index, pos, amt, col, color_buffer, depth_buffer) \
	vec4 col = textureLod(color_buffer, uv, 0.0); \
	float pos = cs_to_buf_pos(uvz_to_cs(uv, textureLod(depth_buffer, uv, 0.0).r));\
	float amt = col.a > 0.0 ? smoothstep(1.0, 1.0 - params.pixel_blend, abs(pos - (index + 1))) : 0.0; \

#define BLEND_SIMPLE(idx, buffer_a, buffer_b) \
	case idx: \
		color.rgb = mix(textureLod(buffer_a, uv, 0.0).rgb, textureLod(buffer_b, uv, 0.0).rgb, buf_frac); \
		break;

#define DEBUG_COLOR(idx, col) \
	case idx: \
		color = col; \
		break;

#define DEBUG_COLOR_TEXTURE(idx, texture) \
	case idx: \
		color = textureLod(texture, uv, 0.0); \
		break;

#define DEBUG_DEPTH_TEXTURE(idx, texture) \
	case idx: \
		color = vec4(vec3(textureLod(texture, uv, 0.0).r), 1.0); \
		break;

void main() {
    ivec2 size = ivec2(params.raster_size);
    ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);

    if (uvi.x >= size.x || uvi.y >= size.y) {
        return;
    }
	
	vec2 uv = vec2(uvi + vec2(0.5)) / size;
	
	float fragment_depth = textureLod(depth_texture, uv, 0.0).r;
	vec4 fragment_cs = uvz_to_cs(uv, fragment_depth);
	float buf_pos = cs_to_buf_pos(fragment_cs);
	int buf_floor = int(floor(buf_pos));
	// FIXME: Why is the sky's buf_pos NaN?
	float buf_frac = params.pixel_blend <= 0.0 ? ((fragment_depth < 1e-6 || abs(buf_pos - buf_floor) < 0.5) ? 0.0 : 1.0) : smoothstep(0.0, 1.0, (buf_pos - buf_floor - 0.5) / params.pixel_blend);
	
	vec4 color = vec4(1.0, 0.0, 1.0, 1.0);
	
	if (params.debug_mode == 1) {
		switch (buf_floor) {
			//#debug_color
			DEBUG_COLOR(0, vec4(1.0, 0.0, 0.0, 1.0))
			DEBUG_COLOR(1, vec4(1.0, 0.25, 0.0, 1.0))
			DEBUG_COLOR(2, vec4(1.0, 0.5, 0.0, 1.0))
			DEBUG_COLOR(3, vec4(1.0, 0.75, 0.0, 1.0))
			DEBUG_COLOR(4, vec4(1.0, 1.0, 0.0, 1.0))
			DEBUG_COLOR(5, vec4(0.75, 1.0, 0.0, 1.0))
			DEBUG_COLOR(6, vec4(0.5, 1.0, 0.0, 1.0))
			DEBUG_COLOR(7, vec4(0.25, 1.0, 0.0, 1.0))
			DEBUG_COLOR(8, vec4(0.0, 1.0, 0.0, 1.0))
			DEBUG_COLOR(9, vec4(0.0, 1.0, 0.25, 1.0))
			DEBUG_COLOR(10, vec4(0.0, 1.0, 0.5, 1.0))
			DEBUG_COLOR(11, vec4(0.0, 1.0, 0.75, 1.0))
			DEBUG_COLOR(12, vec4(0.0, 1.0, 1.0, 1.0))
			DEBUG_COLOR(13, vec4(0.0, 0.75, 1.0, 1.0))
			DEBUG_COLOR(14, vec4(0.0, 0.5, 1.0, 1.0))
			DEBUG_COLOR(15, vec4(0.0, 0.25, 1.0, 1.0))
		}
	} else if (params.debug_mode == 2) {
		color = vec4(vec3(buf_frac), 1.0);
	} else if (params.debug_mode == 3) {
		switch (params.debug_buffer_index) {
			//#debug_color_texture
			case 0:
				color = imageLoad(color_image, uvi);
				break;
			DEBUG_COLOR_TEXTURE(1, downsample_color_buffer_0)
			DEBUG_COLOR_TEXTURE(2, downsample_color_buffer_1)
			DEBUG_COLOR_TEXTURE(3, downsample_color_buffer_2)
			DEBUG_COLOR_TEXTURE(4, downsample_color_buffer_3)
			DEBUG_COLOR_TEXTURE(5, downsample_color_buffer_4)
			DEBUG_COLOR_TEXTURE(6, downsample_color_buffer_5)
			DEBUG_COLOR_TEXTURE(7, downsample_color_buffer_6)
			DEBUG_COLOR_TEXTURE(8, downsample_color_buffer_7)
			DEBUG_COLOR_TEXTURE(9, downsample_color_buffer_8)
			DEBUG_COLOR_TEXTURE(10, downsample_color_buffer_9)
			DEBUG_COLOR_TEXTURE(11, downsample_color_buffer_10)
			DEBUG_COLOR_TEXTURE(12, downsample_color_buffer_11)
			DEBUG_COLOR_TEXTURE(13, downsample_color_buffer_12)
			DEBUG_COLOR_TEXTURE(14, downsample_color_buffer_13)
			DEBUG_COLOR_TEXTURE(15, downsample_color_buffer_14)
			DEBUG_COLOR_TEXTURE(16, downsample_color_buffer_15)
		}
	} else if (params.debug_mode == 4) {
		switch (params.debug_buffer_index) {
			//#debug_depth_texture
			DEBUG_DEPTH_TEXTURE(0, depth_texture)
			DEBUG_DEPTH_TEXTURE(1, downsample_depth_buffer_0)
			DEBUG_DEPTH_TEXTURE(2, downsample_depth_buffer_1)
			DEBUG_DEPTH_TEXTURE(3, downsample_depth_buffer_2)
			DEBUG_DEPTH_TEXTURE(4, downsample_depth_buffer_3)
			DEBUG_DEPTH_TEXTURE(5, downsample_depth_buffer_4)
			DEBUG_DEPTH_TEXTURE(6, downsample_depth_buffer_5)
			DEBUG_DEPTH_TEXTURE(7, downsample_depth_buffer_6)
			DEBUG_DEPTH_TEXTURE(8, downsample_depth_buffer_7)
			DEBUG_DEPTH_TEXTURE(9, downsample_depth_buffer_8)
			DEBUG_DEPTH_TEXTURE(10, downsample_depth_buffer_9)
			DEBUG_DEPTH_TEXTURE(11, downsample_depth_buffer_10)
			DEBUG_DEPTH_TEXTURE(12, downsample_depth_buffer_11)
			DEBUG_DEPTH_TEXTURE(13, downsample_depth_buffer_12)
			DEBUG_DEPTH_TEXTURE(14, downsample_depth_buffer_13)
			DEBUG_DEPTH_TEXTURE(15, downsample_depth_buffer_14)
			DEBUG_DEPTH_TEXTURE(16, downsample_depth_buffer_15)
		}
	} else {
		if (FLAG_TEST(FLAG_SAMPLE_ALL_LAYERS)) {
			//#sample_buffer
			color = imageLoad(color_image, uvi);
			SAMPLE_BUFFER(0, pos_0, amt_0, col_0, downsample_color_buffer_0, downsample_depth_buffer_0)
			SAMPLE_BUFFER(1, pos_1, amt_1, col_1, downsample_color_buffer_1, downsample_depth_buffer_1)
			SAMPLE_BUFFER(2, pos_2, amt_2, col_2, downsample_color_buffer_2, downsample_depth_buffer_2)
			SAMPLE_BUFFER(3, pos_3, amt_3, col_3, downsample_color_buffer_3, downsample_depth_buffer_3)
			SAMPLE_BUFFER(4, pos_4, amt_4, col_4, downsample_color_buffer_4, downsample_depth_buffer_4)
			SAMPLE_BUFFER(5, pos_5, amt_5, col_5, downsample_color_buffer_5, downsample_depth_buffer_5)
			SAMPLE_BUFFER(6, pos_6, amt_6, col_6, downsample_color_buffer_6, downsample_depth_buffer_6)
			SAMPLE_BUFFER(7, pos_7, amt_7, col_7, downsample_color_buffer_7, downsample_depth_buffer_7)
			SAMPLE_BUFFER(8, pos_8, amt_8, col_8, downsample_color_buffer_8, downsample_depth_buffer_8)
			SAMPLE_BUFFER(9, pos_9, amt_9, col_9, downsample_color_buffer_9, downsample_depth_buffer_9)
			SAMPLE_BUFFER(10, pos_10, amt_10, col_10, downsample_color_buffer_10, downsample_depth_buffer_10)
			SAMPLE_BUFFER(11, pos_11, amt_11, col_11, downsample_color_buffer_11, downsample_depth_buffer_11)
			SAMPLE_BUFFER(12, pos_12, amt_12, col_12, downsample_color_buffer_12, downsample_depth_buffer_12)
			SAMPLE_BUFFER(13, pos_13, amt_13, col_13, downsample_color_buffer_13, downsample_depth_buffer_13)
			SAMPLE_BUFFER(14, pos_14, amt_14, col_14, downsample_color_buffer_14, downsample_depth_buffer_14)
			SAMPLE_BUFFER(15, pos_15, amt_15, col_15, downsample_color_buffer_15, downsample_depth_buffer_15)
			if (params.pixel_near < params.pixel_far) {
				//#blend_all_reverse
				color.rgb = mix(color.rgb, col_15.rgb, amt_15);
				color.rgb = mix(color.rgb, col_14.rgb, amt_14);
				color.rgb = mix(color.rgb, col_13.rgb, amt_13);
				color.rgb = mix(color.rgb, col_12.rgb, amt_12);
				color.rgb = mix(color.rgb, col_11.rgb, amt_11);
				color.rgb = mix(color.rgb, col_10.rgb, amt_10);
				color.rgb = mix(color.rgb, col_9.rgb, amt_9);
				color.rgb = mix(color.rgb, col_8.rgb, amt_8);
				color.rgb = mix(color.rgb, col_7.rgb, amt_7);
				color.rgb = mix(color.rgb, col_6.rgb, amt_6);
				color.rgb = mix(color.rgb, col_5.rgb, amt_5);
				color.rgb = mix(color.rgb, col_4.rgb, amt_4);
				color.rgb = mix(color.rgb, col_3.rgb, amt_3);
				color.rgb = mix(color.rgb, col_2.rgb, amt_2);
				color.rgb = mix(color.rgb, col_1.rgb, amt_1);
				color.rgb = mix(color.rgb, col_0.rgb, amt_0);
			} else {
				//#blend_all
				color.rgb = mix(color.rgb, col_0.rgb, amt_0);
				color.rgb = mix(color.rgb, col_1.rgb, amt_1);
				color.rgb = mix(color.rgb, col_2.rgb, amt_2);
				color.rgb = mix(color.rgb, col_3.rgb, amt_3);
				color.rgb = mix(color.rgb, col_4.rgb, amt_4);
				color.rgb = mix(color.rgb, col_5.rgb, amt_5);
				color.rgb = mix(color.rgb, col_6.rgb, amt_6);
				color.rgb = mix(color.rgb, col_7.rgb, amt_7);
				color.rgb = mix(color.rgb, col_8.rgb, amt_8);
				color.rgb = mix(color.rgb, col_9.rgb, amt_9);
				color.rgb = mix(color.rgb, col_10.rgb, amt_10);
				color.rgb = mix(color.rgb, col_11.rgb, amt_11);
				color.rgb = mix(color.rgb, col_12.rgb, amt_12);
				color.rgb = mix(color.rgb, col_13.rgb, amt_13);
				color.rgb = mix(color.rgb, col_14.rgb, amt_14);
				color.rgb = mix(color.rgb, col_15.rgb, amt_15);
			}
		} else {
			color.a = 1.0;
			switch (buf_floor) {
				//#blend_simple
				case 0:
					color.rgb = mix(imageLoad(color_image, uvi).rgb, textureLod(downsample_color_buffer_0, uv, 0.0).rgb, buf_frac);
					break;
				BLEND_SIMPLE(1, downsample_color_buffer_0, downsample_color_buffer_1)
				BLEND_SIMPLE(2, downsample_color_buffer_1, downsample_color_buffer_2)
				BLEND_SIMPLE(3, downsample_color_buffer_2, downsample_color_buffer_3)
				BLEND_SIMPLE(4, downsample_color_buffer_3, downsample_color_buffer_4)
				BLEND_SIMPLE(5, downsample_color_buffer_4, downsample_color_buffer_5)
				BLEND_SIMPLE(6, downsample_color_buffer_5, downsample_color_buffer_6)
				BLEND_SIMPLE(7, downsample_color_buffer_6, downsample_color_buffer_7)
				BLEND_SIMPLE(8, downsample_color_buffer_7, downsample_color_buffer_8)
				BLEND_SIMPLE(9, downsample_color_buffer_8, downsample_color_buffer_9)
				BLEND_SIMPLE(10, downsample_color_buffer_9, downsample_color_buffer_10)
				BLEND_SIMPLE(11, downsample_color_buffer_10, downsample_color_buffer_11)
				BLEND_SIMPLE(12, downsample_color_buffer_11, downsample_color_buffer_12)
				BLEND_SIMPLE(13, downsample_color_buffer_12, downsample_color_buffer_13)
				BLEND_SIMPLE(14, downsample_color_buffer_13, downsample_color_buffer_14)
				BLEND_SIMPLE(15, downsample_color_buffer_14, downsample_color_buffer_15)
				case 16:
					color.rgb = textureLod(downsample_color_buffer_15, uv, 0.0).rgb;
					break;
			}
		}
	}
	
	imageStore(color_image, uvi, color);
}
