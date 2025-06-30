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
	int downsample_color_buffer_count;
	int downsample_color_buffer_minimum;
	int downsample_color_buffer_index;
	int downsample_method;
	int flags;
	int debug_mode;
	int debug_buffer_index;
	int pad_0x3C;
} params;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_texture;

//# downsample_color_buffer_UNIFORMS
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

int cs_to_buf_idx(vec4 pos_cs) {
	vec3 pos_vs = cs_to_vs(pos_cs);
	float frac = (-pos_vs.z - params.pixel_near) / (params.pixel_far - params.pixel_near); // Depth along view direction, not world-space distance
	if (frac <= 0.0) {
		return 0;
	} else if (frac >= 1.0) {
		return params.downsample_color_buffer_count;
	}
	return int(ceil(frac * float(params.downsample_color_buffer_count)));
}

float cs_to_buf_pos(vec4 pos_cs) {
	vec3 pos_vs = cs_to_vs(pos_cs);
	float frac = pow((-pos_vs.z - params.pixel_near) / (params.pixel_far - params.pixel_near), params.pixel_distance_curve); // Depth along view direction, not world-space distance
	if (frac <= 0.0) {
		return float(params.downsample_color_buffer_minimum);
	} else if (frac >= 1.0) {
		return float(params.downsample_color_buffer_count);
	}
	return float(params.downsample_color_buffer_minimum) + frac * float(params.downsample_color_buffer_count - params.downsample_color_buffer_minimum);
}

#define SAMPLE_BUFFER(index, pos, amt, col, color_buffer, depth_buffer) \
	vec4 col = textureLod(color_buffer, uv, 0.0); \
	float pos = cs_to_buf_pos(uvz_to_cs(uv, textureLod(depth_buffer, uv, 0.0).r));\
	float amt = col.a > smoothstep(0.0, -1.0, pos - (index + 1)) ? smoothstep(1.0, 1.0 - params.pixel_blend, abs(pos - (index + 1))) : 0.0; \

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
	int buf_idx = cs_to_buf_idx(fragment_cs);
	float buf_pos = cs_to_buf_pos(fragment_cs);
	int buf_floor = int(floor(buf_pos));
	float buf_frac = params.pixel_blend <= 0.0 ? (buf_pos == buf_floor ? 0.0 : 1.0) : smoothstep(0.0, 1.0, (buf_pos - buf_floor) / params.pixel_blend);
	
	vec4 color = vec4(1.0, 0.0, 0.5, 1.0);
	
	if (params.debug_mode == 1) {
		switch (buf_floor) {
			DEBUG_COLOR(0, vec4(1.0, 0.0, 0.0, 1.0))
			DEBUG_COLOR(1, vec4(1.0, 0.5, 0.0, 1.0))
			DEBUG_COLOR(2, vec4(1.0, 1.0, 0.0, 1.0))
			DEBUG_COLOR(3, vec4(0.5, 1.0, 0.0, 1.0))
			DEBUG_COLOR(4, vec4(0.0, 1.0, 0.0, 1.0))
			DEBUG_COLOR(5, vec4(0.0, 1.0, 0.5, 1.0))
			DEBUG_COLOR(6, vec4(0.0, 1.0, 1.0, 1.0))
			DEBUG_COLOR(7, vec4(0.0, 0.5, 1.0, 1.0))
			DEBUG_COLOR(8, vec4(0.0, 0.0, 1.0, 1.0))
			DEBUG_COLOR(9, vec4(0.5, 0.0, 1.0, 1.0))
			DEBUG_COLOR(10, vec4(1.0, 0.0, 1.0, 1.0))
		}
	} else if (params.debug_mode == 2) {
		switch (params.debug_buffer_index) {
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
		}
	} else if (params.debug_mode == 3) {
		switch (params.debug_buffer_index) {
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
		}
	} else {
		if (FLAG_TEST(FLAG_SAMPLE_ALL_LAYERS)) {
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
			if (params.pixel_near < params.pixel_far) {
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
			}
		} else {
			switch (buf_floor) {
				case 0:
					color = mix(imageLoad(color_image, uvi), textureLod(downsample_color_buffer_0, uv, 0.0), buf_frac);
					break;
				case 1:
					color = mix(textureLod(downsample_color_buffer_0, uv, 0.0), textureLod(downsample_color_buffer_1, uv, 0.0), buf_frac);
					break;
				case 2:
					color = mix(textureLod(downsample_color_buffer_1, uv, 0.0), textureLod(downsample_color_buffer_2, uv, 0.0), buf_frac);
					break;
				case 3:
					color = mix(textureLod(downsample_color_buffer_2, uv, 0.0), textureLod(downsample_color_buffer_3, uv, 0.0), buf_frac);
					break;
				case 4:
					color = mix(textureLod(downsample_color_buffer_3, uv, 0.0), textureLod(downsample_color_buffer_4, uv, 0.0), buf_frac);
					break;
				case 5:
					color = mix(textureLod(downsample_color_buffer_4, uv, 0.0), textureLod(downsample_color_buffer_5, uv, 0.0), buf_frac);
					break;
				case 6:
					color = mix(textureLod(downsample_color_buffer_5, uv, 0.0), textureLod(downsample_color_buffer_6, uv, 0.0), buf_frac);
					break;
				case 7:
					color = mix(textureLod(downsample_color_buffer_6, uv, 0.0), textureLod(downsample_color_buffer_7, uv, 0.0), buf_frac);
					break;
				case 8:
					color = mix(textureLod(downsample_color_buffer_7, uv, 0.0), textureLod(downsample_color_buffer_8, uv, 0.0), buf_frac);
					break;
				case 9:
					color = mix(textureLod(downsample_color_buffer_8, uv, 0.0), textureLod(downsample_color_buffer_9, uv, 0.0), buf_frac);
					break;
				case 10:
					color = textureLod(downsample_color_buffer_9, uv, 0.0);
					break;
			}
		}
	}
	
	imageStore(color_image, uvi, color);
	
	//vec4 fragment_normal_roughness = normal_roughness_compatibility(textureLod(normal_roughness_texture, uv, 0.0));
	//vec3 fragment_normal_vs = fragment_normal_roughness.xyz;
	//vec4 fragment_cs = uvz_to_cs(uv, fragment_depth);
	//vec3 fragment_vs = cs_to_vs(fragment_cs);
}
