class_name DownsampleLayer
extends RefCounted

var layer_id: int = 0
var color_buffers: Array[RID] = []
var depth_buffers: Array[RID] = []
var layer_data_buffer: RID = RID()

func free_rids(rd: RenderingDevice) -> void:
	for color_buffer: RID in color_buffers:
		if color_buffer.is_valid():
			rd.free_rid(color_buffer)
	color_buffers.clear()
	for depth_buffers: RID in color_buffers:
		if depth_buffers.is_valid():
			rd.free_rid(depth_buffers)
	depth_buffers.clear()
