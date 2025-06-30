@tool
class_name DepthPixelatorEffect
extends CompositorEffect

const DEPTH_PIXELATOR_DOWNSAMPLE_SHADER: RDShaderFile = preload("res://addons/depth_pixelator/compositor_effect/depth_pixelator_downsample_shader.glsl")
const DEPTH_PIXELATOR_COMPOSITE_SHADER: RDShaderFile = preload("res://addons/depth_pixelator/compositor_effect/depth_pixelator_composite_shader.glsl")
const MAX_LAYER_COUNT: int = 16

@export_group("Depth Pixelation", "pixel_")
@export_range(0, MAX_LAYER_COUNT, 1) var pixel_layer_count: int = 3
@export_range(0.5, 1.0, 0.001) var pixel_scale_per_layer: float = 0.5
@export_exp_easing("positive_only") var pixel_distance_curve: float = 1.0
@export_range(0.0, 1.0, 0.01) var pixel_layer_blend: float = 0.5
@export var pixel_near_distance: float = 5.0
@export var pixel_far_distance: float = 15.0
@export_flags("Sample All Layers") var pixel_flags: int = 0x1
@export_group("Downsample Layers", "pixel_")
@export var pixel_downsample_buffer_minimum: int = 0
@export_enum("Average", "Brightest", "Darkest", "Pixel", "Closest Depth Pixel") var pixel_downsample_method: int = 0
@export_group("Debug", "debug_")
@export_enum("Disabled", "Depth Splits", "Depth Fractions", "Downsample Buffer", "Downsample Buffer Depth") var debug_mode: int = 0
@export_range(0, MAX_LAYER_COUNT, 1) var debug_debug_downsample_buffer_index: int = 0
@export_range(0, MAX_LAYER_COUNT, 1) var debug_downsample_buffer_iteration_limit: int = MAX_LAYER_COUNT

var rd: RenderingDevice = null
var downsample_shader: RID = RID()
var downsample_pipeline: RID = RID()
var composite_shader: RID = RID()
var composite_pipeline: RID = RID()
var nearest_sampler: RID = RID()
var linear_sampler: RID = RID()

var _size: Vector2i = Vector2i.ZERO
var _pixel_layer_count: int = 0
var _pixel_scale_per_layer: float = 0.0

var _downsample_layers: Array[DownsampleLayer] = []

func _init() -> void:
	effect_callback_type = CompositorEffect.EFFECT_CALLBACK_TYPE_POST_SKY
	access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()
	RenderingServer.call_on_render_thread(_init_compute)

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
	
	var downsample_shader_spirv: RDShaderSPIRV = DEPTH_PIXELATOR_DOWNSAMPLE_SHADER.get_spirv()
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
	
	
	var composite_shader_spirv: RDShaderSPIRV = DEPTH_PIXELATOR_COMPOSITE_SHADER.get_spirv()
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
	for downsample_layer: DownsampleLayer in _downsample_layers:
		downsample_layer.free_rids(rd)
	_downsample_layers.clear()
	
	var color_format: RDTextureFormat = RDTextureFormat.new()
	color_format.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT #RenderingDevice.DATA_FORMAT_A2B10G10R10_UNORM_PACK32 # #RenderingDevice.DATA_FORMAT_B8G8R8A8_UNORM
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
	
	for i: int in clampi(pixel_layer_count, 0, MAX_LAYER_COUNT):
		var downsample_layer: DownsampleLayer = DownsampleLayer.new()
		downsample_layer.layer_id = i
		color_format.width = floori(_size.x * pow(pixel_scale_per_layer, i + 1))
		color_format.height = floori(_size.y * pow(pixel_scale_per_layer, i + 1))
		depth_format.width = floori(_size.x * pow(pixel_scale_per_layer, i + 1))
		depth_format.height = floori(_size.y * pow(pixel_scale_per_layer, i + 1))
		var color_buffer: RID = rd.texture_create(color_format, RDTextureView.new(), [])
		var depth_buffer: RID = rd.texture_create(depth_format, RDTextureView.new(), [])
		downsample_layer.color_buffer = color_buffer
		downsample_layer.depth_buffer = depth_buffer
		_downsample_layers.push_back(downsample_layer)
	_pixel_layer_count = clampi(pixel_layer_count, 0, MAX_LAYER_COUNT)
	_pixel_scale_per_layer = pixel_scale_per_layer

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
	
	if _size != size:
		_size = size
		_create_downsample_layers()
	
	if _pixel_layer_count != clampi(pixel_layer_count, 0, MAX_LAYER_COUNT):
		_create_downsample_layers()
	
	if _pixel_scale_per_layer != pixel_scale_per_layer:
		_create_downsample_layers()
	
	var push_constant: PackedByteArray = PackedByteArray()
	push_constant.resize(64)
	push_constant.encode_float(0x0, size.x)
	push_constant.encode_float(0x4, size.y)
	push_constant.encode_float(0x8, size.x)
	push_constant.encode_float(0xC, size.y)
	push_constant.encode_float(0x10, pixel_near_distance)
	push_constant.encode_float(0x14, pixel_far_distance)
	push_constant.encode_float(0x18, pixel_layer_blend)
	push_constant.encode_float(0x1C, pixel_distance_curve)
	push_constant.encode_s32(0x20, _pixel_layer_count)
	push_constant.encode_s32(0x24, pixel_downsample_buffer_minimum)
	push_constant.encode_s32(0x28, 0)
	push_constant.encode_s32(0x2C, pixel_downsample_method)
	push_constant.encode_s32(0x30, pixel_flags)
	push_constant.encode_s32(0x34, debug_mode)
	push_constant.encode_s32(0x38, debug_debug_downsample_buffer_index)
	push_constant.encode_s32(0x3C, 0)
	
	var scene_data_buffer: RID = render_scene_data.get_uniform_buffer()
	
	#var view_count: int = render_scene_buffers.get_view_count()
	
	# TODO: Multiview
	#for view: int in view_count:
	var src_color_buffer: RID = render_scene_buffers.get_color_layer(0)
	var src_depth_buffer: RID = render_scene_buffers.get_depth_layer(0)
	var src_width: int = size.x
	var src_height: int = size.y
	
	for i: int in _downsample_layers.size():
		var downsample_layer: DownsampleLayer = _downsample_layers[i]
		
		var dst_color_buffer: RID = downsample_layer.color_buffer
		var dst_depth_buffer: RID = downsample_layer.depth_buffer
		var dst_width: int = floori(_size.x * pow(pixel_scale_per_layer, i + 1))
		var dst_height: int = floori(_size.y * pow(pixel_scale_per_layer, i + 1))
		
		var x_groups: int = (dst_width - 1) / 8 + 1
		var y_groups: int = (dst_height - 1) / 8 + 1
		var z_groups: int = 1
		
		push_constant.encode_float(0x0, dst_width)
		push_constant.encode_float(0x4, dst_height)
		push_constant.encode_float(0x8, src_width)
		push_constant.encode_float(0xC, src_height)
		push_constant.encode_s32(0x28, downsample_layer.layer_id + 1)
		
		var uniform0_0: RDUniform = RDUniform.new()
		uniform0_0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform0_0.binding = 0
		uniform0_0.add_id(dst_color_buffer)
		var uniform0_1: RDUniform = RDUniform.new()
		uniform0_1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform0_1.binding = 1
		uniform0_1.add_id(dst_depth_buffer)
		var uniform0_2: RDUniform = RDUniform.new()
		uniform0_2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform0_2.binding = 2
		uniform0_2.add_id(nearest_sampler)
		uniform0_2.add_id(src_color_buffer)
		var uniform0_3: RDUniform = RDUniform.new()
		uniform0_3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform0_3.binding = 3
		uniform0_3.add_id(nearest_sampler)
		uniform0_3.add_id(src_depth_buffer)
		var uniform_set0: RID = UniformSetCacheRD.get_cache(downsample_shader, 0, [uniform0_0, uniform0_1, uniform0_2, uniform0_3])
		
		#if downsample_layer.layer_data_buffer.is_valid():
		#	rd.free_rid(downsample_layer.layer_data_buffer)
		#var layer_data_bytes: PackedByteArray = PackedByteArray()
		#layer_data_bytes.resize(16)
		#layer_data_bytes.encode_s32(0, downsample_layer.layer_id + 1)
		#layer_data_bytes.encode_s32(4, 0)
		#layer_data_bytes.encode_s32(8, 0)
		#layer_data_bytes.encode_s32(12, 0)
		#downsample_layer.layer_data_buffer = rd.storage_buffer_create(layer_data_bytes.size(), layer_data_bytes)
		
		#var uniform1_0: RDUniform = RDUniform.new()
		#uniform1_0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		#uniform1_0.binding = 0
		#uniform1_0.add_id(downsample_layer.layer_data_buffer)
		#var uniform_set1: RID = UniformSetCacheRD.get_cache(downsample_shader, 1, [uniform1_0])
		
		var uniform1_0: RDUniform = RDUniform.new()
		uniform1_0.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		uniform1_0.binding = 0
		uniform1_0.add_id(scene_data_buffer)
		var uniform_set1: RID = UniformSetCacheRD.get_cache(downsample_shader, 1, [uniform1_0])
		
		var compute_list: int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, downsample_pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set0, 0)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set1, 1)
		#rd.compute_list_bind_uniform_set(compute_list, uniform_set2, 2)
		rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
		rd.compute_list_end()
	
	push_constant.encode_float(0x0, size.x)
	push_constant.encode_float(0x4, size.y)
	push_constant.encode_float(0x8, size.x)
	push_constant.encode_float(0xC, size.y)
	push_constant.encode_s32(0x28, 0)
	
	var x_groups: int = (size.x - 1) / 8 + 1
	var y_groups: int = (size.y - 1) / 8 + 1
	var z_groups: int = 1
	
	var uniform0_0: RDUniform = RDUniform.new()
	uniform0_0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform0_0.binding = 0
	uniform0_0.add_id(render_scene_buffers.get_color_layer(0))
	var uniform0_1: RDUniform = RDUniform.new()
	uniform0_1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform0_1.binding = 1
	uniform0_1.add_id(nearest_sampler)
	uniform0_1.add_id(render_scene_buffers.get_depth_layer(0))
	var uniform_set0: RID = UniformSetCacheRD.get_cache(composite_shader, 0, [uniform0_0, uniform0_1])
	
	var uniform_set1_uniforms: Array[RDUniform] = []
	for i: int in MAX_LAYER_COUNT:
		var uniform_color: RDUniform = RDUniform.new()
		uniform_color.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_color.binding = i * 2
		uniform_color.add_id(nearest_sampler)
		if i < _pixel_layer_count:
			uniform_color.add_id(_downsample_layers[i].color_buffer)
		else:
			uniform_color.add_id(render_scene_buffers.get_color_layer(0))
		uniform_set1_uniforms.push_back(uniform_color)
		
		var uniform_depth: RDUniform = RDUniform.new()
		uniform_depth.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform_depth.binding = i * 2 + 1
		uniform_depth.add_id(nearest_sampler)
		if i < _pixel_layer_count:
			uniform_depth.add_id(_downsample_layers[i].depth_buffer)
		else:
			uniform_depth.add_id(render_scene_buffers.get_depth_layer(0))
		uniform_set1_uniforms.push_back(uniform_depth)
	var uniform_set1: RID = UniformSetCacheRD.get_cache(composite_shader, 1, uniform_set1_uniforms)
	
	var uniform2_0: RDUniform = RDUniform.new()
	uniform2_0.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	uniform2_0.binding = 0
	uniform2_0.add_id(scene_data_buffer)
	var uniform_set2: RID = UniformSetCacheRD.get_cache(composite_shader, 2, [uniform2_0])
	
	var compute_list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, composite_pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set0, 0)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set1, 1)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set2, 2)
	rd.compute_list_set_push_constant(compute_list, push_constant, push_constant.size())
	rd.compute_list_dispatch(compute_list, x_groups, y_groups, z_groups)
	rd.compute_list_end()
