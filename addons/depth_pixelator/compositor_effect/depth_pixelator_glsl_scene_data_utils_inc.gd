class_name DepthPixelatorGLSLSceneDataUtilsInc extends Object

const SOURCE_4_6: String = "
	mat4 expand_view_matrix(mat3x4 view_matrix) {
		return transpose(mat4(view_matrix[0], view_matrix[1], view_matrix[2], vec4(0.0, 0.0, 0.0, 1.0)));
	}

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
		return (expand_view_matrix(scene.data.inv_view_matrix) * vec4(pos_vs, apply_translation)).xyz;
	}

	vec3 vs_to_ws(vec3 pos_vs) {
		return vs_to_ws(pos_vs, 1.0);
	}

	vec3 ws_to_vs(vec3 pos_ws, float apply_translation) {
		return (expand_view_matrix(scene.data.view_matrix) * vec4(pos_ws, apply_translation)).xyz;
	}

	vec3 ws_to_vs(vec3 pos_ws) {
		return ws_to_vs(pos_ws, 1.0);
	}
	"

const SOURCE_4_3: String = "
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
	"
