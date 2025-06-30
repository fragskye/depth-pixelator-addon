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

int cs_to_buf_idx(vec4 pos_cs) {
	vec3 pos_vs = cs_to_vs(pos_cs);
	float frac = pow((-pos_vs.z - params.pixel_near) / (params.pixel_far - params.pixel_near), params.pixel_distance_curve); // Depth along view direction, not world-space distance
	if (frac <= 0.0) {
		return params.downsample_buffer_minimum;
	} else if (frac >= 1.0) {
		return params.downsample_buffer_count;
	}
	return int(floor(params.downsample_buffer_minimum + frac * float(params.downsample_buffer_count - params.downsample_buffer_minimum)));
}

#define PROCESS_SAMPLE(sample_buf_idx, sample_uv, sample_cs, sample_col) \
	vec4 sample_col = vec4(0.0); \
	if (sample_buf_idx == params.downsample_buffer_index || sample_buf_idx == params.downsample_buffer_index - 1) { \
		depth = max(depth, sample_cs.z); \
		sample_col = textureLod(src_color_texture, sample_uv, 0.0); \
		if (depth <= 1e-6) { \
			sample_col = vec4(0.0); \
		} \
		if (params.downsample_method == 0) { \
			color.rgb += sample_col.rgb * sample_col.a; \
			color.a += sample_col.a; \
		} else if (params.downsample_method == 1) { \
			if (sample_col.a > 0.0) { \
				float brightness = dot(sample_col.rgb, vec3(0.333333)); \
				if (brightness > brightest) { \
					brightest_color = sample_col; \
					brightest = brightness; \
				} \
				if (brightness < darkest) { \
					darkest_color = sample_col; \
					darkest = brightness; \
				} \
			} \
		} else if (params.downsample_method == 2) { \
			float brightness = dot(sample_col.rgb, vec3(0.333333)); \
			if (brightness > brightest) { \
				color = sample_col; \
				brightest = brightness; \
			} \
		} else if (params.downsample_method == 3) { \
			float brightness = dot(sample_col.rgb, vec3(0.333333)); \
			if (brightness < darkest) { \
				color = sample_col; \
				darkest = brightness; \
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
	vec4 brightest_color = vec4(0.0);
	vec4 darkest_color = vec4(0.0);
	float depth = 0.0;
	
	vec2 scale = params.src_size / params.raster_size;
	ivec2 src_uvi = ivec2(floor(uvi / params.raster_size * params.src_size));
	
	vec2 uv_offset = params.downsample_method == 4 ? vec2(0.5) : vec2(0.0);
	
	/*vec2 sample_0_uv = (floor(vec2(uvi * scale)) + 0.5) / src_size;
	vec2 sample_1_uv = (floor(vec2(uvi * scale + vec2(1.0, 0.0))) + 0.5) / src_size;
	vec2 sample_2_uv = (floor(vec2(uvi * scale + vec2(0.0, 1.0))) + 0.5) / src_size;
	vec2 sample_3_uv = (floor(vec2(uvi * scale + vec2(1.0))) + 0.5) / src_size;/**/
	/*ec2 sample_0_uv = vec2(src_uvi + vec2(0.25)) / params.src_size;
	vec2 sample_1_uv = vec2(src_uvi + vec2(0.75, 0.25)) / params.src_size;
	vec2 sample_2_uv = vec2(src_uvi + vec2(0.25, 0.75)) / params.src_size;
	vec2 sample_3_uv = vec2(src_uvi + vec2(0.75)) / params.src_size;/**/
	/*vec2 sample_0_uv = vec2(src_uvi) / params.src_size;
	vec2 sample_1_uv = vec2(src_uvi + vec2(1.0, 0.0)) / params.src_size;
	vec2 sample_2_uv = vec2(src_uvi + vec2(0.0, 1.0)) / params.src_size;
	vec2 sample_3_uv = vec2(src_uvi + vec2(1.0)) / params.src_size;/**/
	/*vec2 sample_0_uv = vec2(uvi + vec2(0.25)) / size;
	vec2 sample_1_uv = vec2(uvi + vec2(0.75, 0.25)) / size;
	vec2 sample_2_uv = vec2(uvi + vec2(0.25, 0.75)) / size;
	vec2 sample_3_uv = vec2(uvi + vec2(0.75)) / size;/**/
	vec2 sample_0_uv = vec2(uvi + uv_offset + vec2(0.0)) / size;
	vec2 sample_1_uv = vec2(uvi + uv_offset + vec2(1.0, 0.0)) / size;
	vec2 sample_2_uv = vec2(uvi + uv_offset + vec2(0.0, 1.0)) / size;
	vec2 sample_3_uv = vec2(uvi + uv_offset + vec2(1.0)) / size;/**/
	vec4 sample_0_cs = uv_to_cs(sample_0_uv);
	vec4 sample_1_cs = uv_to_cs(sample_1_uv);
	vec4 sample_2_cs = uv_to_cs(sample_2_uv);
	vec4 sample_3_cs = uv_to_cs(sample_3_uv);
	int sample_0_buf_idx = cs_to_buf_idx(sample_0_cs);
	int sample_1_buf_idx = cs_to_buf_idx(sample_1_cs);
	int sample_2_buf_idx = cs_to_buf_idx(sample_2_cs);
	int sample_3_buf_idx = cs_to_buf_idx(sample_3_cs);
	PROCESS_SAMPLE(sample_0_buf_idx, sample_0_uv, sample_0_cs, sample_0_col)
	PROCESS_SAMPLE(sample_1_buf_idx, sample_1_uv, sample_1_cs, sample_1_col)
	PROCESS_SAMPLE(sample_2_buf_idx, sample_2_uv, sample_2_cs, sample_2_col)
	PROCESS_SAMPLE(sample_3_buf_idx, sample_3_uv, sample_3_cs, sample_3_col)
	if (params.downsample_method == 4) {
		if (sample_0_col.a > 0.0) {
			color = sample_0_col;
		} else if (sample_1_col.a > 0.0) {
			color = sample_1_col;
		} else if (sample_2_col.a > 0.0) {
			color = sample_2_col;
		} else if (sample_3_col.a > 0.0) {
			color = sample_3_col;
		}
	} else {
		if (params.downsample_method == 1) {
			float count = 0.0;
			SUM_SAMPLE(count, sample_0_cs, sample_0_col)
			SUM_SAMPLE(count, sample_1_cs, sample_1_col)
			SUM_SAMPLE(count, sample_2_cs, sample_2_col)
			SUM_SAMPLE(count, sample_3_cs, sample_3_col)
			color.a /= 4.0;
			if (count > 0.0) {
				color.rgb /= count;
			} else {
				if (darkest_color.a > 0.0) {
					if (brightest_color.a > 0.0) {
						color.rgb = darkest_color.rgb * darkest_color.a + brightest_color.rgb * brightest_color.a;
						color.rgb /= darkest_color.a + brightest_color.a;
					} else {
						color.rgb = darkest_color.rgb;
					}
				} else if (brightest_color.a > 0.0) {
					color.rgb = brightest_color.rgb;
				}
			}
		}
	}
	
	if (color.a > 0.0) {
		if (params.downsample_method == 0) {
			color.rgb /= color.a;
			color.a *= 0.25;
		}
	} else {
		color = vec4(0.0, 0.0, 0.0, 0.0);
	}
	
	imageStore(dst_color_image, uvi, color);
	imageStore(dst_depth_image, uvi, vec4(depth));
	
	//vec4 fragment_normal_roughness = normal_roughness_compatibility(textureLod(normal_roughness_texture, uv, 0.0));
	//vec3 fragment_normal_vs = fragment_normal_roughness.xyz;
	//vec4 fragment_cs = uvz_to_cs(uv, fragment_depth);
	//vec3 fragment_vs = cs_to_vs(fragment_cs);
}
