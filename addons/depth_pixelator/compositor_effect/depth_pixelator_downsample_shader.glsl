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

layout(rgba16f, set = 0, binding = 0) uniform image2D dst_color_image;
layout(r32f, set = 0, binding = 1) uniform image2D dst_depth_image;
layout(set = 0, binding = 2) uniform sampler2D src_color_texture;
layout(set = 0, binding = 3) uniform sampler2D src_depth_texture;

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

layout(set = 1, binding = 0, std140) uniform SceneDataBlock {
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

vec4 uv_to_cs(vec2 uv) {
	float fragment_depth = textureLod(src_depth_texture, uv, 0.0).r;
	return uvz_to_cs(uv, fragment_depth);
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

#define PROCESS_SAMPLE(sample_buf_floor, sample_uv, sample_cs, sample_col) \
	vec4 sample_col = vec4(0.0); \
	if (sample_buf_floor == params.downsample_buffer_index || sample_buf_floor == params.downsample_buffer_index - 1) { \
		sample_col = textureLod(src_color_texture, sample_uv, 0.0); \
		if (sample_cs.z <= 1e-6) { \
			sample_col = vec4(0.0); \
		} \
		color.a += sample_col.a; \
		if (sample_cs.z > depth) { \
			depth = sample_cs.z; \
			if (params.downsample_method == 4 && sample_col.a > 0.0) { \
				color.rgb = sample_col.rgb; \
			} \
		} \
		if (params.downsample_method == 0) { \
			color.rgb += sample_col.rgb * sample_col.a; \
		} else if (params.downsample_method == 1) { \
			float brightness = dot(sample_col.rgb, vec3(0.333333)); \
			if (brightness > brightest) { \
				color.rgb = sample_col.rgb; \
				brightest = brightness; \
			} \
		} else if (params.downsample_method == 2) { \
			float brightness = dot(sample_col.rgb, vec3(0.333333)); \
			if (brightness < darkest) { \
				color.rgb = sample_col.rgb; \
				darkest = brightness; \
			} \
		} else if (params.downsample_method == 3) { \
			if (sample_col.a > 0.0) { \
				color.rgb = sample_col.rgb; \
			} \
		} \
	}

#define SUM_SAMPLE(count, sample_cs, sample_col) \
	color.a += sample_col.a; \
	if (sample_col.a > 0.0 && dot(abs(sample_col.rgb - brightest_color.rgb), vec3(1.0)) > 1e-6 && dot(abs(sample_col.rgb - darkest_color.rgb), vec3(1.0)) > 1e-6) { \
		color.rgb += sample_col.rgb * sample_col.a; \
		count += sample_col.a; \
	}

void main() {
    ivec2 size = ivec2(params.raster_size);
    ivec2 src_size = ivec2(params.src_size);
    ivec2 uvi = ivec2(gl_GlobalInvocationID.xy);
	
    if (uvi.x >= size.x || uvi.y >= size.y) {
        return;
    }
	
	vec4 color = vec4(0.0);
	float brightest = -infinity;
	float darkest = infinity;
	float depth = 0.0;
	
	vec2 dst_uv_min = vec2(uvi) / size;
	vec2 dst_uv_max = vec2(uvi + vec2(1.0)) / size;
	ivec2 src_uvi_min = ivec2(dst_uv_min * src_size);
	ivec2 src_uvi_max = ivec2(dst_uv_max * src_size);
	ivec2 src_uvi_size = src_uvi_max - src_uvi_min;
	int src_total = src_uvi_size.x * src_uvi_size.y;
	
	for (int src_uvi_y = src_uvi_min.y; src_uvi_y < src_uvi_max.y; src_uvi_y++) {
		for (int src_uvi_x = src_uvi_min.x; src_uvi_x < src_uvi_max.x; src_uvi_x++) {
			ivec2 src_uvi = ivec2(src_uvi_x, src_uvi_y);
			vec2 src_uv = vec2(src_uvi) / src_size;
			
			vec4 sample_cs = uv_to_cs(src_uv);
			float sample_buf_floor = floor(cs_to_buf_pos(sample_cs));
			PROCESS_SAMPLE(sample_buf_floor, src_uv, sample_cs, sample_col)
		}
	}
	
	if (color.a > 0.0) {
		if (params.downsample_method == 0) {
			color.rgb /= color.a;
		}
		color.a /= src_total;
	} else {
		color = vec4(0.0, 0.0, 0.0, 0.0);
	}
	
	imageStore(dst_color_image, uvi, color);
	imageStore(dst_depth_image, uvi, vec4(depth));
}
