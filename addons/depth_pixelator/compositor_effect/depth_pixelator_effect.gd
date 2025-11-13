@tool
class_name DepthPixelatorEffect
extends CompositorEffect

@export_group("Depth Pixelation", "pixel_")
@export var pixel_layer_count: int = 6
@export_range(0.5, 1.0, 0.001) var pixel_scale_per_layer: float = 0.6
@export_exp_easing("positive_only") var pixel_distance_curve: float = 50.0
@export_range(0.0, 1.0, 0.01) var pixel_layer_blend: float = 0.0
@export var pixel_near_distance: float = 100.0
@export var pixel_far_distance: float = 0.0
@export_flags("Sample All Layers") var pixel_flags: int = 0x1
@export_group("Downsample Layers", "pixel_")
@export var pixel_downsample_buffer_minimum: int = 0
@export_enum("Average", "Brightest", "Darkest", "Pixel", "Closest Depth Pixel") var pixel_downsample_method: int = 0
@export_group("Debug", "debug_")
@export_enum("Disabled", "Depth Splits", "Depth Fractions", "Downsample Buffer", "Downsample Buffer Depth") var debug_mode: int = 0
@export var debug_debug_downsample_buffer_index: int = 0

var rd: RenderingDevice = null
var downsample_shader: RID = RID()
var downsample_pipeline: RID = RID()
var composite_shader: RID = RID()
var composite_pipeline: RID = RID()
var nearest_sampler: RID = RID()
var linear_sampler: RID = RID()

var _size: Vector2i = Vector2i.ZERO
var _view_count: int = 0
var _pixel_layer_count: int = 0
var _pixel_scale_per_layer: float = 0.0

var _downsample_layer_views: Array[Array] = []


func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY
	access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()
	_pixel_layer_count = maxi(0, pixel_layer_count)
	_pixel_scale_per_layer = pixel_scale_per_layer
	RenderingServer.call_on_render_thread(_init_compute)
	RenderingServer.call_on_render_thread(_create_downsample_layers)


func _init_compute() -> void:
	if !rd:
		push_error("RenderingDevice not found")
		return
	
	if downsample_shader.is_valid():
		rd.free_rid(downsample_shader)
		downsample_shader = RID()
		downsample_pipeline = RID()
	
	if composite_shader.is_valid():
		rd.free_rid(composite_shader)
		composite_shader = RID()
		composite_pipeline = RID()
	
	var downsample_shader_source: RDShaderSource = RDShaderSource.new()
	downsample_shader_source.source_compute = _apply_codegen(DepthPixelatorGLSLDownsample.SOURCE_COMPUTE)
	
	var downsample_shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(downsample_shader_source)
	if !downsample_shader_spirv.compile_error_compute.is_empty():
		push_error("Error getting depth pixelator downsample shader SPIRV")
		push_error(downsample_shader_spirv.compile_error_compute)
		return
	
	downsample_shader = rd.shader_create_from_spirv(downsample_shader_spirv)
	if !downsample_shader.is_valid():
		push_error("Depth pixelator downsample shader is not valid")
		return
	
	downsample_pipeline = rd.compute_pipeline_create(downsample_shader)
	if !downsample_pipeline.is_valid():
		push_error("Depth pixelator downsample compute pipeline is not valid")
		return
	
	
	var composite_shader_source: RDShaderSource = RDShaderSource.new()
	composite_shader_source.source_compute = _apply_codegen(DepthPixelatorGLSLComposite.SOURCE_COMPUTE)
	var composite_shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(composite_shader_source)
	if !composite_shader_spirv.compile_error_compute.is_empty():
		push_error("Error getting depth pixelator composite shader SPIRV")
		push_error(composite_shader_spirv.compile_error_compute)
		return
	
	composite_shader = rd.shader_create_from_spirv(composite_shader_spirv)
	if !composite_shader.is_valid():
		push_error("Depth pixelator composite shader is not valid")
		return
	
	composite_pipeline = rd.compute_pipeline_create(composite_shader)
	if !composite_pipeline.is_valid():
		push_error("Depth pixelator composite compute pipeline is not valid")
		return
	
	var sampler_state: RDSamplerState = RDSamplerState.new()
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	nearest_sampler = rd.sampler_create(sampler_state)
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	linear_sampler = rd.sampler_create(sampler_state)


func _create_downsample_layers() -> void:
	for downsample_layers: Array[DownsampleLayer] in _downsample_layer_views:
		for downsample_layer: DownsampleLayer in downsample_layers:
			downsample_layer.free_rids(rd)
	_downsample_layer_views.clear()
	
	var color_format: RDTextureFormat = RDTextureFormat.new()
	color_format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	color_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	color_format.width = _size.x
	color_format.height = _size.y
	color_format.depth = 1
	color_format.array_layers = 1
	color_format.mipmaps = 1
	color_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_INPUT_ATTACHMENT_BIT
	
	var depth_format: RDTextureFormat = RDTextureFormat.new()
	depth_format.format = RenderingDevice.DATA_FORMAT_D32_SFLOAT
	depth_format.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	depth_format.width = _size.x
	depth_format.height = _size.y
	depth_format.depth = 1
	depth_format.array_layers = 1
	depth_format.mipmaps = 1
	depth_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT | RenderingDevice.TEXTURE_USAGE_INPUT_ATTACHMENT_BIT
	
	for view: int in _view_count:
		var downsample_layers: Array[DownsampleLayer] = []
		for i: int in _pixel_layer_count:
			var downsample_layer: DownsampleLayer = DownsampleLayer.new()
			downsample_layer.layer_id = i
			color_format.width = maxi(1, floori(_size.x * pow(pixel_scale_per_layer,  i + 1)))
			color_format.height = maxi(1, floori(_size.y * pow(pixel_scale_per_layer, i + 1)))
			depth_format.width = color_format.width
			depth_format.height = color_format.height
			if color_format.width <= 1 || color_format.height <= 1:
				push_warning("pixel_scale_per_layer ^ pixel_layer_count is resulting in buffers that are too small")
			var color_buffer: RID = rd.texture_create(color_format, RDTextureView.new(), [])
			var depth_buffer: RID = rd.texture_create(depth_format, RDTextureView.new(), [])
			downsample_layer.color_buffer = color_buffer
			downsample_layer.depth_buffer = depth_buffer
			downsample_layers.push_back(downsample_layer)
		_downsample_layer_views.push_back(downsample_layers)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if downsample_shader.is_valid():
			rd.free_rid(downsample_shader)
		if composite_shader.is_valid():
			rd.free_rid(composite_shader)


func _render_callback(_effect_callback_type: EffectCallbackType, render_data: RenderData) -> void:
	if !rd:
		return
	
	var render_scene_buffers: RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	if !render_scene_buffers:
		return
	
	var render_scene_data: RenderSceneDataRD = render_data.get_render_scene_data()
	if !render_scene_data:
		return
	
	var size: Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 && size.y == 0:
		return
	
	var view_count: int = render_scene_buffers.get_view_count()
	
	var needs_update: bool = false
	
	if _size != size:
		_size = size
		needs_update = true
	
	if _view_count != view_count:
		_view_count = view_count
		needs_update = true
	
	if _pixel_layer_count != maxi(1, pixel_layer_count):
		needs_update = true
	
	if _pixel_scale_per_layer != pixel_scale_per_layer:
		needs_update = true
	
	if needs_update:
		_pixel_layer_count = maxi(1, pixel_layer_count)
		_pixel_scale_per_layer = pixel_scale_per_layer
		_init_compute()
		_create_downsample_layers()
	
	var push_constant: PackedByteArray = PackedByteArray()
	push_constant.resize(64)
	push_constant.encode_float(0x0, size.x) # raster_size.x
	push_constant.encode_float(0x4, size.y) # raster_size.y
	push_constant.encode_float(0x8, size.x) # src_size.x
	push_constant.encode_float(0xC, size.y) # src_size.y
	push_constant.encode_float(0x10, pixel_near_distance) # pixel_near
	push_constant.encode_float(0x14, pixel_far_distance) # pixel_far
	push_constant.encode_float(0x18, pixel_layer_blend) # pixel_blend
	push_constant.encode_float(0x1C, pixel_distance_curve) # pixel_distance_curve
	push_constant.encode_s32(0x20, _pixel_layer_count) # downsample_buffer_count
	push_constant.encode_s32(0x24, pixel_downsample_buffer_minimum) # downsample_buffer_minimum
	push_constant.encode_s32(0x28, 0) # downsample_buffer_index
	push_constant.encode_s32(0x2C, pixel_downsample_method) # downsample_method
	push_constant.encode_s32(0x30, pixel_flags) # flags
	push_constant.encode_s32(0x34, debug_mode) # debug_mode
	push_constant.encode_s32(0x38, debug_debug_downsample_buffer_index) # debug_buffer_index
	push_constant.encode_s32(0x3C, 0) # pad_0x3C
	
	var scene_data_buffer: RID = render_scene_data.get_uniform_buffer()
	
	rd.draw_command_begin_label("DepthPixelatorDownsample", Color.WHITE)
	
	# Separate the screen into each downsample layer, selecting colors based on depth ranges
	for view: int in view_count:
		var downsample_layers: Array[DownsampleLayer] = _downsample_layer_views[view]
		
		var src_color_buffer: RID = render_scene_buffers.get_color_layer(view)
		var src_depth_buffer: RID = render_scene_buffers.get_depth_layer(view)
		var src_width: int = size.x
		var src_height: int = size.y
		
		for i: int in downsample_layers.size():
			var downsample_layer: DownsampleLayer = downsample_layers[i]
			
			var dst_color_buffer: RID = downsample_layer.color_buffer
			var dst_depth_buffer: RID = downsample_layer.depth_buffer
			var dst_width: int = floori(_size.x * pow(pixel_scale_per_layer, i + 1))
			var dst_height: int = floori(_size.y * pow(pixel_scale_per_layer, i + 1))
			
			@warning_ignore("integer_division")
			var downsample_x_groups: int = (dst_width - 1) / 8 + 1
			@warning_ignore("integer_division")
			var downsample_y_groups: int = (dst_height - 1) / 8 + 1
			var downsample_z_groups: int = 1
			
			push_constant.encode_float(0x0, dst_width) # raster_size.x
			push_constant.encode_float(0x4, dst_height) # raster_size.y
			push_constant.encode_float(0x8, src_width) # src_size.x
			push_constant.encode_float(0xC, src_height) # src_size.y
			push_constant.encode_s32(0x28, downsample_layer.layer_id + 1) # downsample_buffer_index
			
			var uniform_set0_uniforms: Array[RDUniform] = [RDUniform.new(), RDUniform.new(), RDUniform.new(), RDUniform.new()]
			uniform_set0_uniforms[0].binding = 0 # dst_color_image
			uniform_set0_uniforms[0].uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_set0_uniforms[0].add_id(dst_color_buffer)
			uniform_set0_uniforms[1].binding = 1 # dst_depth_image
			uniform_set0_uniforms[1].uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			uniform_set0_uniforms[1].add_id(dst_depth_buffer)
			uniform_set0_uniforms[2].binding = 2 # src_color_texture
			uniform_set0_uniforms[2].uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform_set0_uniforms[2].add_id(nearest_sampler)
			uniform_set0_uniforms[2].add_id(src_color_buffer)
			uniform_set0_uniforms[3].binding = 3 # src_depth_texture
			uniform_set0_uniforms[3].uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform_set0_uniforms[3].add_id(nearest_sampler)
			uniform_set0_uniforms[3].add_id(src_depth_buffer)
			var uniform_set0: RID = UniformSetCacheRD.get_cache(downsample_shader, 0, uniform_set0_uniforms)
			
			var uniform_set1_uniforms: Array[RDUniform] = [RDUniform.new()]
			uniform_set1_uniforms[0].binding = 0 # scene
			uniform_set1_uniforms[0].uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
			uniform_set1_uniforms[0].add_id(scene_data_buffer)
			var uniform_set1: RID = UniformSetCacheRD.get_cache(downsample_shader, 1, uniform_set1_uniforms)
			
			var compute_list: int = rd.compute_list_begin()
			rd.compute_list_bind_compute_pipeline(compute_list, downsample_pipeline)
			rd.compute_list_bind_uniform_set(compute_list, uniform_set0, 0)
			rd.compute_list_bind_uniform_set(compute_list, uniform_set1, 1)
			rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
			rd.compute_list_dispatch(compute_list, downsample_x_groups, downsample_y_groups, downsample_z_groups)
			rd.compute_list_end()
	
	rd.draw_command_end_label()
	
	push_constant.encode_float(0x0, size.x)  # raster_size.x
	push_constant.encode_float(0x4, size.y)  # raster_size.y
	push_constant.encode_float(0x8, size.x)  # src_size.x
	push_constant.encode_float(0xC, size.y) # src_size.y
	push_constant.encode_s32(0x28, 0) # downsample_buffer_index
	
	@warning_ignore("integer_division")
	var composite_x_groups: int = (size.x - 1) / 8 + 1
	@warning_ignore("integer_division")
	var composite_y_groups: int = (size.y - 1) / 8 + 1
	var composite_z_groups: int = 1
	
	rd.draw_command_begin_label("DepthPixelatorComposite", Color.WHITE)
	
	# Composite the final image, combining all the downsample layers
	for view: int in view_count:
		var downsample_layers: Array[DownsampleLayer] = _downsample_layer_views[view]
		
		var uniform_set0_uniforms: Array[RDUniform] = [RDUniform.new(), RDUniform.new()]
		uniform_set0_uniforms[0].binding = 0 # color_image
		uniform_set0_uniforms[0].uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform_set0_uniforms[0].add_id(render_scene_buffers.get_color_layer(view))
		uniform_set0_uniforms[1].binding = 1 # depth_texture
		uniform_set0_uniforms[1].uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_set0_uniforms[1].add_id(nearest_sampler)
		uniform_set0_uniforms[1].add_id(render_scene_buffers.get_depth_layer(view))
		var uniform_set0: RID = UniformSetCacheRD.get_cache(composite_shader, 0, uniform_set0_uniforms)
		
		var uniform_set1_uniforms: Array[RDUniform] = []
		for i: int in _pixel_layer_count:
			var uniform_color: RDUniform = RDUniform.new()
			uniform_color.binding = i * 2 # downsample_color_buffer_n
			uniform_color.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform_color.add_id(nearest_sampler)
			if i < _pixel_layer_count:
				uniform_color.add_id(downsample_layers[i].color_buffer)
			else:
				uniform_color.add_id(render_scene_buffers.get_color_layer(view))
			uniform_set1_uniforms.push_back(uniform_color)
			
			var uniform_depth: RDUniform = RDUniform.new()
			uniform_depth.binding = i * 2 + 1 # downsample_depth_buffer_n
			uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			uniform_depth.add_id(nearest_sampler)
			if i < _pixel_layer_count:
				uniform_depth.add_id(downsample_layers[i].depth_buffer)
			else:
				uniform_depth.add_id(render_scene_buffers.get_depth_layer(view))
			uniform_set1_uniforms.push_back(uniform_depth)
		var uniform_set1: RID = UniformSetCacheRD.get_cache(composite_shader, 1, uniform_set1_uniforms)
		
		var uniform_set2_uniforms: Array[RDUniform] = [RDUniform.new()]
		uniform_set2_uniforms[0].binding = 0 # scene
		uniform_set2_uniforms[0].uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		uniform_set2_uniforms[0].add_id(scene_data_buffer)
		var uniform_set2: RID = UniformSetCacheRD.get_cache(composite_shader, 2, uniform_set2_uniforms)
		
		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, composite_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set0, 0)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set1, 1)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set2, 2)
		rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
		rd.compute_list_dispatch(compute_list, composite_x_groups, composite_y_groups, composite_z_groups)
		rd.compute_list_end()
	
	rd.draw_command_end_label()


func _apply_codegen(source: String) -> String:
	var version_info: Dictionary = Engine.get_version_info()
	
	if version_info.hex >= 0x040600:
		source = source.replace("//#scene_data_inc", DepthPixelatorGLSLSceneDataInc.SOURCE_4_6)
	if version_info.hex >= 0x040500:
		source = source.replace("//#scene_data_inc", DepthPixelatorGLSLSceneDataInc.SOURCE_4_5)
	elif version_info.hex >= 0x040400:
		source = source.replace("//#scene_data_inc", DepthPixelatorGLSLSceneDataInc.SOURCE_4_4)
	elif version_info.hex >= 0x040300:
		source = source.replace("//#scene_data_inc", DepthPixelatorGLSLSceneDataInc.SOURCE_4_3)
	
	if version_info.hex >= 0x040600:
		source = source.replace("//#scene_data_utils_inc", DepthPixelatorGLSLSceneDataUtilsInc.SOURCE_4_6)
	elif version_info.hex >= 0x040300:
		source = source.replace("//#scene_data_utils_inc", DepthPixelatorGLSLSceneDataUtilsInc.SOURCE_4_3)
	
	var source_uniform_buffer: String = ""
	for i: int in _pixel_layer_count:
		source_uniform_buffer += "
			layout(set = 1, binding = %d) uniform sampler2D downsample_color_buffer_%d;
			layout(set = 1, binding = %d) uniform sampler2D downsample_depth_buffer_%d;
			" % [i * 2, i, i * 2 + 1, i]
	source = source.replace("//#uniform_buffer", source_uniform_buffer)
	
	var source_debug_color_texture: String = ""
	for i: int in _pixel_layer_count:
		source_debug_color_texture += "
			DEBUG_COLOR_TEXTURE(%d, downsample_color_buffer_%d)
			" % [i + 1, i]
	source = source.replace("//#debug_color_texture", source_debug_color_texture)
	
	var source_debug_depth_texture: String = ""
	for i: int in _pixel_layer_count:
		source_debug_depth_texture += "
			DEBUG_DEPTH_TEXTURE(%d, downsample_depth_buffer_%d)
			" % [i + 1, i]
	source = source.replace("//#debug_depth_texture", source_debug_depth_texture)
	
	var source_sample_buffer: String = ""
	for i: int in _pixel_layer_count:
		source_sample_buffer += "
			SAMPLE_BUFFER(%d, pos_%d, amt_%d, col_%d, downsample_color_buffer_%d, downsample_depth_buffer_%d)
			" % [i, i, i, i, i, i]
	source = source.replace("//#sample_buffer", source_sample_buffer)
	
	var source_blend_all_reverse: String = ""
	for i: int in range(_pixel_layer_count - 1, -1, -1):
		source_blend_all_reverse += "
			color.rgb = mix(color.rgb, col_%d.rgb, amt_%d);
			" % [i, i]
	source = source.replace("//#blend_all_reverse", source_blend_all_reverse)
	
	var source_blend_all: String = ""
	for i: int in _pixel_layer_count:
		source_blend_all += "
			color.rgb = mix(color.rgb, col_%d.rgb, amt_%d);
			" % [i, i]
	source = source.replace("//#blend_all", source_blend_all)
	
	var source_blend_simple: String = ""
	for i: int in _pixel_layer_count - 1:
		source_blend_simple += "
			BLEND_SIMPLE(%d, downsample_color_buffer_%d, downsample_color_buffer_%d)
			" % [i + 1, i, i]
	source_blend_simple += "
		case %d:
			color.rgb = textureLod(downsample_color_buffer_%d, uv, 0.0).rgb;
			break;
		" % [_pixel_layer_count, _pixel_layer_count - 1]
	source = source.replace("//#blend_simple", source_blend_simple)
	
	return source


class DownsampleLayer extends RefCounted:
	var layer_id: int = 0
	var color_buffer: RID = RID()
	var depth_buffer: RID = RID()
	var layer_data_buffer: RID = RID()


	func free_rids(rd: RenderingDevice) -> void:
		if color_buffer.is_valid():
			rd.free_rid(color_buffer)
		if depth_buffer.is_valid():
			rd.free_rid(depth_buffer)
