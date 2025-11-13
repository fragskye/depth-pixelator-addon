class_name DepthPixelatorGLSLComposite extends Object

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

	layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
	layout(set = 0, binding = 1) uniform sampler2D depth_texture;

	//#uniform_buffer

	//#scene_data_inc

	layout(set = 2, binding = 0, std140) uniform SceneDataBlock {
		SceneData data;
		SceneData prev_data;
	}
	scene;

	//#scene_data_utils_inc

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
			switch (buf_floor % 24) {
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
				DEBUG_COLOR(16, vec4(0.0, 0.0, 1.0, 1.0))
				DEBUG_COLOR(17, vec4(0.25, 0.0, 1.0, 1.0))
				DEBUG_COLOR(18, vec4(0.5, 0.0, 1.0, 1.0))
				DEBUG_COLOR(19, vec4(0.75, 0.0, 1.0, 1.0))
				DEBUG_COLOR(20, vec4(1.0, 0.0, 1.0, 1.0))
				DEBUG_COLOR(21, vec4(1.0, 0.0, 0.75, 1.0))
				DEBUG_COLOR(22, vec4(1.0, 0.0, 0.5, 1.0))
				DEBUG_COLOR(23, vec4(1.0, 0.0, 0.25, 1.0))
			}
		} else if (params.debug_mode == 2) {
			color = vec4(vec3(buf_frac), 1.0);
		} else if (params.debug_mode == 3) {
			switch (params.debug_buffer_index) {
				case 0:
					color = imageLoad(color_image, uvi);
					break;
				//#debug_color_texture
			}
		} else if (params.debug_mode == 4) {
			switch (params.debug_buffer_index) {
				DEBUG_DEPTH_TEXTURE(0, depth_texture)
				//#debug_depth_texture
			}
		} else {
			if (FLAG_TEST(FLAG_SAMPLE_ALL_LAYERS)) {
				color = imageLoad(color_image, uvi);
				//#sample_buffer
				if (params.pixel_near < params.pixel_far) {
					//#blend_all_reverse
				} else {
					//#blend_all
				}
			} else {
				color.a = 1.0;
				switch (buf_floor) {
					case 0:
						color.rgb = mix(imageLoad(color_image, uvi).rgb, textureLod(downsample_color_buffer_0, uv, 0.0).rgb, buf_frac);
						break;
					//#blend_simple
				}
			}
		}
		
		imageStore(color_image, uvi, color);
	}
	"
