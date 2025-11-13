class_name DepthPixelatorGLSLSceneDataInc extends Object

# https://github.com/godotengine/godot/blob/14b60f226445c1463a07f70adaa8c8110d88245c/servers/rendering/renderer_rd/shaders/scene_data_inc.glsl
const SOURCE_4_6: String = "
	#define MAX_VIEWS 2

	struct SceneData {
		mat4 projection_matrix;
		mat4 inv_projection_matrix;
		mat3x4 inv_view_matrix;
		mat3x4 view_matrix;

	#ifdef USE_DOUBLE_PRECISION
		vec4 inv_view_precision;
	#endif

		// only used for multiview
		mat4 projection_matrix_view[MAX_VIEWS];
		mat4 inv_projection_matrix_view[MAX_VIEWS];
		vec4 eye_offset[MAX_VIEWS];

		// Used for billboards to cast correct shadows.
		mat4 main_cam_inv_view_matrix;

		vec2 viewport_size;
		vec2 screen_pixel_size;

		// Use vec4s because std140 doesn't play nice with vec2s, z and w are wasted.
		vec4 directional_penumbra_shadow_kernel[32];
		vec4 directional_soft_shadow_kernel[32];
		vec4 penumbra_shadow_kernel[32];
		vec4 soft_shadow_kernel[32];

		vec2 shadow_atlas_pixel_size;
		vec2 directional_shadow_pixel_size;

		uint directional_light_count;
		float dual_paraboloid_side;
		float z_far;
		float z_near;

		float roughness_limiter_amount;
		float roughness_limiter_limit;
		float opaque_prepass_threshold;
		uint flags;

		mat3 radiance_inverse_xform;

		vec4 ambient_light_color_energy;

		float ambient_color_sky_mix;
		float fog_density;
		float fog_height;
		float fog_height_density;

		float fog_depth_curve;
		float fog_depth_begin;
		float fog_depth_end;
		float fog_sun_scatter;

		vec3 fog_light_color;
		float fog_aerial_perspective;

		float time;
		float taa_frame_count;
		vec2 taa_jitter;

		float emissive_exposure_normalization;
		float IBL_exposure_normalization;
		uint camera_visible_layers;
		float pass_alpha_multiplier;
	};
	"

# https://github.com/godotengine/godot/blob/46277836a60545e729ea2b7c4dc24bfc9565e67c/servers/rendering/renderer_rd/shaders/scene_data_inc.glsl
const SOURCE_4_5: String = "
	#define MAX_VIEWS 2

	struct SceneData {
		mat4 projection_matrix;
		mat4 inv_projection_matrix;
		mat4 inv_view_matrix;
		mat4 view_matrix;

		// only used for multiview
		mat4 projection_matrix_view[MAX_VIEWS];
		mat4 inv_projection_matrix_view[MAX_VIEWS];
		vec4 eye_offset[MAX_VIEWS];

		// Used for billboards to cast correct shadows.
		mat4 main_cam_inv_view_matrix;

		vec2 viewport_size;
		vec2 screen_pixel_size;

		// Use vec4s because std140 doesn't play nice with vec2s, z and w are wasted.
		vec4 directional_penumbra_shadow_kernel[32];
		vec4 directional_soft_shadow_kernel[32];
		vec4 penumbra_shadow_kernel[32];
		vec4 soft_shadow_kernel[32];

		vec2 shadow_atlas_pixel_size;
		vec2 directional_shadow_pixel_size;

		uint directional_light_count;
		float dual_paraboloid_side;
		float z_far;
		float z_near;

		float roughness_limiter_amount;
		float roughness_limiter_limit;
		float opaque_prepass_threshold;
		uint flags;

		mat3 radiance_inverse_xform;

		vec4 ambient_light_color_energy;

		float ambient_color_sky_mix;
		float fog_density;
		float fog_height;
		float fog_height_density;

		float fog_depth_curve;
		float fog_depth_begin;
		float fog_depth_end;
		float fog_sun_scatter;

		vec3 fog_light_color;
		float fog_aerial_perspective;

		float time;
		float taa_frame_count;
		vec2 taa_jitter;

		float emissive_exposure_normalization;
		float IBL_exposure_normalization;
		uint camera_visible_layers;
		float pass_alpha_multiplier;
	};
	"

# https://github.com/godotengine/godot/blob/0eb06da057e8e912d6f9b3de4b3efbd3dc46624c/servers/rendering/renderer_rd/shaders/scene_data_inc.glsl
const SOURCE_4_4: String = "
	#define MAX_VIEWS 2

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

		mediump mat3 radiance_inverse_xform;

		mediump vec4 ambient_light_color_energy;

		mediump float ambient_color_sky_mix;
		bool use_ambient_light;
		bool use_ambient_cubemap;
		bool use_reflection_cubemap;

		highp vec2 shadow_atlas_pixel_size;
		highp vec2 directional_shadow_pixel_size;

		uint directional_light_count;
		mediump float dual_paraboloid_side;
		highp float z_far;
		highp float z_near;

		bool roughness_limiter_enabled;
		mediump float roughness_limiter_amount;
		mediump float roughness_limiter_limit;
		mediump float opaque_prepass_threshold;

		bool fog_enabled;
		uint fog_mode;
		highp float fog_density;
		highp float fog_height;

		highp float fog_height_density;
		highp float fog_depth_curve;
		highp float fog_depth_begin;
		highp float taa_frame_count;

		mediump vec3 fog_light_color;
		highp float fog_depth_end;

		mediump float fog_sun_scatter;
		mediump float fog_aerial_perspective;
		highp float time;
		mediump float reflection_multiplier; // one normally, zero when rendering reflections

		vec2 taa_jitter;
		bool material_uv2_mode;
		float emissive_exposure_normalization;

		float IBL_exposure_normalization;
		bool pancake_shadows;
		uint camera_visible_layers;
		float pass_alpha_multiplier;
	};
	"

# https://github.com/godotengine/godot/blob/08f4560e6987fa9c4b2c4b8e86665e2862a43ed9/servers/rendering/renderer_rd/shaders/scene_data_inc.glsl
const SOURCE_4_3: String = "
	#define MAX_VIEWS 2

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

		mediump mat3 radiance_inverse_xform;

		mediump vec4 ambient_light_color_energy;

		mediump float ambient_color_sky_mix;
		bool use_ambient_light;
		bool use_ambient_cubemap;
		bool use_reflection_cubemap;

		highp vec2 shadow_atlas_pixel_size;
		highp vec2 directional_shadow_pixel_size;

		uint directional_light_count;
		mediump float dual_paraboloid_side;
		highp float z_far;
		highp float z_near;

		bool roughness_limiter_enabled;
		mediump float roughness_limiter_amount;
		mediump float roughness_limiter_limit;
		mediump float opaque_prepass_threshold;

		bool fog_enabled;
		uint fog_mode;
		highp float fog_density;
		highp float fog_height;
		highp float fog_height_density;

		highp float fog_depth_curve;
		highp float pad;
		highp float fog_depth_begin;

		mediump vec3 fog_light_color;
		highp float fog_depth_end;

		mediump float fog_sun_scatter;
		mediump float fog_aerial_perspective;
		highp float time;
		mediump float reflection_multiplier; // one normally, zero when rendering reflections

		vec2 taa_jitter;
		bool material_uv2_mode;
		float emissive_exposure_normalization;

		float IBL_exposure_normalization;
		bool pancake_shadows;
		uint camera_visible_layers;
		float pass_alpha_multiplier;
	};
	"
