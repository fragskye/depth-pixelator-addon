class_name DepthPixelatorGLSLDownsample extends Object

const SOURCE_COMPUTE: String = "
	#version 450

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

	//#scene_data_inc

	layout(set = 1, binding = 0, std140) uniform SceneDataBlock {
		SceneData data;
		SceneData prev_data;
	}
	scene;

	//#scene_data_utils_inc

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
		vec2 dst_uv_max = vec2(uvi + ivec2(1)) / size;
		ivec2 src_uvi_min = ivec2(round(dst_uv_min * src_size));
		ivec2 src_uvi_max = ivec2(round(dst_uv_max * src_size));
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
	"
